import SwiftUI
import UIKit

/// D8 presentation for analyses committed inside an OSGB workspace. The screen
/// never reads the personal analysis service and keeps every action inside the
/// selected workspace/company envelope.
struct IsgWorkspaceAnalysisScreen: View {
    private struct AnalysisTarget: Identifiable {
        let id: UUID
    }

    @ObservedObject var store: IsgWorkspaceStore
    let companyID: UUID
    let companyName: String
    let canOperate: Bool
    let initialAnalysisID: UUID?
    let onInitialAnalysisOpened: (() -> Void)?
    let onBack: () -> Void
    @State private var selectedAnalysis: AnalysisTarget?
    @State private var creatingAnalysis: Bool
    @State private var images: [UIImage] = []
    @State private var analysisRun: IsgWorkspacePhotoAnalysisRun?
    @State private var notice: String?
    @State private var listRevision = UUID()
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    init(store: IsgWorkspaceStore, companyID: UUID, companyName: String,
         canOperate: Bool, startInCreateMode: Bool = false,
         initialAnalysisID: UUID? = nil,
         onInitialAnalysisOpened: (() -> Void)? = nil,
         onBack: @escaping () -> Void) {
        self.store = store
        self.companyID = companyID
        self.companyName = companyName
        self.canOperate = canOperate
        self.initialAnalysisID = initialAnalysisID
        self.onInitialAnalysisOpened = onInitialAnalysisOpened
        self.onBack = onBack
        _creatingAnalysis = State(initialValue: startInCreateMode)
        _selectedAnalysis = State(initialValue: initialAnalysisID.map { AnalysisTarget(id: $0) })
    }

    var body: some View {
        Group {
            if creatingAnalysis {
                NovaPhotoIntakeScreen(images: $images, maximum: 1,
                    onStart: startPhotoAnalysis,
                    onBack: {
                        images = []
                        creatingAnalysis = false
                    })
            } else {
                NovaAnalysisListScreen(load: load, loadStats: {
                    guard let identity = novaCurrentSessionIdentity() else { throw NovaPersonnelFailure.denied }
                    return try await NovaAnalysisWorkspace.summaryStats(identity: identity, method: nil, companyID: companyID)
                }, thumbnail: { _ in nil },
                    onOpen: { selectedAnalysis = .init(id: $0) }, onBack: onBack,
                    onNewPhotoAnalysis: canOperate ? { creatingAnalysis = true } : nil)
                    .id(listRevision)
            }
        }
        // Analysis detail owns a pinned report/action bar. Presenting it over
        // the shared expert shell keeps the global bottom menu out of that
        // result page, exactly like the personal expert flow.
        .novaFullScreenCover(item: $selectedAnalysis) { target in
            NovaAnalysisDetailScreen(analysisID: target.id,
                client: detailClient(target.id),
                onBack: { selectedAnalysis = nil },
                canWrite: canOperate, canEdit: false, canReact: false,
                canFile: canOperate, canFileTraining: false,
                canReport: canOperate, reportResultIsArchiveName: false)
                .modifier(NovaSuccessPresentation())
        }
        .novaFullScreenCover(item: $analysisRun) { run in
            IsgWorkspacePhotoAnalysisProgressScreen(store: store, run: run,
                companyID: companyID, companyName: companyName,
                onComplete: { analysisID in
                    images = []
                    creatingAnalysis = false
                    listRevision = UUID()
                    analysisRun = nil
                    selectedAnalysis = .init(id: analysisID)
                },
                onError: { message in
                    analysisRun = nil
                    notice = message
                    listRevision = UUID()
                })
        }
        .alert(notice ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable,
                                         fallback: "Tamam")) { notice = nil }
        }
        .onAppear { openInitialAnalysisIfNeeded() }
        .onChange(of: initialAnalysisID) { _ in openInitialAnalysisIfNeeded() }
    }

    private func openInitialAnalysisIfNeeded() {
        guard !creatingAnalysis, let initialAnalysisID else { return }
        selectedAnalysis = .init(id: initialAnalysisID)
        onInitialAnalysisOpened?()
    }

    private func startPhotoAnalysis() {
        guard canOperate, let image = images.first else { return }
        analysisRun = .init(image: image)
    }

    private func load(offset: Int) async throws -> (rows: [NovaAnalysisSummary], hasMore: Bool) {
        let page = try await store.analyses(companyID: companyID, offset: offset, limit: 10)
        return (page.rows.map(summary), page.hasMore)
    }

    private func summary(_ value: IsgWorkspaceAnalysisSummary) -> NovaAnalysisSummary {
        let stamp = parseDate(value.createdAt)
        return .init(id: value.id, title: value.title, createdOn: displayDate(stamp, fallback: value.createdAt),
            companyName: companyName, findingCount: value.findingCount, photoCount: value.kind == "photo" ? 1 : 0,
            sectorLabel: nil, highestBand: value.highestBand, focusLabel: nil,
            isReviewed: false, createdAt: stamp)
    }

    private func detailClient(_ analysisID: UUID) -> NovaAnalysisDetailClient {
        .init(load: {
                let value = try await store.analysis(companyID: companyID, analysisID: analysisID)
                return detail(value)
            },
            photos: { [] },
            companies: { [.init(id: companyID, name: companyName, detail: "", sector: nil)] },
            assign: { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            workplaces: { requestedCompany in
                guard requestedCompany == companyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
                let rows = try await store.directory(.workplace, companyID: companyID)
                return rows.map {
                    .init(id: $0.id, name: $0.name, needs_review: false)
                }
            },
            file: { request in await file(request, analysisID: analysisID) },
            edit: { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            remove: { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            react: { _, _, _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            report: { request in try await requestExport(request, analysisID: analysisID) })
    }

    private func detail(_ value: IsgWorkspaceAnalysisResult) -> NovaAnalysisDetailData {
        let method = NovaRiskMethod(rawValue: value.primaryMethod) ?? .fineKinney
        return .init(analysisID: value.analysisID, title: value.title,
            createdOn: displayDate(parseDate(value.createdAt), fallback: value.createdAt),
            methodLabel: NovaNonconformityWords.method(method), method: method,
            companyID: companyID, companyName: companyName,
            sections: [
                .init(kind: .riskAnalysis, items: map(value.riskFindings), isTeaser: false),
                .init(kind: .expertRecommendations, items: map(value.expertItems), isTeaser: false),
                .init(kind: .trainingRecommendations, items: map(value.trainingItems), isTeaser: false)
            ], isProjectionMissing: false, photoCount: 0, sectorLabel: nil, focusLabels: [])
    }

    private func map(_ values: [IsgWorkspaceAnalysisItem]) -> [NovaAnalysisItem] {
        values.enumerated().map { index, value in
            let fk = value.fkScore.map { score in
                NovaAnalysisScore(band: value.fkBand, value: score,
                    factors: [
                        value.fkProbability.map { .init(label: "O", value: $0) },
                        value.fkFrequency.map { .init(label: "F", value: $0) },
                        value.fkSeverity.map { .init(label: RDLocalization.string("analysis.isg.workspace.analysis.screen.s.99bfeb94", table: .analysis, fallback: "Ş"), value: $0) }
                    ].compactMap { $0 })
            }
            let matrix = value.m5Score.map { score in
                NovaAnalysisScore(band: value.m5Band, value: Double(score),
                    factors: [
                        value.m5Probability.map { .init(label: "O", value: Double($0)) },
                        value.m5Severity.map { .init(label: RDLocalization.string("analysis.isg.workspace.analysis.screen.s.c4f0e3a9", table: .analysis, fallback: "Ş"), value: Double($0)) }
                    ].compactMap { $0 })
            }
            return .init(id: value.id, ordinal: value.ordinal ?? value.displayOrder ?? index + 1,
                title: value.title, category: value.category,
                body: value.body ?? value.description ?? "",
                measure: value.recommendation ?? value.recommendedAction,
                references: value.referencesText, audience: value.audience,
                durationLabel: value.durationMinutes == nil ? nil : RDLocalization.string(
                    "localizable.nova.analysis.field.duration", table: .localizable, fallback: "Eğitim süresi"),
                durationValue: value.durationMinutes.map { "\($0) dk" },
                photoIndices: value.sourcePhotoIndices ?? [], fineKinney: fk, matrix: matrix)
        }
    }

    @MainActor private func file(_ request: NovaAnalysisFileRequest,
                                 analysisID: UUID) async -> NovaFindingOutcome {
        guard request.companyID == nil || request.companyID == companyID else {
            return .failed(NovaNonconformityWords.failure(.denied))
        }
        do {
            let source = try await store.analysis(companyID: companyID, analysisID: analysisID)
            let itemKind = request.section == .riskAnalysis ||
                source.expertItems.first(where: { $0.id == request.item.id })?.kind == "unscored_finding"
                ? "finding" : "expert_item"
            var attempt = mutationAttempt
            let openedOn = day(Date())
            let mutationID = attempt.id(namespace: "analysis.file", components: [
                companyID.uuidString, request.workplaceID?.uuidString ?? "firma", analysisID.uuidString,
                itemKind, request.item.id.uuidString, request.severity?.rawValue ?? "", openedOn
            ])
            mutationAttempt = attempt
            let response = try await store.fileAnalysisItem(mutationID: mutationID, companyID: companyID,
                workplaceID: request.workplaceID, sourceScope: "workspace", analysisID: analysisID,
                itemKind: itemKind, itemID: request.item.id, severity: request.severity?.rawValue,
                openedOn: openedOn, dueOn: nil)
            celebrate(response.successMessage)
            return response.result.created ? .opened : .alreadyOpen
        } catch {
            return .failed(RDLocalization.string("localizable.nova.bridge.outcome.failed", table: .localizable,
                fallback: "Bu bulgu için kayıt açılamadı. Aynı işlemi tekrar deneyin."))
        }
    }

    private func requestExport(_ request: NovaAnalysisReportRequest,
                               analysisID: UUID) async throws -> String {
        let analysis = try await store.analysis(companyID: companyID, analysisID: analysisID)
        let findingIDs = analysis.riskFindings.map(\.id)
        let expertIDs = analysis.expertItems.filter { $0.kind == "expert_recommendation" }.map(\.id)
        let trainingIDs = analysis.trainingItems.map(\.id)
        let format = request.format == .excel ? "xlsx" : "pdf"
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "analysis.export", components: [companyID.uuidString,
            analysisID.uuidString, format, findingIDs.map(\.uuidString).joined(separator: ","),
            expertIDs.map(\.uuidString).joined(separator: ","), trainingIDs.map(\.uuidString).joined(separator: ",")])
        mutationAttempt = attempt
        let job = try await store.createExport(mutationID: mutationID, companyID: companyID,
            analysisID: analysisID, format: request.format == .excel ? "xlsx" : "pdf",
            findingIDs: findingIDs, expertItemIDs: expertIDs, trainingItemIDs: trainingIDs)
        if job.status == "succeeded" {
            return RDLocalization.string("localizable.nova.workspace.analysis.export.ready", table: .localizable,
                                         fallback: "Rapor hazırlandı.")
        }
        return RDLocalization.string("localizable.nova.workspace.analysis.export.queued", table: .localizable,
                                     fallback: "Rapor isteği alındı ve hazırlanıyor.")
    }

    private func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func displayDate(_ date: Date?, fallback: String) -> String {
        guard let date else { return String(fallback.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct IsgWorkspacePhotoAnalysisRun: Identifiable {
    let id = UUID()
    let fileMutationID = UUID()
    let jobMutationID = UUID()
    let image: UIImage
}

private struct IsgWorkspacePhotoAnalysisProgressScreen: View {
    private enum Phase {
        case preparing, uploading, queued, analyzing, finalizing

        var title: String {
            switch self {
            case .preparing: return RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.hazirlaniyor.1736bf19", table: .analysis, fallback: "Fotoğraf hazırlanıyor")
            case .uploading: return RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.firmaya.kaydediliyor.f3c872dc", table: .analysis, fallback: "Fotoğraf firmaya kaydediliyor")
            case .queued: return RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.sirasi.hazirlaniyor.0eb73d38", table: .analysis, fallback: "Analiz sırası hazırlanıyor")
            case .analyzing: return RDLocalization.string("analysis.isg.workspace.analysis.screen.isg.analizi.yapiliyor.a160b8cc", table: .analysis, fallback: "İSG analizi yapılıyor")
            case .finalizing: return RDLocalization.string("analysis.isg.workspace.analysis.screen.sonuclar.kaydediliyor.4e61c0eb", table: .analysis, fallback: "Sonuçlar kaydediliyor")
            }
        }

        var detail: String {
            switch self {
            case .preparing: return RDLocalization.string("analysis.isg.workspace.analysis.screen.goruntu.guvenli.yukleme.icin.duzenleniyor.7d324ddf", table: .analysis, fallback: "Görüntü güvenli yükleme için düzenleniyor.")
            case .uploading: return RDLocalization.string("analysis.isg.workspace.analysis.screen.kaynak.fotograf.firma.dosyalarina.baglaniyor.c91d96c2", table: .analysis, fallback: "Kaynak fotoğraf firma dosyalarına bağlanıyor.")
            case .queued: return RDLocalization.string("analysis.isg.workspace.analysis.screen.islem.osgb.analiz.hizmetine.iletildi.cfe50c2c", table: .analysis, fallback: "İşlem OSGB analiz hizmetine iletildi.")
            case .analyzing: return RDLocalization.string("analysis.isg.workspace.analysis.screen.riskler.oneriler.ve.egitim.ihtiyaclari.degerlend.c3a8fab4", table: .analysis, fallback: "Riskler, öneriler ve eğitim ihtiyaçları değerlendiriliyor.")
            case .finalizing: return RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.kaydi.ve.bulgular.son.kez.dogrulaniyor.03be624c", table: .analysis, fallback: "Analiz kaydı ve bulgular son kez doğrulanıyor.")
            }
        }
    }

    @ObservedObject var store: IsgWorkspaceStore
    let run: IsgWorkspacePhotoAnalysisRun
    let companyID: UUID
    let companyName: String
    let onComplete: (UUID) -> Void
    let onError: (String) -> Void
    @State private var phase: Phase = .preparing
    @State private var started = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NovaText(text: RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.analizi.836fd616", table: .analysis, fallback: "Fotoğraf Analizi"), style: .screenTitle)
                    Image(uiImage: run.image)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                    NovaCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.regular)
                                NovaText(text: phase.title, style: .cardTitle)
                            }
                            NovaText(text: phase.detail, style: .body,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                            HStack(spacing: 7) {
                                Image(systemName: "building.2")
                                NovaText(text: companyName, style: .meta)
                            }
                            .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NovaHelpHint(text: RDLocalization.string("analysis.isg.workspace.analysis.screen.bu.ekran.acikken.islem.tamamlandiginda.analiz.ot.cdb427a9", table: .analysis, fallback: "Bu ekran açıkken işlem tamamlandığında analiz otomatik olarak açılır."))
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .interactiveDismissDisabled()
        .task(id: run.id) {
            guard !started else { return }
            started = true
            await perform()
        }
    }

    @MainActor private func perform() async {
        do {
            phase = .preparing
            guard let data = normalizedJPEG(run.image) else {
                throw PhotoAnalysisFailure.invalidImage
            }
            phase = .uploading
            let upload = try await store.uploadFile(mutationID: run.fileMutationID,
                title: RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.kaynak.fotografi.ecbe6618", table: .analysis, fallback: "Analiz kaynak fotoğrafı"),
                filename: "analiz-\(run.id.uuidString.lowercased()).jpg",
                category: "inspection_report", data: data, companyID: companyID)
            phase = .queued
            let submitted = try await store.submitPhotoAnalysis(mutationID: run.jobMutationID,
                companyID: companyID, assetID: upload.assetID)
            let analysisID = try await waitForResult(jobID: submitted.id)
            phase = .finalizing
            onComplete(analysisID)
        } catch is CancellationError {
            return
        } catch {
            onError(message(for: error))
        }
    }

    @MainActor private func waitForResult(jobID: UUID) async throws -> UUID {
        for _ in 0..<120 {
            try Task.checkCancellation()
            let job = try await store.photoAnalysisJob(companyID: companyID, jobID: jobID)
            switch job.status {
            case "succeeded":
                guard let analysisID = job.analysisID else { throw PhotoAnalysisFailure.invalidResult }
                return analysisID
            case "queued":
                phase = .queued
            case "running":
                phase = .analyzing
            case "failed", "cancelled", "reconcile":
                throw PhotoAnalysisFailure.jobFailed(job.errorCode)
            default:
                throw PhotoAnalysisFailure.invalidResult
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw PhotoAnalysisFailure.timedOut
    }

    private func normalizedJPEG(_ image: UIImage) -> Data? {
        func render(maximum: CGFloat, quality: CGFloat) -> Data? {
            let longest = max(image.size.width, image.size.height)
            guard longest > 0 else { return nil }
            let scale = min(1, maximum / longest)
            let size = CGSize(width: max(1, image.size.width * scale),
                              height: max(1, image.size.height * scale))
            let renderer = UIGraphicsImageRenderer(size: size)
            let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            return normalized.jpegData(compressionQuality: quality)
        }
        if let data = render(maximum: 1_600, quality: 0.82), data.count <= 20 * 1_024 * 1_024 {
            return data
        }
        guard let compact = render(maximum: 1_200, quality: 0.62),
              compact.count <= 20 * 1_024 * 1_024 else { return nil }
        return compact
    }

    private func message(for error: Error) -> String {
        if let failure = error as? PhotoAnalysisFailure { return failure.errorDescription }
        let raw = String(describing: error)
        if raw.contains("INSUFFICIENT_CREDITS") {
            return RDLocalization.string("analysis.isg.workspace.analysis.screen.osgb.analiz.kredisi.yetersiz.yetkili.hesaptan.kr.480881ce", table: .analysis, fallback: "OSGB analiz kredisi yetersiz. Yetkili hesaptan kredi durumunu kontrol edin.")
        }
        if raw.contains("PRICING_NOT_AVAILABLE") {
            return RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.analizi.su.anda.kullanilamiyor.biraz.so.82ca72c0", table: .analysis, fallback: "Fotoğraf analizi şu anda kullanılamıyor. Biraz sonra tekrar deneyin.")
        }
        if raw.contains("SOURCE_NOT_FOUND") {
            return RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.guvenli.bicimde.kaydedilemedi.fotografi.7d609992", table: .analysis, fallback: "Fotoğraf güvenli biçimde kaydedilemedi. Fotoğrafı yeniden seçip tekrar deneyin.")
        }
        return RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.baslatilamadi.baglantinizi.kontrol.edip.a.295337eb", table: .analysis, fallback: "Analiz başlatılamadı. Bağlantınızı kontrol edip aynı fotoğrafla tekrar deneyin.")
    }
}

private enum PhotoAnalysisFailure: Error {
    case invalidImage
    case invalidResult
    case jobFailed(String?)
    case timedOut

    var errorDescription: String {
        switch self {
        case .invalidImage:
            return RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.hazirlanamadi.baska.bir.fotograf.secip..b5c321a0", table: .analysis, fallback: "Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar deneyin.")
        case .invalidResult:
            return RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.tamamlandi.ancak.sonuc.kaydi.dogrulanamad.f764e43b", table: .analysis, fallback: "Analiz tamamlandı ancak sonuç kaydı doğrulanamadı. Analizlerim ekranını yenileyin.")
        case .jobFailed(let code):
            switch code {
            case "SOURCE_NOT_FOUND":
                return RDLocalization.string("analysis.isg.workspace.analysis.screen.kaynak.fotograf.bulunamadi.fotografi.yeniden.sec.5e0be326", table: .analysis, fallback: "Kaynak fotoğraf bulunamadı. Fotoğrafı yeniden seçip tekrar deneyin.")
            case "AUTHORITY_REVOKED", "ASSIGNMENT_REVOKED":
                return RDLocalization.string("analysis.isg.workspace.analysis.screen.bu.firma.icin.analiz.yetkiniz.degisti.firma.atam.dd10d711", table: .analysis, fallback: "Bu firma için analiz yetkiniz değişti. Firma atamanızı kontrol edin.")
            case "PROVIDER_SCHEMA_INVALID":
                return RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.sonucu.dogrulanamadi.ayni.fotografla.tekr.28457300", table: .analysis, fallback: "Analiz sonucu doğrulanamadı. Aynı fotoğrafla tekrar deneyin.")
            default:
                return RDLocalization.string("analysis.isg.workspace.analysis.screen.fotograf.analizi.tamamlanamadi.biraz.sonra.tekra.cccb3dbd", table: .analysis, fallback: "Fotoğraf analizi tamamlanamadı. Biraz sonra tekrar deneyin.")
            }
        case .timedOut:
            return RDLocalization.string("analysis.isg.workspace.analysis.screen.analiz.beklenenden.uzun.suruyor.islem.arka.pland.2e730352", table: .analysis, fallback: "Analiz beklenenden uzun sürüyor. İşlem arka planda devam edebilir; Analizlerim listesini biraz sonra yenileyin.")
        }
    }
}
