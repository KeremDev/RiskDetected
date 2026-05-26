import SwiftUI

struct ProfessionalProgressBadgesView: View {
    let badges: [ProfessionalProgressBadge]

    private let columns = [
        GridItem(.flexible(), spacing: RDSpacing.sm),
        GridItem(.flexible(), spacing: RDSpacing.sm),
        GridItem(.flexible(), spacing: RDSpacing.sm)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: RDSpacing.sm) {
                    ForEach(badges) { badge in
                        badgeTile(badge)
                    }

                    ForEach(lockedBadges, id: \.key) { locked in
                        lockedTile(locked)
                    }
                }
                .padding(RDSpacing.lg)
            }
            .background(Color.rdPaper)
            .navigationTitle("Başarılarım")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func badgeTile(_ badge: ProfessionalProgressBadge) -> some View {
        VStack(spacing: 9) {
            Image(systemName: badge.iconName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 48, height: 48)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.md))

            Text(badge.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .padding(.horizontal, 8)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .accessibilityLabel("\(badge.title), kazanıldı")
    }

    private func lockedTile(_ locked: LockedBadge) -> some View {
        VStack(spacing: 9) {
            Image(systemName: locked.icon)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 48, height: 48)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.md))

            Text(locked.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .padding(.horizontal, 8)
        .background(Color.rdWhite.opacity(0.75))
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.rdLine)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .accessibilityLabel("\(locked.title), henüz kazanılmadı")
    }

    private var lockedBadges: [LockedBadge] {
        let existing = Set(badges.map(\.badgeKey))
        return LockedBadge.defaults.filter { !existing.contains($0.key) }
    }
}

private struct LockedBadge {
    let key: String
    let title: String
    let icon: String

    static let defaults: [LockedBadge] = [
        .init(key: "reports:10", title: "10 Rapor", icon: "medal.fill"),
        .init(key: "reports:50", title: "50 Rapor", icon: "trophy.fill"),
        .init(key: "reports:100", title: "Yüz Rapor", icon: "trophy.fill"),
        .init(key: "competency:5", title: "5 Alan", icon: "square.grid.3x2.fill"),
        .init(key: "risk:first_high", title: "Yüksek Risk", icon: "exclamationmark.triangle.fill"),
        .init(key: "active_days:30", title: "30 Aktif Gün", icon: "calendar.badge.checkmark")
    ]
}
