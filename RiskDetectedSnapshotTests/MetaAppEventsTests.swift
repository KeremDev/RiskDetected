import XCTest
import AppTrackingTransparency
import FBSDKCoreKit
@testable import RiskDetected

@MainActor
final class MetaAppEventsTests: XCTestCase {
    func testNoATTPermissionStateCanEnableAdvertiserCollection() {
        XCTAssertTrue(MetaAppEventsService.permitsSDKEvents(status: .notDetermined))
        XCTAssertTrue(MetaAppEventsService.permitsSDKEvents(status: .denied))
        XCTAssertTrue(MetaAppEventsService.permitsSDKEvents(status: .restricted))
        XCTAssertFalse(MetaAppEventsService.permitsSDKEvents(status: .authorized))
        Settings.shared.isAdvertiserIDCollectionEnabled = true
        Settings.shared.isEventDataUsageLimited = false
        MetaAppEventsService.shared.synchronizeTrackingPermission()
        XCTAssertFalse(Settings.shared.isAdvertiserIDCollectionEnabled)
        XCTAssertTrue(Settings.shared.isEventDataUsageLimited)
        XCTAssertNil(AppEvents.shared.userID)
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription"))
    }
    func testBusinessEventsAreDeduplicatedAndContainNoSourceIdentifiers() {
        let suite = "rd.meta.unit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [(String, [String: String], Double?)] = []
        let service = MetaAppEventsService(testDefaults: defaults) { events.append(($0, $1, $2)) }
        let id = UUID()
        service.analysisCompleted(id: id)
        service.analysisCompleted(id: id)
        service.firstAnalysis(userID: id)
        service.firstAnalysis(userID: id)
        service.reportCreated(id: id, format: "pdf")
        service.reportCreated(id: id, format: "pdf")
        XCTAssertEqual(events.map(\.0), ["risk_assessment_completed", "first_risk_analysis", "report_created"])
        XCTAssertEqual(events.last?.1, ["format": "pdf"])
        XCTAssertFalse(events.description.contains(id.uuidString))
        let relaunched = MetaAppEventsService(testDefaults: defaults) { events.append(($0, $1, $2)) }
        relaunched.reportCreated(id: id, format: "pdf")
        XCTAssertEqual(events.count, 3)
    }

    func testTrialAndSubscriptionUseStandardEventsWithoutDoubleRevenue() {
        let suite = "rd.meta.unit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [(String, [String: String], Double?)] = []
        let service = MetaAppEventsService(testDefaults: defaults) { events.append(($0, $1, $2)) }
        service.purchase(transactionID: "trial", productID: "plus.monthly", isTrial: true, price: 249.99, currency: "TRY")
        service.purchase(transactionID: "paid", productID: "pro.monthly", isTrial: false, price: 499.99, currency: "TRY")
        service.purchase(transactionID: "paid", productID: "pro.monthly", isTrial: false, price: 499.99, currency: "TRY")
        service.purchase(transactionID: "", productID: "pro.monthly", isTrial: false, price: 499.99, currency: "TRY")
        XCTAssertEqual(events.map(\.0), ["trial_started", "StartTrial", "subscription_started", "Subscribe"])
        XCTAssertNil(events[0].2)
        XCTAssertEqual(events[1].2, 0)
        XCTAssertNil(events[2].2)
        XCTAssertEqual(events[3].2, 499.99)
        XCTAssertEqual(events[3].1["fb_currency"], "TRY")
    }

    func testExistingAccountDoesNotBecomeNewRegistration() {
        let suite = "rd.meta.unit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var names: [String] = []
        let service = MetaAppEventsService(testDefaults: defaults) { name, _, _ in names.append(name) }
        let now = Date(), id = UUID()
        service.registration(userID: id, createdAt: now.addingTimeInterval(-86400), lastSignInAt: now)
        XCTAssertTrue(names.isEmpty)
        service.registration(userID: id, createdAt: now.addingTimeInterval(-5), lastSignInAt: now)
        service.registration(userID: id, createdAt: now.addingTimeInterval(-5), lastSignInAt: now)
        XCTAssertEqual(names, ["registration_completed", "fb_mobile_complete_registration"])
    }
}
