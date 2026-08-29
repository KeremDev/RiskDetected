import Foundation
import OSLog

enum PaywallEventName: String, Codable {
    case entryTap = "entry_tap"
    case view
    case close
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

enum PaywallEntrySurface: String, Codable {
    case home, analyses, reports, profile
    case analysisResults = "analysis_results"
    case findingDetail = "finding_detail"
    case expertAdvice = "expert_advice"
    case trainingRecommendations = "training_recommendations"
    case approvedNotebook = "approved_notebook"
    case onboarding, unknown
}

/// Kalıcı analitik sözleşmesidir. Vaka adlarını değiştirmek geçmiş raporları böler;
/// yeni giriş noktaları gerektiğinde yeni vaka eklenmelidir.
enum PaywallEntryPoint: String, Codable {
    case homeHeaderUpgrade = "home_header_upgrade"
    case homeHeaderProfileMenuUpgrade = "home_header_profile_menu_upgrade"
    case analysesHeaderUpgrade = "analyses_header_upgrade"
    case analysesHeaderProfileMenuUpgrade = "analyses_header_profile_menu_upgrade"
    case reportsHeaderUpgrade = "reports_header_upgrade"
    case reportsHeaderProfileMenuUpgrade = "reports_header_profile_menu_upgrade"
    case resultHeaderUpgrade = "result_header_upgrade"
    case resultHeaderProfileMenuUpgrade = "result_header_profile_menu_upgrade"
    case quickScanQuotaAlert = "quick_scan_quota_alert"
    case homeCanvasLockedFocus = "home_canvas_locked_focus"
    case homePhotoUploadQuota = "home_photo_upload_quota"
    case homeQuotaHint = "home_quota_hint"
    case homeAnalysisStartQuota = "home_analysis_start_quota"
    case homeQuickScanQuota = "home_quick_scan_quota"
    case homePhotoTrayLockedSlot = "home_photo_tray_locked_slot"
    case homePhotoLimit = "home_photo_limit"
    case analysesCompanyPicker = "analyses_company_picker"
    case reportsCompanyPicker = "reports_company_picker"
    case profileCompanyPicker = "profile_company_picker"
    case profileUpsellCard = "profile_upsell_card"
    case reportsUpsellCard = "reports_upsell_card"
    case reportsLockedReportOptions = "reports_locked_report_options"
    case resultHubRiskAnalysisPromotion = "result_hub_risk_analysis_promotion"
    case resultHubExpertAdvicePromotion = "result_hub_expert_advice_promotion"
    case resultHubTrainingPromotion = "result_hub_training_promotion"
    case resultHubApprovedNotebookPromotion = "result_hub_approved_notebook_promotion"
    case resultLockedReportOptions = "result_locked_report_options"
    case resultSummaryUpgradeHint = "result_summary_upgrade_hint"
    case resultConfidenceChip = "result_confidence_chip"
    case resultFindingLockedFeature = "result_finding_locked_feature"
    case resultLockedFindingPreview = "result_locked_finding_preview"
    case findingDetailPlusProPromotion = "finding_detail_plus_pro_promotion"
    case findingDetailProPromotion = "finding_detail_pro_promotion"
    case findingDetailRegulatoryReferences = "finding_detail_regulatory_references"
    case onboardingFlow = "onboarding_flow"
    case unknown

    var surface: PaywallEntrySurface {
        switch self {
        case .homeHeaderUpgrade, .homeHeaderProfileMenuUpgrade, .quickScanQuotaAlert,
             .homeCanvasLockedFocus, .homePhotoUploadQuota, .homeQuotaHint,
             .homeAnalysisStartQuota, .homeQuickScanQuota,
             .homePhotoTrayLockedSlot, .homePhotoLimit:
            return .home
        case .analysesHeaderUpgrade, .analysesHeaderProfileMenuUpgrade, .analysesCompanyPicker:
            return .analyses
        case .reportsHeaderUpgrade, .reportsHeaderProfileMenuUpgrade,
             .reportsCompanyPicker, .reportsUpsellCard, .reportsLockedReportOptions:
            return .reports
        case .profileCompanyPicker, .profileUpsellCard:
            return .profile
        case .resultHubRiskAnalysisPromotion, .resultHeaderUpgrade,
             .resultHeaderProfileMenuUpgrade, .resultLockedReportOptions,
             .resultSummaryUpgradeHint, .resultConfidenceChip,
             .resultFindingLockedFeature, .resultLockedFindingPreview:
            return .analysisResults
        case .resultHubExpertAdvicePromotion:
            return .expertAdvice
        case .resultHubTrainingPromotion:
            return .trainingRecommendations
        case .resultHubApprovedNotebookPromotion:
            return .approvedNotebook
        case .findingDetailPlusProPromotion, .findingDetailProPromotion,
             .findingDetailRegulatoryReferences:
            return .findingDetail
        case .onboardingFlow:
            return .onboarding
        case .unknown:
            return .unknown
        }
    }

    var component: String {
        switch self {
        case .homeHeaderUpgrade, .analysesHeaderUpgrade, .reportsHeaderUpgrade, .resultHeaderUpgrade:
            return "header_upgrade_cta"
        case .homeHeaderProfileMenuUpgrade, .analysesHeaderProfileMenuUpgrade,
             .reportsHeaderProfileMenuUpgrade, .resultHeaderProfileMenuUpgrade:
            return "header_profile_menu_upgrade"
        case .quickScanQuotaAlert: return "quota_alert"
        case .homeCanvasLockedFocus: return "analysis_focus_lock"
        case .homePhotoUploadQuota: return "photo_upload_quota_lock"
        case .homeQuotaHint: return "quota_status_card"
        case .homeAnalysisStartQuota: return "analysis_start_quota_gate"
        case .homeQuickScanQuota: return "quick_scan_quota_gate"
        case .homePhotoTrayLockedSlot: return "photo_tray_locked_slot"
        case .homePhotoLimit: return "photo_limit_gate"
        case .analysesCompanyPicker, .reportsCompanyPicker, .profileCompanyPicker:
            return "company_picker_lock"
        case .profileUpsellCard, .reportsUpsellCard: return "plan_upsell_card"
        case .reportsLockedReportOptions, .resultLockedReportOptions: return "report_options_lock"
        case .resultHubRiskAnalysisPromotion, .resultHubExpertAdvicePromotion,
             .resultHubTrainingPromotion, .resultHubApprovedNotebookPromotion:
            return "result_membership_promotion"
        case .resultSummaryUpgradeHint: return "result_summary_hint"
        case .resultConfidenceChip: return "confidence_chip"
        case .resultFindingLockedFeature: return "finding_card_locked_feature"
        case .resultLockedFindingPreview: return "locked_finding_preview"
        case .findingDetailPlusProPromotion, .findingDetailProPromotion:
            return "finding_detail_membership_promotion"
        case .findingDetailRegulatoryReferences: return "regulatory_references_lock"
        case .onboardingFlow: return "onboarding_paywall"
        case .unknown: return "unknown"
        }
    }
}

struct PaywallEntryContext: Codable, Equatable {
    let funnelSessionID: UUID
    let entryPoint: PaywallEntryPoint
    let surface: PaywallEntrySurface
    let component: String
    let targetTier: SubscriptionTier?
    let analysisID: UUID?
    let resultSection: String?
    let itemID: String?
    let attributes: [String: String]
    let clientOccurredAt: Date

    enum CodingKeys: String, CodingKey {
        case funnelSessionID = "funnel_session_id"
        case entryPoint = "entry_point"
        case surface, component
        case targetTier = "target_tier"
        case analysisID = "analysis_id"
        case resultSection = "result_section"
        case itemID = "item_id"
        case attributes
        case clientOccurredAt = "client_occurred_at"
    }
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
    private static let pendingEntryKey = "rd.paywall.pendingEntry"
    private static let pendingEntryLifetime: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "PaywallEventService")

    private let supabase: SupabaseService
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let appSessionID = UUID()
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(supabase: SupabaseService = .shared, defaults: UserDefaults = .standard) {
        self.supabase = supabase
        self.defaults = defaults
    }

    @discardableResult
    func beginEntry(
        at entryPoint: PaywallEntryPoint,
        currentTier: SubscriptionTier,
        targetTier: SubscriptionTier? = nil,
        analysisID: UUID? = nil,
        resultSection: AnalysisResultSectionID? = nil,
        itemID: String? = nil,
        attributes: [String: String] = [:],
        funnelSessionID: UUID = UUID(),
        source: PaywallSource = .inApp
    ) -> PaywallEntryContext {
        let context = PaywallEntryContext(
            funnelSessionID: funnelSessionID,
            entryPoint: entryPoint,
            surface: entryPoint.surface,
            component: entryPoint.component,
            targetTier: targetTier,
            analysisID: analysisID,
            resultSection: resultSection?.rawValue,
            itemID: itemID,
            attributes: attributes,
            clientOccurredAt: Date()
        )
        persistPendingEntry(context)
        record(
            .entryTap,
            funnelSessionID: context.funnelSessionID,
            source: source,
            variantID: "claude_design_paywall_v1",
            segmentKey: nil,
            selectedTier: targetTier,
            billing: nil,
            productIdentifier: nil,
            metadata: PaywallEventMetadata(
                layout: "entry",
                currentTier: currentTier.rawValue,
                selectedPackageID: nil,
                noticePresent: false,
                errorMessage: nil,
                contextHeadline: nil,
                purchaseError: nil
            ),
            entryContext: context,
            clientOccurredAt: context.clientOccurredAt
        )
        return context
    }

    func consumePendingEntry(preferredFunnelSessionID: UUID? = nil) -> PaywallEntryContext? {
        guard let data = defaults.data(forKey: Self.pendingEntryKey),
              let context = try? decoder.decode(PaywallEntryContext.self, from: data)
        else {
            defaults.removeObject(forKey: Self.pendingEntryKey)
            return nil
        }
        guard Date().timeIntervalSince(context.clientOccurredAt) <= Self.pendingEntryLifetime else {
            defaults.removeObject(forKey: Self.pendingEntryKey)
            return nil
        }
        if let preferredFunnelSessionID, preferredFunnelSessionID != context.funnelSessionID {
            return nil
        }
        defaults.removeObject(forKey: Self.pendingEntryKey)
        return context
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
        metadata: PaywallEventMetadata,
        entryContext: PaywallEntryContext? = nil,
        clientOccurredAt: Date = Date()
    ) {
        let pending = PendingPaywallEvent(
            funnelSessionID: funnelSessionID.uuidString,
            source: source.rawValue,
            variantID: variantID,
            segmentKey: segmentKey,
            eventName: event.rawValue,
            selectedTier: selectedTier?.rawValue,
            billing: billing,
            productIdentifier: productIdentifier,
            metadata: metadata,
            clientOccurredAt: timestampFormatter.string(from: clientOccurredAt),
            appSessionID: appSessionID.uuidString,
            entryPoint: entryContext?.entryPoint.rawValue,
            entrySurface: entryContext?.surface.rawValue,
            entryComponent: entryContext?.component,
            entryTargetTier: entryContext?.targetTier?.rawValue,
            analysisID: entryContext?.analysisID?.uuidString,
            resultSection: entryContext?.resultSection,
            itemID: entryContext?.itemID,
            entryContext: entryContext
        )
        guard let userID = supabase.currentUserID else {
            enqueuePendingEvent(pending)
            return
        }
        insert(payload(from: pending, userID: userID))
    }

    func flushPendingIfPossible() {
        guard let userID = supabase.currentUserID else { return }
        let pending = pendingEvents()
        guard !pending.isEmpty else { return }
        defaults.removeObject(forKey: Self.pendingEventsKey)
        pending.forEach { insert(payload(from: $0, userID: userID)) }
    }

    private func payload(from event: PendingPaywallEvent, userID: UUID) -> PaywallEventPayload {
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
            metadata: event.metadata,
            clientOccurredAt: event.clientOccurredAt ?? timestampFormatter.string(from: Date()),
            appSessionID: event.appSessionID,
            entryPoint: event.entryPoint,
            entrySurface: event.entrySurface,
            entryComponent: event.entryComponent,
            entryTargetTier: event.entryTargetTier,
            analysisID: event.analysisID,
            resultSection: event.resultSection,
            itemID: event.itemID,
            entryContext: event.entryContext
        )
    }

    private func insert(_ payload: PaywallEventPayload) {
        Task {
            do {
                try await supabase.client.from("paywall_events").insert(payload).execute()
            } catch {
                Self.logger.error("Paywall event insert failed. event=\(payload.eventName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistPendingEntry(_ context: PaywallEntryContext) {
        do {
            defaults.set(try encoder.encode(context), forKey: Self.pendingEntryKey)
        } catch {
            Self.logger.error("Paywall entry context encode failed. error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func enqueuePendingEvent(_ event: PendingPaywallEvent) {
        var events = pendingEvents()
        events.append(event)
        if events.count > 48 { events = Array(events.suffix(48)) }
        do {
            defaults.set(try encoder.encode(events), forKey: Self.pendingEventsKey)
        } catch {
            Self.logger.error("Pending paywall event encode failed. event=\(event.eventName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func pendingEvents() -> [PendingPaywallEvent] {
        guard let data = defaults.data(forKey: Self.pendingEventsKey) else { return [] }
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
    let clientOccurredAt: String?
    let appSessionID: String?
    let entryPoint: String?
    let entrySurface: String?
    let entryComponent: String?
    let entryTargetTier: String?
    let analysisID: String?
    let resultSection: String?
    let itemID: String?
    let entryContext: PaywallEntryContext?
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
    let clientOccurredAt: String
    let appSessionID: String?
    let entryPoint: String?
    let entrySurface: String?
    let entryComponent: String?
    let entryTargetTier: String?
    let analysisID: String?
    let resultSection: String?
    let itemID: String?
    let entryContext: PaywallEntryContext?

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
        case clientOccurredAt = "client_occurred_at"
        case appSessionID = "app_session_id"
        case entryPoint = "entry_point"
        case entrySurface = "entry_surface"
        case entryComponent = "entry_component"
        case entryTargetTier = "entry_target_tier"
        case analysisID = "analysis_id"
        case resultSection = "result_section"
        case itemID = "item_id"
        case entryContext = "entry_context"
    }
}
