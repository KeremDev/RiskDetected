import XCTest
@testable import RiskDetected

@MainActor
final class ClientFlowEventsTests: XCTestCase {
    func testInvalidFieldsAndSignedOutEventsAreNeverQueued() async {
        let name = "rd.flow.test.\(UUID())", owner = UUID()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var sent = 0
        let service = ClientFlowEvents(defaults: defaults, currentUser: { owner }, send: { _ in sent += 1 })
        service.record("private content", "started")
        service.record("photo_picker", "failed", reason: "private error")
        let signedOut = ClientFlowEvents(defaults: defaults, currentUser: { nil }, send: { _ in sent += 1 })
        signedOut.record("home", "completed")
        await service.waitForDelivery()
        XCTAssertNil(defaults.data(forKey: "rd.clientFlow.events.v1"))
        XCTAssertEqual(sent, 0)
    }

    func testRetryUsesSameIDAndAcknowledgesOnlySuccessfulDelivery() async {
        let name = "rd.flow.test.\(UUID())", owner = UUID()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var ids: [UUID] = []
        let service = ClientFlowEvents(defaults: defaults, currentUser: { owner }, retryDelay: 0) { event in
            ids.append(event.client_event_id)
            XCTAssertEqual(event.photo_count, 3)
            if ids.count == 1 { throw URLError(.notConnectedToInternet) }
        }
        service.record("analysis_upload", "started", photoCount: 99)
        await service.waitForDelivery()
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 1)
        let remaining = try! JSONDecoder().decode([ClientFlowEvents.Event].self, from: defaults.data(forKey: "rd.clientFlow.events.v1")!)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRelaunchDoesNotDeliverAnotherAccountsQueuedEvent() async {
        let name = "rd.flow.test.\(UUID())", first = UUID(), second = UUID()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let offline = ClientFlowEvents(defaults: defaults, currentUser: { first }, retryDelay: 0) { _ in throw URLError(.notConnectedToInternet) }
        offline.record("photo_picker", "started")
        await offline.waitForDelivery()
        var owners: [UUID] = []
        let online = ClientFlowEvents(defaults: defaults, currentUser: { second }, send: { owners.append($0.user_id) })
        online.record("home", "completed")
        await online.waitForDelivery()
        XCTAssertEqual(owners, [second])
        let remaining = try! JSONDecoder().decode([ClientFlowEvents.Event].self, from: defaults.data(forKey: "rd.clientFlow.events.v1")!)
        XCTAssertEqual(remaining.map(\.user_id), [first])
    }
}
