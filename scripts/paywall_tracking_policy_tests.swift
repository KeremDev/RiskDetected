import Foundation

// Run with swiftc alongside PaywallTrackingPolicy.swift and PurchaseErrorClassifier.swift.
@main
struct PaywallTrackingPolicyTests {
    static func main() throws {
        let a = UUID(), b = UUID(), journey = UUID(), nextJourney = UUID()
        let owned = PaywallEventOwnership(userID: a, anonymousSessionID: nil)
        assert(owned.belongs(to: a))
        assert(!owned.belongs(to: b))
        assert(owned.assigned(to: b, anonymousSessionID: journey) == owned)
        let anonymous = PaywallEventOwnership(userID: nil, anonymousSessionID: journey)
        let bound = anonymous.assigned(to: a, anonymousSessionID: journey)
        assert(bound.belongs(to: a))
        assert(!bound.assigned(to: b, anonymousSessionID: journey).belongs(to: b))
        assert(anonymous.assigned(to: b, anonymousSessionID: nextJourney).userID == nil)
        let unknown = try JSONDecoder().decode(PaywallEventOwnership.self, from: Data("{}".utf8))
        assert(unknown.assigned(to: a, anonymousSessionID: journey).userID == nil)
        let restored = try JSONDecoder().decode(PaywallEventOwnership.self, from: JSONEncoder().encode(bound))
        assert(restored.belongs(to: a) && !restored.belongs(to: b))
        // Another account's first event must not block delivery of this user's rows.
        let queue: [PaywallEventOwnership?] = [owned, nil, unknown, PaywallEventOwnership(userID: b, anonymousSessionID: nil)]
        assert(queue.filter { $0?.belongs(to: b) == true }.count == 1)
        assert(queue.filter { $0?.belongs(to: UUID()) == true }.isEmpty)
        assert(PaywallTrackingPolicy.purchaseErrorEvent(for: .paymentPending).rawValue == "payment_pending")
        assert(PaywallTrackingPolicy.purchaseErrorEvent(for: .cancelled).rawValue == "purchase_cancelled")
        assert(PaywallTrackingPolicy.purchaseErrorEvent(for: .network).rawValue == "purchase_failed")
        assert(PaywallTrackingPolicy.variantID == "claude_dark_paywall_v2")
        print("PASS: ownership, account switch, anonymous binding, legacy isolation, persistence, mixed queue, pending/cancelled/failed and variant policy")
    }
}
