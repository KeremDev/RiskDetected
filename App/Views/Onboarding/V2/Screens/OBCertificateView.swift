import SwiftUI

struct OBCertificateView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void

    private let helmetItems: [(cert: OBCertificate, title: String, sub: String, hatColor: Color, brimColor: Color)] = [
        (.A, "A Sınıfı İSG Uzmanı", "Çok tehlikeli sınıfta yetkili.",
         Color(hex: "#FFB300"), Color(hex: "#D9A012")),
        (.B, "B Sınıfı İSG Uzmanı", "Tehlikeli ve az tehlikeli sınıflarda yetkili.",
         Color(hex: "#4F86E0"), Color(hex: "#2A5A99")),
        (.C, "C Sınıfı İSG Uzmanı", "Az tehlikeli sınıfta yetkili.",
         Color(hex: "#00B82E"), Color(hex: "#008F24")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 2, total: 5, trailingLabel: "02 / 05", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 14) {
                        OBHeroTile(tint: .warm) { OBHeroCertificate() }
                            .obStage(delay: 0.08)
                        Text("Hangi sertifika sınıfındasın?")
                            .font(.system(size: 28, weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.14)
                        Text("Sana özel risk şablonları hazırlayacağız.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .obStage(delay: 0.28)

                    VStack(spacing: 10) {
                        ForEach(Array(helmetItems.enumerated()), id: \.offset) { i, item in
                            OBCard(
                                title: item.title,
                                subtitle: item.sub,
                                isSelected: state.certificate == item.cert,
                                leading: {
                                    HelmetBadge(letter: item.cert.rawValue,
                                                hatColor: item.hatColor,
                                                brimColor: item.brimColor,
                                                selected: state.certificate == item.cert)
                                }
                            ) {
                                OBHaptic.medium()
                                withAnimation(.obSpring) { state.certificate = item.cert }
                            }
                            .obStage(delay: 0.36 + Double(i) * 0.06)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            OBFooter {
                OBPrimaryButton(title: "Devam", enabled: state.certificate != nil) { onNext() }
                    .obStage(delay: 0.7)
            }
        }
        .background(Color.rdPaper)
    }
}

// MARK: - Helmet badge (44x44) matching SVG hat shape from design

private struct HelmetBadge: View {
    let letter: String
    let hatColor: Color
    let brimColor: Color
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.rdOnyx : Color.rdFog)

            VStack(spacing: 2) {
                Canvas { ctx, size in
                    // Hat path from SVG viewBox 30x18, scaled to 30x18
                    var hat = Path()
                    hat.move(to: CGPoint(x: 3, y: 16))
                    hat.addQuadCurve(to: CGPoint(x: 15, y: 4), control: CGPoint(x: 3, y: 6))
                    hat.addQuadCurve(to: CGPoint(x: 27, y: 16), control: CGPoint(x: 27, y: 6))
                    hat.addLine(to: CGPoint(x: 29, y: 17))
                    hat.addLine(to: CGPoint(x: 1, y: 17))
                    hat.closeSubpath()
                    ctx.fill(hat, with: .color(hatColor))

                    // Brim shadow stripe
                    ctx.fill(Path(CGRect(x: 1, y: 15, width: 28, height: 2.5)),
                             with: .color(brimColor.opacity(0.55)))
                }
                .frame(width: 30, height: 18)

                Text(letter)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? .white : Color.rdOnyx)
            }
        }
        .frame(width: 44, height: 44)
    }
}
