import SwiftUI

struct ProfessionalProgressProfileSection: View {
    let summary: ProfessionalProgressSummary
    let onRefresh: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showBadges = false
    @State private var showCompetencies = false
    @State private var showTitlesSheet = false
    @State private var pendingCelebration: ProfessionalProgressBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: RDSpacing.sm) {
            mdpCard
            ProfessionalProgressWeeklyTrackingCard(summary: summary)
            competencyPreview
        }
        .sheet(isPresented: $showBadges) {
            ProfessionalProgressBadgesView(summary: summary)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompetencies) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    ProfessionalProgressCompetencyMapView(competencies: summary.competencies)
                        .padding(RDSpacing.lg)
                }
                .background(Color.rdPaper)
                .navigationTitle(RDLocalization.string("professionalprogress.professional.progress.profile.section.yetkinlik.haritasi.e9397520", table: .professionalProgress, fallback: "Yetkinlik Haritası"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        RDModalCloseButton {
                            showCompetencies = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTitlesSheet) {
            ProfessionalProgressTitlesSheet(summary: summary)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingCelebration) { badge in
            ProfessionalProgressCelebrationSheet(badge: badge) {
                Task {
                    await ProfessionalProgressService.shared.markBadgeSeen(badge)
                    pendingCelebration = nil
                    await onRefresh()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .task(id: summary.pendingCelebration?.id) {
            if pendingCelebration == nil, let badge = summary.pendingCelebration {
                pendingCelebration = badge
            }
        }
    }

    private var mdpCard: some View {
        ProfessionalProgressHomeCard(
            summary: summary,
            accessibilityIdentifier: "professionalProgress.profile.progress.card",
            displayStyle: .showcase,
            onTap: { showTitlesSheet = true }
        )
    }

    private var competencyPreview: some View {
        VStack(alignment: .leading, spacing: RDSpacing.sm) {
            HStack {
                Text(RDLocalization.string("professionalprogress.professional.progress.profile.section.yetkinlik.haritasi.ab36b62e", table: .professionalProgress, fallback: "Yetkinlik Haritası"))
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Spacer()
                Button(RDLocalization.string("professionalprogress.professional.progress.profile.section.tumu.5dadc5f6", table: .professionalProgress, fallback: "Tümü")) {
                    showCompetencies = true
                }
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
            }

            if summary.topCompetencies.isEmpty {
                emptyCompetency
            } else {
                ProfessionalProgressCompetencyMapView(
                    competencies: summary.competencies,
                    compact: true
                )
            }
        }
        .padding(14)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .rdCardShadow(colorScheme: colorScheme, accent: Color.rdGreen)
    }

    private var emptyCompetency: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 36, height: 36)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.sm))

            Text(RDLocalization.string("professionalprogress.professional.progress.profile.section.analiz.ve.raporlarin.arttikca.yetkinlik.alanlari.b5934c21", table: .professionalProgress, fallback: "Analiz ve raporların arttıkça yetkinlik alanların burada görünür olacak."))
                .font(RDTypography.font(size: RDFontScale.size(13), design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}
