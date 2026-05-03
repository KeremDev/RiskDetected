import SwiftUI

struct RiskDetailView: View {
    let finding: Finding
    var method: RiskMethod = .fineKinney
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                photoCard
                methodologyCard
                comparisonCard

                section("Tehlike açıklaması", body: finding.description)
                section("Önerilen önlem", body: finding.action,
                        accent: Color.rdGreenSoft, accentText: Color.rdGreenDark,
                        icon: "shield.lefthalf.filled")
                section("Standart referansları", body: finding.references,
                        accent: Color.rdFog, accentText: Color.rdGraphite,
                        icon: "books.vertical")

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.rdPaper)
    }

    // MARK: - Header

    private var header: some View {
        let band = finding.band(for: method)
        return VStack(alignment: .leading, spacing: 8) {
            Text(finding.category.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)

            Text(finding.title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.rdBlack)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                RDChip(level: band.level, label: band.label)
                Text("%\(Int(finding.confidence * 100)) güven")
                    .rdMono(size: 11, weight: .semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.rdGreenDark)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.top, 4)
        }
    }

    private var photoCard: some View {
        RDPlaceholderPhoto(label: "Bulgu detayı", cornerRadius: 16)
            .frame(height: 180)
    }

    // MARK: - Methodology

    private var methodologyCard: some View {
        let band = finding.band(for: method)
        let score = finding.score(for: method)

        return RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(method.fullName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(Int(score))")
                        .font(.system(size: 36, weight: .heavy, design: .monospaced))
                        .foregroundStyle(band.color)
                        .tracking(-0.6)
                    Text("R = \(finding.formula(for: method))")
                        .rdMono(size: 12, weight: .semibold)
                        .foregroundStyle(Color.rdSlate)
                }
                Text(band.action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(band.color)
            }
        }
    }

    private var comparisonCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Yöntem karşılaştırması".uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)

                HStack(spacing: 10) {
                    methodBox(
                        title: "Fine-Kinney",
                        formula: "O × F × Ş",
                        score: Int(finding.fkScore),
                        band: finding.fkBand,
                        active: method == .fineKinney
                    )
                    methodBox(
                        title: "5×5 L-Tipi",
                        formula: "O × Ş",
                        score: finding.m5Score,
                        band: finding.m5Band,
                        active: method == .matrix5x5
                    )
                }
            }
        }
    }

    private func methodBox(title: String, formula: String, score: Int, band: RiskBand, active: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
            Text("R = \(formula)")
                .rdMono(size: 10)
                .foregroundStyle(Color.rdSlate)

            Text("\(score)")
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(band.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(band.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(band.color)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? Color.rdBlack : Color.rdLine, lineWidth: active ? 1.5 : 1)
        )
    }

    // MARK: - Section

    private func section(_ title: String, body: String,
                         accent: Color = .rdFog, accentText: Color = .rdGraphite,
                         icon: String = "info.circle") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentText)
                    .padding(.top, 1)
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    RiskDetailView(finding: Finding.mock[0], method: .fineKinney)
}
