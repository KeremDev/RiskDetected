import XCTest
@testable import RiskDetected

/// The home section's arrangement and the unfinished items' turns; Android
/// `NovaForYouLayoutTest` checks the same cases.
final class NovaForYouLayoutTests: XCTestCase {
    private struct Card: Equatable { let id: String; var kind: String { String(id.prefix { $0 != "." }) } }

    private func layout(_ ids: [String], continueID: String? = nil) -> (featured: [String], boxes: [String], strip: String?) {
        let result = NovaForYouLayout.make(ids.map(Card.init), kind: \.kind, id: \.id, continueID: continueID)
        return (result.featured.map(\.id), result.boxes.map(\.id), result.strip?.id)
    }

    private let screen = ["critical.expired", "continue.company_create", "continue.checklist_open",
        "performance.analyses_30d", "discover.risk_wizard", "discover.followup", "motivation.today_analysis"]

    func testSuggestionsOnTopAttentionAndUnfinishedWorkInBoxesProgressAsStrip() {
        let result = layout(screen)
        XCTAssertEqual(result.featured, ["discover.risk_wizard", "discover.followup"])
        XCTAssertEqual(result.boxes, ["critical.expired", "continue.company_create"])
        XCTAssertEqual(result.strip, "performance.analyses_30d")
        XCTAssertEqual(layout(screen, continueID: "continue.checklist_open").boxes, ["critical.expired", "continue.checklist_open"])
        XCTAssertEqual(layout(screen, continueID: "continue.gone").boxes, ["critical.expired", "continue.company_create"])
    }

    func testTheMostUrgentAttentionCardWhateverTheRank() {
        let result = layout(["continue.checklist_open", "critical.soon", "critical.nonconformity_overdue", "performance.analyses_7d"])
        XCTAssertEqual(result.boxes, ["critical.soon", "continue.checklist_open"])
        XCTAssertEqual(result.strip, "performance.analyses_7d")
    }

    func testProgressTakesAnEmptyBoxAndTheStripGoes() {
        let noAttention = layout(["continue.risk_draft", "continue.checklist_open", "performance.analyses_7d", "discover.followup"])
        XCTAssertEqual(noAttention.boxes, ["continue.risk_draft", "performance.analyses_7d"])
        XCTAssertNil(noAttention.strip)
        XCTAssertEqual(layout(["critical.expired", "performance.analyses_7d", "motivation.statistics", "discover.followup"]).boxes,
            ["critical.expired", "performance.analyses_7d"])
        let noProgress = layout(["critical.expired", "continue.risk_draft", "motivation.statistics", "discover.followup"])
        XCTAssertEqual(noProgress.boxes, ["critical.expired", "continue.risk_draft"])
        XCTAssertNil(noProgress.strip)
    }

    func testAFirstStepFillsABoxStillEmpty() {
        XCTAssertEqual(layout(["continue.risk_draft", "discover.checklist", "motivation.statistics"]).boxes,
            ["continue.risk_draft", "motivation.statistics"])
        XCTAssertEqual(layout(["performance.analyses_7d", "discover.checklist", "motivation.statistics"]).boxes,
            ["motivation.statistics", "performance.analyses_7d"])
        let fresh = layout(["motivation.first_company", "motivation.first_personnel", "discover.risk_wizard"])
        XCTAssertEqual(fresh.featured, ["discover.risk_wizard"])
        XCTAssertEqual(fresh.boxes, ["motivation.first_company"])
        XCTAssertNil(fresh.strip)
    }

    func testFirstStepsRotateWhenNoSuggestionIsLeft() {
        let result = layout(["critical.expired", "performance.analyses_7d",
            "motivation.today_analysis", "motivation.statistics", "motivation.photo_analysis"])
        XCTAssertEqual(result.featured, ["motivation.today_analysis", "motivation.statistics", "motivation.photo_analysis"])
        XCTAssertEqual(result.boxes, ["critical.expired", "performance.analyses_7d"])
    }

    func testAtMostFiveSuggestionsAndNothingForAnEmptyFeed() {
        XCTAssertEqual(layout((1...7).map { "discover.f\($0)" }).featured.count, 5)
        XCTAssertEqual(NovaForYouLayout.make([Card](), kind: \.kind).count, 0)
    }

    func testNoTwoPlacesShareAKind() {
        let pool = ["critical.expired", "continue.risk_draft", "performance.analyses_7d", "discover.followup", "motivation.statistics"]
        for mask in 0..<(1 << pool.count) {
            let ids = pool.indices.filter { mask & (1 << $0) != 0 }.flatMap { [pool[$0], pool[$0] + "_2"] }
            let result = layout(ids)
            let below = (result.boxes + [result.strip].compactMap { $0 }).map { Card(id: $0).kind }
            let featuredKinds = Set(result.featured.map { Card(id: $0).kind })
            XCTAssertEqual(Set(below).count, below.count, "\(ids)")
            XCTAssertLessThanOrEqual(result.boxes.count, 2, "\(ids)")
            XCTAssertTrue(featuredKinds.count <= 1 && featuredKinds.isDisjoint(with: below), "\(ids)")
        }
    }

    func testUnfinishedItemsTakeTurnsVisitByVisit() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NovaForYouLayoutTests"))
        defaults.removePersistentDomain(forName: "NovaForYouLayoutTests")
        defer { defaults.removePersistentDomain(forName: "NovaForYouLayoutTests") }
        let ids = ["a", "b", "c"]
        let rotation = NovaForYouContinueRotation(namespace: "me:personal", defaults: defaults)
        XCTAssertEqual(rotation.pick(ids), "a")
        XCTAssertEqual(rotation.pick(ids), "a", "a refresh keeps the visit's item")
        rotation.newVisit()
        XCTAssertEqual(rotation.pick(ids), "b")
        XCTAssertEqual(NovaForYouContinueRotation(namespace: "me:personal", defaults: defaults).pick(ids), "c", "the next visit's model")
        XCTAssertEqual(NovaForYouContinueRotation(namespace: "me:personal", defaults: defaults).pick(ids), "a", "starts over")
        XCTAssertEqual(NovaForYouContinueRotation(namespace: "me:workspace", defaults: defaults).pick(ids), "a", "per user and workspace")

        let done = NovaForYouContinueRotation(namespace: "me:personal", defaults: defaults)
        XCTAssertEqual(done.pick(ids), "b")
        XCTAssertEqual(done.pick(["a", "c"]), "a", "the visit's item was finished")
        XCTAssertNil(done.pick([]))
        XCTAssertNil(NovaForYouContinueRotation.next(after: nil, in: []))
    }
}
