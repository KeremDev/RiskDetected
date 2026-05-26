import SwiftUI

struct ProfessionalProgressWeeklyTrackingCard: View {
    enum DisplayStyle: Equatable {
        case compact
        case regular
    }

    let summary: ProfessionalProgressSummary
    var displayStyle: DisplayStyle = .regular

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
                    .font(.system(size: isCompact ? 15 : 16, weight: .semibold, design: .rounded))
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
        .shadow(color: shadowColor, radius: isCompact ? 8 : 10, x: 0, y: isCompact ? 4 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isCompact ? "professionalProgress.weeklyTracking.home" : "professionalProgress.weeklyTracking.profile")
    }

    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isCompact ? 12 : 14)
                .fill(iconBackground)
                .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)

            Image(systemName: tracking.hasActivity ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: isCompact ? 17 : 19, weight: .black, design: .rounded))
                .foregroundStyle(iconColor)
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
            Color.rdPlanPlusSoft.opacity(0.70),
            Color.rdWhite,
            Color.rdFog.opacity(0.85)
        ]
    }

    private var iconBackground: Color {
        tracking.hasActivity ? Color.rdGreen.opacity(0.14) : Color.rdPlanPlus.opacity(0.14)
    }

    private var iconColor: Color {
        tracking.hasActivity ? Color.rdGreenDark : Color.rdPlanPlusDark
    }

    private var borderColor: Color {
        tracking.hasActivity ? Color.rdGreen.opacity(0.18) : Color.rdPlanPlus.opacity(0.20)
    }

    private var shadowColor: Color {
        tracking.hasActivity ? Color.rdGreen.opacity(0.08) : Color.rdPlanPlus.opacity(0.08)
    }
}
