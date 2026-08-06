import SwiftUI
import UIKit

enum AnalysisWaitingPresentationMode {
    case photo
}

@MainActor
final class AnalysisProgressController: ObservableObject {
    @Published private(set) var progress: Double = 0.03
    @Published private(set) var phase: AnalysisProgressPhase = .preparingInput

    private var target: Double = 0.08
    private var progressTask: Task<Void, Never>?
    private var photoCount: Int = 0
    private var analyzingStartedAt: Date?

    func start(photoCount: Int) {
        progressTask?.cancel()
        self.photoCount = max(photoCount, 0)
        progress = 0.03
        phase = .preparingInput
        target = targetValue(for: .preparingInput)
        analyzingStartedAt = nil

        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 380_000_000)
                guard !Task.isCancelled else { return }
                advanceOneTick()
            }
        }
    }

    func apply(_ update: AnalysisProgressUpdate) {
        let previousPhase = phase
        phase = update.phase

        if update.phase == .analyzing {
            if previousPhase != .analyzing || analyzingStartedAt == nil {
                analyzingStartedAt = Date()
            }
        } else if previousPhase == .analyzing {
            analyzingStartedAt = nil
        }

        target = max(target, targetValue(for: update.phase))
        let floor = floorValue(for: update.phase)
        if progress < floor {
            withAnimation(.easeInOut(duration: 0.18)) {
                progress = min(floor, target)
            }
        }
    }

    func complete() async {
        phase = .finalizingResult
        analyzingStartedAt = nil
        target = max(target, 0.99)

        while progress < 0.99 {
            advanceOneTick(maxStep: 0.035, minStep: 0.010, duration: 0.10)
            try? await Task.sleep(nanoseconds: 90_000_000)
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            progress = 0.99
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        withAnimation(.easeInOut(duration: 0.20)) {
            progress = 1
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        cancel()
    }

    func cancel() {
        progressTask?.cancel()
        progressTask = nil
        analyzingStartedAt = nil
    }

    private func targetValue(for phase: AnalysisProgressPhase) -> Double {
        let multiPhotoBonus = min(Double(max(photoCount - 1, 0)) * 0.012, 0.048)

        switch phase {
        case .preparingInput:
            return min(0.08 + multiPhotoBonus, 0.18)
        case .creatingAnalysis:
            return 0.18
        case .uploadingPhotos:
            return min(0.52 + multiPhotoBonus, 0.58)
        case .submitting:
            return min(0.62 + multiPhotoBonus, 0.68)
        case .queued:
            return min(0.70 + multiPhotoBonus, 0.76)
        case .analyzing:
            return analyzingSoftTarget()
        case .finalizingResult:
            return 0.99
        case .retryingNetwork:
            return min(max(target, progress + 0.035, 0.38), 0.78)
        case .retryingAI:
            return min(max(target, progress + 0.03, 0.62), 0.88)
        case .fallbackModel:
            return min(max(target, progress + 0.04, 0.72), 0.90)
        }
    }

    private func floorValue(for phase: AnalysisProgressPhase) -> Double {
        let multiPhotoBonus = min(Double(max(photoCount - 1, 0)) * 0.008, 0.032)

        switch phase {
        case .preparingInput:
            return 0.03
        case .creatingAnalysis:
            return 0.08
        case .uploadingPhotos:
            return min(0.20 + multiPhotoBonus, 0.24)
        case .submitting:
            return min(0.48 + multiPhotoBonus, 0.54)
        case .queued:
            return min(0.58 + multiPhotoBonus, 0.64)
        case .analyzing:
            return 0.68
        case .finalizingResult:
            return 0.94
        case .retryingNetwork:
            return min(max(progress, 0.22 + multiPhotoBonus), 0.58)
        case .retryingAI:
            return 0.62
        case .fallbackModel:
            return 0.72
        }
    }

    private func advanceOneTick(
        maxStep: Double? = nil,
        minStep: Double? = nil,
        duration: Double = 0.24
    ) {
        let ceiling = min(effectiveTarget(), maximumProgressBeforeCompletion())
        guard progress < ceiling else { return }

        let remaining = ceiling - progress
        let resolvedMaxStep = maxStep ?? ((phase == .analyzing || phase == .finalizingResult) ? 0.009 : 0.014)
        let resolvedMinStep = minStep ?? {
            if progress > 0.90 { return 0.0015 }
            if progress > 0.68 { return 0.0030 }
            return 0.0050
        }()
        let easedStep = max(resolvedMinStep, remaining * 0.18)
        let step = min(remaining, min(resolvedMaxStep, easedStep))

        withAnimation(.easeInOut(duration: duration)) {
            progress = min(progress + step, ceiling)
        }
    }

    private func effectiveTarget() -> Double {
        switch phase {
        case .analyzing:
            return max(target, analyzingSoftTarget())
        case .finalizingResult:
            return max(target, 0.99)
        default:
            return target
        }
    }

    private func maximumProgressBeforeCompletion() -> Double {
        switch phase {
        case .analyzing:
            return 0.98
        case .finalizingResult:
            return 0.99
        default:
            return 0.98
        }
    }

    private func analyzingSoftTarget(now: Date = Date()) -> Double {
        guard let analyzingStartedAt else { return 0.94 }

        let elapsed = max(0, now.timeIntervalSince(analyzingStartedAt))
        switch elapsed {
        case ..<10:
            return interpolatedProgress(from: 0.94, to: 0.95, elapsed: elapsed, duration: 10)
        case ..<25:
            return interpolatedProgress(from: 0.95, to: 0.96, elapsed: elapsed - 10, duration: 15)
        case ..<50:
            return interpolatedProgress(from: 0.96, to: 0.97, elapsed: elapsed - 25, duration: 25)
        default:
            return interpolatedProgress(from: 0.97, to: 0.98, elapsed: elapsed - 50, duration: 25)
        }
    }

    private func interpolatedProgress(from start: Double, to end: Double, elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return end }
        let fraction = min(max(elapsed / duration, 0), 1)
        return start + ((end - start) * fraction)
    }
}

struct AnalyzingView: View {
    /// Parent'tan binding - dismiss icin daha guvenilir (iOS 26 fullScreenCover).
    @Binding var isPresented: Bool
    /// nil = preview / mock modu; set edilirse gercek analiz calistirilir.
    var asyncWork: ((@escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> AnalysisResultBundle)? = nil
    var previewImage: UIImage? = nil
    var presentationMode: AnalysisWaitingPresentationMode = .photo
    var photoCount: Int = 0
    var onComplete: (AnalysisResultBundle?) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    @StateObject private var progressController = AnalysisProgressController()
    @State private var workTask: Task<Void, Never>?
    @State private var minimumDisplayTask: Task<Void, Never>?
    @State private var workDone = false
    @State private var minimumDisplayDone = false
    @State private var workResult: AnalysisResultBundle? = nil
    @State private var progressUpdate: AnalysisProgressUpdate?
    @State private var signalPulse = false
    @State private var isFinishing = false

    private var clampedProgress: Double {
        min(max(progressController.progress, 0), 1)
    }

    private var percentValue: Int {
        if clampedProgress >= 0.999 { return 100 }
        return min(99, max(0, Int((clampedProgress * 100).rounded(.down))))
    }

    private var resolvedPhotoCount: Int {
        max(photoCount, previewImage == nil ? 0 : 1)
    }

    var body: some View {
        ZStack {
            Color.rdPaper.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                scanCard
                    .padding(.bottom, 22)

                VStack(spacing: 6) {
                    Text(RDLocalization.string("localizable.analyzing.view.analiz.devam.ediyor.e37a9f96", table: .localizable, fallback: "Analiz devam ediyor"))
                        .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(Color.rdBlack)
                    Text(heroSubtitle)
                        .font(.system(size: RDFontScale.size(12.5), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.bottom, attentionProgressUpdate == nil ? 18 : 12)

                if let attentionProgressUpdate {
                    progressStatus(attentionProgressUpdate)
                        .padding(.bottom, 18)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                stepsList

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityIdentifier("analysis.loading")
        .onAppear {
            guard workTask == nil else { return }
            if progressController.progress <= 0.031 {
                progressController.start(photoCount: resolvedPhotoCount)
            }
            if minimumDisplayTask == nil && !minimumDisplayDone {
                startMinimumDisplayTimer()
            }
            startWork()
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                signalPulse = true
            }
        }
        .onDisappear {
            guard workDone || isFinishing || !isPresented else { return }
            progressController.cancel()
            minimumDisplayTask?.cancel()
            minimumDisplayTask = nil
            workTask?.cancel()
            workTask = nil
        }
    }

    // MARK: - Scan card

    private var scanCard: some View {
        ZStack {
            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 246, height: 246)
                        .blur(radius: 7)
                        .clipped()
                        .overlay(Color.black.opacity(0.24))
                } else {
                    RDPlaceholderPhoto(label: RDLocalization.string("localizable.analyzing.view.analiz.ediliyor.0f05c1de", table: .localizable, fallback: "Analiz ediliyor"), cornerRadius: 24)
                        .overlay(Color.black.opacity(0.10))
                }

                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    GeometryReader { geo in
                        let h = geo.size.height
                        let cycle = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.55) / 1.55
                        let y = CGFloat(cycle) * (h + 96) - 80

                        LinearGradient(
                            colors: [.clear, Color.rdGreen.opacity(0.62), Color.rdGreen.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 64)
                        .offset(y: y)
                    }
                }

                progressGlassOverlay

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.rdGreen.opacity(0.75), lineWidth: 2)
                    .shadow(color: Color.rdGreen.opacity(0.32), radius: 14)
            }
            .frame(width: 246, height: 246)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 18)

            aiSignal(icon: "shield.lefthalf.filled", label: RDLocalization.string("localizable.analyzing.view.kkd.c193486a", table: .localizable, fallback: "KKD"), alignment: .topLeading)
                .offset(x: -18, y: -12)
            aiSignal(icon: "waveform.path.ecg", label: RDLocalization.string("localizable.analyzing.view.risk.ca6b7fba", table: .localizable, fallback: "Risk"), alignment: .topTrailing)
                .offset(x: 18, y: 26)
            aiSignal(icon: "checklist.checked", label: RDLocalization.string("localizable.analyzing.view.kontrol.c7a07363", table: .localizable, fallback: "Kontrol"), alignment: .bottomLeading)
                .offset(x: -16, y: 16)
        }
        .frame(width: 296, height: 286)
    }

    private var progressGlassOverlay: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percentValue)")
                    .font(.system(size: RDFontScale.size(64), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("analysis.progress.percent")
                Text(RDLocalization.string("localizable.analyzing.view.copy.e242ae58", table: .localizable, fallback: "%"))
                    .font(.system(size: RDFontScale.size(28), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .shadow(color: .black.opacity(0.26), radius: 8, x: 0, y: 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(RDLocalization.string("localizable.analyzing.view.analiz.ilerleme.38fdc176", table: .localizable, fallback: "Analiz ilerleme"))
            .accessibilityValue(RDLocalization.format("localizable.analyzing.view.1.yuzde.b8176445", table: .localizable, fallback: "%1$@ yüzde", arguments: [String(describing: percentValue)]))

            if resolvedPhotoCount > 1 {
                Label(RDLocalization.format("localizable.analyzing.view.1.fotograf.79ece311", table: .localizable, fallback: "%1$@ fotoğraf", arguments: [String(describing: resolvedPhotoCount)]), systemImage: "photo.stack.fill")
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                    Capsule()
                        .fill(Color.rdGreen)
                        .frame(width: max(8, geo.size.width * clampedProgress))
                }
            }
            .frame(width: 156, height: 7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 210)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.rdBlack.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func aiSignal(icon: String, label: String, alignment: Alignment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.rdGreenDark)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule()
                .stroke(Color.rdGreen.opacity(0.26), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: Color.rdGreen.opacity(signalPulse ? 0.26 : 0.08), radius: signalPulse ? 14 : 6, x: 0, y: 5)
        .scaleEffect(signalPulse ? 1.03 : 0.98)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    // MARK: - Steps

    private var heroSubtitle: String {
        switch progressController.phase {
        case .preparingInput:
            return RDLocalization.string("localizable.analyzing.view.fotograflar.analiz.icin.hazirlaniyor.837cec1d", table: .localizable, fallback: "Fotoğraflar analiz için hazırlanıyor.")
        case .creatingAnalysis:
            return RDLocalization.string("localizable.analyzing.view.analiz.kaydi.olusturuluyor.e596706a", table: .localizable, fallback: "Analiz kaydı oluşturuluyor.")
        case .uploadingPhotos:
            return resolvedPhotoCount > 1
                ? RDLocalization.string("localizable.analyzing.view.fotograflar.guvenli.depoya.yukleniyor.5014defb", table: .localizable, fallback: "Fotoğraflar güvenli depoya yükleniyor.")
                : RDLocalization.string("localizable.analyzing.view.fotograf.guvenli.depoya.yukleniyor.efcdecc3", table: .localizable, fallback: "Fotoğraf güvenli depoya yükleniyor.")
        case .submitting:
            return RDLocalization.string("localizable.analyzing.view.istek.guvenli.sekilde.sunucuya.gonderiliyor.648ee33b", table: .localizable, fallback: "İstek güvenli şekilde sunucuya gönderiliyor.")
        case .queued:
            return RDLocalization.string("localizable.analyzing.view.analiz.kuyruga.alindi.sonuc.duzenli.olarak.kontr.4db902f5", table: .localizable, fallback: "Analiz kuyruğa alındı, sonuç düzenli olarak kontrol ediliyor.")
        case .analyzing:
            return RDLocalization.string("localizable.analyzing.view.ai.is.guvenligi.bulgularini.ve.risk.seviyelerini.9d183abc", table: .localizable, fallback: "AI, iş güvenliği bulgularını ve risk seviyelerini çıkarıyor.")
        case .finalizingResult:
            return RDLocalization.string("localizable.analyzing.view.analiz.tamamlandi.sonuc.ekrana.hazirlaniyor.538b7572", table: .localizable, fallback: "Analiz tamamlandı, sonuç ekrana hazırlanıyor.")
        case .retryingNetwork:
            return RDLocalization.string("localizable.analyzing.view.baglanti.toparlanirken.ayni.analiz.korunuyor.14f90e08", table: .localizable, fallback: "Bağlantı toparlanırken aynı analiz korunuyor.")
        case .retryingAI:
            return RDLocalization.string("localizable.analyzing.view.ai.servisi.yogun.analiz.otomatik.tekrar.deneniyo.a2e67967", table: .localizable, fallback: "AI servisi yoğun; analiz otomatik tekrar deneniyor.")
        case .fallbackModel:
            return RDLocalization.string("localizable.analyzing.view.analizi.tamamlamak.icin.yedek.model.devrede.746f2d37", table: .localizable, fallback: "Analizi tamamlamak için yedek model devrede.")
        }
    }

    private var attentionProgressUpdate: AnalysisProgressUpdate? {
        guard let progressUpdate else { return nil }
        switch progressUpdate.phase {
        case .retryingNetwork, .retryingAI, .fallbackModel, .finalizingResult:
            return progressUpdate
        default:
            return nil
        }
    }

    private var steps: [String] {
        [
            RDLocalization.string("localizable.analyzing.view.goruntu.kalitesi.okunuyor.3ec81981", table: .localizable, fallback: "Görüntü kalitesi okunuyor"),
            RDLocalization.string("localizable.analyzing.view.risk.sinyalleri.tanimlaniyor.0d952689", table: .localizable, fallback: "Risk sinyalleri tanımlanıyor"),
            RDLocalization.string("localizable.analyzing.view.kkd.ve.cevresel.kontroller.77cbd607", table: .localizable, fallback: "KKD ve çevresel kontroller"),
            RDLocalization.string("localizable.analyzing.view.bulgular.yapilandiriliyor.c027e804", table: .localizable, fallback: "Bulgular yapılandırılıyor"),
        ]
    }

    private var stepRanges: [(start: Double, end: Double)] {
        [
            (0.03, 0.25),
            (0.25, 0.55),
            (0.55, 0.82),
            (0.82, 1.00),
        ]
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                let fill = stepFill(index)
                let isCompleted = fill >= 0.995
                let isActive = !isCompleted && (fill > 0 || index == currentStepIndex)

                HStack(spacing: 10) {
                    stepDot(index: index, fill: fill)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label)
                            .font(.system(size: RDFontScale.size(13.5), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.rdLine.opacity(0.70))
                                Capsule()
                                    .fill(Color.rdGreen)
                                    .frame(width: max(fill > 0 ? 6 : 0, geo.size.width * fill))
                            }
                        }
                        .frame(height: 5)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                .background(isCompleted || isActive ? Color.rdWhite : Color.rdFog.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(isActive ? Color.rdGreen.opacity(0.42) : Color.rdLine.opacity(0.75), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(color: isActive ? Color.rdGreen.opacity(0.10) : Color.clear, radius: 12, x: 0, y: 7)
                .opacity(isCompleted || isActive ? 1.0 : 0.52)
                .scaleEffect(isActive ? 1.015 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentValue)
                .accessibilityIdentifier("analysis.progress.step.\(index + 1)")
            }
        }
        .frame(maxWidth: 320)
    }

    private var currentStepIndex: Int {
        for (index, range) in stepRanges.enumerated() where clampedProgress < range.end {
            return index
        }
        return max(stepRanges.count - 1, 0)
    }

    private func stepFill(_ index: Int) -> Double {
        guard stepRanges.indices.contains(index) else { return 0 }
        let range = stepRanges[index]
        if clampedProgress >= range.end { return 1 }
        if clampedProgress <= range.start { return 0 }
        return min(max((clampedProgress - range.start) / (range.end - range.start), 0), 1)
    }

    private func progressStatus(_ update: AnalysisProgressUpdate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: update.icon)
                .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(update.title)
                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(update.message)
                    .font(.system(size: RDFontScale.size(11), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.rdGreenSoft.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.rdGreen.opacity(0.16), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func stepDot(index: Int, fill: Double) -> some View {
        let isCompleted = fill >= 0.995
        let isActive = !isCompleted && (fill > 0 || index == currentStepIndex)

        ZStack {
            Circle()
                .fill(isCompleted ? Color.rdGreen : Color.rdFog)
                .overlay(
                    Circle().stroke(isActive ? Color.rdSelected : .clear, lineWidth: 2)
                )

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else if isActive {
                Circle()
                    .fill(Color.rdSelected)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Minimum display

    private func startMinimumDisplayTimer() {
        minimumDisplayTask?.cancel()
        minimumDisplayDone = false
        minimumDisplayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            minimumDisplayDone = true
            finishIfReady()
        }
    }

    // MARK: - Gercek is

    private func startWork() {
        guard let work = asyncWork else {
            workDone = true
            finishIfReady()
            return
        }
        workTask = Task { @MainActor in
            do {
                let result = try await work { update in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        progressUpdate = update
                    }
                    progressController.apply(update)
                }
                if Task.isCancelled {
                    workTask = nil
                    return
                }
                workResult = result
                workDone = true
                finishIfReady()
            } catch {
                if Task.isCancelled {
                    workTask = nil
                    return
                }
                workDone = true
                progressController.cancel()
                minimumDisplayTask?.cancel()
                minimumDisplayTask = nil
                workTask = nil
                let msg = error.localizedDescription
                isPresented = false
                onError(msg)
            }
        }
    }

    private func finishIfReady() {
        guard minimumDisplayDone && workDone && !isFinishing else { return }
        isFinishing = true
        let result = workResult
        Task { @MainActor in
            await progressController.complete()
            isPresented = false
            onComplete(result)
        }
    }
}

#Preview {
    AnalyzingView(isPresented: .constant(true), photoCount: 3)
}
