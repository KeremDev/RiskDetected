import Foundation
import UIKit
import Supabase

/// Analiz akışını orkestre eder:
/// 1. `analyses` kaydı oluştur (status: pending)
/// 2. Edge Function `analyze`'i çağır — Gemini bulguları üretir, DB'ye yazılır
/// 3. Tamamlanan analizi (analyses + findings) çek ve döndür
@MainActor
final class AnalysisService {
    static let shared = AnalysisService()
    static let freeDailyLimit = 2
    private let supabase = SupabaseService.shared

    enum AnalysisError: LocalizedError {
        case notAuthenticated
        case quotaExceeded(remaining: Int, tier: String)
        case alreadyCompleted
        case aiFailed(String)
        case storageFailed(String)
        case databaseFailed(String)
        case invalidInput(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:               return "Önce giriş yapmalısın."
            case .quotaExceeded(let r, _):        return "Günlük kotan doldu (kalan: \(r))."
            case .alreadyCompleted:               return "Bu analiz zaten tamamlanmış."
            case .aiFailed(let msg):              return "AI hatası: \(msg)"
            case .storageFailed(let msg):         return "Yükleme hatası: \(msg)"
            case .databaseFailed(let msg):        return "Veritabanı hatası: \(msg)"
            case .invalidInput(let msg):          return msg
            }
        }
    }

    // MARK: - Public API

    /// Foto bazlı analiz akışı.
    func runPhotoAnalysis(
        userID: UUID,
        images: [UIImage],
        canvases: [AnalysisCanvas],
        title: String? = nil
    ) async throws -> AnalysisResultBundle {
        guard !canvases.isEmpty else {
            throw AnalysisError.invalidInput("En az bir analiz odağı seçmelisin.")
        }
        guard !images.isEmpty else {
            throw AnalysisError.invalidInput("Analiz için bir fotoğraf seçmelisin.")
        }

        // 1) Analyses kaydı (kind=photo, status=pending)
        let analysisID = try await createAnalysis(
            userID: userID,
            kind: "photo",
            canvases: canvases,
            title: title ?? defaultTitle(for: canvases),
            textInput: nil
        )

        // 2) Fotoğrafları Edge Function'a inline base64 gönder.
        // Storage RLS client upload akışını kırdığı için analiz yolu Storage'a bağımlı değil.
        let photoParts = try images.map { try inlineJPEGPart(from: $0) }
        let totalPayloadBytes = photoParts.reduce(0) { $0 + $1.encodedByteCount }
        if totalPayloadBytes > Self.maxInlinePhotoPayloadBytes {
            throw AnalysisError.invalidInput("Fotoğraf paketi çok büyük. Lütfen daha az fotoğraf veya daha düşük çözünürlüklü görsel dene.")
        }

        // 3) Edge function
        try await invokeAnalyze(
            analysisID: analysisID, canvases: canvases,
            textInput: nil, photoPaths: [], photoBase64Parts: photoParts
        )

        // 4) Sonucu çek
        return try await fetchResult(analysisID: analysisID)
    }

    /// Metin bazlı analiz akışı.
    func runTextAnalysis(userID: UUID, text: String, canvases: [AnalysisCanvas]) async throws -> AnalysisResultBundle {
        guard !canvases.isEmpty else {
            throw AnalysisError.invalidInput("En az bir analiz odağı seçmelisin.")
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else {
            throw AnalysisError.invalidInput("Analiz için en az 10 karakterlik açıklama girmelisin.")
        }

        let analysisID = try await createAnalysis(
            userID: userID,
            kind: "text",
            canvases: canvases,
            title: defaultTitle(for: canvases),
            textInput: text
        )

        try await invokeAnalyze(
            analysisID: analysisID, canvases: canvases,
            textInput: text, photoPaths: [], photoBase64Parts: []
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

    /// Tek bir tamamlanmış analizin sonucunu detay ekranı için getirir.
    func result(analysisID: UUID) async throws -> AnalysisResultBundle {
        try await fetchResult(analysisID: analysisID)
    }

    /// Liste kartları için ilk fotoğraf path'lerini getirir.
    func firstPhotoPaths(analysisIDs: [UUID]) async throws -> [UUID: String] {
        guard !analysisIDs.isEmpty else { return [:] }
        do {
            let rows: [AnalysisPhotoRow] = try await supabase.client
                .from("photos")
                .select("analysis_id,storage_path")
                .in("analysis_id", values: analysisIDs.map { $0.uuidString })
                .order("storage_path", ascending: true)
                .execute()
                .value

            var paths: [UUID: String] = [:]
            for row in rows where paths[row.analysisID] == nil {
                paths[row.analysisID] = row.storagePath
            }
            return paths
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    /// Storage'dan güvenli fotoğraf indirir.
    func photoData(path: String) async throws -> Data {
        do {
            return try await supabase.storage
                .from(RDConfig.Bucket.photos)
                .download(path: path)
        } catch {
            throw AnalysisError.storageFailed(error.localizedDescription)
        }
    }

    /// Kullanıcının kayıtlı PDF raporlarını listeler.
    func listReports(limit: Int = 20) async throws -> [ReportRow] {
        do {
            let rows: [ReportRow] = try await supabase.client
                .from("reports")
                .select()
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    /// Oluşturulan PDF'i Storage'a yükler ve `reports` kaydını yazar.
    @discardableResult
    func storeReport(
        userID: UUID,
        bundle: AnalysisResultBundle,
        fileURL: URL,
        kind: PDFReportKind,
        method: RiskMethod
    ) async throws -> ReportRow {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AnalysisError.storageFailed("PDF dosyası okunamadı: \(error.localizedDescription)")
        }

        let fileName = Self.safeReportFileName(for: bundle.analysis, kind: kind, method: method)
        let storagePath = "\(userID.uuidString.lowercased())/\(bundle.analysis.id.uuidString.lowercased())/\(fileName)"

        do {
            _ = try await supabase.storage
                .from(RDConfig.Bucket.reports)
                .upload(
                    storagePath,
                    data: data,
                    options: FileOptions(contentType: "application/pdf", upsert: true)
                )
        } catch {
            throw AnalysisError.storageFailed(error.localizedDescription)
        }

        struct UpsertPayload: Encodable {
            let user_id: String
            let analysis_id: String
            let document_no: String
            let format: String
            let kind: String
            let method: String
            let title: String
            let storage_path: String
            let file_name: String
            let mime_type: String
            let file_size: Int
            let size_bytes: Int
            let page_count: Int
        }

        let fileSize = data.count
        let payload = UpsertPayload(
            user_id: userID.uuidString,
            analysis_id: bundle.analysis.id.uuidString,
            document_no: String(bundle.analysis.id.uuidString.prefix(8)).uppercased(),
            format: "pdf",
            kind: kind.rawValue,
            method: Self.databaseReportMethodValue(method),
            title: bundle.analysis.title,
            storage_path: storagePath,
            file_name: fileName,
            mime_type: "application/pdf",
            file_size: fileSize,
            size_bytes: fileSize,
            page_count: Self.estimatedPageCount(for: kind, findingCount: bundle.findings.count)
        )

        do {
            let row: ReportRow = try await supabase.client
                .from("reports")
                .upsert(payload, onConflict: "user_id,storage_path")
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    /// Storage'daki PDF raporu indirir ve geçici dosya URL'i döndürür.
    func reportFileURL(for report: ReportRow) async throws -> URL {
        let data: Data
        do {
            data = try await supabase.storage
                .from(RDConfig.Bucket.reports)
                .download(path: report.storagePath)
        } catch {
            throw AnalysisError.storageFailed(error.localizedDescription)
        }

        let safeName = report.fileName.isEmpty ? "RiskDetected_Report_\(report.id.uuidString.prefix(8)).pdf" : report.fileName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw AnalysisError.storageFailed("PDF dosyası hazırlanamadı: \(error.localizedDescription)")
        }
    }

    /// Profil ekranı için canlı sayaçlar.
    func profileStats() async throws -> ProfileStats {
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekStart = ISO8601DateFormatter().string(from: startOfWeek)

        async let totalAnalyses = countRows(
            table: "analyses",
            filters: { $0.eq("status", value: "completed") }
        )
        async let weeklyAnalyses = countRows(
            table: "analyses",
            filters: { $0.eq("status", value: "completed").gte("created_at", value: weekStart) }
        )
        async let reportCount = countRowsOrZero(table: "reports")

        return try await ProfileStats(
            analysisCount: totalAnalyses,
            reportCount: reportCount,
            weeklyAnalysisCount: weeklyAnalyses
        )
    }

    /// Free kullanıcı için günlük analiz kullanımını verir.
    func dailyQuotaUsage() async throws -> DailyQuotaUsage {
        let utcDay = DateFormatter()
        utcDay.calendar = Calendar(identifier: .gregorian)
        utcDay.locale = Locale(identifier: "en_US_POSIX")
        utcDay.timeZone = TimeZone(secondsFromGMT: 0)
        utcDay.dateFormat = "yyyy-MM-dd"
        let dayStart = "\(utcDay.string(from: Date()))T00:00:00Z"

        let used = try await countRows(
            table: "analyses",
            filters: {
                $0.eq("status", value: "completed")
                    .gte("created_at", value: dayStart)
            }
        )

        return DailyQuotaUsage(
            used: used,
            limit: Self.freeDailyLimit
        )
    }

    // MARK: - Private steps

    private static let maxInlinePhotoBytes = 1_500_000
    private static let maxInlinePhotoPayloadBytes = 4_500_000

    private func countRows(
        table: String,
        filters: (PostgrestFilterBuilder) -> PostgrestFilterBuilder = { $0 }
    ) async throws -> Int {
        let response: PostgrestResponse<Void> = try await filters(
            supabase.client
                .from(table)
                .select("id", head: true, count: .exact)
        )
        .execute()
        return response.count ?? 0
    }

    private func countRowsOrZero(table: String) async -> Int {
        do {
            return try await countRows(table: table)
        } catch {
            return 0
        }
    }

    private func createAnalysis(
        userID: UUID,
        kind: String,
        canvases: [AnalysisCanvas],
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
        // `canvas` field = primary (first sorted) id — legacy single-id contract korunuyor.
        // Çoklu seçim backend hazır olunca `canvases` array üzerinden işlenecek.
        let sortedIDs  = canvases.map(\.id).sorted()
        let primaryID  = sortedIDs.first ?? canvases[0].id
        let payload = InsertPayload(
            user_id: userID.uuidString,
            kind: kind,
            canvas: primaryID,
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

    private struct InlinePhotoPart: Encodable {
        let mime_type: String
        let data: String
        let width: Int
        let height: Int

        var encodedByteCount: Int {
            data.utf8.count
        }
    }

    private func inlineJPEGPart(from image: UIImage) throws -> InlinePhotoPart {
        let renderSizes: [CGFloat] = [1400, 1200, 1000]
        let qualities: [CGFloat] = [0.72, 0.60, 0.48]

        var lastPhoto: SanitizedPhoto?
        for maxDimension in renderSizes {
            let normalized = image.sanitizedForAnalysis(maxDimension: maxDimension)
            for quality in qualities {
                guard let data = normalized.image.jpegData(compressionQuality: quality) else { continue }
                let photo = SanitizedPhoto(data: data, size: normalized.size)
                lastPhoto = photo
                if data.count <= Self.maxInlinePhotoBytes {
                    return InlinePhotoPart(
                        mime_type: "image/jpeg",
                        data: data.base64EncodedString(),
                        width: photo.width,
                        height: photo.height
                    )
                }
            }
        }

        if let lastPhoto, lastPhoto.data.count <= Self.maxInlinePhotoBytes * 2 {
            return InlinePhotoPart(
                mime_type: "image/jpeg",
                data: lastPhoto.data.base64EncodedString(),
                width: lastPhoto.width,
                height: lastPhoto.height
            )
        }

        throw AnalysisError.invalidInput("Fotoğraf dosyası analiz için çok büyük. Lütfen daha küçük bir görsel seç.")
    }

    private func invokeAnalyze(
        analysisID: UUID,
        canvases: [AnalysisCanvas],
        textInput: String?,
        photoPaths: [String],
        photoBase64Parts: [InlinePhotoPart]
    ) async throws {
        struct Body: Encodable {
            let analysis_id: String
            let canvas: String
            let canvases: [String]
            let text_input: String?
            let photo_paths: [String]
            let photo_base64_parts: [InlinePhotoPart]
        }
        // `canvas` = primary sorted id (tek-canvas contract).
        // `canvases` = tüm seçimler — Edge Function çoklu desteğe geçince kullanılır.
        let sortedCanvasIDs = canvases.map(\.id).sorted()
        let body = Body(
            analysis_id: analysisID.uuidString,
            canvas: sortedCanvasIDs.first ?? canvases[0].id,
            canvases: sortedCanvasIDs,
            text_input: textInput,
            photo_paths: photoPaths,
            photo_base64_parts: photoBase64Parts
        )
        do {
            try await supabase.functions.invoke(
                RDConfig.analyzeFunctionName,
                options: FunctionInvokeOptions(body: body)
            )
        } catch let FunctionsError.httpError(code, data) {
            let msg = Self.functionErrorMessage(from: data)
            switch code {
            case 429:
                if msg.localizedCaseInsensitiveContains("günlük kota") || msg.localizedCaseInsensitiveContains("analiz/gün") {
                    throw AnalysisError.quotaExceeded(remaining: 0, tier: "free")
                }
                throw AnalysisError.aiFailed(msg.isEmpty ? "Gemini kotası doldu. Lütfen daha sonra tekrar dene." : msg)
            case 503:
                throw AnalysisError.aiFailed(msg.isEmpty ? "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene." : msg)
            case 409:
                throw AnalysisError.alreadyCompleted
            default:
                throw AnalysisError.aiFailed(msg.isEmpty ? "HTTP \(code)" : msg)
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

            let photos: [AnalysisPhotoRow] = try await supabase.client
                .from("photos")
                .select("analysis_id,storage_path,width,height,mime_type")
                .eq("analysis_id", value: analysisID.uuidString)
                .order("storage_path", ascending: true)
                .execute()
                .value

            return AnalysisResultBundle(analysis: analysis, findings: findings, photos: photos)
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    private func defaultTitle(for canvases: [AnalysisCanvas]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        let label = canvases.count == 1
            ? canvases[0].title
            : canvases.map(\.title).joined(separator: " + ")
        return "\(label) · \(formatter.string(from: Date()))"
    }

    private static func functionErrorMessage(from data: Data) -> String {
        struct FunctionErrorBody: Decodable {
            let error: String?
        }

        if let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data),
           let error = body.error,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return error
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func safeReportFileName(for analysis: AnalysisRow, kind: PDFReportKind, method: RiskMethod) -> String {
        let normalizedTitle = analysis.title
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let safeTitle = normalizedTitle
            .map { character -> Character in
                if character.isLetter || character.isNumber { return character }
                if character == "-" || character == "_" { return character }
                return "_"
            }
            .reduce(into: "") { partial, character in
                if character == "_" && partial.last == "_" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let titlePart = safeTitle.isEmpty ? "analysis" : String(safeTitle.prefix(48))
        let shortID = String(analysis.id.uuidString.prefix(8)).lowercased()
        return "riskdetected_\(titlePart)_\(kind.rawValue)_\(databaseReportMethodValue(method))_\(shortID).pdf"
    }

    private static func databaseReportMethodValue(_ method: RiskMethod) -> String {
        switch method {
        case .fineKinney:
            return "fine_kinney"
        case .matrix5x5:
            return "matrix_5x5"
        }
    }

    private static func estimatedPageCount(for kind: PDFReportKind, findingCount: Int) -> Int {
        switch kind {
        case .standard:
            return 1 + max(Int(ceil(Double(max(findingCount, 1)) / 5.0)), 1)
        case .riskAnalysis:
            return 1 + max(Int(ceil(Double(max(findingCount, 1)) / 5.0)), 1)
        }
    }
}

private struct SanitizedImage {
    let image: UIImage
    let size: CGSize
}

private struct SanitizedPhoto {
    let data: Data
    let size: CGSize

    var width: Int { Int(size.width.rounded()) }
    var height: Int { Int(size.height.rounded()) }
}

private extension UIImage {
    /// Produces a pixel-only render for analysis/upload. Re-rendering through
    /// UIGraphics drops EXIF/location/camera metadata and normalizes orientation.
    func sanitizedForAnalysis(maxDimension: CGFloat) -> SanitizedImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(
            width: max((size.width * scale).rounded(), 1),
            height: max((size.height * scale).rounded(), 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return SanitizedImage(image: rendered, size: targetSize)
    }
}

// MARK: - Wire row types

struct AnalysisResultBundle: Equatable {
    let analysis: AnalysisRow
    let findings: [FindingRow]
    let photos: [AnalysisPhotoRow]
}

struct AnalysisPhotoRow: Codable, Equatable {
    let analysisID: UUID
    let storagePath: String
    let width: Int?
    let height: Int?
    let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case analysisID = "analysis_id"
        case storagePath = "storage_path"
        case width
        case height
        case mimeType = "mime_type"
    }
}

struct ProfileStats: Equatable {
    let analysisCount: Int
    let reportCount: Int
    let weeklyAnalysisCount: Int
}

struct DailyQuotaUsage: Equatable {
    let used: Int
    let limit: Int

    var remaining: Int {
        max(limit - used, 0)
    }

    var isExhausted: Bool {
        remaining == 0
    }
}

struct ReportRow: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let analysisID: UUID?
    let kind: String
    let method: String
    let title: String
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case analysisID = "analysis_id"
        case kind
        case method
        case title
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case createdAt = "created_at"
    }
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
