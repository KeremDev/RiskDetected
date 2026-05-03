import Foundation
import UIKit
import Supabase

/// Analiz akışını orkestre eder:
/// 1. `analyses` kaydı oluştur (status: pending)
/// 2. (Foto modu için) JPEG'leri Storage `photos` bucket'ına yükle
/// 3. `photos` tablosuna meta yaz
/// 4. Edge Function `analyze`'i çağır — Claude bulguları üretir, DB'ye yazılır
/// 5. Tamamlanan analizi (analyses + findings) çek ve döndür
@MainActor
final class AnalysisService {
    static let shared = AnalysisService()
    private let supabase = SupabaseService.shared

    enum AnalysisError: LocalizedError {
        case notAuthenticated
        case quotaExceeded(remaining: Int, tier: String)
        case alreadyCompleted
        case aiFailed(String)
        case storageFailed(String)
        case databaseFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:               return "Önce giriş yapmalısın."
            case .quotaExceeded(let r, _):        return "Günlük kotan doldu (kalan: \(r))."
            case .alreadyCompleted:               return "Bu analiz zaten tamamlanmış."
            case .aiFailed(let msg):              return "AI hatası: \(msg)"
            case .storageFailed(let msg):         return "Yükleme hatası: \(msg)"
            case .databaseFailed(let msg):        return "Veritabanı hatası: \(msg)"
            }
        }
    }

    // MARK: - Public API

    /// Foto bazlı analiz akışı.
    func runPhotoAnalysis(
        images: [UIImage],
        canvas: AnalysisCanvas,
        title: String? = nil
    ) async throws -> AnalysisResultBundle {
        guard let userID = supabase.currentUserID else { throw AnalysisError.notAuthenticated }

        // 1) Analyses kaydı (kind=photo, status=pending)
        let analysisID = try await createAnalysis(
            userID: userID,
            kind: "photo",
            canvas: canvas,
            title: title ?? defaultTitle(for: canvas),
            textInput: nil
        )

        // 2) Foto upload + photos tablosu
        var photoPaths: [String] = []
        for (index, image) in images.enumerated() {
            let path = "\(userID.uuidString)/\(analysisID.uuidString)/p\(index + 1).jpg"
            try await uploadJPEG(image: image, to: path)
            try await insertPhotoMeta(
                analysisID: analysisID, userID: userID, path: path,
                size: image.size
            )
            photoPaths.append(path)
        }

        // 3) Edge function
        try await invokeAnalyze(
            analysisID: analysisID, canvas: canvas,
            textInput: nil, photoPaths: photoPaths
        )

        // 4) Sonucu çek
        return try await fetchResult(analysisID: analysisID)
    }

    /// Metin bazlı analiz akışı.
    func runTextAnalysis(text: String, canvas: AnalysisCanvas) async throws -> AnalysisResultBundle {
        guard let userID = supabase.currentUserID else { throw AnalysisError.notAuthenticated }

        let analysisID = try await createAnalysis(
            userID: userID,
            kind: "text",
            canvas: canvas,
            title: defaultTitle(for: canvas),
            textInput: text
        )

        try await invokeAnalyze(
            analysisID: analysisID, canvas: canvas,
            textInput: text, photoPaths: []
        )

        return try await fetchResult(analysisID: analysisID)
    }

    /// Geçmiş analizleri listeler.
    func listRecent(limit: Int = 20) async throws -> [AnalysisRow] {
        do {
            let rows: [AnalysisRow] = try await supabase.client
                .from("analyses")
                .select()
                .eq("status", value: "completed")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    // MARK: - Private steps

    private func createAnalysis(
        userID: UUID,
        kind: String,
        canvas: AnalysisCanvas,
        title: String,
        textInput: String?
    ) async throws -> UUID {
        struct InsertPayload: Encodable {
            let user_id: String
            let kind: String
            let canvas: String
            let title: String
            let text_input: String?
            let status: String
        }
        let payload = InsertPayload(
            user_id: userID.uuidString,
            kind: kind,
            canvas: canvas.id,
            title: title,
            text_input: textInput,
            status: "pending"
        )
        do {
            let row: AnalysisRow = try await supabase.client
                .from("analyses")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return row.id
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    private func uploadJPEG(image: UIImage, to path: String) async throws {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw AnalysisError.storageFailed("JPEG dönüştürme başarısız")
        }
        do {
            _ = try await supabase.storage
                .from(RDConfig.Bucket.photos)
                .upload(
                    path: path,
                    file: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        } catch {
            throw AnalysisError.storageFailed(error.localizedDescription)
        }
    }

    private func insertPhotoMeta(analysisID: UUID, userID: UUID, path: String, size: CGSize) async throws {
        struct PhotoRow: Encodable {
            let analysis_id: String
            let user_id: String
            let storage_path: String
            let width: Int
            let height: Int
            let mime_type: String
        }
        do {
            _ = try await supabase.client
                .from("photos")
                .insert(PhotoRow(
                    analysis_id: analysisID.uuidString,
                    user_id: userID.uuidString,
                    storage_path: path,
                    width: Int(size.width),
                    height: Int(size.height),
                    mime_type: "image/jpeg"
                ))
                .execute()
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    private func invokeAnalyze(
        analysisID: UUID,
        canvas: AnalysisCanvas,
        textInput: String?,
        photoPaths: [String]
    ) async throws {
        struct Body: Encodable {
            let analysis_id: String
            let canvas: String
            let text_input: String?
            let photo_paths: [String]
        }
        let body = Body(
            analysis_id: analysisID.uuidString,
            canvas: canvas.id,
            text_input: textInput,
            photo_paths: photoPaths
        )
        do {
            try await supabase.functions.invoke(
                RDConfig.analyzeFunctionName,
                options: FunctionInvokeOptions(body: body)
            )
        } catch let FunctionsError.httpError(code, data) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            switch code {
            case 429:
                throw AnalysisError.quotaExceeded(remaining: 0, tier: "free")
            case 409:
                throw AnalysisError.alreadyCompleted
            default:
                throw AnalysisError.aiFailed("HTTP \(code): \(msg)")
            }
        } catch {
            throw AnalysisError.aiFailed(error.localizedDescription)
        }
    }

    private func fetchResult(analysisID: UUID) async throws -> AnalysisResultBundle {
        do {
            let analysis: AnalysisRow = try await supabase.client
                .from("analyses")
                .select()
                .eq("id", value: analysisID.uuidString)
                .single()
                .execute()
                .value

            let findings: [FindingRow] = try await supabase.client
                .from("findings")
                .select()
                .eq("analysis_id", value: analysisID.uuidString)
                .order("ordinal", ascending: true)
                .execute()
                .value

            return AnalysisResultBundle(analysis: analysis, findings: findings)
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    private func defaultTitle(for canvas: AnalysisCanvas) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        return "\(canvas.title) · \(formatter.string(from: Date()))"
    }
}

// MARK: - Wire row types

struct AnalysisResultBundle: Equatable {
    let analysis: AnalysisRow
    let findings: [FindingRow]
}

struct AnalysisRow: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let title: String
    let kind: String
    let canvas: String
    let status: String
    let aiSummary: String?
    let totalScoreFK: Double?
    let totalScoreM5: Int?
    let highestBandFK: String?
    let highestBandM5: String?
    let findingCount: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID         = "user_id"
        case title
        case kind
        case canvas
        case status
        case aiSummary      = "ai_summary"
        case totalScoreFK   = "total_score_fk"
        case totalScoreM5   = "total_score_m5"
        case highestBandFK  = "highest_band_fk"
        case highestBandM5  = "highest_band_m5"
        case findingCount   = "finding_count"
        case createdAt      = "created_at"
    }
}

struct FindingRow: Codable, Identifiable, Equatable {
    let id: UUID
    let analysisID: UUID
    let ordinal: Int
    let title: String
    let category: String?
    let description: String?
    let recommendedAction: String?
    let referencesText: String?
    let confidence: Double
    let fkProbability: Double
    let fkFrequency: Double
    let fkSeverity: Double
    let fkScore: Double
    let fkBand: String
    let m5Probability: Int
    let m5Severity: Int
    let m5Score: Int
    let m5Band: String

    enum CodingKeys: String, CodingKey {
        case id
        case analysisID         = "analysis_id"
        case ordinal
        case title
        case category
        case description
        case recommendedAction  = "recommended_action"
        case referencesText     = "references_text"
        case confidence
        case fkProbability      = "fk_probability"
        case fkFrequency        = "fk_frequency"
        case fkSeverity         = "fk_severity"
        case fkScore            = "fk_score"
        case fkBand             = "fk_band"
        case m5Probability      = "m5_probability"
        case m5Severity         = "m5_severity"
        case m5Score            = "m5_score"
        case m5Band             = "m5_band"
    }

    /// FindingRow → UI tarafının Finding modeline projeksiyon.
    var asFinding: Finding {
        Finding(
            id: ordinal,
            title: title,
            category: category ?? "",
            confidence: confidence,
            description: description ?? "",
            action: recommendedAction ?? "",
            references: referencesText ?? "",
            fk: FineKinneyParams(
                probability: fkProbability,
                frequency: fkFrequency,
                severity: fkSeverity
            ),
            m5: FiveByFiveParams(
                probability: m5Probability,
                severity: m5Severity
            )
        )
    }
}
