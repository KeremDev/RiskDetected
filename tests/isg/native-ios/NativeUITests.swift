import XCTest

@MainActor final class NativeUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }
    private func boot() {
        app = XCUIApplication(bundleIdentifier: "com.riskdetected.isgnativeharness")
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment = ["ISG_QA_URL": env["ISG_QA_URL"]!, "ISG_QA_KEY": env["ISG_QA_KEY"]!]
        app.launch(); waitState("ready|idle")
    }
    private func waitState(_ text: String) {
        let node = app.staticTexts["qa.state"]
        XCTAssertTrue(node.waitForExistence(timeout: 30))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: node)], timeout: 30), .completed, text)
    }
    private func controlWhileBackgrounded(_ action: String) {
        XCUIDevice.shared.press(.home)
        let env = ProcessInfo.processInfo.environment
        var request = URLRequest(url: URL(string: env["ISG_QA_URL"]! + "/qa/control")!)
        request.httpMethod = "POST"; request.setValue(env["ISG_QA_KEY"]!, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["action": action])
        let completed = expectation(description: "Background capability change")
        URLSession.shared.dataTask(with: request) { _, response, error in
            XCTAssertNil(error); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200); completed.fulfill()
        }.resume()
        wait(for: [completed], timeout: 30)
        app.activate()
    }
    private func tap(_ id: String) {
        let node = app.buttons[id]; XCTAssertTrue(node.waitForExistence(timeout: 30), id)
        for _ in 0..<8 { if node.isHittable { break }; app.scrollViews.element(boundBy: app.scrollViews.count - 1).swipeUp() }
        XCTAssertTrue(node.isHittable, id); node.tap()
    }
    private func field(_ id: String, _ value: String, replacing: Bool = false) {
        let node = app.textFields[id]; XCTAssertTrue(node.waitForExistence(timeout: 20))
        if !node.isHittable { app.scrollViews.firstMatch.swipeDown() }
        node.tap()
        if replacing { node.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (node.value as? String ?? "").count)) }
        node.typeText(value + "\n")
    }
    private func selectA() { tap("qa.company.a"); XCTAssertTrue(app.buttons["personnel.add"].waitForExistence(timeout: 25)) }
    private func directory(_ kind: String) { tap("qa.directory"); tap("qa.directory.\(kind)"); XCTAssertTrue(app.buttons["directory.add"].waitForExistence(timeout: 25)); tap("directory.add") }
    private func choose(_ field: String, _ title: String) {
        tap("directory.field.\(field)")
        let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "directory.option.\(field).", title)).firstMatch
        for _ in 0..<12 { if option.exists && option.isHittable { break }; app.scrollViews.element(boundBy: app.scrollViews.count - 1).swipeUp() }
        XCTAssertTrue(option.exists && option.isHittable, title); option.tap()
    }
    private func saveDirectory() { tap("directory.save"); XCTAssertTrue(app.buttons["directory.add"].waitForExistence(timeout: 25)) }
    func testDirectoryCatalogs() {
        boot(); selectA()
        for (kind, name) in [("workplaces","workplace"),("departments","department"),("jobs","job"),("contractors","contractor")] {
            directory(kind); field("directory.field.name", "Native ios \(name)")
            if kind == "departments" { choose("workplace_id", "Native ios workplace") }
            saveDirectory()
        }
    }
    func testDirectoryDatedContextAndEngagement() {
        boot(); selectA()
        directory("engagements")
        choose("organization_id", "Native ios contractor"); choose("workplace_id", "Native ios workplace")
        field("directory.field.starts_on", "2026-01-01"); field("directory.field.ends_before", "2026-01-01")
        tap("directory.save"); XCTAssertTrue(app.textFields["directory.field.ends_before"].exists)
        field("directory.field.ends_before", "2027-01-01", replacing: true); saveDirectory()
        for (date, previous) in [("2026-01-01",false),("2026-06-01",true)] {
            directory("contexts"); field("directory.field.starts_on",date)
            if previous { choose("previous_id","TR") }
            field("directory.field.timezone","Europe/Istanbul"); field("directory.field.jurisdiction","TR")
            tap("Az"); field("directory.field.evidence_note","Native QA context")
            if previous {
                field("directory.field.starts_on","2026-01-01",replacing:true); tap("directory.save")
                XCTAssertTrue(app.textFields["directory.field.starts_on"].exists)
                field("directory.field.starts_on",date,replacing:true)
            }
            saveDirectory()
        }
    }
    func testDirectoryAssignmentsAndEmployer() {
        boot(); selectA()
        for (date, previous) in [("2026-01-01",false),("2026-06-01",true)] {
            directory("assignments"); choose("workplace_id","Native ios workplace"); choose("department_id","Native ios department"); choose("job_role_id","Native ios job")
            field("directory.field.starts_on",date)
            if previous {
                choose("previous_id","Native ios job")
                field("directory.field.starts_on","2026-01-01",replacing:true); tap("directory.save")
                XCTAssertTrue(app.textFields["directory.field.starts_on"].exists)
                field("directory.field.starts_on",date,replacing:true)
            }
            saveDirectory()
        }
        directory("employers"); choose("organization_id","Native ios contractor"); saveDirectory()
    }
    private func findEmployee() {
        field("personnel.search", "Native ios")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'personnel.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        XCTAssertTrue(app.otherElements["personnel.detail"].exists || app.buttons["personnel.edit"].waitForExistence(timeout: 20) || app.buttons["personnel.restore"].exists)
    }
    func testRealNativePersonnelLifecycleAndBoundaries() throws {
        boot(); selectA()
        tap("qa.drop_next"); waitState("drop_next|idle")
        tap("personnel.add"); field("personnel.name", "Native ios"); field("personnel.department", "Native ios departman")
        tap("personnel.save"); XCTAssertTrue(app.buttons["personnel.retry"].waitForExistence(timeout: 45))
        app.terminate(); boot(); selectA()
        XCTAssertTrue(app.buttons["personnel.recover"].waitForExistence(timeout: 25)); XCTAssertFalse(app.buttons["personnel.add"].isEnabled)
        tap("qa.reset"); waitState("reset|idle|write"); tap("personnel.recover")
        XCTAssertTrue(app.buttons["personnel.edit"].waitForExistence(timeout: 25))
        tap("personnel.edit"); field("personnel.name", "Native ios Son", replacing: true); tap("personnel.save")
        tap("personnel.edit"); tap("personnel.archive"); tap("personnel.archive.confirm")
        let toggle = app.switches["personnel.archived"]; XCTAssertTrue(toggle.waitForExistence(timeout: 25))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        findEmployee(); tap("personnel.restore"); tap("personnel.save"); tap("personnel.back")
    }
    func testWorkspaceBoundaries() throws {
        boot(); selectA()
        for action in ["write_off", "paid_off", "read_off"] {
            controlWhileBackgrounded(action); waitState("|idle|readonly")
            if action == "read_off" { XCTAssertFalse(app.buttons["personnel.add"].exists) }
            else { XCTAssertFalse(app.buttons["personnel.add"].isEnabled) }
            controlWhileBackgrounded("reset"); waitState("|idle|write")
        }
        for action in ["write_off", "paid_off"] {
            tap("qa.\(action)"); waitState("\(action)|idle|readonly")
            XCTAssertFalse(app.buttons["personnel.add"].isEnabled)
            tap("qa.reset"); waitState("reset|idle|write")
        }
        tap("qa.write_off"); waitState("write_off|idle|readonly")
        tap("qa.read_off"); waitState("read_off|idle|readonly"); XCTAssertFalse(app.buttons["personnel.add"].exists)
        tap("qa.reset"); waitState("reset|idle|write")
        tap("qa.company.b"); XCTAssertTrue(app.staticTexts["qa.no.scope"].waitForExistence(timeout: 25))
        tap("qa.account.b"); waitState("account.b|idle"); tap("qa.company.a")
        XCTAssertTrue(app.staticTexts["qa.no.scope"].waitForExistence(timeout: 25))
        tap("qa.company.b"); XCTAssertTrue(app.buttons["personnel.add"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Native ios Son"].exists)
        tap("qa.account.a"); waitState("account.a|idle"); selectA(); findEmployee()
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        let env = ProcessInfo.processInfo.environment
        var request = URLRequest(url: URL(string: env["ISG_QA_URL"]! + "/qa/finish")!)
        request.httpMethod = "POST"; request.setValue(env["ISG_QA_KEY"]!, forHTTPHeaderField: "apikey")
        let finished = expectation(description: "Independent DB assertion")
        URLSession.shared.dataTask(with: request) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "Independent DB assertion must pass")
            finished.fulfill()
        }.resume()
        wait(for: [finished], timeout: 30)
    }
}
