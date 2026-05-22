import Foundation
import OSLog

enum PaywallEventName: String, Codable {
    case view
    case close
    case ctaTap = "cta_tap"
    case planSelect = "plan_select"
    case billingSelect = "billing_select"
    case purchaseStarted = "purchase_started"
    case purchaseSucceeded = "purchase_succeeded"
    case purchaseFailed = "purchase_failed"
    case restoreTap = "restore_tap"
    case personalPlanView = "personal_plan_view"
    case personalPlanContinue = "personal_plan_continue"
    case trialInviteView = "trial_invite_view"
    case trialInviteCtaTap = "trial_invite_cta_tap"
}

struct PaywallEventMetadata: Codable {
    let layout: String
    let currentTier: String
    let selectedPackageID: String?
    let noticePresent: Bool
    let errorMessage: String?
    let contextHeadline: String?
    let purchaseError: String?

    enum CodingKeys: String, CodingKey {
        case layout
        case currentTier = "current_tier"
        case selectedPackageID = "selected_package_id"
        case noticePresent = "notice_present"
        case errorMessage = "error_message"
        case contextHeadline = "context_headline"
        case purchaseError = "purchase_error"
    }
}

@MainActor
final class PaywallEventService {
    static let shared = PaywallEventService()

    private static let pendingEventsKey = "rd.paywall.pendingEvents"

    private static let logger = Logger(
        subsystem: "com.riskdetected.app",
        category: "PaywallEventService"
    )

    private let supabase: SupabaseService
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        supabase: SupabaseService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.supabase = supabase
        self.defaults = defaults
    }

    func record(
        _ event: PaywallEventName,
        funnelSessionID: UUID,
        source: PaywallSource,
        variantID: String,
        segmentKey: String?,
        selectedTier: SubscriptionTier?,
        billing: String?,
        productIdentifier: String?,
        metadata: PaywallEventMetadata
    ) {
        guard let userID = supabase.currentUserID else {
            enqueuePendingEvent(
                PendingPaywallEvent(
                    funnelSessionID: funnelSessionID.uuidString,
                    source: source.rawValue,
                    variantID: variantID,
                    segmentKey: segmentKey,
                    eventName: event.rawValue,
                    selectedTier: selectedTier?.rawValue,
                    billing: billing,
                    productIdentifier: productIdentifier,
                    metadata: metadata
                )
            )
            return
        }

        insert(
            PaywallEventPayload(
                userID: userID.uuidString,
                funnelSessionID: funnelSessionID.uuidString,
                source: source.rawValue,
                variantID: variantID,
                segmentKey: segmentKey,
                eventName: event.rawValue,
                selectedTier: selectedTier?.rawValue,
                billing: billing,
                productIdentifier: productIdentifier,
                metadata: metadata
            )
        )
    }

    func flushPendingIfPossible() {
        guard let userID = supabase.currentUserID else { return }
        let pending = pendingEvents()
        guard !pending.isEmpty else { return }

        defaults.removeObject(forKey: Self.pendingEventsKey)
        pending.forEach { event in
            insert(
                PaywallEventPayload(
                    userID: userID.uuidString,
                    funnelSessionID: event.funnelSessionID,
                    source: event.source,
                    variantID: event.variantID,
                    segmentKey: event.segmentKey,
                    eventName: event.eventName,
                    selectedTier: event.selectedTier,
                    billing: event.billing,
                    productIdentifier: event.productIdentifier,
                    metadata: event.metadata
                )
            )
        }
    }

    private func insert(_ payload: PaywallEventPayload) {
        Task {
            do {
                try await supabase.client
                    .from("paywall_events")
                    .insert(payload)
                    .execute()
            } catch {
                Self.logger.error("Paywall event insert failed. event=\(payload.eventName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func enqueuePendingEvent(_ event: PendingPaywallEvent) {
        var events = pendingEvents()
        events.append(event)
        if events.count > 24 {
            events = Array(events.suffix(24))
        }

        do {
            let data = try encoder.encode(events)
            defaults.set(data, forKey: Self.pendingEventsKey)
        } catch {
            Self.logger.error("Pending paywall event encode failed. event=\(event.eventName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func pendingEvents() -> [PendingPaywallEvent] {
        guard let data = defaults.data(forKey: Self.pendingEventsKey) else {
            return []
        }

        do {
            return try decoder.decode([PendingPaywallEvent].self, from: data)
        } catch {
            Self.logger.error("Pending paywall event decode failed. error=\(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.pendingEventsKey)
            return []
        }
    }
}

private struct PendingPaywallEvent: Codable {
    let funnelSessionID: String
    let source: String
    let variantID: String
    let segmentKey: String?
    let eventName: String
    let selectedTier: String?
    let billing: String?
    let productIdentifier: String?
    let metadata: PaywallEventMetadata
}

private struct PaywallEventPayload: Encodable {
    let userID: String
    let funnelSessionID: String
    let source: String
    let variantID: String
    let segmentKey: String?
    let eventName: String
    let selectedTier: String?
    let billing: String?
    let productIdentifier: String?
    let metadata: PaywallEventMetadata

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case funnelSessionID = "funnel_session_id"
        case source
        case variantID = "variant_id"
        case segmentKey = "segment_key"
        case eventName = "event_name"
        case selectedTier = "selected_tier"
        case billing
        case productIdentifier = "product_identifier"
        case metadata
    }
}
