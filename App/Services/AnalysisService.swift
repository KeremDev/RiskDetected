import Foundation
import UIKit
import Supabase
import Vision
import OSLog

enum AnalysisProgressPhase: Equatable {
    case preparingInput
    case creatingAnalysis
    case uploadingPhotos
    case submitting
    case queued
    case analyzing
    case finalizingResult
    case retryingNetwork
    case retryingAI
    case fallbackModel
}

struct AnalysisProgressUpdate: Equatable {
    let phase: AnalysisProgressPhase
    let title: String
    let message: String
    let icon: String

    static let preparingInput = AnalysisProgressUpdate(
        phase: .preparingInput,
        title: RDLocalization.string("analysis.analysis.service.girdi.hazirlaniyor.9a2af484", table: .analysis, fallback: "Girdi hazırlanıyor"),
        message: RDLocalization.string("analysis.analysis.service.analiz.girdisi.kontrol.edilip.guvenli.paket.hazi.e6b69f6c", table: .analysis, fallback: "Analiz girdisi kontrol edilip güvenli paket hazırlanıyor."),
        icon: "photo.on.rectangle.angled"
    )

    static let creatingAnalysis = AnalysisProgressUpdate(
        phase: .creatingAnalysis,
        title: RDLocalization.string("analysis.analysis.service.analiz.kaydi.aciliyor.63173bd6", table: .analysis, fallback: "Analiz kaydı açılıyor"),
        message: RDLocalization.string("analysis.analysis.service.analiz.guvenli.sekilde.baslatiliyor.9ae4a5e5", table: .analysis, fallback: "Analiz güvenli şekilde başlatılıyor."),
        icon: "doc.badge.plus"
    )

    static let uploadingPhotos = AnalysisProgressUpdate(
        phase: .uploadingPhotos,
        title: RDLocalization.string("analysis.analysis.service.fotograflar.yukleniyor.01c07e4e", table: .analysis, fallback: "Fotoğraflar yükleniyor"),
        message: RDLocalization.string("analysis.analysis.service.fotograflar.guvenli.depoya.kaydediliyor.52cadbe9", table: .analysis, fallback: "Fotoğraflar güvenli depoya kaydediliyor."),
        icon: "icloud.and.arrow.up.fill"
    )

    static let submitting = AnalysisProgressUpdate(
        phase: .submitting,
        title: RDLocalization.string("analysis.analysis.service.analiz.gonderiliyor.ee38fb84", table: .analysis, fallback: "Analiz gönderiliyor"),
        message: RDLocalization.string("analysis.analysis.service.risk.sinyalleri.icin.sunucuya.guvenli.istek.gond.7a0e62d3", table: .analysis, fallback: "Risk sinyalleri için sunucuya güvenli istek gönderiliyor."),
        icon: "paperplane.fill"
    )

    static let retryingAI = AnalysisProgressUpdate(
        phase: .retryingAI,
        title: RDLocalization.string("analysis.analysis.service.ai.servisi.yogun.1ad27216", table: .analysis, fallback: "AI servisi yoğun"),
        message: RDLocalization.string("analysis.analysis.service.model.yanit.vermedi.ayni.analizi.otomatik.tekrar.30fea459", table: .analysis, fallback: "Model yanıt vermedi. Aynı analizi otomatik tekrar deniyoruz."),
        icon: "arrow.clockwise"
    )

    static let retryingNetwork = AnalysisProgressUpdate(
        phase: .retryingNetwork,
        title: RDLocalization.string("analysis.analysis.service.baglanti.tekrar.deneniyor.a6292295", table: .analysis, fallback: "Bağlantı tekrar deneniyor"),
        message: RDLocalization.string("analysis.analysis.service.depo.veya.sunucu.baglantisi.koptu.ayni.analizi.t.6d3ebe27", table: .analysis, fallback: "Depo veya sunucu bağlantısı koptu. Aynı analizi tekrar deniyoruz."),
        icon: "wifi.exclamationmark"
    )

    static let fallbackModel = AnalysisProgressUpdate(
        phase: .fallbackModel,
        title: RDLocalization.string("analysis.analysis.service.alternatif.model.deneniyor.4cae5391", table: .analysis, fallback: "Alternatif model deneniyor"),
        message: RDLocalization.string("analysis.analysis.service.analizi.tamamlamak.icin.uygun.yedek.model.devrey.94d399d7", table: .analysis, fallback: "Analizi tamamlamak için uygun yedek model devreye alındı."),
        icon: "sparkles"
    )

    static let queued = AnalysisProgressUpdate(
        phase: .queued,
        title: RDLocalization.string("analysis.analysis.service.analiz.hazirlaniyor.0e83653a", table: .analysis, fallback: "Analiz hazırlanıyor"),
        message: RDLocalization.string("analysis.analysis.service.uygulamadan.ciksan.bile.analiz.guvenli.sekilde.t.6546513d", table: .analysis, fallback: "Uygulamadan çıksan bile analiz güvenli şekilde tamamlanacak."),
        icon: "clock.arrow.circlepath"
    )

    static let analyzing = AnalysisProgressUpdate(
        phase: .analyzing,
        title: RDLocalization.string("analysis.analysis.service.ai.degerlendiriyor.6fb12004", table: .analysis, fallback: "AI değerlendiriyor"),
        message: RDLocalization.string("analysis.analysis.service.bulgular.risk.seviyeleri.ve.aksiyonlar.yapilandi.62e4c5c9", table: .analysis, fallback: "Bulgular, risk seviyeleri ve aksiyonlar yapılandırılıyor."),
        icon: "brain.head.profile"
    )

    static let finalizingResult = AnalysisProgressUpdate(
        phase: .finalizingResult,
        title: RDLocalization.string("analysis.analysis.service.sonuc.hazirlaniyor.b119fda1", table: .analysis, fallback: "Sonuç hazırlanıyor"),
        message: RDLocalization.string("analysis.analysis.service.analiz.tamamlandi.bulgular.guvenli.sekilde.yukle.290e3c64", table: .analysis, fallback: "Analiz tamamlandı. Bulgular güvenli şekilde yükleniyor."),
        icon: "checkmark.seal.fill"
    )
}

struct AccountDeletionRequestResult: Decodable, Equatable {
    let ok: Bool?
    let completed: Bool?
    let alreadyCompleted: Bool?
    let authUserDeleted: Bool?
    let requestID: String?
    let supportID: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case completed
        case alreadyCompleted = "already_completed"
        case authUserDeleted = "auth_user_deleted"
        case requestID = "request_id"
        case supportID = "support_id"
        case message
    }

    var shouldClearLocalSession: Bool {
        completed == true || alreadyCompleted == true || authUserDeleted == true
    }
}

struct FindingMutationPatch: Encodable, Equatable {
    var title: String?
    var category: String?
    var description: String?
    var recommendedAction: String?
    var recommendedMeasures: [FindingMeasure]?
    var referencesText: String?
    var rootCauseText: String?
    var fkProbability: Double?
    var fkFrequency: Double?
    var fkSeverity: Double?
    var m5Probability: Int?
    var m5Severity: Int?
    var sourcePhotoIndices: [Int]?

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case description
        case recommendedAction = "recommended_action"
        case recommendedMeasures = "recommended_measures"
        case referencesText = "references_text"
        case rootCauseText = "root_cause_text"
        case fkProbability = "fk_probability"
        case fkFrequency = "fk_frequency"
        case fkSeverity = "fk_severity"
        case m5Probability = "m5_probability"
        case m5Severity = "m5_severity"
        case sourcePhotoIndices = "source_photo_indices"
    }
}

private extension DateFormatter {
    static let rdExportFileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter
    }()
}

enum AppClientMetadata {
    static let apiContractVersion = 2
    static let platform = "ios"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static var capabilities: [String: Bool] {
        [
            "multi_photo_analysis": true,
            "multi_photo_coverage_v2": true,
            "editable_findings": true,
            "report_snapshot_v2": true,
            "global_localization_wave1":
                RDGlobalLocalizationBuildGate.isCompiledIn
        ]
    }
}

/// Analiz akışını orkestre eder:
/// 1. `analyses` kaydı oluştur (status: pending)
/// 2. Edge Function `analyze`'i çağır — Gemini bulguları üretir, DB'ye yazılır
/// 3. Tamamlanan analizi (analyses + findings) çek ve döndür
@MainActor
final class AnalysisService {
    static let shared = AnalysisService()
    static let freeDailyLimit = 1
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "AnalysisService")
    private static let analysisRecordCreationTimeoutNanoseconds: UInt64 = 25_000_000_000
    private static let analysisPhotoUploadTimeoutNanoseconds: UInt64 = 45_000_000_000
    private static let analysisPhotoMetadataTimeoutNanoseconds: UInt64 = 15_000_000_000
    private static let analysisPhotoCleanupTimeoutNanoseconds: UInt64 = 10_000_000_000
    private static let analysisSubmissionTimeoutNanoseconds: UInt64 = 45_000_000_000
    private static let analysisSubmissionCleanupTimeoutNanoseconds: UInt64 = 6_000_000_000
    private static let analysisResultPollTimeoutNanoseconds: UInt64 = 12_000_000_000
    private let supabase = SupabaseService.shared

    private static var clientAppVersion: String {
        AppClientMetadata.appVersion
    }

    enum AnalysisError: LocalizedError {
        case notAuthenticated
        case quotaExceeded(message: String, tier: String)
        case alreadyCompleted
        case aiFailed(String)
        case networkFailed(String)
        case storageFailed(String)
        case databaseFailed(String)
        case invalidInput(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:               return RDLocalization.string("analysis.analysis.service.once.giris.yapmalisin.b2421a61", table: .analysis, fallback: "Önce giriş yapmalısın.")
            case .quotaExceeded(let message, _): return message
            case .alreadyCompleted:               return RDLocalization.string("analysis.analysis.service.bu.analiz.zaten.tamamlanmis.298cb56f", table: .analysis, fallback: "Bu analiz zaten tamamlanmış.")
            case .aiFailed(let msg):              return RDLocalization.format("analysis.analysis.service.ai.hatasi.1.37f7e8d6", table: .analysis, fallback: "AI hatası: %1$@", arguments: [String(describing: msg)])
            case .networkFailed(let msg):         return RDLocalization.format("analysis.analysis.service.baglanti.hatasi.1.48a793e3", table: .analysis, fallback: "Bağlantı hatası: %1$@", arguments: [String(describing: msg)])
            case .storageFailed(let msg):         return RDLocalization.format("analysis.analysis.service.yukleme.hatasi.1.76bb6558", table: .analysis, fallback: "Yükleme hatası: %1$@", arguments: [String(describing: msg)])
            case .databaseFailed(let msg):        return RDLocalization.format("analysis.analysis.service.veritabani.hatasi.1.aea21966", table: .analysis, fallback: "Veritabanı hatası: %1$@", arguments: [String(describing: msg)])
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
        localization: RDAnalysisLocalizationRequest? = nil,
        analysisSector: AnalysisSectorID? = nil,
        companyID: UUID? = nil,
        title: String? = nil,
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)? = nil
    ) async throws -> AnalysisResultBundle {
        guard !canvases.isEmpty else {
            throw AnalysisError.invalidInput(RDLocalization.string("analysis.analysis.service.en.az.bir.analiz.odagi.secmelisin.554e3daf", table: .analysis, fallback: "En az bir analiz odağı seçmelisin."))
        }
        guard !images.isEmpty else {
            throw AnalysisError.invalidInput(RDLocalization.string("analysis.analysis.service.analiz.icin.bir.fotograf.secmelisin.584ee62a", table: .analysis, fallback: "Analiz için bir fotoğraf seçmelisin."))
        }
        guard images.count <= 3 else {
            throw AnalysisError.invalidInput(RDLocalization.string("analysis.analysis.service.bir.analizde.en.fazla.3.fotograf.kullanilabilir.f5a759b0", table: .analysis, fallback: "Bir analizde en fazla 3 fotoğraf kullanılabilir."))
        }

        // 1) Fotoğrafları analiz kaydı açılmadan önce hazırla.
        // Hazırlık başarısız olursa DB'de boş pending analiz bırakmayız.
        onProgress?(.preparingInput)
        let preparedPhotos = try await Self.makePreparedJPEGPhotos(from: images)
        let totalPayloadBytes = preparedPhotos.reduce(0) { $0 + $1.encodedByteCount }
        if totalPayloadBytes > Self.maxInlinePhotoPayloadBytes {
            throw AnalysisError.invalidInput(RDLocalization.string("analysis.analysis.service.fotograf.paketi.cok.buyuk.lutfen.daha.az.fotogra.f9d64c24", table: .analysis, fallback: "Fotoğraf paketi çok büyük. Lütfen daha az fotoğraf veya daha düşük çözünürlüklü görsel dene."))
        }

        // 2) Analyses kaydı (kind=photo, status=pending)
        onProgress?(.creatingAnalysis)
        let resolvedTitle = title ?? defaultTitle(for: canvases)
        let analysisID = try await createAnalysis(
            userID: userID,
            kind: "photo",
            canvases: canvases,
            title: resolvedTitle,
            textInput: nil,
            companyID: companyID,
            analysisSector: analysisSector,
            localization: localization
        )
        InFlightAnalysisStore.shared.save(
            InFlightAnalysis(
                analysisID: analysisID,
                userID: userID,
                photoCount: images.count,
                startedAt: Date(),
                title: resolvedTitle,
                kind: "photo"
            )
        )

        // 3) Edge function
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        var uploadedPhotoPaths: [String] = []
        do {
            onProgress?(.uploadingPhotos)
            uploadedPhotoPaths = try await uploadPhotosForAnalysis(
                userID: userID,
                analysisID: analysisID,
                photos: preparedPhotos
            )
        } catch {
            await cleanupUploadedPhotos(
                userID: userID,
                analysisID: analysisID,
                paths: uploadedPhotoPaths,
                supportID: supportID
            )
            await markAnalysisSubmissionFailedIfStillPending(
                analysisID: analysisID,
                supportID: supportID,
                error: error,
                delayBeforeCheck: false
            )
            InFlightAnalysisStore.shared.clear(analysisID: analysisID)
            throw error
        }

        onProgress?(.submitting)
        do {
            try await invokeAnalyze(
                analysisID: analysisID, canvases: canvases,
                textInput: nil, companyID: companyID,
                analysisSector: analysisSector,
                localization: localization,
                photoPaths: uploadedPhotoPaths, photoBase64Parts: [],
                requestID: requestID, supportID: supportID,
                onProgress: onProgress
            )
        } catch {
            let queuedOrLater = await recoverPhotoSubmissionIfServerAccepted(
                analysisID: analysisID,
                userID: userID,
                uploadedPhotoPaths: uploadedPhotoPaths,
                supportID: supportID,
                error: error,
                onProgress: onProgress
            )
            if queuedOrLater {
                return try await waitForCompletedResult(analysisID: analysisID, photoCount: images.count, onProgress: onProgress)
            }
            let markedFailed = await markAnalysisSubmissionFailedIfStillPending(
                analysisID: analysisID,
                supportID: supportID,
                error: error,
                delayBeforeCheck: false
            )
            if markedFailed {
                await cleanupUploadedPhotos(
                    userID: userID,
                    analysisID: analysisID,
                    paths: uploadedPhotoPaths,
                    supportID: supportID
                )
                InFlightAnalysisStore.shared.clear(analysisID: analysisID)
            }
            throw error
        }

        // 4) Backend kuyruğa aldıktan sonra sonucu DB status ile izle.
        return try await waitForCompletedResult(analysisID: analysisID, photoCount: images.count, onProgress: onProgress)
    }

    /// Geçmiş analizleri listeler.
    func listRecent(
        limit: Int = 20,
        companyID: UUID? = nil,
        includeHiddenTextAnalyses: Bool = false
    ) async throws -> [AnalysisRow] {
        do {
            let rows: [AnalysisRow]
            if let companyID {
                if includeHiddenTextAnalyses {
                    rows = try await supabase.client
                        .from("analyses")
                        .select()
                        .eq("status", value: "completed")
                        .eq("company_id", value: companyID.uuidString)
                        .order("created_at", ascending: false)
                        .limit(limit)
                        .execute()
                        .value
                } else {
                    rows = try await supabase.client
                        .from("analyses")
                        .select()
                        .eq("status", value: "completed")
                        .eq("kind", value: "photo")
                        .eq("company_id", value: companyID.uuidString)
                        .order("created_at", ascending: false)
                        .limit(limit)
                        .execute()
                        .value
                }
            } else {
                if includeHiddenTextAnalyses {
                    rows = try await supabase.client
                        .from("analyses")
                        .select()
                        .eq("status", value: "completed")
                        .order("created_at", ascending: false)
                        .limit(limit)
                        .execute()
                        .value
                } else {
                    rows = try await supabase.client
                        .from("analyses")
                        .select()
                        .eq("status", value: "completed")
                        .eq("kind", value: "photo")
                        .order("created_at", ascending: false)
                        .limit(limit)
                        .execute()
                        .value
                }
            }
            return rows
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    /// Tek bir tamamlanmış analizin sonucunu detay ekranı için getirir.
    func result(analysisID: UUID) async throws -> AnalysisResultBundle {
        #if DEBUG
        if Self.isUITestMainLaunch {
            return Self.uiTestResultBundle(analysisID: analysisID)
        }
        #endif
        let bundle = try await fetchResult(analysisID: analysisID)
        InFlightAnalysisStore.shared.clear(analysisID: analysisID)
        return bundle
    }

    /// Devam eden bir analize yeniden bağlanır. Fotoğraf yüklemez ve Edge Function çağırmaz.
    func resumeAnalysis(
        analysisID: UUID,
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)? = nil
    ) async throws -> AnalysisResultBundle {
        #if DEBUG
        if Self.isUITestMainLaunch {
            onProgress?(.finalizingResult)
            return Self.uiTestResultBundle(analysisID: analysisID)
        }
        #endif
        return try await waitForCompletedResult(analysisID: analysisID, onProgress: onProgress)
    }

    func updateFinding(
        analysisID: UUID,
        findingID: UUID,
        expectedVersion: Int?,
        patch: FindingMutationPatch
    ) async throws -> AnalysisResultBundle {
        #if DEBUG
        if Self.isUITestMainLaunch {
            return Self.uiTestResultBundle(analysisID: analysisID, updatedFindingID: findingID, patch: patch)
        }
        #endif
        return try await mutateFinding(
            analysisID: analysisID,
            findingID: findingID,
            action: "update",
            expectedVersion: expectedVersion,
            patch: patch
        )
    }

    func deleteFinding(
        analysisID: UUID,
        findingID: UUID,
        expectedVersion: Int?
    ) async throws -> AnalysisResultBundle {
        #if DEBUG
        if Self.isUITestMainLaunch {
            return Self.uiTestResultBundle(analysisID: analysisID, deletedFindingID: findingID)
        }
        #endif
        return try await mutateFinding(
            analysisID: analysisID,
            findingID: findingID,
            action: "delete",
            expectedVersion: expectedVersion,
            patch: nil
        )
    }

    private func mutateFinding(
        analysisID: UUID,
        findingID: UUID,
        action: String,
        expectedVersion: Int?,
        patch: FindingMutationPatch?
    ) async throws -> AnalysisResultBundle {
        struct Body: Encodable {
            let analysis_id: String
            let finding_id: String
            let action: String
            let patch: FindingMutationPatch?
            let expected_finding_version: Int?
            let client_app_version: String
            let client_app_build: String
            let client_platform: String
            let api_contract_version: Int
            let client_capabilities: [String: Bool]
            let request_id: String
            let support_id: String
        }
        struct ResponseBody: Decodable {
            let bundle: AnalysisResultBundle
        }

        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        let body = Body(
            analysis_id: analysisID.uuidString,
            finding_id: findingID.uuidString,
            action: action,
            patch: patch,
            expected_finding_version: expectedVersion,
            client_app_version: Self.clientAppVersion,
            client_app_build: AppClientMetadata.appBuild,
            client_platform: AppClientMetadata.platform,
            api_contract_version: AppClientMetadata.apiContractVersion,
            client_capabilities: AppClientMetadata.capabilities,
            request_id: requestID,
            support_id: supportID
        )

        do {
            let response: ResponseBody = try await supabase.functions.invoke(
                RDConfig.mutateAnalysisFindingFunctionName,
                options: FunctionInvokeOptions(body: body)
            )
            return response.bundle
        } catch let FunctionsError.httpError(code, data) {
            let payload = Self.functionErrorPayload(from: data)
            let remoteSupportID = payload.supportID ?? supportID
            let message = payload.message.isEmpty ? RDLocalization.string("analysis.analysis.service.bulgu.guncellenemedi.e5339f0c", table: .analysis, fallback: "Bulgu güncellenemedi.") : payload.message
            if code == 409 {
                throw AnalysisError.databaseFailed(Self.appendSupportID(remoteSupportID, to: message))
            }
            if code == 423 {
                throw AnalysisError.invalidInput(Self.appendSupportID(remoteSupportID, to: message))
            }
            throw AnalysisError.databaseFailed(Self.appendSupportID(remoteSupportID, to: message))
        } catch {
            throw AnalysisError.databaseFailed(Self.appendSupportID(supportID, to: error.localizedDescription))
        }
    }

    func assignCompany(to analysisID: UUID, companyID: UUID) async throws {
        struct Payload: Encodable {
            let company_id: String
        }

        do {
            try await supabase.client
                .from("analyses")
                .update(Payload(company_id: companyID.uuidString))
                .eq("id", value: analysisID.uuidString)
                .execute()
        } catch {
            throw AnalysisError.databaseFailed(RDLocalization.string("analysis.analysis.service.firma.analize.baglanamadi.0ca828a7", table: .analysis, fallback: "Firma analize bağlanamadı."))
        }
    }

    /// Liste kartları için ilk fotoğraf path'lerini getirir.
    func firstPhotoPaths(analysisIDs: [UUID]) async throws -> [UUID: String] {
        guard !analysisIDs.isEmpty else { return [:] }
        do {
            let rows: [AnalysisPhotoRow] = try await supabase.client
                .from("photos")
                .select("analysis_id,storage_path,width,height,mime_type,sequence_index")
                .in("analysis_id", values: analysisIDs.map { $0.uuidString })
                .order("sequence_index", ascending: true)
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

        #if DEBUG
        if Self.isUITestMainLaunch, path.hasPrefix("ui-tests/") {
            let fixtureData = await MainActor.run {
                Self.uiTestPhotoData(path: path)
            }
            guard let fixtureData else {
                throw AnalysisError.storageFailed("UI test fotoğraf fixture verisi oluşturulamadı.")
            }
            return fixtureData
        }
        #endif

        if DataActionFailureSimulation.isEnabled(.photoDownload) {
            let error = DataActionFailureSimulation.simulatedError(.photoDownload)
            Self.logger.error("Photo download simulation support=\(resolvedSupportID, privacy: .public) request=\(resolvedRequestID, privacy: .public) path=\(path, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.analiz.fotografi.indirilemedi.destek.kodu.1.98cdb4a9", table: .analysis, fallback: "Analiz fotoğrafı indirilemedi. Destek kodu: %1$@", arguments: [String(describing: resolvedSupportID)]))
        }

        do {
            return try await supabase.storage
                .from(RDConfig.Bucket.photos)
                .download(path: path)
        } catch {
            Self.logger.error("Photo download failed support=\(resolvedSupportID, privacy: .public) request=\(resolvedRequestID, privacy: .public) path=\(path, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.analiz.fotografi.indirilemedi.destek.kodu.1.98cdb4a9", table: .analysis, fallback: "Analiz fotoğrafı indirilemedi. Destek kodu: %1$@", arguments: [String(describing: resolvedSupportID)]))
        }
    }

    /// Kullanıcının kayıtlı PDF raporlarını listeler.
    func listReports(
        limit: Int = 20,
        offset: Int = 0,
        companyID: UUID? = nil,
        photoAnalysesOnly: Bool = false
    ) async throws -> [ReportRow] {
        do {
            let start = max(offset, 0)
            let end = start + max(limit, 1) - 1
            let baseSelect = "id,user_id,analysis_id,company_id,company_snapshot,format,kind,method,title,storage_path,file_name,mime_type,file_size,request_id,support_id,created_at"
            let select = photoAnalysesOnly ? "\(baseSelect),analyses!inner(kind)" : baseSelect
            let rows: [ReportRow]
            if let companyID {
                if photoAnalysesOnly {
                    rows = try await supabase.client
                        .from("reports")
                        .select(select)
                        .eq("company_id", value: companyID.uuidString)
                        .eq("analyses.kind", value: "photo")
                        .order("created_at", ascending: false)
                        .range(from: start, to: end)
                        .execute()
                        .value
                } else {
                    rows = try await supabase.client
                        .from("reports")
                        .select(select)
                        .eq("company_id", value: companyID.uuidString)
                        .order("created_at", ascending: false)
                        .range(from: start, to: end)
                        .execute()
                        .value
                }
            } else {
                if photoAnalysesOnly {
                    rows = try await supabase.client
                        .from("reports")
                        .select(select)
                        .eq("analyses.kind", value: "photo")
                        .order("created_at", ascending: false)
                        .range(from: start, to: end)
                        .execute()
                        .value
                } else {
                    rows = try await supabase.client
                        .from("reports")
                        .select(select)
                        .order("created_at", ascending: false)
                        .range(from: start, to: end)
                        .execute()
                        .value
                }
            }
            return rows
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    /// Free plandaki tek seferlik risk analizi tablosu deneme hakkını döndürür.
    func freeRiskAnalysisTrialUsage() async throws -> DailyQuotaUsage {
        guard supabase.currentUserID != nil else {
            throw AnalysisError.notAuthenticated
        }
        let used = try await countRiskAnalysisTrialReports() > 0 ? 1 : 0
        return DailyQuotaUsage(used: used, limit: 1)
    }

    @discardableResult
    func generateExcelReport(
        analysisID: UUID,
        method: RiskMethod,
        language: RDLanguage = .turkish,
        companyID: UUID? = nil,
        requestID: String,
        supportID: String
    ) async throws -> ReportRow {
        struct Body: Encodable {
            let analysis_id: String
            let method: String
            let report_kind: String
            let report_language: String
            let company_id: String?
            let client_app_version: String
            let client_app_build: String
            let client_platform: String
            let api_contract_version: Int
            let client_capabilities: [String: Bool]
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
            report_language: language.rawValue,
            company_id: companyID?.uuidString,
            client_app_version: Self.clientAppVersion,
            client_app_build: AppClientMetadata.appBuild,
            client_platform: AppClientMetadata.platform,
            api_contract_version: AppClientMetadata.apiContractVersion,
            client_capabilities: AppClientMetadata.capabilities,
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
            let message = payload.message.isEmpty ? RDLocalization.string("analysis.analysis.service.excel.raporu.olusturulamadi.cd2b864c", table: .analysis, fallback: "Excel raporu oluşturulamadı.") : payload.message
            Self.logger.error("Excel report invoke failed support=\(remoteSupportID, privacy: .public) request=\(requestID, privacy: .public) http=\(code) message=\(message, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.1.destek.kodu.2.aa38ed07", table: .analysis, fallback: "%1$@ Destek kodu: %2$@", arguments: [String(describing: message), String(describing: remoteSupportID)]))
        } catch {
            Self.logger.error("Excel report invoke failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.excel.raporu.olusturulamadi.destek.kodu.1.d244e651", table: .analysis, fallback: "Excel raporu oluşturulamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
        company: Company? = nil,
        requestID: String,
        supportID: String
    ) async throws -> ReportRow {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.error("Report read failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.dosyasi.okunamadi.destek.kodu.1.8fe80d5b", table: .analysis, fallback: "PDF dosyası okunamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        #if DEBUG
        if Self.isUITestMainLaunch {
            return ReportRow(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000d399")!,
                userID: userID,
                analysisID: bundle.analysis.id,
                companyID: company?.id,
                companySnapshot: company.map(CompanySnapshot.init(company:)),
                format: "pdf",
                kind: kind.rawValue,
                method: Self.databaseReportMethodValue(method),
                title: bundle.analysis.title,
                storagePath: "ui-test/reports/generated-\(kind.rawValue).pdf",
                fileName: "generated-\(kind.rawValue).pdf",
                mimeType: "application/pdf",
                fileSize: data.count,
                requestID: requestID,
                supportID: supportID,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        #endif

        let fileName = Self.safeReportFileName(
            for: bundle.analysis,
            kind: kind,
            method: method,
            requestID: requestID
        )
        let storagePath = "\(userID.uuidString.lowercased())/\(bundle.analysis.id.uuidString.lowercased())/\(fileName)"

        if ReportFailureSimulation.isEnabled(.storageUpload) {
            let error = ReportFailureSimulation.simulatedError(.storageUpload)
            Self.logger.error("Report upload simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) path=\(storagePath, privacy: .private(mask: .hash))")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.dosyasi.rapor.arsivine.yuklenemedi.destek.ko.44094f33", table: .analysis, fallback: "PDF dosyası rapor arşivine yüklenemedi. Destek kodu: %1$@. %2$@", arguments: [String(describing: supportID), String(describing: error.localizedDescription)]))
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
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.dosyasi.rapor.arsivine.yuklenemedi.destek.ko.91e9a238", table: .analysis, fallback: "PDF dosyası rapor arşivine yüklenemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        struct RegisterReportPayload: Encodable {
            let analysis_id: String
            let kind: String
            let method: String
            let report_language: String
            let title: String
            let storage_path: String
            let file_name: String
            let mime_type: String
            let file_size: Int
            let size_bytes: Int
            let page_count: Int
            let company_id: String?
            let findings_snapshot_json: [FindingRow]
            let photos_snapshot_json: [AnalysisPhotoRow]
            let analysis_edit_version: Int
            let generated_from_user_edited_findings: Bool
            let source_photo_count: Int
            let visible_findings_count: Int
            let client_app_version: String
            let client_app_build: String
            let client_platform: String
            let api_contract_version: Int
            let client_capabilities: [String: Bool]
            let request_id: String
            let support_id: String
        }

        let fileSize = data.count
        let payload = RegisterReportPayload(
            analysis_id: bundle.analysis.id.uuidString,
            kind: kind.rawValue,
            method: Self.databaseReportMethodValue(method),
            report_language: bundle.analysis.resolvedOutputLanguage.rawValue,
            title: bundle.analysis.title,
            storage_path: storagePath,
            file_name: fileName,
            mime_type: "application/pdf",
            file_size: fileSize,
            size_bytes: fileSize,
            page_count: Self.estimatedPageCount(for: kind, findingCount: bundle.findings.count),
            company_id: company?.id.uuidString,
            findings_snapshot_json: bundle.findings,
            photos_snapshot_json: bundle.photos,
            analysis_edit_version: bundle.analysis.analysisEditVersion ?? 0,
            generated_from_user_edited_findings: bundle.analysis.hasUserEdits == true,
            source_photo_count: bundle.analysis.photoCount ?? bundle.photos.count,
            visible_findings_count: bundle.findings.count,
            client_app_version: Self.clientAppVersion,
            client_app_build: AppClientMetadata.appBuild,
            client_platform: AppClientMetadata.platform,
            api_contract_version: AppClientMetadata.apiContractVersion,
            client_capabilities: AppClientMetadata.capabilities,
            request_id: requestID,
            support_id: supportID
        )

        if ReportFailureSimulation.isEnabled(.metadataInsert) {
            let error = ReportFailureSimulation.simulatedError(.metadataInsert)
            Self.logger.error("Report metadata simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.pdf.olusturuldu.ancak.rapor.arsiv.kaydi.tamamlan.6f67c1a8", table: .analysis, fallback: "PDF oluşturuldu ancak rapor arşiv kaydı tamamlanamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        do {
            let row: ReportRow = try await supabase.functions.invoke(
                RDConfig.registerReportFunctionName,
                options: FunctionInvokeOptions(body: payload)
            )
            return row
        } catch let FunctionsError.httpError(_, data) {
            let payload = Self.functionErrorPayload(from: data)
            let remoteSupportID = payload.supportID ?? supportID
            let message = payload.message.isEmpty ? RDLocalization.string("analysis.analysis.service.rapor.arsiv.kaydi.tamamlanamadi.5b477571", table: .analysis, fallback: "Rapor arşiv kaydı tamamlanamadı.") : payload.message
            Self.logger.error("Report metadata function failed support=\(remoteSupportID, privacy: .public) request=\(requestID, privacy: .public) message=\(message, privacy: .public)")
            do {
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.reports)
                    .remove(paths: [storagePath])
            } catch {
                Self.logger.error("Report orphan cleanup failed support=\(remoteSupportID, privacy: .public) request=\(requestID, privacy: .public) path=\(storagePath, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            }
            let joinedMessage = "\(payload.code ?? "") \(message)"
            if AppErrorMessage.isFreeRiskAnalysisTrialExhausted(joinedMessage) {
                throw AnalysisError.databaseFailed("free_risk_analysis_trial_exhausted:1/1\nDestek kodu: \(remoteSupportID)")
            }
            if AppErrorMessage.isReportQuotaExceeded(joinedMessage) {
                throw AnalysisError.databaseFailed("report_quota_exceeded\nDestek kodu: \(remoteSupportID)")
            }
            throw AnalysisError.databaseFailed(Self.appendSupportID(remoteSupportID, to: message))
        } catch {
            Self.logger.error("Report metadata save failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            do {
                _ = try await supabase.storage
                    .from(RDConfig.Bucket.reports)
                    .remove(paths: [storagePath])
            } catch {
                Self.logger.error("Report orphan cleanup failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) path=\(storagePath, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            }
            if AppErrorMessage.isFreeRiskAnalysisTrialExhausted(error.localizedDescription) {
                throw AnalysisError.databaseFailed("free_risk_analysis_trial_exhausted:1/1\nDestek kodu: \(supportID)")
            }
            if AppErrorMessage.isReportQuotaExceeded(error.localizedDescription) {
                throw AnalysisError.databaseFailed("report_quota_exceeded\nDestek kodu: \(supportID)")
            }
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.pdf.olusturuldu.ancak.rapor.arsiv.kaydi.tamamlan.6f67c1a8", table: .analysis, fallback: "PDF oluşturuldu ancak rapor arşiv kaydı tamamlanamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }
    }

    private func sendReportReadyNotificationIfPossible(
        reportID: UUID,
        requestID: String,
        supportID: String
    ) async {
        struct Body: Encodable {
            let report_id: String
            let request_id: String
            let support_id: String
        }

        do {
            try await supabase.functions.invoke(
                RDConfig.sendReportReadyNotificationFunctionName,
                options: FunctionInvokeOptions(
                    body: Body(
                        report_id: reportID.uuidString,
                        request_id: requestID,
                        support_id: supportID
                    )
                )
            )
        } catch {
            Self.logger.error("Report ready notification failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(reportID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func isTransientReportUploadError(_ error: Error) -> Bool {
        let lower = error.localizedDescription.lowercased(with: .autoupdatingCurrent)
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
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.raporu.indirilemedi.destek.kodu.1.3ab369c0", table: .analysis, fallback: "PDF raporu indirilemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        do {
            data = try await supabase.storage
                .from(RDConfig.Bucket.reports)
                .download(path: report.storagePath)
        } catch {
            Self.logger.error("Report download failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.raporu.indirilemedi.destek.kodu.1.3ab369c0", table: .analysis, fallback: "PDF raporu indirilemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        let safeName = report.fileName.isEmpty ? "RiskDetected_Report_\(report.id.uuidString.prefix(8)).pdf" : report.fileName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Self.logger.error("Report local file write failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.dosyasi.paylasim.icin.hazirlanamadi.destek.k.90ef78f6", table: .analysis, fallback: "PDF dosyası paylaşım için hazırlanamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }
    }

    /// Kullanıcının seçtiği tek PDF raporu ve ilişkili Storage dosyasını siler.
    func deleteReport(_ report: ReportRow, requestID: String, supportID: String) async throws {
        #if DEBUG
        if Self.isUITestMainLaunch {
            return
        }
        #endif

        if ReportFailureSimulation.isEnabled(.deleteStorage) {
            let error = ReportFailureSimulation.simulatedError(.deleteStorage)
            Self.logger.error("Report file delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.dosyasi.silinemedi.destek.kodu.1.b2852e2a", table: .analysis, fallback: "PDF dosyası silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        if ReportFailureSimulation.isEnabled(.deleteMetadata) {
            let error = ReportFailureSimulation.simulatedError(.deleteMetadata)
            Self.logger.error("Report metadata delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.pdf.rapor.kaydi.silinemedi.destek.kodu.1.fa03fd0c", table: .analysis, fallback: "PDF rapor kaydı silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        do {
            _ = try await supabase.storage
                .from(RDConfig.Bucket.reports)
                .remove(paths: [report.storagePath])
        } catch {
            Self.logger.error("Report file delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.dosyasi.silinemedi.destek.kodu.1.b2852e2a", table: .analysis, fallback: "PDF dosyası silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }

        do {
            try await supabase.client
                .from("reports")
                .delete()
                .eq("id", value: report.id.uuidString)
                .execute()
        } catch {
            Self.logger.error("Report metadata delete failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) report=\(report.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.pdf.rapor.kaydi.silinemedi.destek.kodu.1.fa03fd0c", table: .analysis, fallback: "PDF rapor kaydı silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
                    throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.analiz.fotograflari.silinemedi.destek.kodu.1.7a4387fe", table: .analysis, fallback: "Analiz fotoğrafları silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
                throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.analiz.kaydi.silinemedi.destek.kodu.1.5c6536ef", table: .analysis, fallback: "Analiz kaydı silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.analiz.silinemedi.destek.kodu.1.b4e76efb", table: .analysis, fallback: "Analiz silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
                throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.veri.disa.aktarimi.olusturulamadi.destek.kodu.1.49e26b28", table: .analysis, fallback: "Veri dışa aktarımı oluşturulamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
            }

            async let analyses = listAllAnalyses()
            async let findings = listAllFindings()
            async let photos = listAllPhotos()
            async let reports = listAllReports()

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
            var exportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RiskDetected-SensitiveExports", isDirectory: true)
            if FileManager.default.fileExists(atPath: exportDirectory.path) {
                try FileManager.default.removeItem(at: exportDirectory)
            }
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try exportDirectory.setResourceValues(resourceValues)

            let timestamp = DateFormatter.rdExportFileStamp.string(from: Date())
            let url = exportDirectory
                .appendingPathComponent("RiskDetected_Verilerim_\(String(userID.uuidString.prefix(8)))_\(timestamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch let error as AnalysisError {
            throw error
        } catch {
            Self.logger.error("Data export failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.veri.disa.aktarimi.olusturulamadi.destek.kodu.1.49e26b28", table: .analysis, fallback: "Veri dışa aktarımı oluşturulamadı. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }
    }

    func removeUserDataExport(at url: URL) {
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RiskDetected-SensitiveExports", isDirectory: true)
            .standardizedFileURL
        let candidate = url.standardizedFileURL
        let rootPrefix = exportRoot.path.hasSuffix("/") ? exportRoot.path : exportRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return }
        try? FileManager.default.removeItem(at: candidate)
    }

    /// Kullanıcının tüm PDF raporlarını ve Storage dosyalarını siler.
    func deleteAllReports(requestID: String, supportID: String) async throws {
        do {
            let reports = try await listAllReports()
            guard !reports.isEmpty else { return }

            let paths = reports.map(\.storagePath)

            if !paths.isEmpty {
                if DataActionFailureSimulation.isEnabled(.bulkReportDelete) {
                    let error = DataActionFailureSimulation.simulatedError(.bulkReportDelete)
                    Self.logger.error("Bulk report delete simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.pdf.rapor.dosyalari.silinemedi.destek.kodu.1.de15afb0", table: .analysis, fallback: "PDF rapor dosyaları silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.pdf.raporlari.silinemedi.destek.kodu.1.995cb4a0", table: .analysis, fallback: "PDF raporları silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }
    }

    /// Kullanıcının tüm analizlerini, ilişkili Storage dosyalarını ve cascade DB kayıtlarını siler.
    func deleteAllAnalyses(requestID: String, supportID: String) async throws {
        do {
            let analyses = try await listAllAnalyses()

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
                    throw AnalysisError.storageFailed(RDLocalization.format("analysis.analysis.service.analiz.fotograflari.silinemedi.destek.kodu.1.7a4387fe", table: .analysis, fallback: "Analiz fotoğrafları silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.analizler.silinemedi.destek.kodu.1.4c948c01", table: .analysis, fallback: "Analizler silinemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
        }
    }

    /// Hesap silme işlemini kullanıcı JWT'siyle doğrulanan Edge Function üzerinden başlatır.
    func requestAccountDeletion(userID: UUID, email: String?, requestID: String, supportID: String) async throws -> AccountDeletionRequestResult {
        struct Payload: Encodable {
            let email: String?
            let request_id: String
            let support_id: String
            let client_platform: String
            let app_language: String
        }

        let payload = Payload(
            email: email,
            request_id: requestID,
            support_id: supportID,
            client_platform: AppClientMetadata.platform,
            app_language: RDLanguage.current.rawValue
        )

        do {
            if DataActionFailureSimulation.isEnabled(.accountDeletionRequest) {
                let error = DataActionFailureSimulation.simulatedError(.accountDeletionRequest)
                Self.logger.error("Account deletion request simulation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.hesap.silme.talebi.kaydedilemedi.destek.kodu.1.e3953344", table: .analysis, fallback: "Hesap silme talebi kaydedilemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
            }

            let result: AccountDeletionRequestResult = try await supabase.functions.invoke(
                RDConfig.accountDeletionRequestFunctionName,
                options: FunctionInvokeOptions(body: payload)
            )
            guard result.shouldClearLocalSession else {
                let message = result.message ?? RDLocalization.string("analysis.analysis.service.hesap.silme.islemi.tamamlanamadi.a5017312", table: .analysis, fallback: "Hesap silme işlemi tamamlanamadı.")
                Self.logger.error("Account deletion request returned incomplete support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) user=\(userID.uuidString, privacy: .private(mask: .hash))")
                throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.1.destek.kodu.2.9ac9dfc0", table: .analysis, fallback: "%1$@ Destek kodu: %2$@", arguments: [String(describing: message), String(describing: supportID)]))
            }
            return result
        } catch let FunctionsError.httpError(_, data) {
            let payload = Self.functionErrorPayload(from: data)
            let remoteSupportID = payload.supportID ?? supportID
            let message = payload.message.isEmpty ? RDLocalization.string("analysis.analysis.service.hesap.silme.islemi.baslatilamadi.16a2d364", table: .analysis, fallback: "Hesap silme işlemi başlatılamadı.") : payload.message
            Self.logger.error("Account deletion request failed support=\(remoteSupportID, privacy: .public) request=\(requestID, privacy: .public) user=\(userID.uuidString, privacy: .private(mask: .hash)) message=\(message, privacy: .public)")
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.1.destek.kodu.2.aa38ed07", table: .analysis, fallback: "%1$@ Destek kodu: %2$@", arguments: [String(describing: message), String(describing: remoteSupportID)]))
        } catch {
            Self.logger.error("Account deletion request failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) user=\(userID.uuidString, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed(RDLocalization.format("analysis.analysis.service.hesap.silme.talebi.kaydedilemedi.destek.kodu.1.e3953344", table: .analysis, fallback: "Hesap silme talebi kaydedilemedi. Destek kodu: %1$@", arguments: [String(describing: supportID)]))
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

    /// Free kullanıcı için bugünkü ücretsiz standart analiz kullanımını verir.
    /// Kullanım, silinebilir analiz kayıtlarından değil kalıcı quota ledger'ından okunur.
    func dailyQuotaUsage() async throws -> DailyQuotaUsage {
        if DataActionFailureSimulation.isEnabled(.quotaExceeded) {
            return DailyQuotaUsage(
                used: Self.freeDailyLimit,
                limit: Self.freeDailyLimit
            )
        }
        guard let userID = supabase.currentUserID else {
            throw AnalysisError.notAuthenticated
        }
        let dayStart = Self.istanbulStartOfTodayISO()

        let used = try await countRows(
            table: "usage_events",
            filters: {
                $0.eq("user_id", value: userID.uuidString)
                    .in("feature", values: ["analysis_standard", "analysis_detailed"])
                    .in("event_type", values: ["reserved", "completed"])
                    .gte("created_at", value: dayStart)
            }
        )

        return DailyQuotaUsage(
            used: used,
            limit: Self.freeDailyLimit
        )
    }

    /// Kullanıcının rapor kotası kullanımını verir. Free standart rapor hakkı günlük,
    /// paid plan rapor hakları aylık takip edilir.
    func monthlyReportQuotaUsage(tier: SubscriptionTier) async throws -> DailyQuotaUsage {
        guard let userID = supabase.currentUserID else {
            throw AnalysisError.notAuthenticated
        }
        let periodStart = tier == .free
            ? Self.istanbulStartOfTodayISO()
            : Self.istanbulStartOfCurrentMonthISO()

        let used = try await countRows(
            table: "usage_events",
            filters: {
                $0.eq("user_id", value: userID.uuidString)
                    .eq("feature", value: "report_standard")
                    .eq("event_type", value: "completed")
                    .gte("created_at", value: periodStart)
            }
        )

        return DailyQuotaUsage(
            used: used,
            limit: Self.monthlyReportLimit(for: tier)
        )
    }

    // MARK: - Private steps

    nonisolated private static let maxInlinePhotoBytes = 1_500_000
    nonisolated private static let maxInlinePhotoBase64Bytes = 2_100_000
    nonisolated private static let maxInlinePhotoPayloadBytes = 5_500_000

    private static func istanbulStartOfTodayISO() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = RDConfig.Quota.businessTimeZone
        let startOfDay = calendar.startOfDay(for: Date())

        return isoString(from: startOfDay)
    }

    private static func istanbulStartOfCurrentMonthISO() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = RDConfig.Quota.businessTimeZone
        let components = calendar.dateComponents([.year, .month], from: Date())
        let startOfMonth = calendar.date(from: components) ?? calendar.startOfDay(for: Date())
        return isoString(from: startOfMonth)
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func monthlyReportLimit(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return 1
        case .plus: return 150
        case .pro: return 750
        }
    }

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

    private func countRiskAnalysisTrialReports(since periodStart: String? = nil) async throws -> Int {
        guard let userID = supabase.currentUserID else {
            throw AnalysisError.notAuthenticated
        }
        return try await countRows(
            table: "usage_events",
            filters: { builder in
                var filtered = builder
                    .eq("user_id", value: userID.uuidString)
                    .eq("feature", value: "report_risk_analysis_trial")
                    .eq("event_type", value: "completed")
                if let periodStart {
                    filtered = filtered.gte("created_at", value: periodStart)
                }
                return filtered
            }
        )
    }

    private func listAllReports(pageSize: Int = 500) async throws -> [ReportRow] {
        var offset = 0
        var allRows: [ReportRow] = []

        while true {
            let rows = try await listReports(limit: pageSize, offset: offset)
            allRows.append(contentsOf: rows)
            guard rows.count == pageSize else { break }
            offset += pageSize
        }

        return allRows
    }

    private func listAllAnalyses(pageSize: Int = 500) async throws -> [AnalysisRow] {
        var offset = 0
        var allRows: [AnalysisRow] = []

        while true {
            let rows: [AnalysisRow] = try await supabase.client
                .from("analyses")
                .select()
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            allRows.append(contentsOf: rows)
            guard rows.count == pageSize else { break }
            offset += pageSize
        }

        return allRows
    }

    private func listAllFindings(pageSize: Int = 500) async throws -> [FindingRow] {
        var offset = 0
        var allRows: [FindingRow] = []

        while true {
            let rows: [FindingRow] = try await supabase.client
                .from("findings")
                .select()
                .order("ordinal", ascending: true)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            allRows.append(contentsOf: rows)
            guard rows.count == pageSize else { break }
            offset += pageSize
        }

        return allRows
    }

    private func listAllPhotos(pageSize: Int = 500) async throws -> [AnalysisPhotoRow] {
        var offset = 0
        var allRows: [AnalysisPhotoRow] = []

        while true {
            let rows: [AnalysisPhotoRow] = try await supabase.client
                .from("photos")
                .select("analysis_id,storage_path,width,height,mime_type")
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            allRows.append(contentsOf: rows)
            guard rows.count == pageSize else { break }
            offset += pageSize
        }

        return allRows
    }

    private func createAnalysis(
        userID: UUID,
        kind: String,
        canvases: [AnalysisCanvas],
        title: String,
        textInput: String?,
        companyID: UUID?,
        analysisSector: AnalysisSectorID?,
        localization: RDAnalysisLocalizationRequest?
    ) async throws -> UUID {
        struct InsertPayload: Encodable {
            let user_id: String
            let kind: String
            let canvas: String
            let title: String
            let text_input: String?
            let company_id: String?
            let status: String
            let analysis_sector: String?
            let analysis_sector_source: String?
            let analysis_sector_prompt_version: String?
            let primary_method: String?
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
            company_id: companyID?.uuidString,
            status: "pending",
            analysis_sector: analysisSector?.rawValue,
            analysis_sector_source: analysisSector == nil ? nil : "user_selected",
            analysis_sector_prompt_version: analysisSector == nil ? nil : AnalysisSectorID.activeAnalysisPromptVersion,
            primary_method: localization?.method.rawValue
        )
        do {
            let row: AnalysisRow = try await Self.withTimeout(
                nanoseconds: Self.analysisRecordCreationTimeoutNanoseconds,
                timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.kaydi.baslatilirken.baglanti.zaman.asimin.cbbfd8a2", table: .analysis, fallback: "Analiz kaydı başlatılırken bağlantı zaman aşımına uğradı. Lütfen bağlantını kontrol edip tekrar dene."))
            ) {
                try await self.supabase.client
                    .from("analyses")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                    .value
            }
            return row.id
        } catch let error as AnalysisError {
            throw error
        } catch {
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    private final class TimeoutRaceState<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var didFinish = false
        private var continuation: CheckedContinuation<T, Error>?
        private var operationTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        func setContinuation(_ continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            if didFinish {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func setTasks(operationTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
            lock.lock()
            if didFinish {
                lock.unlock()
                operationTask.cancel()
                timeoutTask.cancel()
                return
            }
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
            lock.unlock()
        }

        func finish(_ result: Result<T, Error>) {
            let continuation: CheckedContinuation<T, Error>?
            let operationTask: Task<Void, Never>?
            let timeoutTask: Task<Void, Never>?

            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            continuation = self.continuation
            operationTask = self.operationTask
            timeoutTask = self.timeoutTask
            self.continuation = nil
            self.operationTask = nil
            self.timeoutTask = nil
            lock.unlock()

            operationTask?.cancel()
            timeoutTask?.cancel()

            switch result {
            case .success(let value):
                continuation?.resume(returning: value)
            case .failure(let error):
                continuation?.resume(throwing: error)
            }
        }
    }

    private static func withTimeout<T>(
        nanoseconds: UInt64,
        timeoutError: Error,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let state = TimeoutRaceState<T>()
        return try await withCheckedThrowingContinuation { continuation in
            state.setContinuation(continuation)
            let operationTask = Task {
                do {
                    state.finish(.success(try await operation()))
                } catch {
                    state.finish(.failure(error))
                }
            }
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                    state.finish(.failure(timeoutError))
                } catch {
                    state.finish(.failure(error))
                }
            }
            state.setTasks(operationTask: operationTask, timeoutTask: timeoutTask)
        }
    }

    private struct InlinePhotoPart: Encodable, Sendable {
        let mime_type: String
        let data: String
        let width: Int
        let height: Int
        let decoded_byte_count: Int
        let jpeg_quality: Double
        let quality_policy: String
        let max_dimension: Int
        let client_photo_id: String
        let sequence_index: Int

        var encodedByteCount: Int {
            data.utf8.count
        }
    }

    private struct PreparedAnalysisPhoto: Sendable {
        let data: Data
        let width: Int
        let height: Int
        let decodedByteCount: Int
        let encodedByteCount: Int
        let jpegQuality: Double
        let qualityPolicy: String
        let maxDimension: Int
        let clientPhotoID: String
        let sequenceIndex: Int
    }

    private struct StoredAnalysisPhotoInsert: Encodable {
        let analysis_id: String
        let user_id: String
        let storage_path: String
        let width: Int
        let height: Int
        let size_bytes: Int
        let byte_size: Int
        let mime_type: String
        let sequence_index: Int
        let client_photo_id: String
        let is_primary: Bool
        let upload_payload_version: String
        let compression_metadata: PhotoCompressionMetadata
    }

    private struct PhotoCompressionMetadata: Encodable {
        let jpeg_quality: Double
        let quality_policy: String
        let max_dimension: Int
        let encoded_byte_count: Int
        let storage_strategy: String
    }

    private struct PhotoCompressionCandidate: Sendable {
        let maxDimension: Int
        let jpegQuality: Double
    }

    nonisolated private static let analysisPhotoQualityPolicy = "balanced-v3-1536-floor1024"
    nonisolated private static let analysisPhotoCompressionCandidates: [PhotoCompressionCandidate] = [
        .init(maxDimension: 1536, jpegQuality: 0.78),
        .init(maxDimension: 1536, jpegQuality: 0.70),
        .init(maxDimension: 1400, jpegQuality: 0.76),
        .init(maxDimension: 1400, jpegQuality: 0.68),
        .init(maxDimension: 1200, jpegQuality: 0.72),
        .init(maxDimension: 1200, jpegQuality: 0.62),
        .init(maxDimension: 1024, jpegQuality: 0.68),
        .init(maxDimension: 1024, jpegQuality: 0.60),
        .init(maxDimension: 1024, jpegQuality: 0.52)
    ]

    nonisolated private static func makePreparedJPEGPhotos(from images: [UIImage]) async throws -> [PreparedAnalysisPhoto] {
        try await Task.detached(priority: .userInitiated) {
            var photos: [PreparedAnalysisPhoto] = []
            photos.reserveCapacity(images.count)
            var totalPayloadBytes = 0
            let photoCount = max(images.count, 1)
            let adaptiveMaxEncodedBytes = min(
                maxInlinePhotoBase64Bytes,
                maxInlinePhotoPayloadBytes / photoCount
            )
            let adaptiveMaxDecodedBytes = min(
                maxInlinePhotoBytes,
                max(450_000, Int(Double(adaptiveMaxEncodedBytes) * 0.72))
            )

            for (index, image) in images.enumerated() {
                let photo = try autoreleasepool {
                    try preparedJPEGPhoto(
                        from: image,
                        sequenceIndex: index + 1,
                        maxEncodedBytes: adaptiveMaxEncodedBytes,
                        maxDecodedBytes: adaptiveMaxDecodedBytes
                    )
                }
                let projectedPayloadBytes = totalPayloadBytes + photo.encodedByteCount
                if projectedPayloadBytes > maxInlinePhotoPayloadBytes {
                    throw AnalysisError.invalidInput(RDLocalization.string("analysis.analysis.service.fotograf.paketi.cok.buyuk.kaliteyi.korumak.icin..410a35fa", table: .analysis, fallback: "Fotoğraf paketi çok büyük. Kaliteyi korumak için lütfen daha az fotoğraf seçerek tekrar dene."))
                }
                totalPayloadBytes = projectedPayloadBytes
                photos.append(photo)
            }

            return photos
        }.value
    }

    nonisolated private static func preparedJPEGPhoto(
        from image: UIImage,
        sequenceIndex: Int,
        maxEncodedBytes: Int,
        maxDecodedBytes: Int
    ) throws -> PreparedAnalysisPhoto {
        for candidate in analysisPhotoCompressionCandidates {
            let normalized = image.sanitizedForAnalysis(maxDimension: CGFloat(candidate.maxDimension))
            guard let data = normalized.image.jpegData(compressionQuality: CGFloat(candidate.jpegQuality)) else {
                continue
            }
            guard data.count <= maxDecodedBytes else { continue }

            let encodedByteCount = base64EncodedByteCount(for: data.count)
            guard encodedByteCount <= maxEncodedBytes else { continue }

            let photo = SanitizedPhoto(data: data, size: normalized.size)
            return PreparedAnalysisPhoto(
                data: data,
                width: photo.width,
                height: photo.height,
                decodedByteCount: data.count,
                encodedByteCount: encodedByteCount,
                jpegQuality: candidate.jpegQuality,
                qualityPolicy: analysisPhotoQualityPolicy,
                maxDimension: candidate.maxDimension,
                clientPhotoID: UUID().uuidString,
                sequenceIndex: sequenceIndex
            )
        }

        throw AnalysisError.invalidInput(RDLocalization.string("analysis.analysis.service.fotograf.dosyasi.analiz.icin.cok.buyuk.kaliteyi..66137a94", table: .analysis, fallback: "Fotoğraf dosyası analiz için çok büyük. Kaliteyi korumak için lütfen daha küçük bir görsel veya daha az fotoğraf seç."))
    }

    nonisolated private static func base64EncodedByteCount(for byteCount: Int) -> Int {
        ((byteCount + 2) / 3) * 4
    }

    private func uploadPhotosForAnalysis(
        userID: UUID,
        analysisID: UUID,
        photos: [PreparedAnalysisPhoto]
    ) async throws -> [String] {
        var uploadedPaths: [String] = []
        uploadedPaths.reserveCapacity(photos.count)
        let userPath = userID.uuidString.lowercased()
        let analysisPath = analysisID.uuidString.lowercased()
        let plannedPaths = photos
            .sorted(by: { $0.sequenceIndex < $1.sequenceIndex })
            .map { "\(userPath)/\(analysisPath)/p\($0.sequenceIndex).jpg" }

        do {
            for photo in photos.sorted(by: { $0.sequenceIndex < $1.sequenceIndex }) {
                let storagePath = "\(userPath)/\(analysisPath)/p\(photo.sequenceIndex).jpg"
                do {
                    _ = try await Self.withTimeout(
                        nanoseconds: Self.analysisPhotoUploadTimeoutNanoseconds,
                        timeoutError: AnalysisError.storageFailed(RDLocalization.string("analysis.analysis.service.fotograf.yuklenirken.baglanti.zaman.asimina.ugra.5316c341", table: .analysis, fallback: "Fotoğraf yüklenirken bağlantı zaman aşımına uğradı. Lütfen bağlantını kontrol edip tekrar dene."))
                    ) {
                        try await self.supabase.storage
                            .from(RDConfig.Bucket.photos)
                            .upload(
                                storagePath,
                                data: photo.data,
                                options: FileOptions(contentType: "image/jpeg", upsert: true)
                            )
                    }
                    uploadedPaths.append(storagePath)
                } catch let error as AnalysisError {
                    throw error
                } catch {
                    throw AnalysisError.storageFailed(error.localizedDescription)
                }

                let insert = StoredAnalysisPhotoInsert(
                    analysis_id: analysisID.uuidString,
                    user_id: userID.uuidString,
                    storage_path: storagePath,
                    width: photo.width,
                    height: photo.height,
                    size_bytes: photo.decodedByteCount,
                    byte_size: photo.decodedByteCount,
                    mime_type: "image/jpeg",
                    sequence_index: photo.sequenceIndex,
                    client_photo_id: photo.clientPhotoID,
                    is_primary: photo.sequenceIndex == 1,
                    upload_payload_version: "photo-batch-storage-v1",
                    compression_metadata: PhotoCompressionMetadata(
                        jpeg_quality: photo.jpegQuality,
                        quality_policy: photo.qualityPolicy,
                        max_dimension: photo.maxDimension,
                        encoded_byte_count: photo.encodedByteCount,
                        storage_strategy: "client-storage-paths-v1"
                    )
                )

                do {
                    _ = try await Self.withTimeout(
                        nanoseconds: Self.analysisPhotoMetadataTimeoutNanoseconds,
                        timeoutError: AnalysisError.databaseFailed(RDLocalization.string("analysis.analysis.service.fotograf.bilgisi.kaydedilirken.baglanti.zaman.as.c3a91d7f", table: .analysis, fallback: "Fotoğraf bilgisi kaydedilirken bağlantı zaman aşımına uğradı. Lütfen tekrar dene."))
                    ) {
                        try await self.supabase.client
                            .from("photos")
                            .insert(insert)
                            .execute()
                    }
                } catch let error as AnalysisError {
                    throw error
                } catch {
                    throw AnalysisError.databaseFailed(error.localizedDescription)
                }
            }

            return uploadedPaths
        } catch {
            await cleanupUploadedPhotos(
                userID: userID,
                analysisID: analysisID,
                paths: Array(Set(uploadedPaths + plannedPaths)).sorted(),
                supportID: AppErrorMessage.newSupportID()
            )
            throw error
        }
    }

    private func cleanupUploadedPhotos(
        userID: UUID,
        analysisID: UUID,
        paths: [String],
        supportID: String
    ) async {
        do {
            try await Self.withTimeout(
                nanoseconds: Self.analysisPhotoCleanupTimeoutNanoseconds,
                timeoutError: AnalysisError.storageFailed(RDLocalization.string("analysis.analysis.service.fotograf.temizligi.zaman.asimina.ugradi.8959411e", table: .analysis, fallback: "Fotoğraf temizliği zaman aşımına uğradı."))
            ) {
                if !paths.isEmpty {
                    _ = try await self.supabase.storage
                        .from(RDConfig.Bucket.photos)
                        .remove(paths: paths)
                }

                _ = try await self.supabase.client
                    .from("photos")
                    .delete()
                    .eq("analysis_id", value: analysisID.uuidString)
                    .eq("user_id", value: userID.uuidString)
                    .execute()
            }
        } catch {
            Self.logger.error("Photo upload cleanup skipped analysis=\(analysisID.uuidString, privacy: .public) support=\(supportID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func invokeAnalyze(
        analysisID: UUID,
        canvases: [AnalysisCanvas],
        textInput: String?,
        companyID: UUID?,
        analysisSector: AnalysisSectorID?,
        localization: RDAnalysisLocalizationRequest?,
        photoPaths: [String],
        photoBase64Parts: [InlinePhotoPart],
        requestID: String,
        supportID: String,
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)?
    ) async throws {
        struct Body: Encodable {
            let analysis_id: String
            let canvas: String
            let canvases: [String]
            let analysis_mode: String
            let text_input: String?
            let request_id: String
            let support_id: String
            let company_id: String?
            let analysis_sector: String?
            let analysis_sector_source: String?
            let analysis_sector_prompt_version: String?
            let app_language: String
            let output_language: String?
            let output_locale: String?
            let work_jurisdiction_country: String?
            let work_jurisdiction_region: String?
            let safety_profile_id: String?
            let safety_profile_version: Int?
            let method: String?
            let photo_paths: [String]
            let photo_base64_parts: [InlinePhotoPart]
            let client_app_version: String
            let client_app_build: String
            let client_platform: String
            let api_contract_version: Int
            let client_capabilities: [String: Bool]
        }
        // `canvas` = primary sorted id (tek-canvas contract).
        // `canvases` = tüm seçimler — Edge Function çoklu desteğe geçince kullanılır.
        let sortedCanvasIDs = canvases.map(\.id).sorted()
        let analysisMode = Self.analysisMode(for: canvases)
        let body = Body(
            analysis_id: analysisID.uuidString.lowercased(),
            canvas: sortedCanvasIDs.first ?? canvases[0].id,
            canvases: sortedCanvasIDs,
            analysis_mode: analysisMode,
            text_input: textInput,
            request_id: requestID,
            support_id: supportID,
            company_id: companyID?.uuidString,
            analysis_sector: analysisSector?.rawValue,
            analysis_sector_source: analysisSector == nil ? nil : "user_selected",
            analysis_sector_prompt_version: analysisSector == nil ? nil : AnalysisSectorID.activeAnalysisPromptVersion,
            app_language: RDLanguage.current.rawValue,
            output_language: localization?.outputLanguage.rawValue,
            output_locale: localization?.outputLocale.rawValue,
            work_jurisdiction_country: localization?.workJurisdictionCountry.rawValue,
            work_jurisdiction_region: localization?.workJurisdictionRegion,
            safety_profile_id: localization?.safetyProfileID.rawValue,
            safety_profile_version: localization?.safetyProfileVersion,
            method: localization?.method.rawValue,
            photo_paths: photoPaths,
            photo_base64_parts: photoBase64Parts,
            client_app_version: Self.clientAppVersion,
            client_app_build: AppClientMetadata.appBuild,
            client_platform: AppClientMetadata.platform,
            api_contract_version: AppClientMetadata.apiContractVersion,
            client_capabilities: AppClientMetadata.capabilities
        )
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                try await Self.withTimeout(
                    nanoseconds: Self.analysisSubmissionTimeoutNanoseconds,
                    timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.istegi.sunucuya.gonderilirken.baglanti.za.f977e5d0", table: .analysis, fallback: "Analiz isteği sunucuya gönderilirken bağlantı zaman aşımına uğradı. Lütfen bağlantını kontrol edip tekrar dene."))
                ) {
                    try await self.supabase.functions.invoke(
                        RDConfig.analyzeFunctionName,
                        options: FunctionInvokeOptions(body: body)
                    )
                }
                onProgress?(.queued)
                return
            } catch let FunctionsError.httpError(code, data) {
                let payload = Self.functionErrorPayload(from: data)
                let msg = payload.message
                let errorCode = payload.code ?? ""
                let remoteSupportID = payload.supportID ?? supportID

                if code == 429,
                   msg.localizedCaseInsensitiveContains("günlük kota") || msg.localizedCaseInsensitiveContains("analiz/gün") || errorCode == "quota_exceeded" {
                    let fallbackMessage = msg.isEmpty ? RDLocalization.string("analysis.analysis.service.analiz.kotan.doldu.cf5ccd2e", table: .analysis, fallback: "Analiz kotan doldu.") : msg
                    throw AnalysisError.quotaExceeded(message: Self.appendSupportID(remoteSupportID, to: fallbackMessage), tier: payload.tier ?? "free")
                }
                if code == 409 {
                    throw AnalysisError.alreadyCompleted
                }
                if errorCode == "PHOTO_LIMIT_EXCEEDED" {
                    let fallbackMessage = msg.isEmpty ? RDLocalization.string("analysis.analysis.service.bu.plan.icin.fotograf.limiti.asildi.07089206", table: .analysis, fallback: "Bu plan için fotoğraf limiti aşıldı.") : msg
                    throw AnalysisError.invalidInput(Self.appendSupportID(remoteSupportID, to: fallbackMessage))
                }
                if errorCode == "OUTPUT_LANGUAGE_CONTRACT_FAILED" {
                    let localizedMessage = RDLocalization.string(
                        "analysis.analysis.service.output.language.contract.failed",
                        table: .analysis,
                        fallback: "Analiz, seçilen çıktı diliyle güvenli biçimde tamamlanamadı. Lütfen tekrar dene."
                    )
                    throw AnalysisError.aiFailed(
                        Self.appendSupportID(remoteSupportID, to: localizedMessage)
                    )
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
                    throw AnalysisError.aiFailed(messageWithSupport.isEmpty ? Self.appendSupportID(remoteSupportID, to: RDLocalization.string("analysis.analysis.service.gemini.kotasi.doldu.lutfen.daha.sonra.tekrar.den.1495b164", table: .analysis, fallback: "Gemini kotası doldu. Lütfen daha sonra tekrar dene.")) : messageWithSupport)
                case 503:
                    throw AnalysisError.aiFailed(messageWithSupport.isEmpty ? Self.appendSupportID(remoteSupportID, to: RDLocalization.string("analysis.analysis.service.gemini.modeli.su.anda.yogun.biraz.sonra.tekrar.d.a4d34a5c", table: .analysis, fallback: "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene.")) : messageWithSupport)
                default:
                    throw AnalysisError.aiFailed(messageWithSupport.isEmpty ? Self.appendSupportID(remoteSupportID, to: "HTTP \(code)") : messageWithSupport)
                }
            } catch {
                if attempt < maxAttempts {
                    onProgress?(.retryingNetwork)
                    Self.logger.info("Analyze invoke network retry support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) attempt=\(attempt) error=\(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                let fallbackMessage = photoBase64Parts.isEmpty
                    ? RDLocalization.string("analysis.analysis.service.analiz.istegi.sunucuya.gonderilemedi.ag.baglanti.31e2f63b", table: .analysis, fallback: "Analiz isteği sunucuya gönderilemedi. Ağ bağlantısı kesildi veya istek zaman aşımına uğradı. Lütfen bağlantını kontrol edip tekrar dene.")
                    : RDLocalization.string("analysis.analysis.service.fotograf.paketi.sunucuya.gonderilemedi.ag.baglan.c2b4ccc1", table: .analysis, fallback: "Fotoğraf paketi sunucuya gönderilemedi. Ağ bağlantısı kesildi veya istek zaman aşımına uğradı. Lütfen bağlantını kontrol edip tekrar dene.")
                throw AnalysisError.networkFailed(Self.appendSupportID(supportID, to: fallbackMessage))
            }
        }
    }

    private struct AnalysisSubmissionFailurePatch: Encodable {
        let status: String
        let status_message: String
    }

    private struct AnalysisStatusSnapshot: Decodable {
        let status: String
        let findingCount: Int?
        let photoCount: Int?
        let statusMessage: String?
        let queuedAt: String?
        let workerStartedAt: String?
        let completedAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case status
            case findingCount = "finding_count"
            case photoCount = "photo_count"
            case statusMessage = "status_message"
            case queuedAt = "queued_at"
            case workerStartedAt = "worker_started_at"
            case completedAt = "completed_at"
            case updatedAt = "updated_at"
        }
    }

    private func fetchAnalysisSubmissionStatus(analysisID: UUID) async throws -> String {
        try await fetchAnalysisStatusSnapshot(analysisID: analysisID).status
    }

    private func fetchAnalysisStatusSnapshot(analysisID: UUID) async throws -> AnalysisStatusSnapshot {
        try await Self.withTimeout(
            nanoseconds: Self.analysisSubmissionCleanupTimeoutNanoseconds,
            timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.durumu.kontrol.edilirken.baglanti.zaman.a.ad467eeb", table: .analysis, fallback: "Analiz durumu kontrol edilirken bağlantı zaman aşımına uğradı."))
        ) {
            try await self.supabase.client
                .from("analyses")
                .select("status,finding_count,photo_count,status_message,queued_at,worker_started_at,completed_at,updated_at")
                .eq("id", value: analysisID.uuidString)
                .single()
                .execute()
                .value
        }
    }

    private func recoverPhotoSubmissionIfServerAccepted(
        analysisID: UUID,
        userID: UUID,
        uploadedPhotoPaths: [String],
        supportID: String,
        error: Error,
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)?
    ) async -> Bool {
        let probeDelays: [UInt64] = [
            2_000_000_000,
            3_000_000_000,
            5_000_000_000
        ]

        var lastStatus: String?
        var lastProbeError: Error?
        for delay in probeDelays {
            try? await Task.sleep(nanoseconds: delay)
            do {
                let status = try await fetchAnalysisSubmissionStatus(analysisID: analysisID)
                lastStatus = status
                guard status == "pending" else {
                    Self.logger.info("Analyze invoke error recovered by DB status analysis=\(analysisID.uuidString, privacy: .public) support=\(supportID, privacy: .public) status=\(status, privacy: .public)")
                    onProgress?(status == "analyzing" ? .analyzing : .queued)
                    return true
                }
            } catch {
                lastProbeError = error
                Self.logger.error("Analyze invoke recovery status probe failed analysis=\(analysisID.uuidString, privacy: .public) support=\(supportID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        guard lastStatus == "pending" else {
            if let lastProbeError {
                Self.logger.error("Analyze invoke recovery skipped cleanup after unknown status analysis=\(analysisID.uuidString, privacy: .public) support=\(supportID, privacy: .public) error=\(lastProbeError.localizedDescription, privacy: .public)")
            }
            return false
        }

        await cleanupUploadedPhotos(
            userID: userID,
            analysisID: analysisID,
            paths: uploadedPhotoPaths,
            supportID: supportID
        )
        await markAnalysisSubmissionFailedIfStillPending(
            analysisID: analysisID,
            supportID: supportID,
            error: error,
            delayBeforeCheck: false
        )
        return false
    }

    @discardableResult
    private func markAnalysisSubmissionFailedIfStillPending(
        analysisID: UUID,
        supportID: String,
        error: Error,
        delayBeforeCheck: Bool = true
    ) async -> Bool {
        if delayBeforeCheck {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        do {
            let status = try await fetchAnalysisSubmissionStatus(analysisID: analysisID)
            guard status == "pending" else { return false }

            let message = Self.submissionFailureStatusMessage(error: error, supportID: supportID)
            try await Self.withTimeout(
                nanoseconds: Self.analysisSubmissionCleanupTimeoutNanoseconds,
                timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.hata.durumu.guncellenirken.baglanti.zaman.37c7975a", table: .analysis, fallback: "Analiz hata durumu güncellenirken bağlantı zaman aşımına uğradı."))
            ) {
                _ = try await self.supabase.client
                    .from("analyses")
                    .update(AnalysisSubmissionFailurePatch(status: "failed", status_message: message))
                    .eq("id", value: analysisID.uuidString)
                    .eq("status", value: "pending")
                    .execute()
            }
            return true
        } catch {
            Self.logger.error("Analysis submission failure mark skipped analysis=\(analysisID.uuidString, privacy: .public) support=\(supportID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func submissionFailureStatusMessage(error: Error, supportID: String) -> String {
        let message: String
        if let analysisError = error as? AnalysisError {
            switch analysisError {
            case .networkFailed(let text), .aiFailed(let text), .storageFailed(let text), .databaseFailed(let text), .invalidInput(let text):
                message = text
            case .quotaExceeded(let text, _):
                message = text
            case .alreadyCompleted:
                message = RDLocalization.string("analysis.analysis.service.bu.analiz.zaten.tamamlanmis.ca77e711", table: .analysis, fallback: "Bu analiz zaten tamamlanmış.")
            case .notAuthenticated:
                message = RDLocalization.string("analysis.analysis.service.kullanici.oturumu.bulunamadi.83ff7aa4", table: .analysis, fallback: "Kullanıcı oturumu bulunamadı.")
            }
        } else {
            message = error.localizedDescription
        }
        return appendSupportID(supportID, to: message)
    }

    private static func analysisMode(for canvases: [AnalysisCanvas]) -> String {
        canvases.contains { $0.isPaid } ? "detailed" : "standard"
    }

    private func waitForCompletedResult(
        analysisID: UUID,
        photoCount: Int? = nil,
        onProgress: (@MainActor (AnalysisProgressUpdate) -> Void)?
    ) async throws -> AnalysisResultBundle {
        let startedAt = Date()
        let storedPhotoCount = InFlightAnalysisStore.shared.load()?.analysisID == analysisID
            ? InFlightAnalysisStore.shared.load()?.photoCount
            : nil
        var deadlineSeconds: TimeInterval = ((photoCount ?? storedPhotoCount ?? 0) > 1) ? 420 : 300
        var lastReportedStatus: String?
        var consecutivePollFailures = 0

        while Date().timeIntervalSince(startedAt) < deadlineSeconds {
            try Task.checkCancellation()
            let snapshot: AnalysisStatusSnapshot

            do {
                snapshot = try await fetchAnalysisStatusSnapshot(analysisID: analysisID)
                if (snapshot.photoCount ?? 0) > 1 {
                    deadlineSeconds = 420
                }
                consecutivePollFailures = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                consecutivePollFailures += 1
                onProgress?(.retryingNetwork)
                lastReportedStatus = "retryingNetwork"
                Self.logger.error("Analysis status poll failed analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")

                let delaySeconds = min(2 + consecutivePollFailures, 8)
                try await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                continue
            }

            switch snapshot.status {
            case "completed":
                if lastReportedStatus != snapshot.status {
                    onProgress?(.finalizingResult)
                    lastReportedStatus = snapshot.status
                }
                let bundle = try await fetchCompletedResult(
                    analysisID: analysisID,
                    statusSnapshot: snapshot
                )
                InFlightAnalysisStore.shared.clear(analysisID: analysisID)
                return bundle
            case "failed":
                InFlightAnalysisStore.shared.clear(analysisID: analysisID)
                throw AnalysisError.aiFailed(snapshot.statusMessage ?? RDLocalization.string("analysis.analysis.service.analiz.arka.planda.tamamlanamadi.lutfen.tekrar.d.6ddc19ce", table: .analysis, fallback: "Analiz arka planda tamamlanamadı. Lütfen tekrar dene."))
            case "queued", "pending", "analyzing":
                if lastReportedStatus != snapshot.status {
                    onProgress?(snapshot.status == "analyzing" ? .analyzing : .queued)
                    lastReportedStatus = snapshot.status
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            default:
                Self.logger.error("Analysis status poll returned unknown status analysis=\(analysisID.uuidString, privacy: .public) status=\(snapshot.status, privacy: .public)")
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        throw AnalysisError.aiFailed(RDLocalization.string("analysis.analysis.service.analiz.arka.planda.devam.ediyor.tamamlandiginda..a1f01fa4", table: .analysis, fallback: "Analiz arka planda devam ediyor. Tamamlandığında bildirim göndereceğiz; sonucu Geçmiş analizler ekranından açabilirsin."))
    }

    private func fetchResult(analysisID: UUID) async throws -> AnalysisResultBundle {
        let core = try await fetchResultCore(analysisID: analysisID, expectedFindingCount: nil)
        return await hydrateResultBundle(
            analysisID: analysisID,
            analysis: core.analysis,
            findings: core.findings
        )
    }

    private func fetchCompletedResult(
        analysisID: UUID,
        statusSnapshot: AnalysisStatusSnapshot
    ) async throws -> AnalysisResultBundle {
        let core = try await fetchResultCore(
            analysisID: analysisID,
            expectedFindingCount: statusSnapshot.findingCount
        )
        return await hydrateResultBundle(
            analysisID: analysisID,
            analysis: core.analysis,
            findings: core.findings
        )
    }

    private func fetchResultCore(
        analysisID: UUID,
        expectedFindingCount: Int?
    ) async throws -> (analysis: AnalysisRow, findings: [FindingRow]) {
        do {
            let analysis: AnalysisRow = try await Self.withTimeout(
                nanoseconds: Self.analysisResultPollTimeoutNanoseconds,
                timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.kaydi.alinirken.baglanti.zaman.asimina.ug.605d0305", table: .analysis, fallback: "Analiz kaydı alınırken bağlantı zaman aşımına uğradı."))
            ) {
                try await self.supabase.client
                    .from("analyses")
                    .select()
                    .eq("id", value: analysisID.uuidString)
                    .single()
                    .execute()
                    .value
            }

            var findings = try await fetchFindingRows(analysisID: analysisID)
            let expectedCount = expectedFindingCount ?? analysis.findingCount
            if analysis.status == "completed", expectedCount > 0, findings.isEmpty {
                for attempt in 1...3 {
                    Self.logger.error("Completed analysis has no findings yet analysis=\(analysisID.uuidString, privacy: .public) expected=\(expectedCount) attempt=\(attempt)")
                    try await Task.sleep(nanoseconds: UInt64(250 + attempt * 250) * 1_000_000)
                    findings = try await fetchFindingRows(analysisID: analysisID)
                    if !findings.isEmpty { break }
                }
            }

            if analysis.status == "completed", expectedCount > 0, findings.isEmpty {
                throw AnalysisError.databaseFailed(RDLocalization.string("analysis.analysis.service.analiz.sonucu.hazir.ama.bulgular.yuklenemedi.lut.d92d4f00", table: .analysis, fallback: "Analiz sonucu hazır ama bulgular yüklenemedi. Lütfen Geçmiş analizlerden tekrar açmayı dene."))
            }

            return (analysis, findings)
        } catch let error as AnalysisError {
            Self.logger.error("Analysis result core hydration failed analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        } catch {
            Self.logger.error("Analysis result core hydration failed analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw AnalysisError.databaseFailed(error.localizedDescription)
        }
    }

    private func fetchFindingRows(analysisID: UUID) async throws -> [FindingRow] {
        try await Self.withTimeout(
            nanoseconds: Self.analysisResultPollTimeoutNanoseconds,
            timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.bulgulari.alinirken.baglanti.zaman.asimin.7e2115c8", table: .analysis, fallback: "Analiz bulguları alınırken bağlantı zaman aşımına uğradı."))
        ) {
            try await self.supabase.client
                .from("findings")
                .select()
                .eq("analysis_id", value: analysisID.uuidString)
                .order("ordinal", ascending: true)
                .execute()
                .value
        }
    }

    private func hydrateResultBundle(
        analysisID: UUID,
        analysis: AnalysisRow,
        findings: [FindingRow]
    ) async -> AnalysisResultBundle {
        async let photos = fetchOptionalPhotos(analysisID: analysisID)
        async let photoSummaries = fetchOptionalPhotoSummaries(analysisID: analysisID)
        let resolvedPhotos = await photos
        let resolvedPhotoSummaries = await photoSummaries
        return AnalysisResultBundle(
            analysis: analysis,
            findings: findings,
            photos: resolvedPhotos,
            photoSummaries: resolvedPhotoSummaries
        )
    }

    private func fetchOptionalPhotos(analysisID: UUID) async -> [AnalysisPhotoRow] {
        do {
            return try await Self.withTimeout(
                nanoseconds: Self.analysisResultPollTimeoutNanoseconds,
                timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.analiz.fotograflari.alinirken.baglanti.zaman.asi.85ac4949", table: .analysis, fallback: "Analiz fotoğrafları alınırken bağlantı zaman aşımına uğradı."))
            ) {
                try await self.supabase.client
                    .from("photos")
                    .select("analysis_id,storage_path,width,height,mime_type,sequence_index,client_photo_id,is_primary,thumbnail_storage_path,annotation_storage_path,user_caption,ai_scene_summary")
                    .eq("analysis_id", value: analysisID.uuidString)
                    .order("sequence_index", ascending: true)
                    .order("storage_path", ascending: true)
                    .execute()
                    .value
            }
        } catch {
            Self.logger.error("Optional analysis photos hydration skipped analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func fetchOptionalPhotoSummaries(analysisID: UUID) async -> [AnalysisPhotoSummaryRow] {
        do {
            return try await Self.withTimeout(
                nanoseconds: Self.analysisResultPollTimeoutNanoseconds,
                timeoutError: AnalysisError.networkFailed(RDLocalization.string("analysis.analysis.service.fotograf.ozetleri.alinirken.baglanti.zaman.asimi.1cc36761", table: .analysis, fallback: "Fotoğraf özetleri alınırken bağlantı zaman aşımına uğradı."))
            ) {
                try await self.supabase.client
                    .from("analysis_photo_summaries")
                    .select("analysis_id,photo_sequence_index,scene_summary,candidate_findings_count,generated_findings_count,highest_risk_level,ai_confidence,coverage_status,coverage_gap_reason,target_findings_min,target_findings_max")
                    .eq("analysis_id", value: analysisID.uuidString)
                    .order("photo_sequence_index", ascending: true)
                    .execute()
                    .value
            }
        } catch {
            Self.logger.error("Optional analysis photo summaries hydration skipped analysis=\(analysisID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func defaultTitle(for canvases: [AnalysisCanvas]) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("dMMMyHHmm")
        let label = canvases.count == 1
            ? canvases[0].title
            : canvases.map(\.title).joined(separator: " + ")
        return "\(label) · \(formatter.string(from: Date()))"
    }

    private static func functionErrorPayload(from data: Data) -> (message: String, supportID: String?, code: String?, tier: String?) {
        struct FunctionErrorBody: Decodable {
            let error: String?
            let message: String?
            let support_id: String?
            let code: String?
            let tier: String?
        }

        if let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) {
            let message = (body.message ?? body.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return (message, body.support_id, body.code, body.tier)
            }
        }

        return (String(data: data, encoding: .utf8) ?? "", nil, nil, nil)
    }

    private static func appendSupportID(_ supportID: String, to message: String) -> String {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.localizedCaseInsensitiveContains("destek kodu") else { return clean }
        return RDLocalization.format("analysis.analysis.service.1.destek.kodu.2.337dcc1b", table: .analysis, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: clean), String(describing: supportID)])
    }

    private static func safeReportFileName(
        for analysis: AnalysisRow,
        kind: PDFReportKind,
        method: RiskMethod,
        requestID: String
    ) -> String {
        let normalizedTitle = analysis.title
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "I")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "Ğ", with: "G")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "Ü", with: "U")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "Ş", with: "S")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "Ö", with: "O")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: "Ç", with: "C")
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let safeTitle = normalizedTitle
            .map { character -> Character in
                guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
                    return "_"
                }
                if (48...57).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value)) {
                    return character
                }
                if character == "-" || character == "_" {
                    return character
                }
                return "_"
            }
            .reduce(into: "") { partial, character in
                if character == "_" && partial.last == "_" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let titlePart = safeTitle.isEmpty ? "analysis" : String(safeTitle.prefix(48))
        let shortID = String(analysis.id.uuidString.prefix(8)).lowercased()
        let archiveID = archiveFileSuffix(requestID: requestID)
        let reportKind = analysis.resolvedOutputLanguage == .english
            ? "risk-assessment"
            : "risk-analizi"
        return [
            "riskdetected",
            titlePart,
            reportKind,
            kind.rawValue,
            databaseReportMethodValue(method),
            shortID,
            archiveID,
        ].joined(separator: "_") + ".pdf"
    }

    private static func archiveFileSuffix(requestID: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: Date())
        let requestPart = requestID
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        return "\(timestamp)_\(requestPart.isEmpty ? "request" : String(requestPart))"
    }

    private static func databaseReportMethodValue(_ method: RiskMethod) -> String {
        switch method {
        case .fineKinney:
            return "fine_kinney"
        case .matrix5x5:
            return "matrix_5x5"
        }
    }

    private static func reportDocumentNo(
        for analysis: AnalysisRow,
        kind: PDFReportKind,
        method: RiskMethod,
        requestID: String
    ) -> String {
        let shortID = String(analysis.id.uuidString.prefix(8)).uppercased()
        let requestPart = requestID
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(4)
        let uniquePart = requestPart.isEmpty ? "RPT" : String(requestPart)
        let base: String
        switch kind {
        case .standard:
            base = "\(shortID)-STD"
        case .riskAnalysis:
            switch method {
            case .fineKinney:
                base = "\(shortID)-FK"
            case .matrix5x5:
                base = "\(shortID)-M5"
            }
        }
        return "\(base)-\(uniquePart)"
    }

    private static func estimatedPageCount(for kind: PDFReportKind, findingCount: Int) -> Int {
        switch kind {
        case .standard:
            return 1 + max(Int(ceil(Double(max(findingCount, 1)) / 5.0)), 1)
        case .riskAnalysis:
            return 1 + max(Int(ceil(Double(max(findingCount, 1)) / 5.0)), 1)
        }
    }

    #if DEBUG
    private static var isUITestMainLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_MAIN")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_MAIN"] == "1"
    }

    @MainActor
    private static func uiTestPhotoData(path: String) -> Data? {
        let size = CGSize(width: 640, height: 480)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let seed = path.utf8.reduce(0) { ($0 + Int($1)) % 3 }
        let colors: [(UIColor, UIColor)] = [
            (
                UIColor(red: 0.08, green: 0.12, blue: 0.13, alpha: 1),
                UIColor(red: 0.14, green: 0.78, blue: 0.36, alpha: 1)
            ),
            (
                UIColor(red: 0.13, green: 0.16, blue: 0.22, alpha: 1),
                UIColor(red: 0.98, green: 0.72, blue: 0.10, alpha: 1)
            ),
            (
                UIColor(red: 0.12, green: 0.17, blue: 0.20, alpha: 1),
                UIColor(red: 0.24, green: 0.62, blue: 0.92, alpha: 1)
            )
        ]
        let palette = colors[seed]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            palette.0.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            palette.1.withAlphaComponent(0.82).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 54, y: 62, width: 532, height: 356),
                cornerRadius: 32
            ).fill()

            UIColor.white.withAlphaComponent(0.92).setStroke()
            let marker = UIBezierPath(ovalIn: CGRect(x: 202, y: 112, width: 236, height: 236))
            marker.lineWidth = 12
            marker.stroke()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            NSString(string: "UI TEST FOTOĞRAF \(seed + 1)").draw(
                in: CGRect(x: 142, y: 360, width: 356, height: 42),
                withAttributes: attributes
            )
        }
        return image.jpegData(compressionQuality: 0.88)
    }

    private static func uiTestResultBundle(
        analysisID: UUID,
        updatedFindingID: UUID? = nil,
        patch: FindingMutationPatch? = nil,
        deletedFindingID: UUID? = nil
    ) -> AnalysisResultBundle {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!
        let rows = Finding.mock.compactMap { finding -> FindingRow? in
            let rowID = uiTestFindingID(ordinal: finding.id)
            if rowID == deletedFindingID {
                return nil
            }
            let appliesPatch = rowID == updatedFindingID
            let fkProbability = appliesPatch ? (patch?.fkProbability ?? finding.fk.probability) : finding.fk.probability
            let fkFrequency = appliesPatch ? (patch?.fkFrequency ?? finding.fk.frequency) : finding.fk.frequency
            let fkSeverity = appliesPatch ? (patch?.fkSeverity ?? finding.fk.severity) : finding.fk.severity
            let fkScore = fkProbability * fkFrequency * fkSeverity
            let m5Probability = appliesPatch ? (patch?.m5Probability ?? finding.m5.probability) : finding.m5.probability
            let m5Severity = appliesPatch ? (patch?.m5Severity ?? finding.m5.severity) : finding.m5.severity
            let m5Score = m5Probability * m5Severity
            let defaultSourcePhotoIndices: [Int]
            switch finding.id {
            case 1:
                defaultSourcePhotoIndices = [3]
            case 2:
                defaultSourcePhotoIndices = [2, 3]
            case 3:
                defaultSourcePhotoIndices = []
            default:
                defaultSourcePhotoIndices = [1]
            }
            return FindingRow(
                id: rowID,
                analysisID: analysisID,
                ordinal: finding.id,
                title: appliesPatch ? (patch?.title ?? finding.title) : finding.title,
                category: appliesPatch ? (patch?.category ?? finding.category) : finding.category,
                description: appliesPatch ? (patch?.description ?? finding.description) : finding.description,
                recommendedAction: appliesPatch ? (patch?.recommendedAction ?? finding.action) : finding.action,
                recommendedMeasures: appliesPatch ? (patch?.recommendedMeasures ?? finding.controlMeasures) : finding.controlMeasures,
                referencesText: appliesPatch ? (patch?.referencesText ?? finding.references) : finding.references,
                rootCauseText: appliesPatch ? (patch?.rootCauseText ?? finding.rootCause) : finding.rootCause,
                needsFieldVerification: finding.id == 1,
                confidence: finding.confidence,
                fkProbability: fkProbability,
                fkFrequency: fkFrequency,
                fkSeverity: fkSeverity,
                fkScore: fkScore,
                fkBand: RiskBands.fineKinney(fkScore).level.rawValue,
                m5Probability: m5Probability,
                m5Severity: m5Severity,
                m5Score: m5Score,
                m5Band: RiskBands.matrix5x5(m5Score).level.rawValue,
                sourcePhotoIndices: patch?.sourcePhotoIndices ?? defaultSourcePhotoIndices,
                lastUserEditAt: appliesPatch || rowID == deletedFindingID ? ISO8601DateFormatter().string(from: Date()) : nil,
                userEditCount: appliesPatch ? 1 : nil,
                findingVersion: appliesPatch ? 2 : 1,
                displayOrder: finding.id
            )
        }
        var analysis = AnalysisRow(
            id: analysisID,
            userID: userID,
            companyID: nil,
            title: RDLocalization.string("analysis.analysis.service.ui.test.saha.analizi.ef355d01", table: .analysis, fallback: "UI Test Saha Analizi"),
            kind: "photo",
            canvas: "ppe",
            status: "completed",
            statusMessage: nil,
            aiSummary: "UI test fixture analizi tamamlandı. Bulgular rapor ve PDF akışını gerçek ekran üzerinde doğrulamak için hazırlanmıştır.",
            totalScoreFK: 1_920,
            totalScoreM5: 62,
            highestBandFK: RiskLevel.critical.rawValue,
            highestBandM5: RiskLevel.critical.rawValue,
            findingCount: rows.count,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            analysisSector: "construction",
            analysisSectorSource: "user_selected",
            analysisSectorPromptVersion: AnalysisSectorID.activeAnalysisPromptVersion
        )
        let fixtureLanguage = RDLanguage.current
        analysis.outputLanguage = fixtureLanguage.rawValue
        analysis.outputLocale = fixtureLanguage == .english ? "en-GB" : "tr-TR"
        analysis.workJurisdictionCountry = fixtureLanguage == .english ? "ZZ" : "TR"
        analysis.safetyProfileID = fixtureLanguage == .english
            ? "english_international_generic_v1"
            : "turkey_current_v1"
        analysis.safetyProfileVersion = 1
        analysis.localizationSnapshot = RDAnalysisLocalizationSnapshot(
            schemaVersion: 1,
            outputLanguage: analysis.outputLanguage,
            outputLocale: analysis.outputLocale,
            workJurisdictionCountry: analysis.workJurisdictionCountry,
            workJurisdictionRegion: nil,
            safetyProfileID: analysis.safetyProfileID,
            safetyProfileVersion: analysis.safetyProfileVersion,
            structuredRegulatoryReferencesEnabled: fixtureLanguage == .turkish
        )
        let photos = (1...3).map { index in
            AnalysisPhotoRow(
                analysisID: analysisID,
                storagePath: "ui-tests/analysis-\(analysisID.uuidString)/p\(index).jpg",
                width: 1024,
                height: 768,
                mimeType: "image/jpeg",
                sequenceIndex: index,
                clientPhotoID: "ui-test-photo-\(index)",
                isPrimary: index == 1
            )
        }
        return AnalysisResultBundle(analysis: analysis, findings: rows, photos: photos)
    }

    private static func uiTestFindingID(ordinal: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", ordinal))!
    }
    #endif
}

struct InFlightAnalysis: Codable, Equatable {
    let analysisID: UUID
    let userID: UUID
    let photoCount: Int
    let startedAt: Date
    let title: String
    let kind: String

    var isExpired: Bool {
        Date().timeIntervalSince(startedAt) > 30 * 60
    }
}

@MainActor
final class InFlightAnalysisStore {
    static let shared = InFlightAnalysisStore()

    private let key = "rd.analysis.inFlight.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ analysis: InFlightAnalysis) {
        guard let data = try? JSONEncoder().encode(analysis) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> InFlightAnalysis? {
        guard let data = defaults.data(forKey: key),
              let analysis = try? JSONDecoder().decode(InFlightAnalysis.self, from: data) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        if analysis.isExpired {
            clear(analysisID: analysis.analysisID)
            return nil
        }
        return analysis
    }

    func load(for userID: UUID) -> InFlightAnalysis? {
        guard let analysis = load() else { return nil }
        guard analysis.userID == userID else {
            clear(analysisID: analysis.analysisID)
            return nil
        }
        return analysis
    }

    func clear(analysisID: UUID) {
        guard let current = loadWithoutExpiryCheck() else {
            defaults.removeObject(forKey: key)
            return
        }
        if current.analysisID == analysisID {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadWithoutExpiryCheck() -> InFlightAnalysis? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(InFlightAnalysis.self, from: data)
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

struct AnalysisResultBundle: Codable, Equatable {
    let analysis: AnalysisRow
    let findings: [FindingRow]
    let photos: [AnalysisPhotoRow]
    var photoSummaries: [AnalysisPhotoSummaryRow]? = nil
}

struct AnalysisPhotoSummaryRow: Codable, Equatable {
    let analysisID: UUID
    let photoSequenceIndex: Int
    let sceneSummary: String?
    let candidateFindingsCount: Int?
    let generatedFindingsCount: Int?
    let highestRiskLevel: String?
    let aiConfidence: Double?
    let coverageStatus: String?
    let coverageGapReason: String?
    let targetFindingsMin: Int?
    let targetFindingsMax: Int?

    enum CodingKeys: String, CodingKey {
        case analysisID = "analysis_id"
        case photoSequenceIndex = "photo_sequence_index"
        case sceneSummary = "scene_summary"
        case candidateFindingsCount = "candidate_findings_count"
        case generatedFindingsCount = "generated_findings_count"
        case highestRiskLevel = "highest_risk_level"
        case aiConfidence = "ai_confidence"
        case coverageStatus = "coverage_status"
        case coverageGapReason = "coverage_gap_reason"
        case targetFindingsMin = "target_findings_min"
        case targetFindingsMax = "target_findings_max"
    }
}

struct AnalysisPhotoRow: Codable, Equatable {
    let analysisID: UUID
    let storagePath: String
    let width: Int?
    let height: Int?
    let mimeType: String?
    var sequenceIndex: Int? = nil
    var clientPhotoID: String? = nil
    var isPrimary: Bool? = nil
    var thumbnailStoragePath: String? = nil
    var annotationStoragePath: String? = nil
    var userCaption: String? = nil
    var aiSceneSummary: String? = nil

    enum CodingKeys: String, CodingKey {
        case analysisID = "analysis_id"
        case storagePath = "storage_path"
        case width
        case height
        case mimeType = "mime_type"
        case sequenceIndex = "sequence_index"
        case clientPhotoID = "client_photo_id"
        case isPrimary = "is_primary"
        case thumbnailStoragePath = "thumbnail_storage_path"
        case annotationStoragePath = "annotation_storage_path"
        case userCaption = "user_caption"
        case aiSceneSummary = "ai_scene_summary"
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
    let companyID: UUID?
    let companySnapshot: CompanySnapshot?
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
    var reportLanguage: String? = nil
    var reportLocale: String? = nil
    var safetyProfileID: String? = nil
    var safetyProfileVersion: Int? = nil
    var regulatorySectionsEnabled: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case analysisID = "analysis_id"
        case companyID = "company_id"
        case companySnapshot = "company_snapshot"
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
        case reportLanguage = "report_language"
        case reportLocale = "report_locale"
        case safetyProfileID = "safety_profile_id"
        case safetyProfileVersion = "safety_profile_version"
        case regulatorySectionsEnabled = "regulatory_sections_enabled"
    }
}

extension ReportRow {
    var isExcelReport: Bool {
        format == "xlsx" || mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    }

    var isRiskAnalysisReport: Bool {
        kind == PDFReportKind.riskAnalysis.rawValue || kind == "risk_analysis"
    }

    var usesRiskAnalysisTrial: Bool {
        isRiskAnalysisReport || isExcelReport
    }
}

struct RDAnalysisLocalizationSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int?
    let outputLanguage: String?
    let outputLocale: String?
    let workJurisdictionCountry: String?
    let workJurisdictionRegion: String?
    let safetyProfileID: String?
    let safetyProfileVersion: Int?
    let structuredRegulatoryReferencesEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case outputLanguage = "output_language"
        case outputLocale = "output_locale"
        case workJurisdictionCountry = "work_jurisdiction_country"
        case workJurisdictionRegion = "work_jurisdiction_region"
        case safetyProfileID = "safety_profile_id"
        case safetyProfileVersion = "safety_profile_version"
        case structuredRegulatoryReferencesEnabled = "structured_regulatory_references_enabled"
    }

    var isComplete: Bool {
        schemaVersion == 1
            && RDLanguage(rawValue: outputLanguage ?? "") != nil
            && !(outputLocale ?? "").isEmpty
            && !(workJurisdictionCountry ?? "").isEmpty
            && !(safetyProfileID ?? "").isEmpty
            && (safetyProfileVersion ?? 0) > 0
            && structuredRegulatoryReferencesEnabled != nil
    }
}

struct AnalysisRow: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let companyID: UUID?
    let title: String
    let kind: String
    let canvas: String
    let status: String
    let statusMessage: String?
    let aiSummary: String?
    let totalScoreFK: Double?
    let totalScoreM5: Int?
    let highestBandFK: String?
    let highestBandM5: String?
    let findingCount: Int
    let createdAt: String?
    let analysisSector: String?
    let analysisSectorSource: String?
    let analysisSectorPromptVersion: String?
    var inputPayloadVersion: String? = nil
    var photoCount: Int? = nil
    var maxPhotosAllowedAtCreation: Int? = nil
    var maxFindingsPerPhoto: Int? = nil
    var maxFindingsTotal: Int? = nil
    var generatedFindingsCount: Int? = nil
    var visibleFindingsCount: Int? = nil
    var hiddenOrRejectedFindingsCount: Int? = nil
    var hasUserEdits: Bool? = nil
    var userEditCount: Int? = nil
    var analysisEditVersion: Int? = nil
    var planAtCreation: String? = nil
    var outputLanguage: String? = nil
    var outputLocale: String? = nil
    var workJurisdictionCountry: String? = nil
    var workJurisdictionRegion: String? = nil
    var safetyProfileID: String? = nil
    var safetyProfileVersion: Int? = nil
    var localizationSnapshot: RDAnalysisLocalizationSnapshot? = nil

    var analysisSectorID: AnalysisSectorID? {
        guard let analysisSector else { return nil }
        return AnalysisSectorID(rawValue: analysisSector)
    }

    var analysisSectorLabel: String? {
        analysisSectorID?.label()
    }

    /// Rows created before the localization snapshot migration are Turkish.
    var resolvedOutputLanguage: RDLanguage {
        RDLanguage(rawValue: localizationSnapshot?.outputLanguage ?? outputLanguage ?? "")
            ?? .turkish
    }

    var hasCompleteLocalizationSnapshot: Bool {
        localizationSnapshot?.isComplete == true
    }

    var supportsStructuredRegulatoryReferences: Bool {
        if let enabled = localizationSnapshot?.structuredRegulatoryReferencesEnabled {
            return enabled
        }
        return (workJurisdictionCountry ?? RDWorkJurisdictionCountry.turkey.rawValue)
            == RDWorkJurisdictionCountry.turkey.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID         = "user_id"
        case companyID      = "company_id"
        case title
        case kind
        case canvas
        case status
        case statusMessage   = "status_message"
        case aiSummary      = "ai_summary"
        case totalScoreFK   = "total_score_fk"
        case totalScoreM5   = "total_score_m5"
        case highestBandFK  = "highest_band_fk"
        case highestBandM5  = "highest_band_m5"
        case findingCount   = "finding_count"
        case createdAt      = "created_at"
        case analysisSector = "analysis_sector"
        case analysisSectorSource = "analysis_sector_source"
        case analysisSectorPromptVersion = "analysis_sector_prompt_version"
        case inputPayloadVersion = "input_payload_version"
        case photoCount = "photo_count"
        case maxPhotosAllowedAtCreation = "max_photos_allowed_at_creation"
        case maxFindingsPerPhoto = "max_findings_per_photo"
        case maxFindingsTotal = "max_findings_total"
        case generatedFindingsCount = "generated_findings_count"
        case visibleFindingsCount = "visible_findings_count"
        case hiddenOrRejectedFindingsCount = "hidden_or_rejected_findings_count"
        case hasUserEdits = "has_user_edits"
        case userEditCount = "user_edit_count"
        case analysisEditVersion = "analysis_edit_version"
        case planAtCreation = "plan_at_creation"
        case outputLanguage = "output_language"
        case outputLocale = "output_locale"
        case workJurisdictionCountry = "work_jurisdiction_country"
        case workJurisdictionRegion = "work_jurisdiction_region"
        case safetyProfileID = "safety_profile_id"
        case safetyProfileVersion = "safety_profile_version"
        case localizationSnapshot = "localization_snapshot"
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
    let recommendedMeasures: [FindingMeasure]?
    let referencesText: String?
    let rootCauseText: String?
    var needsFieldVerification: Bool? = nil
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
    var origin: String? = nil
    var sourcePhotoIndices: [Int]? = nil
    var aiConfidence: Double? = nil
    var lastUserEditAt: String? = nil
    var userEditCount: Int? = nil
    var findingVersion: Int? = nil
    var displayOrder: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case analysisID         = "analysis_id"
        case ordinal
        case title
        case category
        case description
        case recommendedAction  = "recommended_action"
        case recommendedMeasures = "recommended_measures"
        case referencesText     = "references_text"
        case rootCauseText      = "root_cause_text"
        case needsFieldVerification = "needs_field_verification"
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
        case origin
        case sourcePhotoIndices = "source_photo_indices"
        case aiConfidence = "ai_confidence"
        case lastUserEditAt = "last_user_edit_at"
        case userEditCount = "user_edit_count"
        case findingVersion = "finding_version"
        case displayOrder = "display_order"
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
            measures: recommendedMeasures ?? [],
            references: referencesText ?? "",
            rootCause: rootCauseText ?? "",
            needsFieldVerification: needsFieldVerification == true,
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
