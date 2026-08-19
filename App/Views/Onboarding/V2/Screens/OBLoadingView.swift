import SwiftUI

struct OBLoadingView: View {
    @ObservedObject var state: OnboardingV2State
    let onComplete: () -> Void

    @State private var title: String = RDLocalization.string("onboarding.obloading.view.sana.ozel.kurulum.hazirlaniyor.a7043077", table: .onboarding, fallback: "Sana özel kurulum hazırlanıyor…")
    @State private var revealed: [Bool] = [false, false, false]
    @State private var done: [Bool] = [false, false, false]
    @State private var rotation: Double = 0
    @State private var corePulse: CGFloat = 1
    @State private var ringPulse1: CGFloat = 0.7
    @State private var ringOpacity1: Double = 0.4
    @State private var ringPulse2: CGFloat = 0.7
    @State private var ringOpacity2: Double = 0.4
    @State private var leaving: Bool = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            loader

            Text(title)
                .font(.system(size: RDFontScale.size(20), weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Color.rdOnyx)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: title)

            VStack(spacing: 14) {
                stepRow(0, text: stepText(0))
                stepRow(1, text: stepText(1))
                stepRow(2, text: stepText(2))
            }
            .frame(maxWidth: 320)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rdPaper)
        .opacity(leaving ? 0 : 1)
        .animation(.easeInOut(duration: 0.32), value: leaving)
        .onAppear { runSequence() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.loading")
    }

    private var loader: some View {
        ZStack {
            Circle().stroke(Color.rdOnyx.opacity(0.07), lineWidth: 1.5).frame(width: 112, height: 112)
            Circle().stroke(Color.rdOnyx.opacity(0.04), lineWidth: 1.5).frame(width: 84, height: 84)

            Circle().stroke(Color.rdOnyx, lineWidth: 1.5)
                .frame(width: 112, height: 112)
                .scaleEffect(ringPulse1)
                .opacity(ringOpacity1)
            Circle().stroke(Color.rdOnyx, lineWidth: 1.5)
                .frame(width: 112, height: 112)
                .scaleEffect(ringPulse2)
                .opacity(ringOpacity2)

            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(Color.rdOnyx, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(rotation))

            ZStack {
                Circle().fill(Color.rdOnyx)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: RDFontScale.size(20), weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .scaleEffect(corePulse)
            .shadow(color: Color.rdOnyx.opacity(0.18), radius: 12, y: 8)
        }
        .frame(width: 112, height: 112)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                corePulse = 0.94
            }
            withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) {
                ringPulse1 = 1.35; ringOpacity1 = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) {
                    ringPulse2 = 1.35; ringOpacity2 = 0
                }
            }
        }
    }

    private func stepRow(_ i: Int, text: AttributedString) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done[i] ? Color.rdGreen : Color.rdOnyx.opacity(0.06))
                if done[i] {
                    Image(systemName: "checkmark")
                        .font(.system(size: RDFontScale.size(11), weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().fill(Color.rdSlate.opacity(0.8))
                        .frame(width: 6, height: 6)
                        .scaleEffect(revealed[i] ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: revealed[i])
                }
            }
            .frame(width: 28, height: 28)

            Text(text)
                .font(.system(size: RDFontScale.size(14), weight: .medium))
                .foregroundStyle(done[i] ? Color.rdOnyx : Color.rdSlate)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .opacity(revealed[i] ? 1 : 0)
        .offset(y: revealed[i] ? 0 : 8)
        .animation(.obSpring, value: revealed[i])
    }

    private func stepText(_ i: Int) -> AttributedString {
        switch i {
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

    /// Kullanıcının seçimi cümlenin içinde nerede geçiyorsa orada koyulaşır. Etiket
    /// cümleye yer tutucuyla giriyor; böylece boşluk ve sözcük sırası çeviriye kalıyor,
    /// metin parçaları uç uca eklenmiyor.
    private func highlighting(_ label: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: label) {
            text[range].foregroundColor = .rdOnyx
            text[range].font = .system(size: RDFontScale.size(14), weight: .semibold)
        }
        return text
    }

    private func runSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4)  { revealed[0] = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1)  { revealed[1] = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8)  { revealed[2] = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9)  { OBHaptic.soft(); withAnimation(.obSpring) { done[0] = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8)  { OBHaptic.soft(); withAnimation(.obSpring) { done[1] = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7)  { OBHaptic.soft(); withAnimation(.obSpring) { done[2] = true } }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0)  { title = RDLocalization.string("onboarding.obloading.view.plan.hazir.d352f51f", table: .onboarding, fallback: "Plan hazır.") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5)  { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.85) { onComplete() }
    }
}

#Preview {
    let state = OnboardingV2State()
    state.certificate = .A
    state.hazards = [.critical]
    state.sectors = [.construction]
    return OBLoadingView(state: state) {}
}
