import AppTrackingTransparency
import FBSDKCoreKit
import Foundation
import OSLog
import UIKit

/// Marketing telemetry is best effort; never awaited by a business operation.
/// Only fixed event names/product metadata are sent, never user IDs or safety content.
@MainActor
final class MetaAppEventsService {
    static let shared = MetaAppEventsService()
    private let ledger: MetaEventLedger
    private var testSink: ((String, [String: String], Double?) -> Void)?
    private var configured = false
    private let logger = Logger(subsystem: "com.riskdetected.app", category: "MetaAppEvents")

    private init() { ledger = MetaEventLedger(defaults: .standard) }

    #if DEBUG
    init(testDefaults: UserDefaults, sink: @escaping (String, [String: String], Double?) -> Void) {
        ledger = MetaEventLedger(defaults: testDefaults)
        testSink = sink
        configured = true
    }
    #endif

    func configure(application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard !configured else { return }
        guard Self.permitsSDKEvents() else { return }
        #if DEBUG
        // Fixtures must never pollute the real Meta dataset.
        guard !CommandLine.arguments.contains(where: { $0.hasPrefix("RD_UI_TEST_") }),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("RD_UI_TEST_") }) else { return }
        #endif
        guard let token = Bundle.main.object(forInfoDictionaryKey: "FacebookClientToken") as? String,
              !token.isEmpty, !token.contains("$(") else {
            logger.error("Meta disabled: missing Client Token")
            return
        }
        Settings.shared.isAutoLogAppEventsEnabled = false
        #if DEBUG
        if CommandLine.arguments.contains("RD_META_DIAGNOSTICS") {
            Settings.shared.enableLoggingBehavior(.appEvents)
        }
        #endif
        Settings.shared.isSKAdNetworkReportEnabled = true
        synchronizeTrackingPermission()
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        configured = true
    }

    func activate() {
        guard configured, Self.permitsSDKEvents() else { return }
        synchronizeTrackingPermission()
        // SDK owns install detection/session timing and SKAN conversion updates.
        AppEvents.shared.activateApp()
        emit("first_launch", sourceID: "installation")
    }

    func handle(_ url: URL) {
        guard configured, Self.permitsSDKEvents() else { return }
        // Forward for AEM without consuming Google/Supabase authentication URLs.
        ApplicationDelegate.shared.application(UIApplication.shared, open: url, sourceApplication: nil, annotation: nil)
    }

    static func permitsSDKEvents(status: ATTrackingManager.AuthorizationStatus = ATTrackingManager.trackingAuthorizationStatus) -> Bool {
        // SDK 18 reads ATT directly on iOS 17+, ignoring its tracking setter.
        // Never reuse a previous test/legacy grant for this no-tracking release.
        status != .authorized
    }

    func synchronizeTrackingPermission() {
        Settings.shared.isAdvertiserIDCollectionEnabled = false
        Settings.shared.isEventDataUsageLimited = true
        AppEvents.shared.userID = nil
        AppEvents.shared.clearUserData()
        if #available(iOS 17, *) {
            // SDK 17+ reads ATT directly on iOS 17+.
        } else {
            Settings.shared.isAdvertiserTrackingEnabled = false
        }
    }

    func registration(userID: UUID, createdAt: Date, lastSignInAt: Date?) {
        guard MetaEventLedger.isNewRegistration(createdAt: createdAt, lastSignInAt: lastSignInAt, now: Date()) else { return }
        emit("registration_completed", sourceID: userID.uuidString, standard: "fb_mobile_complete_registration")
    }

    func analysisCompleted(id: UUID) {
        emit("risk_assessment_completed", sourceID: id.uuidString)
    }

    func firstAnalysis(userID: UUID) {
        emit("first_risk_analysis", sourceID: userID.uuidString)
    }

    func reportCreated(id: UUID, format: String) {
        emit("report_created", sourceID: id.uuidString, parameters: ["format": format])
    }

    func purchase(transactionID: String, productID: String, isTrial: Bool, price: Double?, currency: String?) {
        guard !transactionID.isEmpty else { return }
        var parameters = ["fb_content_id": productID]
        if let currency { parameters["fb_currency"] = currency }
        emit(isTrial ? "trial_started" : "subscription_started", sourceID: transactionID,
             standard: isTrial ? "StartTrial" : "Subscribe", parameters: parameters,
             value: isTrial ? 0 : price)
    }

    private func emit(_ name: String, sourceID: String, standard: String? = nil,
                      parameters: [String: String] = [:], value: Double? = nil) {
        guard configured, testSink != nil || Self.permitsSDKEvents(), ledger.claim(name, sourceID: sourceID) else { return }
        if testSink == nil { synchronizeTrackingPermission() }
        let fields = Dictionary(uniqueKeysWithValues: parameters.map { (AppEvents.ParameterName(rawValue: $0.key), $0.value) })
        for event in [name, standard].compactMap({ $0 }) {
            if let testSink {
                testSink(event, parameters, event == standard ? value : nil)
                continue
            }
            if let value, event == standard {
                AppEvents.shared.logEvent(AppEvents.Name(rawValue: event), valueToSum: value, parameters: fields)
            } else {
                AppEvents.shared.logEvent(AppEvents.Name(rawValue: event), parameters: fields)
            }
        }
        // SDK persists/batches and retries delivery. Never block the business result.
    }
}
