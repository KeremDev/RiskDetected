import SwiftUI

struct ProfessionalProgressCompetencyMapView: View {
    let competencies: [ProfessionalProgressCompetencyStat]
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: RDSpacing.sm) {
            if !compact {
                Text("Yetkinlik Haritası")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
            }

            if compact {
                compactChart
            } else {
                VStack(spacing: 10) {
                    ForEach(displayRows) { stat in
                        competencyRow(stat)
                    }
                }
            }
        }
    }

    private var displayRows: [ProfessionalProgressCompetencyStat] {
        let statsByKey = Dictionary(uniqueKeysWithValues: competencies.map { ($0.competencyKey, $0) })
        let all = ProfessionalProgressCompetency.allCases.map { competency in
            statsByKey[competency.rawValue] ?? ProfessionalProgressCompetencyStat(
                userID: UUID(),
                competencyKey: competency.rawValue,
                analysisCount: 0,
                reportCount: 0,
                findingCount: 0,
                criticalCount: 0,
                highCount: 0,
                mediumCount: 0,
                lowCount: 0,
                unknownCount: 0,
                onboardingSeed: false,
                lastDetectedAt: nil
            )
        }

        if compact {
            let active = all
                .filter { $0.signalCount > 0 || $0.onboardingSeed }
                .sorted { $0.signalCount == $1.signalCount ? $0.score > $1.score : $0.signalCount > $1.signalCount }
            return Array(active.prefix(4))
        }
        return all
    }

    private var compactChart: some View {
        let rows = displayRows
        let total = chartTotal(rows)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                donutChart(rows: rows, total: total)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color.rdGreenDark)
                        Text("Yetkinlik dağılımı")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 7),
                            GridItem(.flexible(), spacing: 7)
                        ],
                        alignment: .leading,
                        spacing: 7
                    ) {
                        ForEach(rows) { stat in
                            compactLegendChip(stat, total: total)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactChartAccessibilityLabel(rows: rows, total: total))
    }

    private func donutChart(rows: [ProfessionalProgressCompetencyStat], total: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.rdFog, lineWidth: 16)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, stat in
                let start = sliceStart(index: index, rows: rows, total: total)
                let end = sliceEnd(index: index, rows: rows, total: total)
                Circle()
                    .trim(from: start + 0.006, to: max(start + 0.008, end - 0.006))
                    .stroke(
                        stat.competency?.accent ?? Color.rdGreen,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Circle()
                .fill(Color.rdWhite)
                .frame(width: 66, height: 66)
                .overlay(Circle().stroke(Color.rdLine.opacity(0.72), lineWidth: 1))

            VStack(spacing: 0) {
                Text("\(rows.count)")
                    .rdMono(size: 22, weight: .bold)
                    .foregroundStyle(Color.rdBlack)
                Text("alan")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .frame(width: 118, height: 118)
    }

    private func compactLegendChip(_ stat: ProfessionalProgressCompetencyStat, total: Int) -> some View {
        let competency = stat.competency ?? .fire
        let percent = Int((Double(chartWeight(stat)) / Double(total) * 100).rounded())

        return HStack(spacing: 5) {
            Circle()
                .fill(competency.accent)
                .frame(width: 7, height: 7)
            Text(compactLabel(for: competency))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 2)
            Text("%\(percent)")
                .rdMono(size: 10, weight: .bold)
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(Color.rdBlack)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(competency.accent.opacity(0.10))
        .clipShape(Capsule())
    }

    private func chartWeight(_ stat: ProfessionalProgressCompetencyStat) -> Int {
        max(stat.signalCount, stat.onboardingSeed ? 1 : 0)
    }

    private func compactLabel(for competency: ProfessionalProgressCompetency) -> String {
        switch competency {
        case .workingAtHeight: return "Yüksekte"
        case .psychosocial: return "Psikososyal"
        case .construction: return "İnşaat"
        case .ergonomics: return "Ergonomi"
        case .electrical: return "Elektrik"
        case .chemical: return "Kimyasal"
        case .mechanical: return "Mekanik"
        case .factory: return "Fabrika"
        case .fire: return "Yangın"
        case .mining: return "Maden"
        case .ppe: return "KKD"
        }
    }

    private func chartTotal(_ rows: [ProfessionalProgressCompetencyStat]) -> Int {
        max(rows.reduce(0) { $0 + chartWeight($1) }, 1)
    }

    private func sliceStart(index: Int, rows: [ProfessionalProgressCompetencyStat], total: Int) -> CGFloat {
        let previous = rows.prefix(index).reduce(0) { $0 + chartWeight($1) }
        return CGFloat(previous) / CGFloat(total)
    }

    private func sliceEnd(index: Int, rows: [ProfessionalProgressCompetencyStat], total: Int) -> CGFloat {
        let previousAndCurrent = rows.prefix(index + 1).reduce(0) { $0 + chartWeight($1) }
        return CGFloat(previousAndCurrent) / CGFloat(total)
    }

    private func compactChartAccessibilityLabel(rows: [ProfessionalProgressCompetencyStat], total: Int) -> String {
        let parts = rows.map { stat in
            let competency = stat.competency?.label ?? stat.competencyKey
            let percent = Int((Double(chartWeight(stat)) / Double(total) * 100).rounded())
            return "\(competency) yüzde \(percent)"
        }
        return "Yetkinlik dağılımı. \(parts.joined(separator: ", "))."
    }

    private func competencyRow(_ stat: ProfessionalProgressCompetencyStat) -> some View {
        let competency = stat.competency ?? .fire
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: competency.icon)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(competency.accent)
                    .frame(width: 32, height: 32)
                    .background(competency.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: RDRadius.sm))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(competency.label)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                        if stat.onboardingSeed && stat.signalCount == 0 {
                            Text("Beyan edilen alan")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdGreenDark)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.rdGreenSoft)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(stat.findingCount) bulgu · \(stat.reportCount) rapor")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }

                Spacer(minLength: 0)

                Text("\(stat.score)")
                    .rdMono(size: 16, weight: .bold)
                    .foregroundStyle(Color.rdBlack)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.rdFog)
                    Capsule()
                        .fill(competency.accent)
                        .frame(width: geo.size.width * CGFloat(stat.score) / 100)
                }
            }
            .frame(height: 6)

            if !compact && stat.findingCount > 0 {
                HStack(spacing: 6) {
                    riskChip(label: "Kritik", count: stat.criticalCount, color: .rdCritical)
                    riskChip(label: "Yüksek", count: stat.highCount, color: .rdHigh)
                    riskChip(label: "Orta", count: stat.mediumCount, color: .rdMedium)
                    riskChip(label: "Düşük", count: stat.lowCount, color: .rdLow)
                }
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.md)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.md))
    }

    private func riskChip(label: String, count: Int, color: Color) -> some View {
        Text("\(label) \(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}
