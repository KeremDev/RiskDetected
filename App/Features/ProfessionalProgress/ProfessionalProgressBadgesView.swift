import SwiftUI

struct ProfessionalProgressBadgesView: View {
    let badges: [ProfessionalProgressBadge]
    private let summary: ProfessionalProgressSummary?
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: RDSpacing.sm),
        GridItem(.flexible(), spacing: RDSpacing.sm),
        GridItem(.flexible(), spacing: RDSpacing.sm)
    ]

    init(badges: [ProfessionalProgressBadge], summary: ProfessionalProgressSummary? = nil) {
        self.badges = badges
        self.summary = summary
    }

    init(summary: ProfessionalProgressSummary) {
        self.badges = summary.badges
        self.summary = summary
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: RDSpacing.sm) {
                    ForEach(displayBadges) { badge in
                        badgeTile(badge)
                    }
                }
                .padding(.horizontal, RDSpacing.lg)
                .padding(.top, RDSpacing.md)
                .padding(.bottom, RDSpacing.lg)
            }
            .background(Color.rdPaper)
            .navigationTitle("Başarılarım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private func badgeTile(_ badge: BadgeDisplayItem) -> some View {
        VStack(spacing: 9) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(badge.iconBackground)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(Color.rdWhite, lineWidth: 3)
                    )
                    .shadow(
                        color: badge.isEarned ? badge.accent.opacity(0.22) : .clear,
                        radius: 10,
                        x: 0,
                        y: 6
                    )

                Image(systemName: badge.icon)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(badge.iconForeground)
                    .frame(width: 52, height: 52)

                if badge.isEarned {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(badge.accent)
                        .background(Circle().fill(Color.rdWhite))
                        .offset(x: 4, y: -2)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.rdWhite))
                        .offset(x: 4, y: -2)
                }
            }

            Text(badge.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(badge.isEarned ? Color.rdBlack : Color.rdSlate)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        .padding(.horizontal, 6)
        .background(badge.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(badge.borderStyle, lineWidth: badge.isEarned ? 1.2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .accessibilityLabel("\(badge.title), \(badge.isEarned ? "kazanıldı" : "henüz kazanılmadı")")
    }

    private var displayBadges: [BadgeDisplayItem] {
        let earnedKeys = Set(badges.map(\.badgeKey))
        return BadgeCatalogItem.defaults.map { item in
            BadgeDisplayItem(
                key: item.key,
                title: item.title,
                icon: item.icon,
                accent: item.accent,
                isEarned: item.isEarned(summary: summary, earnedKeys: earnedKeys)
            )
        }
    }
}

private struct BadgeDisplayItem: Identifiable {
    let key: String
    let title: String
    let icon: String
    let accent: Color
    let isEarned: Bool

    var id: String { key }

    var iconBackground: Color {
        isEarned ? accent.opacity(0.2) : Color.rdFog
    }

    var iconForeground: Color {
        isEarned ? accent : Color.rdSlate.opacity(0.78)
    }

    var cardBackground: Color {
        isEarned ? Color.rdWhite : Color.rdWhite.opacity(0.72)
    }

    var borderStyle: Color {
        isEarned ? accent.opacity(0.25) : Color.rdLine.opacity(0.65)
    }
}

private struct BadgeCatalogItem {
    let key: String
    let title: String
    let icon: String
    let accent: Color
    let requirement: BadgeRequirement

    func isEarned(summary: ProfessionalProgressSummary?, earnedKeys: Set<String>) -> Bool {
        guard !earnedKeys.contains(key) else { return true }
        guard let summary else { return false }

        switch requirement {
        case .reportCount(let threshold):
            return summary.profile.totalReports >= threshold
        case .competencyCount(let threshold):
            let activeCompetencies = summary.competencies.filter {
                $0.findingCount > 0 || $0.reportCount > 0
            }.count
            return activeCompetencies >= threshold
        case .highRisk:
            return summary.profile.highFindings + summary.profile.criticalFindings > 0
        case .activeDays(let threshold):
            return summary.profile.activeDays >= threshold
        }
    }

    static let defaults: [BadgeCatalogItem] = [
        .init(
            key: "reports:10",
            title: "10 Rapor",
            icon: "medal.fill",
            accent: Color(hex: "#0E9F6E"),
            requirement: .reportCount(10)
        ),
        .init(
            key: "reports:50",
            title: "50 Rapor",
            icon: "trophy.fill",
            accent: Color(hex: "#D97706"),
            requirement: .reportCount(50)
        ),
        .init(
            key: "reports:100",
            title: "Yüz Rapor",
            icon: "trophy.fill",
            accent: Color(hex: "#B45309"),
            requirement: .reportCount(100)
        ),
        .init(
            key: "competency:5",
            title: "5 Alan",
            icon: "square.grid.3x2.fill",
            accent: Color(hex: "#2563EB"),
            requirement: .competencyCount(5)
        ),
        .init(
            key: "risk:first_high",
            title: "Yüksek Risk",
            icon: "exclamationmark.triangle.fill",
            accent: Color.rdCritical,
            requirement: .highRisk
        ),
        .init(
            key: "active_days:30",
            title: "30 Aktif Gün",
            icon: "calendar.badge.checkmark",
            accent: Color(hex: "#7C3AED"),
            requirement: .activeDays(30)
        )
    ]
}

private enum BadgeRequirement {
    case reportCount(Int)
    case competencyCount(Int)
    case highRisk
    case activeDays(Int)
}
