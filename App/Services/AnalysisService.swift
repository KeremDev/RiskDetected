import Foundation
import UIKit
import Supabase
import Vision
import OSLog

struct AnalysisProgressUpdate: Equatable {
    let title: String
    let message: String
    let icon: String

    static let retryingAI = AnalysisProgressUpdate(
        title: "AI servisi yoğun",
        message: "Model yanıt vermedi. Aynı analizi otomatik tekrar deniyoruz.",
        icon: "arrow.clockwise"
    )

    static let fallbackModel = AnalysisProgressUpdate(
        title: "Alternatif model deneniyor",
        message: "Analizi tamamlamak için uygun yedek model devreye alındı.",
        icon: "sparkles"
    )
}

/// Analiz akışını orkestre eder:
/// 1. `analyses` kaydı oluştur (status: pending)
/// 2. Edge Function `analyze`'i çağır — Gemini bulguları üretir, DB'ye yazılır
/// 3. Tamamlanan analizi (analyses + findings) çek ve döndür
@MainActor
final class AnalysisService {
    static let shared = AnalysisService()
    static let freeDailyLimit = 2
    nonisolated static let maxTextInputCharacters = 100
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "AnalysisService")
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
        title: String? = nil,
        userPrompt: String = "",
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)? = nil
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
        let photoParts = try await Self.makeInlineJPEGParts(from: images)
        let totalPayloadBytes = photoParts.reduce(0) { $0 + $1.encodedByteCount }
        if totalPayloadBytes > Self.maxInlinePhotoPayloadBytes {
            throw AnalysisError.invalidInput("Fotoğraf paketi çok büyük. Lütfen daha az fotoğraf veya daha düşük çözünürlüklü görsel dene.")
        }

        // 3) Edge function
        try await invokeAnalyze(
            analysisID: analysisID, canvases: canvases,
            textInput: nil, photoPaths: [], photoBase64Parts: photoParts,
            userPrompt: userPrompt,
            onProgress: onProgress
        )

        // 4) Sonucu çek
        return try await fetchResult(analysisID: analysisID)
    }

    /// Metin bazlı analiz akışı.
    func runTextAnalysis(
        userID: UUID,
        text: String,
        canvases: [AnalysisCanvas],
        userPrompt: String = "",
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)? = nil
    ) async throws -> AnalysisResultBundle {
        guard !canvases.isEmpty else {
            throw AnalysisError.invalidInput("En az bir analiz odağı seçmelisin.")
        }
        let trimmedText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextInputCharacters))

        guard trimmedText.count >= 10 else {
            throw AnalysisError.invalidInput("Analiz için en az 10 karakterlik açıklama girmelisin.")
        }

        let analysisID = try await createAnalysis(
            userID: userID,
            kind: "text",
            canvases: canvases,
            title: defaultTitle(for: canvases),
            textInput: trimmedText
        )

        try await invokeAnalyze(
            analysisID: analysisID, canvases: canvases,
            textInput: trimmedText, photoPaths: [], photoBase64Parts: [],
            userPrompt: userPrompt,
            onProgress: onProgress
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
    func photoData(path: String, requestID: String? = nil, supportID: String? = nil) async throws -> Data {
        let resolvedRequestID = requestID ?? UUID().uuidString
        let resolvedSupportID = supportID ?? AppErrorMessage.newSupportID()

        if DataActionFailureSimulation.isEnabled(.photoDownload) {
            let error = DataActionFailureSimulation.simulatedError(.photoDownload)
            Self.logger.error("Photo download simulation support=\(resolvedSupportID, privacy: .public) request=\(resolvedRequestID, privacy: .public) path=\(path, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("Analiz fotoğrafı indirilemedi. Destek kodu: \(resolvedSupportID)")
        }

        do {
            return try await supabase.storage
                .from(RDConfig.Bucket.photos)
                .download(path: path)
        } catch {
            Self.logger.error("Photo download failed support=\(resolvedSupportID, privacy: .public) request=\(resolvedRequestID, privacy: .public) path=\(path, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("Analiz fotoğrafı indirilemedi. Destek kodu: \(resolvedSupportID)")
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

    @discardableResult
    func generateExcelReport(
        analysisID: UUID,
        method: RiskMethod,
        requestID: String,
        supportID: String
    ) async throws -> ReportRow {
        struct Body: Encodable {
            let analysis_id: String
            let method: String
            let report_kind: String
            let request_id: String
            let support_id: String
        }

        struct ExcelReportResponse: Decodable {
            let report: ReportRow
            let requestID: String?
            let supportID: String?

            enum CodingKeys: String, CodingKey {
                case report
                case requestID = "request_id"
                case supportID = "support_id"
            }
        }

        let body = Body(
            analysis_id: analysisID.uuidString,
            method: Self.databaseReportMethodValue(method),
            report_kind: PDFReportKind.riskAnalysis.rawValue,
            request_id: requestID,
            support_id: supportID
        )

        do {
            let response: ExcelReportResponse = try await supabase.functions.invoke(
                RDConfig.generateExcelReportFunctionName,
                options: FunctionInvokeOptions(body: body)
            )
            return response.report
        } catch let FunctionsError.httpError(code, data) {
            let payload = Self.functionErrorPayload(from: data)
            let remoteSupportID = payload.supportID ?? supportID
            let message = payload.message.isEmpty ? "Excel raporu oluşturulamadı." : payload.message
            Self.logger.error("Excel report invoke failed support=\(remoteSupportID, privacy: .public) request=\(requestID, privacy: .public) http=\(code) message=\(message, privacy: .public)")
            throw AnalysisError.storageFailed("\(message) Destek kodu: \(remoteSupportID)")
        } catch {
            Self.logger.error("Excel report invoke failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("Excel raporu oluşturulamadı. Destek kodu: \(supportID)")
        }
    }

    /// Oluşturulan PDF'i Storage'a yükler ve `reports` kaydını yazar.
    @discardableResult
    func storeReport(
        userID: UUID,
        bundle: AnalysisResultBundle,
        fileURL: URL,
        kind: PDFReportKind,
        method: RiskMethod,
        requestID: String,
        supportID: String
    ) async throws -> ReportRow {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.error("Report read failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("PDF dosyası okunamadı. Destek kodu: \(supportID)")
        }

        let fileName = Self.safeReportFileName(for: bundle.analysis, kind: kind, method: method)
        let storagePath = "\(userID.uuidString.lowercased())/\(bundle.analysis.id.uuidString.lowercased())/\(fileName)"

        if ReportFailureSimulation.isEnabled(.storageUpload) {
            let error = ReportFailureSimulation.simulatedError(.storageUpload)
            Self.logger.error("Report upload simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) path=\(storagePath, privacy: .private(mask: .hash))")
            throw AnalysisError.storageFailed("PDF dosyası rapor arşivine yüklenemedi. Destek kodu: \(supportID). \(error.localizedDescription)")
        }

        let maxUploadAttempts = 3
        var lastUploadError: Error?
        for attempt in 1...maxUploadAttempts {
            do {
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.reports)
                    .upload(
                        storagePath,
                        data: data,
                        options: FileOptions(contentType: "application/pdf", upsert: true)
                    )
                lastUploadError = nil
                break
            } catch {
                lastUploadError = error
                let canRetry = attempt < maxUploadAttempts && Self.isTransientReportUploadError(error)
                Self.logger.error("Report upload failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) attempt=\(attempt) retry=\(canRetry, privacy: .public) path=\(storagePath, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
                guard canRetry else { break }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
            }
        }

        if lastUploadError != nil {
            throw AnalysisError.storageFailed("PDF dosyası rapor arşivine yüklenemedi. Destek kodu: \(supportID)")
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
            let request_id: String
            let support_id: String
        }

        let fileSize = data.count
        let payload = UpsertPayload(
            user_id: userID.uuidString,
            analysis_id: bundle.analysis.id.uuidString,
            document_no: Self.reportDocumentNo(for: bundle.analysis, kind: kind, method: method),
            format: "pdf",
            kind: kind.rawValue,
            method: Self.databaseReportMethodValue(method),
            title: bundle.analysis.title,
            storage_path: storagePath,
            file_name: fileName,
            mime_type: "application/pdf",
            file_size: fileSize,
            size_bytes: fileSize,
            page_count: Self.estimatedPageCount(for: kind, findingCount: bundle.findings.count),
            request_id: requestID,
            support_id: supportID
        )

        if ReportFailureSimulation.isEnabled(.metadataInsert) {
            let error = ReportFailureSimulation.simulatedError(.metadataInsert)
            Self.logger.error("Report metadata simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("PDF oluşturuldu ancak rapor arşiv kaydı tamamlanamadı. Destek kodu: \(supportID)")
        }

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
            Self.logger.error("Report metadata save failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("PDF oluşturuldu ancak rapor arşiv kaydı tamamlanamadı. Destek kodu: \(supportID)")
        }
    }

    private static func isTransientReportUploadError(_ error: Error) -> Bool {
        let lower = error.localizedDescription.lowercased(with: Locale(identifier: "tr_TR"))
        return lower.contains("network connection was lost") ||
            lower.contains("connection was lost") ||
            lower.contains("network") ||
            lower.contains("internet") ||
            lower.contains("offline") ||
            lower.contains("timed out") ||
            lower.contains("timeout") ||
            lower.contains("temporarily") ||
            lower.contains("unavailable") ||
            lower.contains("503") ||
            lower.contains("500") ||
            lower.contains("502") ||
            lower.contains("504")
    }

    /// Storage'daki PDF raporu indirir ve geçici dosya URL'i döndürür.
    func reportFileURL(for report: ReportRow, requestID: String, supportID: String) async throws -> URL {
        let data: Data
        if ReportFailureSimulation.isEnabled(.download) {
            let error = ReportFailureSimulation.simulatedError(.download)
            Self.logger.error("Report download simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("PDF raporu indirilemedi. Destek kodu: \(supportID)")
        }

        do {
            data = try await supabase.storage
                .from(RDConfig.Bucket.reports)
                .download(path: report.storagePath)
        } catch {
            Self.logger.error("Report download failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("PDF raporu indirilemedi. Destek kodu: \(supportID)")
        }

        let safeName = report.fileName.isEmpty ? "RiskDetected_Report_\(report.id.uuidString.prefix(8)).pdf" : report.fileName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Self.logger.error("Report local file write failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("PDF dosyası paylaşım için hazırlanamadı. Destek kodu: \(supportID)")
        }
    }

    /// Kullanıcının seçtiği tek PDF raporu ve ilişkili Storage dosyasını siler.
    func deleteReport(_ report: ReportRow, requestID: String, supportID: String) async throws {
        if ReportFailureSimulation.isEnabled(.deleteStorage) {
            let error = ReportFailureSimulation.simulatedError(.deleteStorage)
            Self.logger.error("Report file delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("PDF dosyası silinemedi. Destek kodu: \(supportID)")
        }

        if ReportFailureSimulation.isEnabled(.deleteMetadata) {
            let error = ReportFailureSimulation.simulatedError(.deleteMetadata)
            Self.logger.error("Report metadata delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("PDF rapor kaydı silinemedi. Destek kodu: \(supportID)")
        }

        do {
            _ = try await supabase.storage
                .from(RDConfig.Bucket.reports)
                .remove(paths: [report.storagePath])
        } catch {
            Self.logger.error("Report file delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed("PDF dosyası silinemedi. Destek kodu: \(supportID)")
        }

        do {
            try await supabase.client
                .from("reports")
                .delete()
                .eq("id", value: report.id.uuidString)
                .execute()
        } catch {
            Self.logger.error("Report metadata delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("PDF rapor kaydı silinemedi. Destek kodu: \(supportID)")
        }
    }

    /// Analizi kullanıcı isteğiyle siler. DB cascade findings/photos/reports
    /// kayıtlarını temizler; Storage dosyaları silme öncesi kaldırılır.
    func deleteAnalysis(analysisID: UUID, requestID: String, supportID: String) async throws {
        do {
            async let photoRows: [AnalysisPhotoRow] = supabase.client
                .from("photos")
                .select("analysis_id,storage_path,width,height,mime_type")
                .eq("analysis_id", value: analysisID.uuidString)
                .execute()
                .value

            async let reportRows: [ReportRow] = supabase.client
                .from("reports")
                .select()
                .eq("analysis_id", value: analysisID.uuidString)
                .execute()
                .value

            let (photos, reports) = try await (photoRows, reportRows)
            let photoPaths = photos.map(\.storagePath)
            let reportPaths = reports.map(\.storagePath)

            if !photoPaths.isEmpty {
                if DataActionFailureSimulation.isEnabled(.analysisDeleteStorage) {
                    let error = DataActionFailureSimulation.simulatedError(.analysisDeleteStorage)
                    Self.logger.error("Analysis photo delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    throw AnalysisError.storageFailed("Analiz fotoğrafları silinemedi. Destek kodu: \(supportID)")
                }
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.photos)
                    .remove(paths: photoPaths)
            }

            if !reportPaths.isEmpty {
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.reports)
                    .remove(paths: reportPaths)
            }

            if DataActionFailureSimulation.isEnabled(.analysisDeleteMetadata) {
                let error = DataActionFailureSimulation.simulatedError(.analysisDeleteMetadata)
                Self.logger.error("Analysis metadata delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                throw AnalysisError.databaseFailed("Analiz kaydı silinemedi. Destek kodu: \(supportID)")
            }

            try await supabase.client
                .from("analyses")
                .delete()
                .eq("id", value: analysisID.uuidString)
                .execute()
        } catch let error as AnalysisError {
            throw error
        } catch {
            Self.logger.error("Analysis delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("Analiz silinemedi. Destek kodu: \(supportID)")
        }
    }

    /// Kullanıcının analiz/rapor özetini JSON olarak dışa aktarır.
    func exportUserData(userID: UUID, profile: UserProfile?, requestID: String, supportID: String) async throws -> URL {
        struct ExportPayload: Encodable {
            let exported_at: String
            let user_id: String
            let profile: UserProfile?
            let analyses: [AnalysisRow]
            let findings: [FindingRow]
            let photos: [AnalysisPhotoRow]
            let reports: [ReportRow]
        }

        do {
            if DataActionFailureSimulation.isEnabled(.dataExport) {
                let error = DataActionFailureSimulation.simulatedError(.dataExport)
                Self.logger.error("Data export simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                throw AnalysisError.databaseFailed("Veri dışa aktarımı oluşturulamadı. Destek kodu: \(supportID)")
            }

            async let analyses: [AnalysisRow] = supabase.client
                .from("analyses")
                .select()
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value

            async let findings: [FindingRow] = supabase.client
                .from("findings")
                .select()
                .order("ordinal", ascending: true)
                .limit(5000)
                .execute()
                .value

            async let photos: [AnalysisPhotoRow] = supabase.client
                .from("photos")
                .select("analysis_id,storage_path,width,height,mime_type")
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value

            async let reports = listReports(limit: 1000)

            let (analysisRows, findingRows, photoRows, reportRows) = try await (analyses, findings, photos, reports)

            let payload = ExportPayload(
                exported_at: ISO8601DateFormatter().string(from: Date()),
                user_id: userID.uuidString,
                profile: profile,
                analyses: analysisRows,
                findings: findingRows,
                photos: photoRows,
                reports: reportRows
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(payload)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("RiskDetected_Verilerim_\(String(userID.uuidString.prefix(8))).json")
            try data.write(to: url, options: .atomic)
            return url
        } catch let error as AnalysisError {
            throw error
        } catch {
            Self.logger.error("Data export failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("Veri dışa aktarımı oluşturulamadı. Destek kodu: \(supportID)")
        }
    }

    /// Kullanıcının tüm PDF raporlarını ve Storage dosyalarını siler.
    func deleteAllReports(requestID: String, supportID: String) async throws {
        do {
            let reports = try await listReports(limit: 1000)
            guard !reports.isEmpty else { return }

            let paths = reports.map(\.storagePath)

            if !paths.isEmpty {
                if DataActionFailureSimulation.isEnabled(.bulkReportDelete) {
                    let error = DataActionFailureSimulation.simulatedError(.bulkReportDelete)
                    Self.logger.error("Bulk report delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    throw AnalysisError.storageFailed("PDF rapor dosyaları silinemedi. Destek kodu: \(supportID)")
                }
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.reports)
                    .remove(paths: paths)
            }

            try await supabase.client
                .from("reports")
                .delete()
                .in("id", values: reports.map { $0.id.uuidString })
                .execute()
        } catch let error as AnalysisError {
            throw error
        } catch {
            Self.logger.error("Bulk report delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("PDF raporları silinemedi. Destek kodu: \(supportID)")
        }
    }

    /// Kullanıcının tüm analizlerini, ilişkili Storage dosyalarını ve cascade DB kayıtlarını siler.
    func deleteAllAnalyses(requestID: String, supportID: String) async throws {
        do {
            let analyses: [AnalysisRow] = try await supabase.client
                .from("analyses")
                .select()
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value

            let ids = analyses.map(\.id)
            guard !ids.isEmpty else { return }

            async let photoRows: [AnalysisPhotoRow] = supabase.client
                .from("photos")
                .select("analysis_id,storage_path,width,height,mime_type")
                .in("analysis_id", values: ids.map { $0.uuidString })
                .execute()
                .value

            async let reportRows: [ReportRow] = supabase.client
                .from("reports")
                .select()
                .in("analysis_id", values: ids.map { $0.uuidString })
                .execute()
                .value

            let (photos, reports) = try await (photoRows, reportRows)
            let photoPaths = photos.map(\.storagePath)
            let reportPaths = reports.map(\.storagePath)

            if !photoPaths.isEmpty {
                if DataActionFailureSimulation.isEnabled(.bulkAnalysisDelete) {
                    let error = DataActionFailureSimulation.simulatedError(.bulkAnalysisDelete)
                    Self.logger.error("Bulk analysis delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    throw AnalysisError.storageFailed("Analiz fotoğrafları silinemedi. Destek kodu: \(supportID)")
                }
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.photos)
                    .remove(paths: photoPaths)
            }

            if !reportPaths.isEmpty {
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.reports)
                    .remove(paths: reportPaths)
            }

            try await supabase.client
                .from("analyses")
                .delete()
                .in("id", values: ids.map { $0.uuidString })
                .execute()
        } catch let error as AnalysisError {
            throw error
        } catch {
            Self.logger.error("Bulk analysis delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("Analizler silinemedi. Destek kodu: \(supportID)")
        }
    }

    /// Hesap silme talebini denetlenebilir şekilde kaydeder.
    func requestAccountDeletion(userID: UUID, email: String?, requestID: String, supportID: String) async throws {
        struct Payload: Encodable {
            let user_id: String
            let email: String?
            let requested_scope: String
            let note: String
        }

        let payload = Payload(
            user_id: userID.uuidString,
            email: email,
            requested_scope: "account_and_data",
            note: "User requested account and data deletion from iOS Profile > Verilerim."
        )

        do {
            if DataActionFailureSimulation.isEnabled(.accountDeletionRequest) {
                let error = DataActionFailureSimulation.simulatedError(.accountDeletionRequest)
                Self.logger.error("Account deletion request simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                throw AnalysisError.databaseFailed("Hesap silme talebi kaydedilemedi. Destek kodu: \(supportID)")
            }

            try await supabase.client
                .from("account_deletion_requests")
                .insert(payload)
                .execute()
        } catch {
            Self.logger.error("Account deletion request failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed("Hesap silme talebi kaydedilemedi. Destek kodu: \(supportID)")
        }
    }

    /// Profil ekranı için canlı sayaçlar.
    func profileStats() async throws -> ProfileStats {
        let recentWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekStart = ISO8601DateFormatter().string(from: recentWeekStart)

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
        if DataActionFailureSimulation.isEnabled(.quotaExceeded) {
            return DailyQuotaUsage(
                used: Self.freeDailyLimit,
                limit: Self.freeDailyLimit
            )
        }

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

    nonisolated private static let maxInlinePhotoBytes = 1_500_000
    nonisolated private static let maxInlinePhotoPayloadBytes = 4_500_000

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

    private struct InlinePhotoPart: Encodable, Sendable {
        let mime_type: String
        let data: String
        let width: Int
        let height: Int

        var encodedByteCount: Int {
            data.utf8.count
        }
    }

    nonisolated private static func makeInlineJPEGParts(from images: [UIImage]) async throws -> [InlinePhotoPart] {
        try await Task.detached(priority: .userInitiated) {
            try images.map { try inlineJPEGPart(from: $0) }
        }.value
    }

    nonisolated private static func inlineJPEGPart(from image: UIImage) throws -> InlinePhotoPart {
        let renderSizes: [CGFloat] = [1400, 1200, 1000]
        let qualities: [CGFloat] = [0.72, 0.60, 0.48]

        var lastPhoto: SanitizedPhoto?
        for maxDimension in renderSizes {
            let normalized = image.sanitizedForAnalysis(maxDimension: maxDimension)
            for quality in qualities {
                guard let data = normalized.image.jpegData(compressionQuality: quality) else { continue }
                let photo = SanitizedPhoto(data: data, size: normalized.size)
                lastPhoto = photo
                if data.count <= maxInlinePhotoBytes {
                    return InlinePhotoPart(
                        mime_type: "image/jpeg",
                        data: data.base64EncodedString(),
                        width: photo.width,
                        height: photo.height
                    )
                }
            }
        }

        if let lastPhoto, lastPhoto.data.count <= maxInlinePhotoBytes * 2 {
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
        photoBase64Parts: [InlinePhotoPart],
        userPrompt: String,
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)?
    ) async throws {
        struct Body: Encodable {
            let analysis_id: String
            let canvas: String
            let canvases: [String]
            let text_input: String?
            let user_prompt: String?
            let request_id: String
            let support_id: String
            let photo_paths: [String]
            let photo_base64_parts: [InlinePhotoPart]
        }
        // `canvas` = primary sorted id (tek-canvas contract).
        // `canvases` = tüm seçimler — Edge Function çoklu desteğe geçince kullanılır.
        let sortedCanvasIDs = canvases.map(\.id).sorted()
        let cleanPrompt = String(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        let body = Body(
            analysis_id: analysisID.uuidString,
            canvas: sortedCanvasIDs.first ?? canvases[0].id,
            canvases: sortedCanvasIDs,
            text_input: textInput,
            user_prompt: cleanPrompt.isEmpty ? nil : cleanPrompt,
            request_id: requestID,
            support_id: supportID,
            photo_paths: photoPaths,
            photo_base64_parts: photoBase64Parts
        )
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                try await supabase.functions.invoke(
                    RDConfig.analyzeFunctionName,
                    options: FunctionInvokeOptions(body: body)
                )
                return
            } catch let FunctionsError.httpError(code, data) {
                let payload = Self.functionErrorPayload(from: data)
                let msg = payload.message
                let errorCode = payload.code ?? ""
                let remoteSupportID = payload.supportID ?? supportID

                if code == 429,
                   msg.localizedCaseInsensitiveContains("günlük kota") || msg.localizedCaseInsensitiveContains("analiz/gün") || errorCode == "quota_exceeded" {
                    throw AnalysisError.quotaExceeded(remaining: 0, tier: "free")
                }
                if code == 409 {
                    throw AnalysisError.alreadyCompleted
                }

                let retryable = [429, 500, 502, 503, 504].contains(code)
                if retryable, attempt < maxAttempts {
                    onProgress?(.retryingAI)
                    Self.logger.info("Analyze invoke retry support=\(remoteSupportID, privacy: .public) request=\(requestID, privacy: .public) attempt=\(attempt) http=\(code)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }

                let messageWithSupport = Self.appendSupportID(remoteSupportID, to: msg)
                switch code {
                case 429:
                    throw AnalysisError.aiFailed(messageWithSupport.isEmpty ? Self.appendSupportID(remoteSupportID, to: "Gemini kotası doldu. Lütfen daha sonra tekrar dene.") : messageWithSupport)
                case 503:
                    throw AnalysisError.aiFailed(messageWithSupport.isEmpty ? Self.appendSupportID(remoteSupportID, to: "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene.") : messageWithSupport)
                default:
                    throw AnalysisError.aiFailed(messageWithSupport.isEmpty ? Self.appendSupportID(remoteSupportID, to: "HTTP \(code)") : messageWithSupport)
                }
            } catch {
                if attempt < maxAttempts {
                    onProgress?(.retryingAI)
                    Self.logger.info("Analyze invoke network retry support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) attempt=\(attempt) error=\(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                throw AnalysisError.aiFailed(error.localizedDescription)
            }
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

    private static func functionErrorPayload(from data: Data) -> (message: String, supportID: String?, code: String?) {
        struct FunctionErrorBody: Decodable {
            let error: String?
            let message: String?
            let support_id: String?
            let code: String?
        }

        if let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) {
            let message = (body.error ?? body.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return (message, body.support_id, body.code)
            }
        }

        return (String(data: data, encoding: .utf8) ?? "", nil, nil)
    }

    private static func appendSupportID(_ supportID: String, to message: String) -> String {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.localizedCaseInsensitiveContains("destek kodu") else { return clean }
        return "\(clean)\nDestek kodu: \(supportID)"
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

    private static func reportDocumentNo(for analysis: AnalysisRow, kind: PDFReportKind, method: RiskMethod) -> String {
        let shortID = String(analysis.id.uuidString.prefix(8)).uppercased()
        switch kind {
        case .standard:
            return "\(shortID)-STD"
        case .riskAnalysis:
            switch method {
            case .fineKinney:
                return "\(shortID)-FK"
            case .matrix5x5:
                return "\(shortID)-M5"
            }
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
    /// UIGraphics drops EXIF/location/camera metadata, normalizes orientation and
    /// applies lightweight privacy protection before AI/Storage use.
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
        return SanitizedImage(image: rendered.blurringDetectedFaces(), size: targetSize)
    }

    private func blurringDetectedFaces() -> UIImage {
        guard let cgImage else { return self }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return self
        }

        guard let faces = request.results, !faces.isEmpty else { return self }
        guard let sourceCI = CIImage(image: self) else { return self }

        let extent = sourceCI.extent
        let clamped = sourceCI.clampedToExtent()
        let blurred = clamped
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 22])
            .cropped(to: extent)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))

            for face in faces {
                let rect = Self.visionRect(face.boundingBox, imageSize: size)
                    .insetBy(dx: -size.width * 0.018, dy: -size.height * 0.018)
                    .intersection(CGRect(origin: .zero, size: size))

                guard rect.width > 1, rect.height > 1 else { continue }

                let ciRect = CGRect(
                    x: rect.minX,
                    y: size.height - rect.maxY,
                    width: rect.width,
                    height: rect.height
                )

                guard let crop = Self.ciContext.createCGImage(blurred, from: ciRect) else { continue }
                UIImage(cgImage: crop).draw(in: rect)
            }
        }
    }

    private static func visionRect(_ normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.minX * imageSize.width,
            y: (1 - normalizedRect.maxY) * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
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
    let format: String?
    let kind: String
    let method: String
    let title: String
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int?
    let requestID: String?
    let supportID: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case analysisID = "analysis_id"
        case format
        case kind
        case method
        case title
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case requestID = "request_id"
        case supportID = "support_id"
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
