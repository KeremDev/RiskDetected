import SwiftUI

/// Record-level deadlines on the home page. The source is the same scoped
/// timeline used by Evrak Takibi; counts are never turned into fake cards.
struct NovaHomeDeadlineBoard: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    let scopeID: UUID?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var overdue: [NovaFollowupPage.Row] = []
    @State private var upcoming: [NovaFollowupPage.Row] = []
    @State private var overdueCount = 0
    @State private var upcomingCount = 0
    @State private var overdueHasMore = false
    @State private var upcomingHasMore = false
    @State private var expandedOverdue = false
    @State private var expandedUpcoming = false
    @State private var loading = true
    @State private var loadingMore: String?
    @State private var failed = false
    @State private var revision = 0
    @State private var selected: NovaFollowupPage.Row?
    @State private var selectedTraining: NovaFollowupPage.Row?

    private var requestKey: String {
        "\(identity.userID):\(identity.sessionID):\(scopeID?.uuidString ?? "personal"):\(revision)"
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    column(.overdue)
                    column(.upcoming)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    column(.overdue)
                    column(.upcoming)
                }
            }
        }
        .task(id: requestKey) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { event in
            guard event.object as? UUID == identity.userID else { return }
            revision += 1
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { revision += 1 }
        }
        .novaPopup(item: $selected, onDismiss: { revision += 1 }) { row in
            NovaFollowupDestination(identity: identity, row: row, canWrite: canWrite,
                onBack: { selected = nil })
        }
        .novaFullScreenCover(item: $selectedTraining, onDismiss: { revision += 1 }) { row in
            NovaFollowupDestination(identity: identity, row: row, canWrite: canWrite,
                onBack: { selectedTraining = nil })
        }
        .accessibilityIdentifier("nova.home.deadlines")
    }

    private enum Bucket {
        case overdue, upcoming

        var title: String { self == .overdue ? "Süresi Geçenler" : "Yaklaşan" }
        var symbol: String { self == .overdue ? "exclamationmark.circle" : "calendar.badge.clock" }
        var status: String { self == .overdue ? "expired" : "soon" }
        var empty: String { self == .overdue ? "Süresi geçen iş yok" : "Yaklaşan iş yok" }
        var background: NovaColorToken { self == .overdue ? .statusDangerBg : .statusInfoBg }
        var ink: NovaColorToken { self == .overdue ? .statusDangerInk : .statusInfoInk }
    }

    private func column(_ bucket: Bucket) -> some View {
        let rows = bucket == .overdue ? overdue : upcoming
        let count = bucket == .overdue ? overdueCount : upcomingCount
        let expanded = bucket == .overdue ? expandedOverdue : expandedUpcoming
        let hasMore = bucket == .overdue ? overdueHasMore : upcomingHasMore
        let visible = expanded ? rows : Array(rows.prefix(3))
        let ink = bucket.ink.color(in: scheme)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: bucket.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(bucket.title)
                    .font(NovaFont.font(.bodyStrong))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text(loading ? "·" : String(count))
                    .font(NovaFont.font(.meta))
                    .frame(minWidth: 26, minHeight: 26)
                    .background(ink.opacity(0.10), in: Circle())
            }
            .foregroundStyle(ink)
            .frame(minHeight: 30)

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 66)
            } else if failed {
                Text("Kayıtlar yüklenemedi")
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                Button("Tekrar dene") { revision += 1 }
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(ink)
            } else if rows.isEmpty {
                Text(bucket.empty)
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            } else {
                ForEach(visible) { row in
                    deadlineCard(row, ink: ink)
                }
                if rows.count > 3 || hasMore {
                    if expanded && hasMore {
                        Button {
                            Task { await loadMore(bucket) }
                        } label: {
                            Text(loadingMore == bucket.status ? "Yükleniyor…" : "Daha fazla")
                                .font(NovaFont.font(.meta))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingMore != nil)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { setExpanded(bucket, !expanded) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "Daha az" : "Tümünü gör")
                            Image(systemName: expanded ? "chevron.up" : "chevron.right")
                        }
                        .font(NovaFont.font(.meta))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(bucket.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier(bucket == .overdue ? "nova.home.deadlines.overdue" : "nova.home.deadlines.upcoming")
    }

    private func deadlineCard(_ row: NovaFollowupPage.Row, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title)
                .font(NovaFont.font(.bodyStrong))
                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.company_name)
                .font(NovaFont.font(.meta))
                .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .lineLimit(2)
            if let date = row.due_on {
                Label(NovaStatisticsSnapshot.dayLabel(date), systemImage: "calendar")
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Button {
                if row.kind == "training" { selectedTraining = row }
                else { selected = row }
            } label: {
                HStack(spacing: 4) {
                    Text("İncele")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(NovaFont.font(.meta))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nova.home.deadline.inspect.\(row.id)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 15))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func setExpanded(_ bucket: Bucket, _ value: Bool) {
        if bucket == .overdue { expandedOverdue = value }
        else { expandedUpcoming = value }
    }

    @MainActor private func refresh() async {
        loading = true
        failed = false
        let service = NovaFollowupService(identity: identity)
        do {
            async let overduePage = service.load(company: nil, status: "expired")
            async let upcomingPage = service.load(company: nil, status: "soon")
            let (late, soon) = try await (overduePage, upcomingPage)
            try Task.checkCancellation()
            overdue = late.rows
            upcoming = soon.rows
            overdueCount = late.expired
            upcomingCount = soon.soon
            overdueHasMore = late.has_more
            upcomingHasMore = soon.has_more
        } catch {
            if !Task.isCancelled { failed = true }
        }
        if !Task.isCancelled { loading = false }
    }

    @MainActor private func loadMore(_ bucket: Bucket) async {
        guard loadingMore == nil else { return }
        loadingMore = bucket.status
        defer { loadingMore = nil }
        do {
            let offset = bucket == .overdue ? overdue.count : upcoming.count
            let page = try await NovaFollowupService(identity: identity).load(
                company: nil, status: bucket.status, offset: offset)
            try Task.checkCancellation()
            if bucket == .overdue {
                overdue += page.rows
                overdueHasMore = page.has_more
            } else {
                upcoming += page.rows
                upcomingHasMore = page.has_more
            }
        } catch {
            // Keep the already visible records; the next tap can retry.
        }
    }
}
