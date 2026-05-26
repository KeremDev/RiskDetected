import SwiftUI

struct ProfessionalProgressTitlesSheet: View {
    let summary: ProfessionalProgressSummary

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                progressHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                titleSection("Temel Rütbeler", titles: Array(ProfessionalProgressTitle.allCases.prefix(3)))
                sectionDivider
                titleSection("Uzmanlık Rütbeleri", titles: Array(ProfessionalProgressTitle.allCases.dropFirst(3).prefix(3)))
                sectionDivider
                titleSection("Ustalık", titles: Array(ProfessionalProgressTitle.allCases.suffix(1)))
                Spacer(minLength: 0)
            }
            .background(Color.rdWhite)
        }
        .background(Color.rdWhite)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Mesleki Ünvanlar")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.rdWhite)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rdLine)
                .frame(height: 1)
        }
    }

    private var progressHeader: some View {
        ProfessionalProgressHomeCard(
            summary: summary,
            accessibilityIdentifier: "professionalProgress.titles.progress.card",
            displayStyle: .showcase
        )
    }

    private func titleSection(_ title: String, titles: [ProfessionalProgressTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .padding(.horizontal, 24)

            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                ForEach(titles) { professionalTitle in
                    rankTile(professionalTitle)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.rdFog)
            .frame(height: 6)
    }

    private func rankTile(_ title: ProfessionalProgressTitle) -> some View {
        let earned = summary.profile.totalMDP >= title.threshold
        let current = title == summary.currentTitle
        let style = RankVisualStyle(title: title)

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                rankIcon(style: style, earned: earned, current: current)

                if current {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdPlanPlus)
                        .background(Circle().fill(Color.rdWhite).frame(width: 20, height: 20))
                        .offset(x: 3, y: -2)
                } else if !earned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(Color.rdWhite)
                        .frame(width: 20, height: 20)
                        .background(Color.rdSlate.opacity(0.80))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.rdWhite, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(spacing: 1) {
                Text(title.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(earned ? Color.rdBlack : Color.rdSlate)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)

                Text("\(formattedNumber(title.threshold)) MDP")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(earned ? Color.rdSlate : Color.rdSlate.opacity(0.70))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title.label), \(earned ? "kazanıldı" : "henüz kazanılmadı")")
    }

    private func rankIcon(style: RankVisualStyle, earned: Bool, current: Bool) -> some View {
        ZStack {
            Circle()
                .fill(earned ? style.background : lockedIconBackground)
                .frame(width: 58, height: 58)
                .shadow(color: earned ? style.shadow : Color.rdSlate.opacity(0.12), radius: earned ? 12 : 7, x: 0, y: 5)

            Circle()
                .stroke(earned ? Color.rdWhite : Color.rdLine, lineWidth: 4)
                .frame(width: 58, height: 58)

            Circle()
                .stroke(current ? Color.rdPlanPlus.opacity(0.95) : Color.clear, lineWidth: 3)
                .frame(width: 66, height: 66)

            Image(systemName: style.symbol)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(earned ? style.foreground : Color.rdSlate.opacity(0.45))
                .symbolRenderingMode(.hierarchical)

            if earned {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .offset(x: 17, y: -17)
            }
        }
        .frame(width: 70, height: 70)
    }

    private var lockedIconBackground: LinearGradient {
        LinearGradient(
            colors: [Color.rdFog, Color(hex: "#E5E9EC")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct RankVisualStyle {
    let symbol: String
    let background: LinearGradient
    let foreground: Color
    let shadow: Color

    init(title: ProfessionalProgressTitle) {
        switch title {
        case .candidate:
            symbol = "person.crop.circle.badge.checkmark"
            foreground = Color(hex: "#087C5B")
            shadow = Color(hex: "#00B894").opacity(0.26)
            background = Self.gradient("#DDFCF0", "#48CFAE")
        case .fieldObserver:
            symbol = "binoculars.fill"
            foreground = Color(hex: "#9A5B00")
            shadow = Color(hex: "#C57A12").opacity(0.26)
            background = Self.gradient("#FFF2D4", "#D59A45")
        case .riskHunter:
            symbol = "scope"
            foreground = Color(hex: "#8F421D")
            shadow = Color(hex: "#A15C38").opacity(0.28)
            background = Self.gradient("#FFE1D0", "#B66A45")
        case .hazardAnalyst:
            symbol = "exclamationmark.triangle.fill"
            foreground = Color(hex: "#8F2B13")
            shadow = Color(hex: "#E85D35").opacity(0.28)
            background = Self.gradient("#FFE1D6", "#F97345")
        case .seniorRiskSpecialist:
            symbol = "shield.checkered"
            foreground = Color(hex: "#4F6F98")
            shadow = Color(hex: "#8EA0B8").opacity(0.30)
            background = Self.gradient("#E8F1FF", "#93A9C8")
        case .safetyStrategist:
            symbol = "flag.checkered"
            foreground = Color.rdPlanPlusDark
            shadow = Color.rdPlanPlus.opacity(0.32)
            background = Self.gradient("#FFF3BF", "#F0A400")
        case .masterHSESpecialist:
            symbol = "crown.fill"
            foreground = Color(hex: "#102A43")
            shadow = Color(hex: "#102A43").opacity(0.24)
            background = Self.gradient("#DDEBFF", "#476B97")
        }
    }

    private static func gradient(_ top: String, _ bottom: String) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: top), Color(hex: bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
