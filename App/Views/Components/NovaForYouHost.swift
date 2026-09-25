import SwiftUI

/// Loads the "Senin İçin" cards for the signed-in session and turns what the
/// user does with them into queued events. The section view stays free of the
/// service; the root decides what a card opens.
@MainActor final class NovaForYouModel: ObservableObject {
    @Published private(set) var phase: NovaForYouSection.Phase = .loading
    @Published private(set) var feed: NovaForYouFeed?
    /// The unfinished item this visit shows. A model lives for one visit to
    /// the home page; returning from the background starts another.
    @Published private(set) var continueID: String?
    private var rotation: NovaForYouContinueRotation?
    /// The last answer per user and workspace, so returning to the home page
    /// draws at once while the fresh answer loads.
    private static var cache: [String: NovaForYouFeed] = [:]
    /// Impressions already reported today, per user and workspace.
    private static var reported: Set<String> = []

    func load(identity: NovaSessionIdentity, routes: [String], personal: Bool) async {
        let service = NovaForYouService(identity: identity)
        let namespace = service.namespace
        if let cached = Self.cache[namespace] { show(cached, namespace) } else if feed == nil { phase = .loading }
        // Queued decisions reach the server before the read, so it answers with them.
        await NovaForYouOutbox.shared.flush(service)
        do {
            let result = try await service.load(local: NovaLocalDraftDigest.collect(identity: identity, personal: personal), routes: routes)
            Self.cache[namespace] = result
            show(result, namespace)
        } catch {
            // A failed refresh keeps the cards already on screen.
            if !Task.isCancelled, feed == nil { phase = .failed }
        }
    }

    func dismiss(_ card: NovaForYouCard, identity: NovaSessionIdentity) {
        record(.card("dismiss", [card.id]), identity: identity)
    }

    /// Opening a suggested feature counts as trying it; the other kinds only
    /// note that the card was used.
    func opened(_ card: NovaForYouCard, identity: NovaSessionIdentity) {
        record(.card("act", [card.id]), identity: identity)
    }

    /// Reports the cards that were actually drawn: once a day per card, and only
    /// the kinds whose rotation depends on it.
    func shown(_ cards: [NovaForYouCard], identity: NovaSessionIdentity) {
        let service = NovaForYouService(identity: identity)
        let day = Self.istanbulDay(Date())
        let fresh = cards.filter { ["discover", "performance", "motivation"].contains($0.kind)
            && !Self.reported.contains("\(service.namespace)|\(day)|\($0.id)") }
        guard !fresh.isEmpty else { return }
        fresh.forEach { Self.reported.insert("\(service.namespace)|\(day)|\($0.id)") }
        // The server takes at most five cards per event.
        for start in stride(from: 0, to: fresh.count, by: 5) {
            NovaForYouOutbox.shared.add(.card("shown", fresh[start..<min(start + 5, fresh.count)].map(\.id)), namespace: service.namespace)
        }
        Task { await NovaForYouOutbox.shared.flush(service) }
    }

    private func record(_ event: NovaForYouEvent, identity: NovaSessionIdentity) {
        let service = NovaForYouService(identity: identity)
        NovaForYouOutbox.shared.add(event, namespace: service.namespace)
        if let current = feed { show(current, service.namespace) }
        Task { await NovaForYouOutbox.shared.flush(service) }
    }

    /// Cards hidden by an event that has not reached the server yet stay
    /// hidden; the last decision per card wins, as it does on the server.
    private func show(_ value: NovaForYouFeed, _ namespace: String) {
        var hidden: [String: Bool] = [:]
        for event in NovaForYouOutbox.shared.pending(namespace).sorted(by: { $0.occurredAt < $1.occurredAt }) {
            for card in event.cards {
                switch event.action {
                case "dismiss": hidden[card] = true
                case "restore": hidden[card] = false
                case "act" where card.hasPrefix("discover."): hidden[card] = true
                default: break
                }
            }
        }
        let visible = value.removing(Set(hidden.filter(\.value).keys))
        if rotation?.namespace != namespace { rotation = NovaForYouContinueRotation(namespace: namespace) }
        continueID = rotation?.pick(Self.unfinished(visible))
        feed = visible
        phase = .ready(visible)
    }

    /// The app came back from the background: the next unfinished item takes its turn.
    func newVisit() {
        rotation?.newVisit()
        if let feed { continueID = rotation?.pick(Self.unfinished(feed)) }
    }

    /// The unfinished items this build can word, in server order.
    private static func unfinished(_ feed: NovaForYouFeed) -> [String] {
        (feed.cards + feed.more).filter { $0.kind == "continue" && NovaForYouCopy.make($0, kindTitle: { kind in kind }) != nil }.map(\.id)
    }

    static func istanbulDay(_ date: Date) -> String { NovaListPreset.istanbulDay(date) }
}

struct NovaForYouHost: View {
    let identity: NovaSessionIdentity
    /// Personal sessions may offer an interrupted company create.
    let personal: Bool
    /// The targets this session can open with all of their filters.
    let routes: [String]
    /// Changes when the session, the records or the tab change.
    let refreshKey: String
    let onOpen: (NovaForYouCard) -> Void
    var onFeed: (NovaForYouFeed?) -> Void = { _ in }
    @StateObject private var model = NovaForYouModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var revision = 0
    @State private var backgrounded = false

    var body: some View {
        NovaForYouSection(phase: model.phase, kindTitle: NovaFollowupPage.typeTitle(kind:),
            onOpen: { card in
                model.opened(card, identity: identity)
                onOpen(card)
            },
            onDismiss: { model.dismiss($0, identity: identity) },
            onRetry: { revision += 1 },
            onShown: { model.shown($0, identity: identity) },
            continueID: model.continueID)
        .task(id: "\(refreshKey):\(revision):\(routes.joined(separator: ","))") {
            await model.load(identity: identity, routes: routes, personal: personal)
        }
        .onChange(of: model.feed) { onFeed($0) }
        .onChange(of: scenePhase) { phase in
            if phase == .background { backgrounded = true }
            guard phase == .active else { return }
            if backgrounded {
                backgrounded = false
                model.newVisit()
            }
            revision += 1
        }
    }
}
