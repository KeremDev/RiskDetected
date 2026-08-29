import SwiftUI

struct ProfessionalProgressWeeklyTrackingCard: View {
    enum DisplayStyle: Equatable {
        case compact
        case regular
    }

    let summary: ProfessionalProgressSummary
    var displayStyle: DisplayStyle = .regular
    @Environment(\.colorScheme) private var colorScheme

    private var tracking: ProfessionalProgressWeeklyTracking {
        summary.weeklyTracking
    }

    private var isCompact: Bool {
        displayStyle == .compact
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(tracking.body)
                    .font(RDTypography.font(size: isCompact ? 15 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(isCompact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 10 : 13)
        .background {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .rdCardShadow(
            colorScheme: colorScheme,
            accent: tracking.hasActivity ? Color.rdGreen : Color.rdInfo,
            radius: isCompact ? 4 : 5,
            x: isCompact ? 5 : 6,
            y: isCompact ? 6 : 8
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isCompact ? "professionalProgress.weeklyTracking.home" : "professionalProgress.weeklyTracking.profile")
    }

    private var statusIcon: some View {
        let boxSize: CGFloat = isCompact ? 34 : 40
        let innerSize: CGFloat = isCompact ? 23 : 27

        return ZStack {
            RoundedRectangle(cornerRadius: isCompact ? 12 : 14)
                .fill(iconBackground)
                .frame(width: boxSize, height: boxSize)

            if tracking.hasActivity {
                Image(systemName: "checkmark.seal.fill")
                    .font(RDTypography.font(size: isCompact ? 17 : 19, weight: .black, design: .rounded))
                    .foregroundStyle(iconColor)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.rdInfo, Color(hex: "#7C5CFF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: innerSize, height: innerSize)
                        .shadow(color: Color.rdInfo.opacity(0.24), radius: 5, x: 0, y: 2)

                    Image(systemName: "play.fill")
                        .font(RDTypography.font(size: isCompact ? 9 : 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                        .offset(x: 1)

                    Image(systemName: "sparkle")
                        .font(RDTypography.font(size: isCompact ? 7 : 8, weight: .black, design: .rounded))
                        .foregroundStyle(Color.rdInfo)
                        .frame(width: isCompact ? 14 : 16, height: isCompact ? 14 : 16)
                        .background(Color.rdWhite.opacity(0.94))
                        .clipShape(Circle())
                        .offset(x: isCompact ? 10 : 12, y: isCompact ? -10 : -12)
                }
            }
        }
    }

    private var backgroundColors: [Color] {
        if tracking.hasActivity {
            return [
                Color.rdGreenSoft.opacity(0.86),
                Color.rdWhite,
                Color.rdPlanPlusSoft.opacity(0.46)
            ]
        }
        return [
            Color(hex: "#EEF6FF"),
            Color.rdWhite,
            Color(hex: "#F6F3FF")
        ]
    }

    private var iconBackground: Color {
        tracking.hasActivity ? Color.rdGreen.opacity(0.14) : Color.rdInfo.opacity(0.13)
    }

    private var iconColor: Color {
        tracking.hasActivity ? Color.rdGreenDark : Color.rdInfo
    }

    private var borderColor: Color {
        tracking.hasActivity ? Color.rdGreen.opacity(0.18) : Color.rdInfo.opacity(0.18)
    }

    private var shadowColor: Color {
        tracking.hasActivity ? Color.rdGreen.opacity(0.08) : Color.rdInfo.opacity(0.07)
    }
}
