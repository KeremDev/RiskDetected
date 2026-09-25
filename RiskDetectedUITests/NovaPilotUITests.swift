import XCTest

final class NovaPilotUITests: XCTestCase {
    /// "Mail ile devam et" on the sign-in page: a password that breaks the rules is refused
    /// before any request; an address with an account and a wrong password is told so and
    /// never asked for a code; a new address signs up with the typed password and gets the
    /// code page. The code boxes once dropped every key, and after a refused code the
    /// keyboard stayed down.
    func testMailButtonSignsInOrSignsUp() throws {
        #if NOVA_PILOT_BUILD
        var app = launchNovaLogin()
        fillSignIn(app, email: "yeni@example.com", password: "kisa1")
        app.buttons["Mail ile devam et"].tap()
        XCTAssertTrue(app.staticTexts["Şifre en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."]
            .waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Kodu gir"].exists)
        app.terminate()

        app = launchNovaLogin()
        fillSignIn(app, email: "exists@example.com", password: "Yanlis123")
        app.buttons["Mail ile devam et"].tap()
        // Over the 128-character limit of a plain element query, so matched by label.
        let wrongPassword = "Şifren yanlış. Şifreni bilmiyorsan aşağıdan kodla yenisini belirleyebilirsin. "
            + "Apple veya Google ile kaydolduysan o butonla giriş yap."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", wrongPassword)).firstMatch
            .waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["Doğrulama kodu"].exists, "a wrong password must not ask for a code")
        XCTAssertTrue(app.buttons["Şifreni bilmiyor musun?"].exists)
        app.terminate()

        app = launchNovaLogin()
        fillSignIn(app, email: "yeni@example.com", password: "Yeni12345")
        app.buttons["Mail ile devam et"].tap()
        XCTAssertTrue(app.staticTexts["Kodu gir"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Kodu yeni@example.com adresine gönderdik."].exists)
        dismissSavePassword(app)
        let code = app.textFields["Doğrulama kodu"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        // A refused code keeps its digits and the keyboard; fixing one box checks it again.
        code.typeText("012345")
        XCTAssertTrue(app.staticTexts[codeRejected].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Kodu yeniden gönder"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays for the fix")
        XCTAssertEqual(code.value as? String, "012345")
        let keyboard = app.keyboards.firstMatch
        let keyboardTop = keyboard.frame.minY
        tapCodeBox(app, 0)
        // Selecting a box keeps the keyboard where it was; it does not drop and come back.
        for _ in 0..<5 {
            XCTAssertTrue(keyboard.exists)
            XCTAssertEqual(keyboard.frame.minY, keyboardTop, accuracy: 1)
            Thread.sleep(forTimeInterval: 0.1)
        }
        app.typeText("7")
        XCTAssertTrue(app.staticTexts["Hesabın hazır"].waitForExistence(timeout: 8))
        #endif
    }

    /// "Hesap oluştur" still opens the signup page, which ends on the same code page.
    func testSignupLinkOpensSignupAndCode() throws {
        #if NOVA_PILOT_BUILD
        let app = launchNovaLogin()
        let email = app.textFields["E-posta adresin"]
        email.tap(); email.typeText("harness@example.com\n")
        app.buttons["nova.login.signup"].tap()
        XCTAssertTrue(app.staticTexts["Mail ile hesap oluştur"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["E-posta adresin"].value as? String, "harness@example.com")
        // A visible field: iOS offers a strong password over a secure new-password field.
        let show = app.buttons["Göster"]
        waitUntilHittable(show)
        show.tap()
        let newPassword = app.textFields["Parola oluştur"]
        newPassword.tap(); newPassword.typeText("harness")
        // The rules under the field follow the typing.
        XCTAssertEqual(ruleValue(app, "lower"), "tamam")
        XCTAssertEqual(ruleValue(app, "upper"), "eksik")
        newPassword.typeText("H12\n")
        XCTAssertEqual(ruleValue(app, "upper"), "tamam")
        XCTAssertEqual(ruleValue(app, "digit"), "tamam")
        app.buttons["nova.signup.submit"].tap()

        XCTAssertTrue(app.staticTexts["Kodu gir"].waitForExistence(timeout: 8))
        dismissSavePassword(app)
        let code = app.textFields["Doğrulama kodu"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        // A lost connection is not a wrong code: it offers another try.
        code.typeText("999999")
        XCTAssertTrue(app.staticTexts["Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Tekrar dene"].exists)
        XCTAssertFalse(app.staticTexts[codeRejected].exists)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText("8")
        XCTAssertTrue(app.staticTexts["Hesabın hazır"].waitForExistence(timeout: 8))
        #endif
    }

    /// "Şifreni bilmiyor musun?" (forgotten, or never set after mailed-code sign-ins): the address, then the 6-digit code from the reset mail on the
    /// code page, then the new password.
    func testPasswordResetWithCode() throws {
        #if NOVA_PILOT_BUILD
        let app = launchNovaLogin()
        app.buttons["Şifreni bilmiyor musun?"].tap()
        XCTAssertTrue(app.staticTexts["Şifreni belirle"].waitForExistence(timeout: 8))
        let email = app.textFields["E-posta adresin"]
        waitUntilHittable(email)
        email.tap(); email.typeText("exists@example.com")
        app.buttons["nova.reset.send"].tap()

        XCTAssertTrue(app.staticTexts["Kodu gir"].waitForExistence(timeout: 8))
        let code = app.textFields["Doğrulama kodu"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        code.typeText("000000")
        XCTAssertTrue(app.staticTexts[codeRejected].waitForExistence(timeout: 8))
        // Backspace clears every box, and the code can be typed again from the start.
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        XCTAssertFalse(app.staticTexts[codeRejected].exists)
        XCTAssertEqual((code.value as? String) ?? "", "")
        app.typeText("123456")
        let verified = XCTAttachment(screenshot: app.screenshot())
        verified.name = "İSGADA-code-verified"
        verified.lifetime = .keepAlways; add(verified)

        XCTAssertTrue(app.staticTexts["Yeni şifreni belirle"].waitForExistence(timeout: 8))
        let show = app.buttons["Göster"]
        waitUntilHittable(show)
        show.tap()
        let newPassword = app.textFields["Yeni şifre"]
        newPassword.tap(); newPassword.typeText("Zayif")
        app.buttons["nova.reset.save"].tap()
        XCTAssertTrue(app.staticTexts["Şifre en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."]
            .waitForExistence(timeout: 5))
        XCTAssertEqual(ruleValue(app, "digit"), "eksik")
        newPassword.tap(); newPassword.typeText("Guclu123\n")
        XCTAssertEqual(ruleValue(app, "length"), "tamam")
        app.buttons["nova.reset.save"].tap()
        XCTAssertTrue(app.staticTexts["Şifren kaydedildi"].waitForExistence(timeout: 8))
        #endif
    }

    func testWizardExpansionVisualAudit() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_CHECKLIST_PICKER", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Kontrol nerede yapılacak?"].waitForExistence(timeout: 20))
        let independent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bağımsız kontrol")).firstMatch
        XCTAssertTrue(independent.waitForExistence(timeout: 5)); independent.tap()
        XCTAssertTrue(app.staticTexts["Kontrol listesini seç"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sektör")).firstMatch.exists)
        XCTAssertTrue(app.textFields["nova.checklist.start.search"].exists)
        let checklist = XCTAttachment(screenshot: app.screenshot())
        checklist.name = "İSGADA-checklist-filter-wizard"
        checklist.lifetime = .keepAlways; add(checklist)
        app.terminate()

        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_REPORT_CENTER", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Rapor Merkezi"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Yeni rapor oluştur"].exists)
        XCTAssertTrue(app.buttons["Arşiv"].exists)
        let report = XCTAttachment(screenshot: app.screenshot())
        report.name = "İSGADA-report-center"
        report.lifetime = .keepAlways; add(report)
        let companyReport = app.buttons["report.center.kind.company"]
        XCTAssertTrue(companyReport.waitForExistence(timeout: 5)); companyReport.tap()
        XCTAssertTrue(app.staticTexts["Kapsam ve dönem"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Neyi raporlamak istiyorsunuz?"].exists)
        app.buttons["Devam"].tap()
        XCTAssertTrue(app.staticTexts["Raporda neler yer alsın?"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["Örn. Yönetici notu"].exists)
        let reportWizard = XCTAttachment(screenshot: app.screenshot())
        reportWizard.name = "İSGADA-report-content-wizard"
        reportWizard.lifetime = .keepAlways; add(reportWizard)
        app.terminate()

        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_COMPANY_WIZARD", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Firma bilgileri"].exists)
        let company = XCTAttachment(screenshot: app.screenshot())
        company.name = "İSGADA-company-fullscreen-wizard"
        company.lifetime = .keepAlways; add(company)
        app.terminate()
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    /// "Senin İçin": the unused features rotate in the large area on their own and by swipe; below it the
    /// attention box, the unfinished-work box and the progress strip, never two of a kind. The unfinished items
    /// take turns: every launch shows the next one (the screen of 25.09.2026).
    func testForYouRotatesSuggestionsAboveAttentionAndProgress() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_FORYOU", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }
        func featured(_ key: String) -> XCUIElement { app.buttons["nova.home.foryou.featured.discover.\(key)"] }
        func onScreen(_ element: XCUIElement, within seconds: TimeInterval) -> Bool {
            let shown = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
            return XCTWaiter.wait(for: [shown], timeout: seconds) == .completed
        }
        let unfinished = ["continue.company_create", "continue.checklist_open"]
        func shownUnfinished() -> String? { unfinished.first { app.buttons["nova.home.foryou.card.\($0)"].exists } }

        XCTAssertTrue(onScreen(featured("risk_wizard"), within: 20))
        XCTAssertTrue(app.buttons["nova.home.foryou.card.critical.expired"].exists)
        XCTAssertTrue(app.buttons["nova.home.foryou.strip.performance.analyses_30d"].exists)
        let boxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.home.foryou.card."))
        XCTAssertEqual(boxes.count, 2)
        let first = try XCTUnwrap(shownUnfinished(), "one unfinished item in its box")
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "İSGADA-foryou-boxes-and-strip"
        screen.lifetime = .keepAlways; add(screen)

        XCTAssertTrue(onScreen(featured("followup"), within: 9), "moves on by itself")
        // The slide animates for a moment; the first card leaves once it settles.
        let left = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: featured("risk_wizard"))
        XCTAssertEqual(XCTWaiter.wait(for: [left], timeout: 3), .completed, "the first card has moved off")
        featured("followup").swipeLeft()
        XCTAssertTrue(onScreen(featured("statistics"), within: 4), "moves on by swipe")
        XCTAssertTrue(onScreen(featured("risk_wizard"), within: 9), "starts over after the last one")

        app.terminate(); app.launch()
        XCTAssertTrue(onScreen(featured("risk_wizard"), within: 20))
        let second = try XCTUnwrap(shownUnfinished())
        XCTAssertNotEqual(second, first, "the next visit shows the next unfinished item")
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompanyDetailShowsCompactSectionsWithoutTrackingCard() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_COMPANY_PROGRESS", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["company.progress"].waitForExistence(timeout: 8))
        let progressSegments = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "company.progress.segment."))
        XCTAssertEqual(progressSegments.count, 10)
        let riskSegment = app.buttons["company.progress.segment.risk"]
        XCTAssertTrue(riskSegment.exists)
        for _ in 0..<3 where !riskSegment.isHittable { app.swipeUp() }
        XCTAssertTrue(riskSegment.isHittable); riskSegment.tap()
        XCTAssertFalse(app.buttons["Dosya Ekle"].exists)
        XCTAssertFalse(app.buttons["Evrak Takibi"].exists)
        XCTAssertFalse(app.staticTexts["Evrak süreleri"].exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Personel,")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["company.section.nonconformities"].waitForExistence(timeout: 8))

        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "İSGADA-company-detail-progress"
        top.lifetime = .keepAlways
        add(top)

        XCTAssertFalse(app.staticTexts["Firma Takibi"].exists)
        let inspections = app.buttons["company.section.inspections"]
        for _ in 0..<10 where !inspections.exists { app.swipeUp() }
        XCTAssertTrue(inspections.exists); inspections.tap()
        XCTAssertTrue(app.buttons["equipment.inspection.new"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.stat.")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Süreçler ve Takip"].exists)

        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "İSGADA-company-detail-tracking-bottom"
        bottom.lifetime = .keepAlways
        add(bottom)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testPeriodicControlUsesCompactAccordion() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_PERIODIC", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }

        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.stat.")).firstMatch.waitForExistence(timeout: 8))
        let addButton = app.buttons["equipment.inspection.new"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8)); addButton.tap()
        let serials = app.staticTexts.matching(NSPredicate(format: "label == %@", "KRN-001"))
        XCTAssertTrue(serials.firstMatch.waitForExistence(timeout: 8))
        guard let serial = serials.allElementsBoundByIndex.min(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("No equipment choice")
            return
        }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: serial.frame.midX, dy: serial.frame.midY)).tap()

        XCTAssertTrue(app.descendants(matching: .any)["equipment.task.performed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["equipment.task.due"].exists)
        XCTAssertTrue(app.staticTexts["1 / 3"].exists)
        app.buttons["Devam"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        app.buttons["Devam"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Kontrolü kaydet"].exists)
        XCTAssertFalse(app.buttons["Düzenle"].exists)
        XCTAssertFalse(app.buttons["Envanterden çıkar"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "İSGADA-periodic-control-accordion"
        shot.lifetime = .keepAlways
        add(shot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompanyCardExposesDirectLogoPickerAndLargePopupCloseTarget() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertTrue(app.buttons["company.logo.picker"].waitForExistence(timeout: 5))
        let logo = XCTAttachment(screenshot: app.screenshot()); logo.name = "İSGADA-company-direct-logo-picker"; logo.lifetime = .keepAlways; add(logo)
        app.buttons["company.edit"].tap()
        let close = app.buttons["nova.popup.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(close.frame.width, 47)
        XCTAssertGreaterThanOrEqual(close.frame.height, 47)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "İSGADA-company-editor"; shot.lifetime = .keepAlways; add(shot)
        close.tap()
        XCTAssertTrue(app.buttons["company.edit"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testDirectPersonnelSheetPreservesCompanyAccordion() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        let section = app.buttons["company.section.personnel"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        XCTAssertTrue(app.textFields["personnel.search"].waitForExistence(timeout: 5))
        let create = app.buttons["personnel.add"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["personnel.job"].exists)
        XCTAssertTrue(app.buttons["nova.popup.close"].exists)
        let popup = XCTAttachment(screenshot: app.screenshot()); popup.name = "İSGADA-centered-personnel-popup"; popup.lifetime = .keepAlways; add(popup)
        app.buttons["nova.popup.close"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Personeller"].exists)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testDirectorySearchAndPersonnelSheet() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        for _ in 0..<5 { if app.buttons["company.directory.workplaces"].exists { break }; app.swipeUp() }
        app.buttons["company.directory.workplaces"].tap()
        XCTAssertTrue(app.textFields["directory.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Merkez"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["W-hidden-internal-code"].exists)
        XCTAssertTrue(app.buttons["Bilgi geçmişi"].exists)
        let directory = XCTAttachment(screenshot: app.screenshot()); directory.name = "İSGADA-compact-directory"; directory.lifetime = .keepAlways; add(directory)
        let search = app.textFields["directory.search"]
        search.tap(); search.typeText("bulunamayan")
        XCTAssertTrue(app.staticTexts["Aramanızla eşleşen kayıt yok."].waitForExistence(timeout: 5))
        app.buttons["nova.popup.close"].tap()
        app.buttons["company.section.personnel"].tap()
        let add = app.buttons["personnel.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["personnel.save"].isEnabled)
        app.buttons["personnel.save"].tap()
        XCTAssertTrue(app.staticTexts["personnel.message"].exists)
        let name = app.textFields["personnel.name"]
        name.tap(); name.typeText("Deneme")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.48)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(name.value as? String, "Deneme")
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "İSGADA-personnel-sheet"; form.lifetime = .keepAlways; self.add(form)
        app.buttons["nova.popup.close"].tap()
        XCTAssertTrue(app.buttons["personnel.add"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testConfirmedCompanySuccessAutoDismisses() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let create = app.buttons["nova.pilot.company.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); create.tap()
        let name = app.textFields["nova.pilot.company.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Yeni Firma")
        let sector = app.textFields["nova.pilot.company.sector"]
        sector.tap(); sector.typeText("Metal\n")
        app.buttons["nova.pilot.company.submit"].tap()
        let popup = app.descendants(matching: .any).matching(identifier: "nova.success").firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "İSGADA-success"; shot.lifetime = .keepAlways; add(shot)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: popup)
        waitForExpectations(timeout: 5)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompactCompanyAndPersonnelScreens() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_DARK_MODE"]
        app.launch()
        defer { app.terminate() }
        let create = app.buttons["nova.pilot.company.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Panele dön"].exists)
        let companyRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(companyRow.exists)
        create.tap()
        let name = app.textFields["nova.pilot.company.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        app.buttons["nova.pilot.company.submit"].tap()
        XCTAssertTrue(app.staticTexts["nova.pilot.company.error"].waitForExistence(timeout: 3))
        name.tap(); name.typeText("Yeni Firma")
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        let sector = app.textFields["nova.pilot.company.sector"]
        sector.tap(); sector.typeText("Metal")
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "İSGADA-company-form"; form.lifetime = .keepAlways; add(form)
        app.buttons["nova.popup.close"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["company.section.personnel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["company.section.info"].exists)
        let company = XCTAttachment(screenshot: app.screenshot()); company.name = "İSGADA-company-summary"; company.lifetime = .keepAlways; add(company)
        app.buttons["company.section.personnel"].tap()
        let person = app.buttons["personnel.row.00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        XCTAssertTrue(app.buttons["personnel.back"].isHittable)
        let archive = app.buttons["personnel.detail.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5)); archive.tap()
        XCTAssertTrue(app.buttons["personnel.archive.confirm"].waitForExistence(timeout: 5))
        app.buttons["personnel.archive.cancel"].tap()
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    func testPilotDesignAndUnavailableCompanyState() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_PILOT", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["nova.pilot.root"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Özet verileri henüz bağlı değil."].exists)
        app.buttons["nova.home.assistant"].tap()
        XCTAssertTrue(app.alerts["İSGADA pilot"].waitForExistence(timeout: 5))
        app.alerts.buttons["Tamam"].tap()
        app.buttons["nova.tab.companies"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yeni tasarım hazır.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nova.pilot.company.create"].exists)
        XCTAssertFalse(app.buttons["Firma ekle / düzenle"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "İSGADA-pilot-unavailable-company-state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["nova.tab.profile"].tap()
        XCTAssertTrue(app.scrollViews["profile.root"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires the private NOVA_PILOT_BUILD configuration")
        #endif
    }

    func testNonPilotRetainsLegacyRoot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["root.main"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.otherElements["nova.pilot.root"].exists)
    }
}

/// Screenshot-only audit of the current analysis surfaces. The review build
/// supplies deterministic fixture data and never writes to a live account.
final class NovaDesignAuditUITests: XCTestCase {
    private let analysisID = "00000000-0000-4000-8000-000000000006"

    func testLegacyAnalysisOpensFromSavedFindingsWithoutProjection() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = [
            "RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_ANALYSIS",
            "RD_UI_TEST_LEGACY_ANALYSIS_DETAIL", "RD_UI_TEST_RESULT_HUB_MISSING", "RD_UI_TEST_LIGHT_MODE"
        ]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["analysis.list.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.staticTexts["UI Test Saha Analizi"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[
            "Bu eski analiz kayıtlı bulgularından gösteriliyor; bazı ek öneri bölümleri bulunmayabilir."
        ].exists)
        XCTAssertTrue(app.buttons["analysis.detail.section.risk_analysis"].label.contains("3"))
        XCTAssertTrue(app.buttons["analysis.detail.section.expert_recommendations"].label.contains("2"))
        XCTAssertFalse(app.buttons["analysis.detail.select.all"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "İSGADA-legacy-analysis-fallback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testAnalysisResultAndSectionSurfaces() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_ANALYSIS", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["analysis.list.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        capture(app, name: "01-analysis-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Analiz Sonucu"].waitForExistence(timeout: 10))
        capture(app, name: "02-analysis-result-risk")
        XCTAssertTrue(app.buttons["analysis.detail.method.fine_kinney"].exists)
        XCTAssertFalse(app.buttons["analysis.detail.select.all"].exists)
        XCTAssertFalse(app.buttons["analysis.detail.section.approved_notebook"].exists)

        app.buttons["analysis.detail.report"].tap()
        XCTAssertTrue(app.buttons["analysis.report.run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["analysis.detail.select.all"].exists)
        capture(app, name: "02b-analysis-report-options")
        app.buttons["nova.popup.close"].tap()

        let finding = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "analysis.finding.")).firstMatch
        XCTAssertTrue(finding.waitForExistence(timeout: 5))
        finding.tap()
        XCTAssertTrue(app.staticTexts["Bulgu Detayı"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Korkuluk eksik"].exists)
        sleep(1) // Let the full-screen push finish before the visual audit capture.
        capture(app, name: "04-analysis-finding-detail")

        app.buttons["analysis.finding.file"].tap()
        XCTAssertTrue(app.staticTexts["Uygunsuzluk oluştur"].waitForExistence(timeout: 5))
        capture(app, name: "04b-analysis-filing-company")
        let company = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Örnek Metal A.Ş.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 5))
        company.tap()
        let create = app.buttons["analysis.file.run"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.staticTexts["Bulgu Detayı"].waitForExistence(timeout: 5))

        app.buttons["analysis.finding.detail.back"].tap()

        for section in ["expert_recommendations", "training_recommendations"] {
            let tab = app.buttons["analysis.detail.section.\(section)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing analysis section tab: \(section)")
            tab.tap()
            capture(app, name: "03-analysis-\(section)")
        }
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testFindingDetailSurface() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_FINDING", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["nonconformity.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        capture(app, name: "05-findings-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Kayıt detayı"].waitForExistence(timeout: 10))
        capture(app, name: "06-finding-detail")
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    #if NOVA_PILOT_BUILD
    private func capture(_ app: XCUIApplication, name: String, file: StaticString = #filePath, line: UInt = #line) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}

private extension XCTestCase {
    /// Page changes cross-fade; a control is only tappable once the old page has gone.
    func waitUntilHittable(_ element: XCUIElement) {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        wait(for: [hittable], timeout: 8)
    }

    /// The pilot entry gate on the sign-in page, with the network-free auth stub.
    func launchNovaLogin() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_AUTH", "RD_UI_TEST_NOVA_AUTH_STUB", "RD_UI_TEST_LIGHT_MODE",
                               "-nova.pilot.onboarding.completed.v1", "YES"]
        app.launch()
        XCTAssertTrue(app.textFields["E-posta adresin"].waitForExistence(timeout: 20))
        return app
    }

    func fillSignIn(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["E-posta adresin"]
        emailField.tap(); emailField.typeText(email + "\n")
        let passwordField = app.secureTextFields["Şifren"]
        passwordField.tap(); passwordField.typeText(password + "\n")
    }

    var codeRejected: String {
        "Kod yanlış ya da süresi dolmuş. Hatalı rakama dokunup düzelt ya da yeni kod iste."
    }

    /// Taps one of the six code boxes. They carry no accessibility element of their own (the
    /// hidden text field does), so the tap goes by position: 24 pt page margins, 8 pt gaps.
    func tapCodeBox(_ app: XCUIApplication, _ index: Int) {
        let field = app.textFields["Doğrulama kodu"]
        let width = app.windows.firstMatch.frame.width
        let box = (width - 48 - 40) / 6
        let x = 24 + CGFloat(index) * (box + 8) + box / 2
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: field.frame.midY)).tap()
    }

    /// "tamam" or "eksik" for one rule under a new-password field.
    func ruleValue(_ app: XCUIApplication, _ rule: String) -> String? {
        let element = app.descendants(matching: .any)["nova.password.rule.\(rule)"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.value as? String
    }

    /// Leaving a page with a password, iOS offers to save it.
    func dismissSavePassword(_ app: XCUIApplication) {
        let notNow = app.buttons["Sonra"]
        if notNow.waitForExistence(timeout: 4) { notNow.tap() }
    }
}
