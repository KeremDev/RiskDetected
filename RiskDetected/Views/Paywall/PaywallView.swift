import SwiftUI

struct PaywallView: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void

    enum Plan: String, CaseIterable, Identifiable {
        case yearly, monthly
        var id: String { rawValue }

        var label: String {
            switch self {
            case .yearly:  return "Yıllık"
            case .monthly: return "Aylık"
            }
        }

        var price: String {
            switch self {
            case .yearly:  return "₺149,99"
            case .monthly: return "₺249,99"
            }
        }

        var sub: String {
            switch self {
            case .yearly:  return "ay başına · ₺1.799,99 yıllık"
            case .monthly: return "ay başına · istediğin zaman iptal"
            }
        }

        var badge: String? {
            self == .yearly ? "2 ay hediye" : nil
        }
    }

    @State private var selected: Plan = .yearly

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.rdWhite.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        features
                        plansSection
                        footnote
                        ctaButton
                        legalRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 56) // close button area
                    .padding(.bottom, 24)
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Color.rdBlack)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            RDProBadge()
            Text("Sahanın profesyonel risk asistanı.")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.rdBlack)
                .fixedSize(horizontal: false, vertical: true)
            Text("PRO ile detaylı risk tabloları, sınırsız PDF rapor ve gelişmiş AI canvasları açılır.")
                .font(.system(size: 15))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Feature {
        let icon: String
        let title: String
        let detail: String
    }

    private let featureList: [Feature] = [
        .init(icon: "rectangle.3.group", title: "Detaylı risk analizi tablosu",
              detail: "Olasılık × etki matrisi ve kontrol önerileri"),
        .init(icon: "arrow.down.to.line", title: "Sınırsız PDF rapor",
              detail: "Logolu, denetim hazır, paylaşılabilir"),
        .init(icon: "doc.text", title: "Geçmiş analizlere tam erişim",
              detail: "90 günden uzun sınırsız arşiv"),
        .init(icon: "sparkles", title: "Gelişmiş AI canvasları",
              detail: "Acil risk + prosedür uygunluk modülleri"),
    ]

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(featureList.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: f.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color.rdGreenDark)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.rdBlack)
                        Text(f.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rdSlate)
                    }
                    Spacer()
                }
            }
        }
    }

    private var plansSection: some View {
        VStack(spacing: 10) {
            ForEach(Plan.allCases) { plan in
                planRow(plan)
            }
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        let active = selected == plan
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.15)) { selected = plan }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(active ? Color.rdBlack : Color.rdLine, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if active {
                        Circle().fill(Color.rdBlack).frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text(plan.sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rdSlate)
                }

                Spacer()
                Text(plan.price)
                    .rdMono(size: 18, weight: .bold)
                    .foregroundStyle(Color.rdBlack)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(active ? Color.rdBlack : Color.rdLine,
                                    lineWidth: active ? 2 : 1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if let badge = plan.badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.rdGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.top, -10)
                        .padding(.trailing, 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        Text("7 gün ücretsiz dene · İlk ödeme öncesi hatırlatma")
            .font(.system(size: 12))
            .foregroundStyle(Color.rdSlate)
            .frame(maxWidth: .infinity)
    }

    private var ctaButton: some View {
        RDButton(title: "PRO'yu Etkinleştir", style: .detect, trailingIcon: "arrow.right", height: 56) {
            onSubscribe()
        }
    }

    private var legalRow: some View {
        HStack(spacing: 14) {
            Spacer()
            Text("Geri Yükle"); separator; Text("Şartlar"); separator; Text("Gizlilik")
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.rdSlate)
    }

    private var separator: some View {
        Text("·").foregroundStyle(Color.rdSlate.opacity(0.6))
    }
}

#Preview {
    PaywallView(onClose: {}, onSubscribe: {})
}
