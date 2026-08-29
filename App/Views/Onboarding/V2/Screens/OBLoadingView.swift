import SwiftUI

struct OBLoadingView: View {
    @ObservedObject var state: OnboardingV2State
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var startedAt: Date?
    @State private var title = RDLocalization.string(
        "onboarding.obloading.view.sana.ozel.kurulum.hazirlaniyor.a7043077",
        table: .onboarding,
        fallback: "Sana özel kurulum hazırlanıyor…"
    )
    @State private var leaving = false
    @State private var hasStarted = false
    @State private var flowTask: Task<Void, Never>?

    private let loadingDuration: TimeInterval = 10

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 740

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: leaving)) { context in
                let progress = loadingProgress(at: context.date)

                VStack(spacing: compact ? 12 : 16) {
                    Spacer(minLength: compact ? 8 : 18)

                    progressView(progress: progress, compact: compact)

                    Text(title)
                        .font(RDTypography.font(size: RDFontScale.size(compact ? 19 : 22), weight: .bold))
                        .tracking(-0.45)
                        .foregroundStyle(Color.rdOnyx)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.25), value: title)

                    VStack(spacing: compact ? 8 : 10) {
                        stepRow(0, text: stepText(0), progress: progress, compact: compact)
                        stepRow(1, text: stepText(1), progress: progress, compact: compact)
                        stepRow(2, text: stepText(2), progress: progress, compact: compact)
                    }
                    .frame(maxWidth: 352)

                    OBLoadingTestimonialCarousel(compact: compact)
                        .frame(maxWidth: 352)

                    Spacer(minLength: compact ? 8 : 18)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.rdPaper)
        .opacity(leaving ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: leaving)
        .onAppear(perform: startFlowIfNeeded)
        .onDisappear(perform: cancelTask)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.loading")
    }

    private func startFlowIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        startedAt = Date()

        flowTask = Task { @MainActor in
            guard await wait(3.34) else { return }
            OBHaptic.soft()
            guard await wait(3.33) else { return }
            OBHaptic.soft()
            guard await wait(3.33) else { return }
            OBHaptic.success()
            title = RDLocalization.string(
                "onboarding.obloading.view.plan.hazir.d352f51f",
                table: .onboarding,
                fallback: "Plan hazır."
            )
            guard await wait(0.35) else { return }
            leaving = true
            guard await wait(0.30) else { return }
            onComplete()
        }
    }

    private func cancelTask() {
        flowTask?.cancel()
        flowTask = nil
    }

    @MainActor
    private func wait(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private extension OBLoadingView {
    func progressView(progress: Double, compact: Bool) -> some View {
        let diameter: CGFloat = compact ? 112 : 132
        let lineWidth: CGFloat = compact ? 9 : 10
        let percentage = min(100, Int((progress * 100).rounded(.down)))

        return ZStack {
            Circle()
                .stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1)
                .frame(width: diameter + 22, height: diameter + 22)

            Circle()
                .stroke(Color.rdOnyx.opacity(0.10), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(progress, 0.006))
                .stroke(
                    Color.rdOnyx,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.08), value: progress)

            Circle()
                .fill(Color.rdWhite)
                .padding(lineWidth + 7)
                .shadow(color: Color.rdOnyx.opacity(0.06), radius: 10, y: 5)

            VStack(spacing: 1) {
                Text("\(percentage)%")
                    .font(RDTypography.font(size: RDFontScale.size(compact ? 28 : 32), weight: .bold))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(Color.rdOnyx)

                Text(RDLocalization.string(
                    "onboarding.obloading.view.risk.analizi.hazirlaniyor.fbb92976",
                    table: .onboarding,
                    fallback: "Risk analizi"
                ))
                .font(RDTypography.font(size: RDFontScale.size(10), weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RDLocalization.string(
            "onboarding.obloading.view.yukleme.ilerlemesi.97991bbf",
            table: .onboarding,
            fallback: "Yükleme ilerlemesi"
        ))
        .accessibilityValue("\(percentage)%")
    }

    func loadingProgress(at date: Date) -> Double {
        guard let startedAt else { return 0 }
        return min(max(date.timeIntervalSince(startedAt) / loadingDuration, 0), 1)
    }
}

private extension OBLoadingView {
    func stepRow(
        _ index: Int,
        text: AttributedString,
        progress: Double,
        compact: Bool
    ) -> some View {
        let status = stepStatus(index, progress: progress)

        return HStack(spacing: 12) {
            stepStatusIcon(status)

            Text(text)
                .font(RDTypography.font(size: RDFontScale.size(compact ? 12.5 : 13.5), weight: .medium))
                .foregroundStyle(status == .pending ? Color.rdSlate.opacity(0.78) : Color.rdSlate)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: compact ? 46 : 50)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(status == .active ? Color.rdOnyx.opacity(0.20) : Color.rdOnyx.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.rdOnyx.opacity(status == .active ? 0.07 : 0.035), radius: 8, y: 3)
        .animation(.easeInOut(duration: 0.25), value: status)
    }

    @ViewBuilder
    func stepStatusIcon(_ status: OBLoadingStepStatus) -> some View {
        ZStack {
            Circle()
                .fill(status == .completed ? Color.rdOnyx : Color.rdOnyx.opacity(0.055))

            switch status {
            case .completed:
                Image(systemName: "checkmark")
                    .font(RDTypography.font(size: RDFontScale.size(10), weight: .bold))
                    .foregroundStyle(Color.rdWhite)
                    .transition(.scale.combined(with: .opacity))
            case .active:
                if reduceMotion {
                    Circle()
                        .stroke(Color.rdOnyx, lineWidth: 2)
                        .padding(7)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.rdOnyx)
                        .controlSize(.mini)
                }
            case .pending:
                Circle()
                    .fill(Color.rdSlate.opacity(0.48))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 28, height: 28)
    }

    func stepStatus(_ index: Int, progress: Double) -> OBLoadingStepStatus {
        let lowerBound = Double(index) / 3
        let upperBound = Double(index + 1) / 3

        if progress >= upperBound || progress >= 1 {
            return .completed
        }
        if progress >= lowerBound {
            return .active
        }
        return .pending
    }
}

private enum OBLoadingStepStatus: Equatable {
    case pending
    case active
    case completed
}

private extension OBLoadingView {
    func stepText(_ index: Int) -> AttributedString {
        switch index {
        case 0:
            let label = state.primarySectorLabel
            return highlighting(
                label,
                in: RDLocalization.format(
                    "onboarding.obloading.view.icin.risk.analiz.sablonlari.yukleniyor.4b30b304",
                    table: .onboarding,
                    fallback: "%1$@ için risk analiz şablonları yükleniyor...",
                    arguments: [label]
                )
            )
        case 1:
            let label = state.hazardsLabel
            return highlighting(
                label,
                in: RDLocalization.format(
                    "onboarding.obloading.view.sinifi.icin.kontrol.listesi.hazirlaniyor.85dc6c38",
                    table: .onboarding,
                    fallback: "%1$@ sınıfı için kontrol listesi hazırlanıyor...",
                    arguments: [label]
                )
            )
        default:
            let label = state.certificateLabel
            return highlighting(
                label,
                in: RDLocalization.format(
                    "onboarding.obloading.view.icin.rapor.formati.kisisellestiriliyor.34aea260",
                    table: .onboarding,
                    fallback: "%1$@ için rapor formatı kişiselleştiriliyor...",
                    arguments: [label]
                )
            )
        }
    }

    func highlighting(_ label: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: label) {
            text[range].foregroundColor = .rdOnyx
            text[range].font = RDTypography.font(size: RDFontScale.size(13.5), weight: .bold)
        }
        return text
    }
}

#Preview {
    let state = OnboardingV2State()
    state.certificate = .A
    state.hazards = [.critical]
    state.sectors = [.construction]
    return OBLoadingView(state: state) {}
}
