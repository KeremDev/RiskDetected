import Foundation
import OSLog

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
    case reportsReportCompanyPicker = "reports_report_company_picker"
    case resultHubRiskAnalysisPromotion = "result_hub_risk_analysis_promotion"
    case resultHubExpertAdvicePromotion = "result_hub_expert_advice_promotion"
    case resultHubTrainingPromotion = "result_hub_training_promotion"
    case resultHubApprovedNotebookPromotion = "result_hub_approved_notebook_promotion"
    case resultLockedReportOptions = "result_locked_report_options"
    case resultReportCompanyPicker = "result_report_company_picker"
    case resultSummaryUpgradeHint = "result_summary_upgrade_hint"
    case resultConfidenceChip = "result_confidence_chip"
    case resultFindingLockedFeature = "result_finding_locked_feature"
    case resultLockedFindingPreview = "result_locked_finding_preview"
    case findingDetailPlusProPromotion = "finding_detail_plus_pro_promotion"
    case findingDetailProPromotion = "finding_detail_pro_promotion"
    case findingDetailRegulatoryReferences = "finding_detail_regulatory_references"
    case onboardingPersonalPlan = "onboarding_personal_plan"
    case onboardingTrialInvite = "onboarding_trial_invite"
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
             .reportsCompanyPicker, .reportsUpsellCard, .reportsLockedReportOptions,
             .reportsReportCompanyPicker:
            return .reports
        case .profileCompanyPicker, .profileUpsellCard:
            return .profile
        case .resultHubRiskAnalysisPromotion, .resultHeaderUpgrade,
             .resultHeaderProfileMenuUpgrade, .resultLockedReportOptions,
             .resultReportCompanyPicker,
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
        case .onboardingPersonalPlan, .onboardingTrialInvite, .onboardingFlow:
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
        case .analysesCompanyPicker, .reportsCompanyPicker, .profileCompanyPicker,
             .reportsReportCompanyPicker, .resultReportCompanyPicker:
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
        case .onboardingPersonalPlan: return "personal_plan_screen"
        case .onboardingTrialInvite: return "trial_invite_screen"
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
    private static let pendingEntryOwnerKey = "rd.paywall.pendingEntryOwner"
    private static let anonymousSessionKey = "rd.paywall.anonymousSession"
    private static let pendingEntryLifetime: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "PaywallEventService")

    private let supabase: SupabaseService
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let appSessionID = UUID()
    private var isFlushingPendingEvents = false
    private var deliveryRetryTask: Task<Void, Never>?
    private var deliveryRetryAttempt = 0
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
        var enrichedAttributes = attributes
        enrichedAttributes["client_platform"] = "ios"
        let context = PaywallEntryContext(
            funnelSessionID: funnelSessionID,
            entryPoint: entryPoint,
            surface: entryPoint.surface,
            component: entryPoint.component,
            targetTier: targetTier,
            analysisID: analysisID,
            resultSection: resultSection?.rawValue,
            itemID: itemID,
            attributes: enrichedAttributes,
            clientOccurredAt: Date()
        )
        persistPendingEntry(context)
        record(
            .entryTap,
            funnelSessionID: context.funnelSessionID,
            source: source,
            variantID: PaywallTrackingPolicy.variantID,
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
        guard let ownerData = defaults.data(forKey: Self.pendingEntryOwnerKey),
              let owner = try? decoder.decode(PaywallEventOwnership.self, from: ownerData),
              owner == currentOwnership || (supabase.currentUserID.map { owner.belongs(to: $0) } ?? false)
        else { return nil }
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
            clientEventID: UUID().uuidString,
            ownership: currentOwnership,
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
        // Persist before the network request. A close action is immediately followed by view
        // dismissal and the process can also be suspended while PostgREST is in flight; a
        // fire-and-forget insert permanently lost both cases.
        enqueuePendingEvent(pending)
        flushPendingIfPossible()
    }

    func flushPendingIfPossible() {
        deliveryRetryTask?.cancel()
        deliveryRetryTask = nil
        guard !isFlushingPendingEvents,
              let userID = supabase.currentUserID,
              pendingEvents().contains(where: { $0.ownership?.belongs(to: userID) == true })
        else { return }

        isFlushingPendingEvents = true
        Task { [weak self] in
            guard let self else { return }
            await self.drainPendingEvents(userID: userID)
        }
    }

    private func payload(from event: PendingPaywallEvent, userID: UUID) -> PaywallEventPayload {
        PaywallEventPayload(
            clientEventID: event.clientEventID ?? UUID().uuidString,
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

    private func drainPendingEvents(userID: UUID) async {
        var deliveryFailed = false
        defer {
            isFlushingPendingEvents = false
            if deliveryFailed {
                scheduleDeliveryRetry()
            } else if !pendingEvents().contains(where: { $0.ownership?.belongs(to: userID) == true }) {
                deliveryRetryAttempt = 0
                // Another account may have signed in while a request was in flight.
                if supabase.currentUserID != userID { flushPendingIfPossible() }
            } else {
                // Covers an event enqueued after the drain observed an empty queue.
                flushPendingIfPossible()
            }
        }

        while supabase.currentUserID == userID,
              let event = pendingEvents().first(where: { $0.ownership?.belongs(to: userID) == true }) {
            let payload = payload(from: event, userID: userID)
            do {
                try await supabase.client
                    .from("paywall_events")
                    .upsert(
                        payload,
                        onConflict: "client_event_id",
                        ignoreDuplicates: true
                    )
                    .execute()
                removePendingEvent(clientEventID: payload.clientEventID)
            } catch {
                deliveryFailed = true
                Self.logger.error("Paywall event insert failed. event=\(payload.eventName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                // Keep the event on disk and retry it with the same client_event_id, so a lost
                // HTTP response cannot create a duplicate.
                return
            }
        }
    }

    private func scheduleDeliveryRetry() {
        guard deliveryRetryTask == nil,
              let userID = supabase.currentUserID,
              pendingEvents().contains(where: { $0.ownership?.belongs(to: userID) == true })
        else { return }

        let cappedAttempt = min(deliveryRetryAttempt, 6)
        let delaySeconds = min(300, 5 * (1 << cappedAttempt))
        deliveryRetryAttempt = min(deliveryRetryAttempt + 1, 6)
        deliveryRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.deliveryRetryTask = nil
            self.flushPendingIfPossible()
        }
    }

    private func persistPendingEntry(_ context: PaywallEntryContext) {
        do {
            defaults.set(try encoder.encode(context), forKey: Self.pendingEntryKey)
            defaults.set(try encoder.encode(currentOwnership), forKey: Self.pendingEntryOwnerKey)
        } catch {
            Self.logger.error("Paywall entry context encode failed. error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private var anonymousSessionID: UUID {
        if let raw = defaults.string(forKey: Self.anonymousSessionKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.anonymousSessionKey)
        return id
    }

    private var currentOwnership: PaywallEventOwnership {
        PaywallEventOwnership(userID: supabase.currentUserID,
                              anonymousSessionID: supabase.currentUserID == nil ? anonymousSessionID : nil)
    }

    /// Bind only this anonymous onboarding journey, never another account's queue
    /// or legacy rows with unknown ownership. Such rows remain on disk, unsent.
    func authenticationChanged(userID: UUID?, endedSession: Bool) {
        if endedSession {
            defaults.set(UUID().uuidString, forKey: Self.anonymousSessionKey)
            defaults.removeObject(forKey: Self.pendingEntryKey)
            defaults.removeObject(forKey: Self.pendingEntryOwnerKey)
        }
        guard let userID else { return }
        let anonymousID = anonymousSessionID
        var events = pendingEvents()
        for index in events.indices {
            events[index].ownership = events[index].ownership?.assigned(to: userID, anonymousSessionID: anonymousID)
        }
        persistPendingEvents(events, eventNameForLog: "bind_onboarding_owner")
        if let data = defaults.data(forKey: Self.pendingEntryOwnerKey),
           let owner = try? decoder.decode(PaywallEventOwnership.self, from: data),
           let bound = try? encoder.encode(owner.assigned(to: userID, anonymousSessionID: anonymousID)) {
            defaults.set(bound, forKey: Self.pendingEntryOwnerKey)
        }
        // An anonymous journey can be claimed by only one login.
        defaults.set(UUID().uuidString, forKey: Self.anonymousSessionKey)
        flushPendingIfPossible()
    }

    private func enqueuePendingEvent(_ event: PendingPaywallEvent) {
        var events = pendingEvents()
        events.append(event)
        persistPendingEvents(events, eventNameForLog: event.eventName)
    }

    private func removePendingEvent(clientEventID: String) {
        let events = pendingEvents().filter { $0.clientEventID != clientEventID }
        persistPendingEvents(events, eventNameForLog: "delivery_ack")
    }

    private func persistPendingEvents(
        _ events: [PendingPaywallEvent],
        eventNameForLog: String
    ) {
        do {
            if events.isEmpty {
                defaults.removeObject(forKey: Self.pendingEventsKey)
            } else {
                defaults.set(try encoder.encode(events), forKey: Self.pendingEventsKey)
            }
        } catch {
            Self.logger.error("Pending paywall event encode failed. event=\(eventNameForLog, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func pendingEvents() -> [PendingPaywallEvent] {
        guard let data = defaults.data(forKey: Self.pendingEventsKey) else { return [] }
        do {
            var events = try decoder.decode([PendingPaywallEvent].self, from: data)
            var upgradedLegacyQueue = false
            for index in events.indices where events[index].clientEventID == nil {
                events[index].clientEventID = UUID().uuidString
                upgradedLegacyQueue = true
            }
            if upgradedLegacyQueue {
                persistPendingEvents(events, eventNameForLog: "legacy_queue_upgrade")
            }
            return events
        } catch {
            Self.logger.error("Pending paywall event decode failed. error=\(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.pendingEventsKey)
            return []
        }
    }
}

private struct PendingPaywallEvent: Codable {
    var clientEventID: String?
    var ownership: PaywallEventOwnership?
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
    let clientEventID: String
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
        case clientEventID = "client_event_id"
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
