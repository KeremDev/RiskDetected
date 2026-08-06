import SwiftUI

struct RDPlanUpsellCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.rdPlanPlus.opacity(colorScheme == .dark ? 0.10 : 0.16))
                    .frame(width: 96, height: 96)
                    .blur(radius: colorScheme == .dark ? 22 : 16)
                    .offset(x: 42, y: -58)

                Circle()
                    .fill(Color.rdGreen.opacity(colorScheme == .dark ? 0.08 : 0.10))
                    .frame(width: 86, height: 86)
                    .blur(radius: colorScheme == .dark ? 22 : 18)
                    .offset(x: -214, y: 78)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        RDTierBadge(tier: .plus)
                        RDTierBadge(tier: .pro)
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: RDFontScale.size(20), weight: .bold, design: .rounded))
                            .foregroundStyle(arrowColor)
                    }

                    Text(RDLocalization.string("localizable.rdplan.upsell.card.plus.veya.pro.ya.yukselt.e876bb04", table: .localizable, fallback: "Plus veya Pro'ya yükselt"))
                        .font(.system(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)

                    VStack(alignment: .leading, spacing: 7) {
                        benefit(RDLocalization.string("localizable.rdplan.upsell.card.daha.fazla.gunluk.analiz.0ca99c4a", table: .localizable, fallback: "Daha fazla günlük analiz"))
                        benefit(RDLocalization.string("localizable.rdplan.upsell.card.detayli.risk.raporlari.3eb225a9", table: .localizable, fallback: "Detaylı risk raporları"))
                        benefit(RDLocalization.string("localizable.rdplan.upsell.card.fine.kinney.5x5.matris.1e70bf1b", table: .localizable, fallback: "Fine-Kinney + 5x5 matris"))
                        benefit(RDLocalization.string("localizable.rdplan.upsell.card.pdf.ve.excel.disa.aktarim.6dd65472", table: .localizable, fallback: "PDF ve Excel dışa aktarım"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
            .profileCardDepth(colorScheme: colorScheme, accent: Color.rdPlanPlus)
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color(hex: "#0D1110"), Color(hex: "#121817"), Color(hex: "#1A1509")]
            : [Color(hex: "#F8FAF9"), Color(hex: "#EEF2F1"), Color(hex: "#F6F0DF")]
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.rdBlack
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.70) : Color.rdSlate
    }

    private var arrowColor: Color {
        colorScheme == .dark ? Color.rdPlanPlus : Color.rdPlanPlusDark
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.rdPlanPlus.opacity(0.22) : Color.rdLine.opacity(0.95)
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: RDFontScale.size(9), weight: .black, design: .rounded))
                .foregroundStyle(Color.rdOnyx)
                .frame(width: 18, height: 18)
                .background(Color.rdPlanPlus)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: RDFontScale.size(12.5), weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

#Preview("Plan Upsell Card") {
    RDPlanUpsellCard {}
        .padding(20)
        .background(Color.rdPaper)
}
