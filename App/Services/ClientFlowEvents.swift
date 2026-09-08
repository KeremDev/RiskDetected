import Foundation

/// First-party diagnostics, deliberately separate from Meta and quota accounting.
@MainActor
final class ClientFlowEvents {
    static let shared = ClientFlowEvents()
    private let key = "rd.clientFlow.events.v1"
    private let session = UUID()
    private var flushing = false
    private var deliveryTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let currentUser: () -> UUID?
    private let send: (Event) async throws -> Void
    private let retryDelay: UInt64
    struct Event: Codable {
        var client_event_id = UUID()
        let user_id: UUID
        let session_id: UUID
        var platform = "ios"
        let app_version: String
        let app_build: String
        let stage: String
        let outcome: String
        let reason: String
        let photo_count: Int
        let client_occurred_at: String
    }
    static let stages: Set<String> = ["home", "photo_picker", "photo_import", "photo_ready", "analysis_cta", "analysis_validation", "analysis_prepare", "analysis_create", "analysis_upload", "analysis_submit", "analysis_result", "billing_launch", "billing_result"]
    static let outcomes: Set<String> = ["started", "completed", "cancelled", "blocked", "failed", "pending"]
    static let reasons: Set<String> = ["none", "unknown", "auth", "quota", "safety_profile", "photo_limit", "no_photo", "permission", "io", "network", "timeout", "runtime_gate", "membership", "activity_inactive", "already_running", "store", "backend"]

    init(defaults: UserDefaults = .standard,
         currentUser: @escaping () -> UUID? = { SupabaseService.shared.currentUserID },
         retryDelay: UInt64 = 5_000_000_000,
         send: ((Event) async throws -> Void)? = nil) {
        self.defaults = defaults
        self.currentUser = currentUser
        self.retryDelay = retryDelay
        self.send = send ?? { event in
            try await SupabaseService.shared.client.from("client_flow_events")
                .upsert(event, onConflict: "client_event_id", ignoreDuplicates: true).execute()
        }
    }

    func waitForDelivery() async { await deliveryTask?.value }

    func record(_ stage: String, _ outcome: String, reason: String = "none", photoCount: Int = 0) {
        guard Self.stages.contains(stage), Self.outcomes.contains(outcome), Self.reasons.contains(reason),
              let owner = currentUser() else { return }
        let event = Event(user_id: owner, session_id: session,
            app_version: String((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown").prefix(32)),
            app_build: String((Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown").prefix(16)),
            stage: stage, outcome: outcome, reason: reason, photo_count: min(3, max(0, photoCount)),
            client_occurred_at: ISO8601DateFormatter().string(from: Date()))
        save(Array((read() + [event]).suffix(200)))
        flush()
    }

    private func read() -> [Event] {
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([Event].self, from: data) else { return [] }
        return events.filter { (ISO8601DateFormatter().date(from: $0.client_occurred_at) ?? .distantPast) > Date().addingTimeInterval(-86400) }
    }
    private func save(_ events: [Event]) {
        if let data = try? JSONEncoder().encode(events) { defaults.set(data, forKey: key) }
    }
    private func flush() {
        guard !flushing else { return }
        save(read()) // Remove expired entries even when the current account has none to send.
        flushing = true
        deliveryTask = Task {
            defer { flushing = false }
            var failures = 0
            while let next = read().first(where: { $0.user_id == currentUser() }) {
                do {
                    try await send(next)
                    save(read().filter { $0.client_event_id != next.client_event_id })
                    failures = 0
                } catch {
                    failures += 1
                    guard failures < 3, !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: UInt64(failures) * retryDelay)
                }
            }
        }
    }
}
