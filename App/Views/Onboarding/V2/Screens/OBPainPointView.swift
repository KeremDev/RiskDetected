import SwiftUI

struct OBPainPointView: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var checked: [Bool] = [false, false, false]
    @State private var shimmer: CGFloat = -1.0

    private let pains: [(icon: String, text: String)] = [
        ("clock", "Saatlerce süren rapor yazımı."),
        ("photo.on.rectangle.angled", "Dağınık fotoğraflar ve notlar."),
        ("calendar.badge.exclamationmark", "Geç teslim edilen değerlendirmeler.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(showBack: false, step: 1, total: 5, trailingLabel: "01 / 05")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        OBHeroTile(tint: .dusk) {
                            ZStack {
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(hex: "#F4F1E8"))
                                    .offset(x: 32, y: -18)
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(Color(hex: "#F8F7F3"))
                                    .rotationEffect(.degrees(5))
                            }
                        }
                        .obStage(delay: 0.08)

                        Text("Sahada gördüklerini akşam ofiste mi yazıyorsun?")
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(-0.6)
                            .lineSpacing(2)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.14)

                        Text("Tanıdık geliyor mu?")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(height: 1)
                        .obStage(delay: 0.28)

                    VStack(spacing: 10) {
                        ForEach(Array(pains.enumerated()), id: \.offset) { i, p in
                            painCard(icon: p.icon, text: p.text, isChecked: checked[i])
                                .obStage(delay: 0.32 + Double(i) * 0.08)
                        }
                    }

                    mirror
                        .padding(.top, 8)
                        .obStage(delay: 0.62)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            OBFooter {
                OBPrimaryButton(title: "Devam", accessibilityID: "onboarding.pain.continue") { onNext() }
                    .obStage(delay: 0.78)
                Button {
                    OBHaptic.soft(); onSkip()
                } label: {
                    Text("Atla")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.rdSlate.opacity(0.6))
                        .padding(.vertical, 6)
                }
                .obStage(delay: 0.88)
                .accessibilityIdentifier("onboarding.pain.skip")
            }
        }
        .background(Color.rdPaper)
        .onAppear { runCheckSequence() }
        .accessibilityIdentifier("onboarding.pain_point")
    }

    private func painCard(icon: String, text: String, isChecked: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.rdOnyx)
                .frame(width: 40, height: 40)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.rdOnyx)
                .lineLimit(2)
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.rdOnyx.opacity(0.18), lineWidth: 1.5)
                    .opacity(isChecked ? 0 : 1)
                Circle()
                    .fill(Color.rdGreen)
                    .scaleEffect(isChecked ? 1 : 0.2)
                    .opacity(isChecked ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(isChecked ? 1 : 0)
                    .scaleEffect(isChecked ? 1 : 0.4)
            }
            .frame(width: 22, height: 22)
            .animation(.spring(response: 0.45, dampingFraction: 0.55), value: isChecked)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private var mirror: some View {
        HStack {
            (Text("Bunu ").foregroundColor(.white)
             + Text("birlikte").foregroundColor(Color(hex: "#4FE07E")).bold()
             + Text(" değiştireceğiz.").foregroundColor(.white))
                .font(.system(size: 16, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(
            ZStack {
                Color.rdOnyx
                RadialGradient(colors: [Color.rdGreen.opacity(0.22), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 200)
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color(hex: "#4FE07E").opacity(0.4), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .blur(radius: 6)
                    .rotationEffect(.degrees(18))
                    .offset(x: geo.size.width * shimmer)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { startShimmer() }
    }

    private func runCheckSequence() {
        for i in 0..<pains.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.45) {
                OBHaptic.soft()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    checked[i] = true
                }
            }
        }
    }

    private func startShimmer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            animateShimmer()
        }
    }

    private func animateShimmer() {
        shimmer = -1.0
        withAnimation(.easeInOut(duration: 1.5)) {
            shimmer = 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            animateShimmer()
        }
    }
}
