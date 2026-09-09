import Foundation

enum PaywallTrackingPolicy {
    static let variantID = "claude_dark_paywall_v2"

    static func purchaseErrorEvent(for kind: PurchaseErrorClassification.Kind) -> PaywallEventName {
        switch kind {
        case .paymentPending: return .paymentPending
        case .cancelled: return .purchaseCancelled
        default: return .purchaseFailed
        }
    }
}

enum PaywallEventName: String, Codable {
    case entryTap = "entry_tap"
    case view, close
    case ctaTap = "cta_tap"
    case planSelect = "plan_select"
    case billingSelect = "billing_select"
    case purchaseStarted = "purchase_started"
    case purchaseSucceeded = "purchase_succeeded"
    case purchaseFailed = "purchase_failed"
    case purchaseCancelled = "purchase_cancelled"
    case paymentPending = "payment_pending"
    case restoreTap = "restore_tap"
    case personalPlanView = "personal_plan_view"
    case personalPlanContinue = "personal_plan_continue"
    case trialInviteView = "trial_invite_view"
    case trialInviteCtaTap = "trial_invite_cta_tap"
}

/// Local-only ownership; never infer the owner of a legacy event at delivery time.
struct PaywallEventOwnership: Codable, Equatable {
    var userID: UUID?
    let anonymousSessionID: UUID?

    func belongs(to userID: UUID) -> Bool { self.userID == userID }

    func assigned(to userID: UUID, anonymousSessionID: UUID) -> Self {
        guard self.userID == nil, self.anonymousSessionID == anonymousSessionID else { return self }
        return Self(userID: userID, anonymousSessionID: self.anonymousSessionID)
    }
}
