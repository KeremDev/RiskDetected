import SwiftUI

struct ProfessionalProgressProfileSection: View {
    let summary: ProfessionalProgressSummary
    let onRefresh: () async -> Void

    @State private var showBadges = false
    @State private var showCompetencies = false
    @State private var showTitlesSheet = false
    @State private var pendingCelebration: ProfessionalProgressBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: RDSpacing.sm) {
            mdpCard
            ProfessionalProgressWeeklyTrackingCard(summary: summary)
            competencyPreview
            messagesPreview
        }
        .sheet(isPresented: $showBadges) {
            ProfessionalProgressBadgesView(summary: summary)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompetencies) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    ProfessionalProgressCompetencyMapView(competencies: summary.competencies)
                        .padding(RDSpacing.lg)
                }
                .background(Color.rdPaper)
                .navigationTitle("Yetkinlik Haritası")
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
            .presentationDetents([.height(330)])
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
                Text("Yetkinlik Haritası")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Spacer()
                Button("Tümü") {
                    showCompetencies = true
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
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
    }

    private var emptyCompetency: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 36, height: 36)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.sm))

            Text("Analiz ve raporların arttıkça yetkinlik alanların burada görünür olacak.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var messagesPreview: some View {
        if let message = summary.messages.first {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 36, height: 36)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: RDRadius.sm))
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(message.body)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
    }
}
