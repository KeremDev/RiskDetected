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
            sectionHeader
            mdpCard
            ProfessionalProgressWeeklyTrackingCard(summary: summary)
            quickStats
            competencyPreview
            messagesPreview
        }
        .sheet(isPresented: $showBadges) {
            ProfessionalProgressBadgesView(badges: summary.badges)
                .presentationDetents([.large])
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

    private var sectionHeader: some View {
        HStack {
            Text("Mesleki İlerleme")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.rdSlate)
            Spacer()
            Button {
                showBadges = true
            } label: {
                Label("Başarılarım", systemImage: "rosette")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
            }
            .buttonStyle(.plain)
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

    private var quickStats: some View {
        HStack(spacing: 7) {
            stat(
                value: summary.profile.totalAnalyses,
                label: "Analiz",
                icon: "waveform.path.ecg",
                color: .rdInfo
            )
            stat(
                value: summary.profile.totalReports,
                label: "Rapor",
                icon: "doc.text.fill",
                color: .rdGreen
            )
            stat(
                value: summary.weeklyTracking.reportsCount,
                label: "Bu hafta",
                icon: "calendar.badge.checkmark",
                color: .rdPlanPlus
            )
            stat(
                value: summary.profile.criticalFindings + summary.profile.highFindings,
                label: "Yüksek/Kritik",
                icon: "exclamationmark.triangle.fill",
                color: .rdCritical
            )
        }
    }

    private func stat(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.xs))
            Text("\(value)")
                .rdMono(size: 18, weight: .bold)
                .foregroundStyle(Color.rdBlack)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 78)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.md)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.md))
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
