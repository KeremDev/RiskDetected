import CryptoKit
import Foundation
import Security
import XCTest

final class RiskDetectedUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testFreeTierPaywallUsesRetryWhenStorePriceUnavailable() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        tap("Yükselt", timeout: 20)
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 10).exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 15).exists)
        XCTAssertFalse(app.staticTexts["₺199,99"].exists)
        XCTAssertFalse(app.staticTexts["₺1.999,99"].exists)

        tap("Tekrar dene", timeout: 15)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 5).exists)
    }

    func testOnboardingPersonalPlanReachesAuth() throws {
        launchApp()

        completeQuestionsToPersonalPlan()
        XCTAssertTrue(waitFor("Hesabımı Oluştur").exists)

        tap("Hesabımı Oluştur")
        XCTAssertTrue(waitFor("Apple ile devam et").exists)
        XCTAssertTrue(waitForOne(["onboarding.auth.google", "Google"]).exists)
        XCTAssertTrue(waitFor("E-posta ile devam et").exists)
    }

    func testTrialInviteAndTimelinePaywallRenderWithAuthBypass() throws {
        launchApp(extraArguments: ["RD_UI_TEST_BYPASS_AUTH"])

        completeQuestionsToPersonalPlan()
        tap("Hesabımı Oluştur")

        tapScrolling("₺0,00'ye dene", timeout: 10)

        XCTAssertTrue(waitFor("onboarding.notification_permission", timeout: 8).exists)
        XCTAssertTrue(waitFor("Şimdi ödeme alınmayacak").exists)
        tap("onboarding.notification_permission.cta")

        XCTAssertTrue(waitFor("Yıllık", timeout: 8).exists)
        XCTAssertTrue(waitFor("Aylık").exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12).exists)
        XCTAssertTrue(waitFor("Geri yükle").exists)
        XCTAssertTrue(waitFor("Kullanım Şartları").exists)
        XCTAssertTrue(waitFor("Gizlilik Politikası").exists)
        XCTAssertTrue(waitFor("Firma Yönetimi").exists)
        XCTAssertTrue(waitFor("Çoklu Fotoğraf Analizi").exists)

        tap("Kullanım Şartları")
        XCTAssertTrue(waitFor("Yasal Bilgilendirme", timeout: 4).exists)
        XCTAssertTrue(waitFor("Kullanım Koşulları").exists)
        tap("Pencereyi kapat")

        tap("Aylık")
        XCTAssertFalse(app.staticTexts["₺199,99/ay — istediğin zaman iptal"].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne(["App Store fiyatı yükleniyor", "Fiyat alınamadı"], timeout: 8).exists)

        tap("Yıllık")
        XCTAssertFalse(app.staticTexts["7 gün ücretsiz, sonra ₺1.999,99 (₺166,67/ay)"].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne(["App Store fiyatı yükleniyor", "Fiyat alınamadı"], timeout: 8).exists)
    }

    func testOnboardingAllQuestionScreensAndAuthEmailPanelRender() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        tap("onboarding.splash.start")

        XCTAssertTrue(waitFor("onboarding.pain_point").exists)
        XCTAssertTrue(waitFor("Saatlerce süren rapor yazımı.").exists)
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.certificate").exists)
        tap("onboarding.certificate.a")
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.hazard").exists)
        tap("onboarding.hazard.critical")
        tap("onboarding.hazard.high")
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.sector").exists)
        XCTAssertTrue(waitFor("Birden fazla seçebilirsin. Her analiz öncesinde, o fotoğrafı hangi sektör kapsamında değerlendirmek istediğini ayrıca soracağız.").exists)
        tap("onboarding.sector.construction")
        tap("onboarding.sector.manufacturing")
        tap("onboarding.sector.mining")
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.frequency").exists)
        tap("onboarding.frequency.6_15")
        tap("Planımı Hazırla")

        XCTAssertTrue(waitFor("onboarding.loading", timeout: 8).exists)
        XCTAssertTrue(waitFor("onboarding.personal_plan", timeout: 12).exists)
        tap("Hesabımı Oluştur")

        XCTAssertTrue(waitFor("onboarding.auth", timeout: 8).exists)
        XCTAssertTrue(waitFor("onboarding.auth.apple").exists)
        XCTAssertTrue(waitFor("onboarding.auth.google").exists)
        XCTAssertTrue(waitFor("E-posta ile devam et").exists)
        XCTAssertTrue(waitFor("onboarding.auth.sign_in_existing").exists)
    }

    func testOnboardingSplashClassicDesignRenderAndStart() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        XCTAssertTrue(waitFor("Profesyonel İSG Asistanı").exists)
        XCTAssertTrue(waitFor("onboarding.splash.subtitle").exists)
        XCTAssertTrue(waitFor("onboarding.splash.preview_phone").exists)
        XCTAssertTrue(waitFor("onboarding.splash.progress").exists)
        XCTAssertTrue(waitFor("onboarding.splash.chip.detection").exists)
        XCTAssertTrue(waitFor("onboarding.splash.chip.preparing").exists)
        XCTAssertTrue(waitFor("onboarding.splash.skip").exists)

        tap("onboarding.splash.start")
        XCTAssertTrue(waitFor("onboarding.pain_point").exists)
    }

    func testOnboardingSplashSkipShowsConfirmation() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        tap("onboarding.splash.skip")

        XCTAssertTrue(waitFor("onboarding.skip_confirmation").exists)
        XCTAssertTrue(waitFor("Sana özel sonuçlar veremeyeceğiz").exists)
        XCTAssertTrue(waitFor("Cevaplamaya devam et").exists)
        XCTAssertTrue(waitFor("Yine de atla").exists)
    }

    func testMainTabsProfileAndDarkModeRenderWithBypass() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DARK_MODE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        XCTAssertTrue(waitFor("UI Test Kullanıcı").exists)
        XCTAssertTrue(waitFor("Firmalarım").exists)

        tapTab(.analyses)
        XCTAssertTrue(waitFor("Analizler").exists)

        tapTab(.reports)
        XCTAssertTrue(waitFor("Denetime hazır çıktılar").exists)

        tapTab(.home)
        XCTAssertTrue(waitFor("Saha fotoğrafı yükle").exists)
    }

    func testHomeMultiPhotoSlotsRenderForPaidFixture() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_PHOTO_TRAY"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("Saha fotoğrafları").exists)
        XCTAssertTrue(waitFor("0/5").exists)
        XCTAssertTrue(waitFor("home.photo_tray").exists)
        XCTAssertTrue(waitFor("home.photo_slot.1").exists)
        XCTAssertTrue(waitFor("home.photo_slot.5").exists)
    }

    func testQuickScanButtonOpensPhotoTray() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("tab.quick_scan")
        XCTAssertTrue(waitFor("home.photo_tray").exists)
        XCTAssertTrue(waitFor("home.photo_slot.5").exists)
    }

    func testFreeLockedPhotoSlotOpensPaywall() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER", "RD_UI_TEST_OPEN_PHOTO_TRAY"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("Çoklu fotoğraf özelliği için hesabınızı yükseltin").exists)
        tap("home.photo_slot.2")
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 10).exists)
    }

    func testHomePhotoUploadReturnsToTrayAfterAnnotation() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DIRECT_HOME_PHOTO_PICK"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.photo_tray.open")
        XCTAssertTrue(waitFor("İşaretlemeyi kaydet", timeout: 8).exists)

        tap("İşaretlemeyi kaydet", timeout: 8)

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        XCTAssertTrue(waitFor("1/5").exists)
        XCTAssertTrue(waitFor("Analize geç").exists)
    }

    func testPhotoTrayWithExistingPhotosFixtureRenders() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        XCTAssertTrue(waitFor("2/5").exists)
        XCTAssertTrue(waitFor("home.photo_slot.1").exists)
        XCTAssertTrue(waitFor("home.photo_slot.2").exists)
        XCTAssertTrue(waitFor("home.photo_slot.5").exists)
        XCTAssertTrue(waitFor("Analize geç").exists)
    }

    func testAnalyzingProgressOverlayRendersWithPercentAndSteps() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_ANALYZING"])

        XCTAssertTrue(waitFor("analysis.loading", timeout: 10).exists)
        XCTAssertTrue(waitFor("analysis.progress.percent", timeout: 4).exists)
        XCTAssertTrue(waitFor("Görüntü kalitesi okunuyor").exists)
        XCTAssertTrue(waitFor("Bulgular yapılandırılıyor").exists)
        XCTAssertFalse(app.staticTexts["Netlik ve görüntü okunabilirliği kontrol ediliyor"].waitForExistence(timeout: 0.5))
        XCTAssertTrue(waitFor("5 fotoğraf").exists)
        XCTAssertFalse(app.staticTexts["100"].waitForExistence(timeout: 0.5))
        XCTAssertTrue(waitFor("Bağlantı tekrar deneniyor", timeout: 6).exists)
    }

    func testAnalyzingProgressCompletesIntoResult() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_ANALYZING_COMPLETES"])

        XCTAssertTrue(waitFor("analysis.loading", timeout: 10).exists)
        XCTAssertTrue(waitFor("analysis.progress.percent", timeout: 4).exists)
        XCTAssertTrue(waitFor("Sonuç hazırlanıyor", timeout: 8).exists)
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 12).exists)
    }

    func testE2ERealFivePhotoAnalysisCompletes() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RD_E2E_REAL_5_PHOTO_ANALYSIS"] == "1" else {
            throw XCTSkip("Set RD_E2E_REAL_5_PHOTO_ANALYSIS=1 to run the real Supabase 5-photo analysis gate.")
        }
        let email = environment["RD_E2E_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = environment["RD_E2E_PASSWORD"] ?? ""
        guard !email.isEmpty, !password.isEmpty else {
            throw XCTSkip("RD_E2E_EMAIL and RD_E2E_PASSWORD are required for the real Supabase E2E gate.")
        }

        app = XCUIApplication()
        app.launchArguments = [
            "RD_E2E_REAL_5_PHOTO_ANALYSIS",
            "-UIViewAnimationEnabled", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launchEnvironment["RD_E2E_REAL_5_PHOTO_ANALYSIS"] = "1"
        app.launchEnvironment["RD_E2E_EMAIL"] = email
        app.launchEnvironment["RD_E2E_PASSWORD"] = password
        launchPreparedApp()

        XCTAssertTrue(waitFor("analysis.loading", timeout: 75).exists)
        XCTAssertTrue(waitFor("analysis.progress.percent", timeout: 8).exists)
        XCTAssertTrue(waitFor("5 fotoğraf", timeout: 8).exists)
        XCTAssertFalse(app.staticTexts["100"].waitForExistence(timeout: 0.5))
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 420).exists)
    }

    func testAnnotateFromPhotoTrayUsesSaveCopy() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        tap("home.photo_slot.1")
        XCTAssertTrue(waitFor("İşaretlemeyi kaydet", timeout: 8).exists)
        XCTAssertFalse(app.buttons["İşaretli alanları analiz et"].waitForExistence(timeout: 1))
    }

    func testResultFindingDeleteButtonRequiresConfirmation() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapScrolling("home.recent_analysis.3. Kat şantiye girişi", timeout: 8)
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)

        tapScrolling("result.finding.1.delete", timeout: 10)
        XCTAssertTrue(waitFor("Bulgu silinsin mi?", timeout: 4).exists)
        XCTAssertTrue(waitFor("Bu bulgu yeni raporlara dahil edilmeyecek. Eski rapor snapshotları ve audit kaydı korunur.", timeout: 4).exists)
        tap("Vazgeç", timeout: 4)
        XCTAssertFalse(exists("Bulgu silinsin mi?", timeout: 1))
    }

    func testResultFindingShowsFieldVerificationBadge() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT"])

        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)
        XCTAssertTrue(waitFor("result.finding.1.field_verification", timeout: 8).exists)
        XCTAssertTrue(waitFor("Saha teyidi", timeout: 4).exists)
    }

    func testResultFindingDetailUsesSourcePhoto() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT"])

        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)
        tapScrolling("result.finding.1.card", timeout: 10)
        XCTAssertTrue(waitFor("result.detail.photo_index.4", timeout: 8).exists)
        XCTAssertTrue(waitFor("Foto 4", timeout: 4).exists)
        XCTAssertTrue(waitFor("result.detail.close", timeout: 4).exists)
    }

    func testFindingEditorSheetRendersCompactControls() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT", "RD_UI_TEST_OPEN_FINDING_EDITOR"])

        XCTAssertTrue(waitFor("Bulguyu Düzenle", timeout: 10).exists)
        XCTAssertTrue(waitFor("Tolerans dışı").exists)
        XCTAssertTrue(waitFor("finding_editor.fk_probability").exists)
        XCTAssertTrue(waitFor("finding_editor.fk_frequency").exists)
        XCTAssertTrue(waitFor("finding_editor.fk_severity").exists)
        XCTAssertTrue(waitFor("finding_editor.m5_probability").exists)
        XCTAssertTrue(waitFor("finding_editor.m5_severity").exists)
        XCTAssertTrue(waitFor("Düzeltici önlem").exists)
        XCTAssertTrue(waitFor("Önleyici kontrol").exists)
        XCTAssertTrue(waitFor("finding_editor.delete").exists)
        XCTAssertTrue(waitFor("finding_editor.cancel").exists)
        XCTAssertTrue(waitFor("finding_editor.save").exists)
    }

    func testProfileDarkModePreferencesCanSwitchTheme() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DARK_MODE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        XCTAssertTrue(waitFor("profile.root").exists)
        XCTAssertTrue(waitFor("profile.hero.card").exists)
        XCTAssertTrue(waitFor("profile.row.notifications").exists)
        XCTAssertTrue(waitFor("profile.row.companies").exists)
    }

    func testInAppPaywallClaudePlusAndProRenderWithFreeTier() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("İlk haftanız bizden.", timeout: 8).exists)
        XCTAssertTrue(waitFor("Neler dahil?").exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 15).exists)
        XCTAssertFalse(app.staticTexts["₺199,99"].exists)
        XCTAssertFalse(app.staticTexts["₺1.999,99"].exists)
        XCTAssertTrue(waitFor("Firma yönetimi").exists)
        let multiPhotoAnalysis = waitFor("Çoklu Fotoğraf Analizi")
        let plusCTA = waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12)
        XCTAssertLessThan(multiPhotoAnalysis.frame.maxY, plusCTA.frame.minY)

        tap("Şartlar")
        XCTAssertTrue(waitFor("Yasal Bilgilendirme", timeout: 4).exists)
        XCTAssertTrue(waitFor("Kullanım Koşulları").exists)
        tap("Pencereyi kapat")

        tap("Aylık")
        XCTAssertTrue(waitFor("Plus’a abone olun.").exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12).exists)

        tap("in_app_paywall.plus.pro_link")
        XCTAssertTrue(waitFor("Limitsiz Özellikler").exists)
        XCTAssertTrue(waitFor("Tüm Plus özellikleri dahil").exists)
        tap("Aylık")
        XCTAssertFalse(app.staticTexts["Tüm Pro özellikleri aylık ₺499,99 ile."].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne([
            "Tüm Pro özellikleri aylık fiyat yükleniyor ile.",
            "Tüm Pro özellikleri aylık fiyat alınamadı ile."
        ], timeout: 8).exists)
        tap("Yıllık")
        XCTAssertFalse(app.staticTexts["Yıllık ₺4.999,99 ile tüm Pro özellikleri."].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne([
            "Yıllık fiyat yükleniyor ile tüm Pro özellikleri.",
            "Yıllık fiyat alınamadı ile tüm Pro özellikleri."
        ], timeout: 8).exists)
        XCTAssertTrue(waitFor("Plus aboneliğini incele").exists)

        tap("in_app_paywall.pro.plus_link")
        XCTAssertTrue(waitFor("İlk haftanız bizden.").exists)
    }

    func testPaywallYearlyMonthlyToggleForPlusAndPro() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        tap("Aylık")
        XCTAssertTrue(waitFor("Plus’a abone olun.").exists)
        tap("Yıllık")
        XCTAssertTrue(waitFor("İlk haftanız bizden.").exists)

        tap("in_app_paywall.plus.pro_link")
        XCTAssertTrue(waitFor("in_app_paywall.pro", timeout: 8).exists)
        tap("Aylık")
        XCTAssertFalse(app.staticTexts["Tüm Pro özellikleri aylık ₺499,99 ile."].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne([
            "Tüm Pro özellikleri aylık fiyat yükleniyor ile.",
            "Tüm Pro özellikleri aylık fiyat alınamadı ile."
        ], timeout: 8).exists)
        tap("Yıllık")
        XCTAssertFalse(app.staticTexts["Yıllık ₺4.999,99 ile tüm Pro özellikleri."].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne([
            "Yıllık fiyat yükleniyor ile tüm Pro özellikleri.",
            "Yıllık fiyat alınamadı ile tüm Pro özellikleri."
        ], timeout: 8).exists)
    }

    func testCompanyPickerV2FieldsRenderWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("Firmalarım")

        XCTAssertTrue(waitFor("Firmalarım").exists)
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
        XCTAssertTrue(waitFor("Çok Tehlikeli · Bakım Ekibi").exists)

        tap("company_picker.add")
        XCTAssertTrue(waitFor("Yeni firma").exists)
        XCTAssertTrue(waitFor("Firma adı").exists)
        XCTAssertTrue(waitFor("Firma detayları").exists)
        XCTAssertTrue(waitFor("Adres").exists)
        XCTAssertTrue(waitFor("İlgili kişi").exists)
        XCTAssertTrue(waitFor("Departman / ekip").exists)
        XCTAssertTrue(waitFor("Rapor varsayılanları").exists)
        XCTAssertTrue(waitFor("Varsayılan sorumlu").exists)
        XCTAssertTrue(waitFor("Varsayılan termin günü").exists)
    }

    func testCompanyManagementAddEditArchiveWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("Firmalarım")

        tap("company_picker.add")
        XCTAssertTrue(waitFor("Yeni firma").exists)
        typeInto("company.editor.name", text: "Test V2 Firma")
        tapScrolling("Az Tehlikeli")
        tapScrolling("Firmayı kaydet")

        XCTAssertTrue(waitFor("Test V2 Firma", timeout: 8).exists)
        XCTAssertTrue(waitFor("Az Tehlikeli").exists)

        tap("Test V2 Firma işlemleri")
        tap("Düzenle")
        clearAndType("company.editor.name", text: "Test V2 Firma Güncel")
        tapScrolling("Firmayı kaydet")

        XCTAssertTrue(waitFor("Test V2 Firma Güncel", timeout: 8).exists)
        tap("Test V2 Firma Güncel işlemleri")
        tap("Arşivle")
        tap("Arşivle")
        XCTAssertFalse(exists("Test V2 Firma Güncel", timeout: 3))
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
    }

    func testCompanyFilterSheetsRenderWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.analyses)
        tap("analysis.company_filter")
        XCTAssertTrue(waitFor("Analiz firma filtresi").exists)
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
        tap("Pencereyi kapat")

        tapTab(.reports)
        tap("report.company_filter")
        XCTAssertTrue(waitFor("Rapor firma filtresi").exists)
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
    }

    func testReportArchiveSearchFilterAndDeleteWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.reports)
        XCTAssertTrue(waitFor("report.root").exists)
        XCTAssertTrue(waitFor("Test Firma Raporu", timeout: 8).exists)

        typeInto("report.archive.search", text: "Test Firma")
        XCTAssertTrue(waitFor("Test Firma Raporu").exists)
        tap("report.archive.filter.Standart")
        XCTAssertTrue(waitFor("Test Firma Raporu").exists)

        longPress("report.archive.row.00000000-0000-0000-0000-00000000A101")
        tap("Raporu sil")
        tap("Raporu sil")
        XCTAssertFalse(exists("Test Firma Raporu", timeout: 3))
    }

    func testReportCreationFromArchiveAnalysisWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.reports)
        XCTAssertTrue(waitFor("report.root").exists)
        tap("report.analysis.row.00000000-0000-0000-0000-00000000A201", timeout: 8)

        XCTAssertTrue(waitFor("report.source_sheet", timeout: 8).exists)
        tap("report.source_sheet.open_settings")
        XCTAssertTrue(waitFor("report.settings", timeout: 8).exists)
        XCTAssertTrue(waitFor("Standart Rapor").exists)
        tap("report.settings.kind.standard")
        tap("Rapor oluştur")

        XCTAssertTrue(waitFor("Önizlemeyi kapat", timeout: 20).exists)
        tap("Önizlemeyi kapat")
        XCTAssertTrue(waitFor("UI Test Rapor Kaynağı", timeout: 8).exists)
    }

    func testNotificationSettingsSheetStaysSimpleWithBypass() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("profile.row.notifications")

        XCTAssertTrue(waitFor("Bildirimler kapalı").exists)
        XCTAssertTrue(waitFor("Açtığında analiz sonucu, rapor hazır olma ve önemli hesap güvenliği bildirimlerini alabilirsin.").exists)
        XCTAssertTrue(waitFor("Bildirimleri aç").exists)
        XCTAssertFalse(exists("Supabase", timeout: 1))
    }

    func testFreeRiskAnalysisTrialDoesNotLockStandardReport() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER", "RD_UI_TEST_LONG_REPORT_FIELDS", "RD_UI_TEST_REPORT_LOGO"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        app.swipeUp()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.53)).tap()
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)

        tapScrolling("Rapor Oluştur", timeout: 10)
        XCTAssertTrue(waitFor("report.settings", timeout: 8).exists)
        XCTAssertTrue(waitFor("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!").exists)
        XCTAssertTrue(waitFor("Tebrikler! Bir tane risk analizi oluşturma hakkı tanımlandı. Hemen deneyebilirsin.").exists)
        XCTAssertTrue(waitFor("Hızlı Uygunsuzluk Raporu, ek bilgi girmeden oluşturulur.").exists)

        tap("report.settings.kind.riskAnalysis")
        XCTAssertTrue(waitFor("Risk analizi PDF oluştur", timeout: 5).exists)
        XCTAssertFalse(app.staticTexts["Bugünkü standart rapor hakkın doldu. Hakların yarın yenilenir."].exists)

        tap("Risk analizi PDF oluştur")
        XCTAssertTrue(waitFor("Önizlemeyi kapat", timeout: 12).exists)
        tap("Önizlemeyi kapat")

        tapScrolling("Rapor Oluştur", timeout: 10)
        XCTAssertTrue(waitFor("report.settings", timeout: 8).exists)
        XCTAssertFalse(app.staticTexts["Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!"].exists)
        XCTAssertTrue(waitFor("Bir kez tanımlanan hakkını kullandın. Risk analizi tabloları Plus ile devam eder.").exists)
        XCTAssertTrue(waitFor("Hızlı Uygunsuzluk Raporu, ek bilgi girmeden oluşturulur.").exists)
    }

    func testProfileAccountDeletionVisibleAndCopyWithBypass() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("profile.row.delete_account")
        XCTAssertTrue(waitFor("Hesabın ve verilerin silinsin mi?").exists)
        XCTAssertTrue(waitFor("Hesabın, profilin, analizlerin, raporların ve saklanan dosyaların kalıcı olarak silinir. Silme işlemi uygulama içinde tamamlanır; e-posta, destek veya web sitesi gerekmez. Aktif App Store aboneliğin varsa iptal ve yönetim işlemleri Apple abonelik ayarlarından yapılır. Bu işlem geri alınamaz.").exists)
        XCTAssertTrue(waitFor("Hesabımı sil / Delete Account").exists)
    }

    func testHardUpdatePolicyBlocksAppWithUpdateCTA() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FORCE_HARD_UPDATE"])

        XCTAssertTrue(waitFor("app_release.hard_update", timeout: 10).exists)
        XCTAssertTrue(waitFor("Güncelleme gerekli").exists)
        XCTAssertTrue(waitFor("Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.").exists)
        XCTAssertTrue(waitFor("App Store'da güncelle").exists)
    }

    func testSoftUpdatePolicyCanBeDismissed() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FORCE_SOFT_UPDATE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("app_release.soft_update", timeout: 10).exists)
        XCTAssertTrue(waitFor("Yeni sürüm hazır").exists)
        tap("Daha sonra")
        XCTAssertFalse(exists("app_release.soft_update", timeout: 2))
    }

    func testActiveAnalysisSectorPickerRequiresSelectionBeforeCanvas() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.mode.text")
        typeInto("home.text_input", text: "Korkuluk eksik, işçi emniyet kemeri kullanmıyor.")
        tap("home.start_scan")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        XCTAssertFalse(isEnabled("Devam et"))

        tap("analysis_sector_chip_construction")
        XCTAssertTrue(isEnabled("Devam et"))
        tap("Devam et")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
        XCTAssertTrue(waitFor("Odaklı Analiz").exists)
    }

    func testActiveAnalysisSectorSingleSelectionReplacesPreviousChoice() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.mode.text")
        typeInto("home.text_input", text: "Forklift yaya yoluna girdi, raf istifi yüksek.")
        tap("home.start_scan")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        tap("analysis_sector_chip_construction")
        tap("analysis_sector_chip_manufacturing")
        tap("Devam et")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
    }

    func testActiveAnalysisSectorFullGridShowsLogisticsWarehouseChip() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.mode.text")
        typeInto("home.text_input", text: "Depo rampasında zemin kaygan ve forklift trafiği yoğun.")
        tap("home.start_scan")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        XCTAssertTrue(waitFor("analysis_sector_chip_logistics_warehouse", timeout: 8).exists)
        tap("analysis_sector_chip_logistics_warehouse")
        tap("Devam et")
        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
    }

    func testProfileShowsDeviceIntegrityWarningWhenFlagged() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DEVICE_INTEGRITY_WARNING"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)

        XCTAssertTrue(waitFor("profile.device_integrity.warning").exists)
        XCTAssertTrue(waitFor("Cihaz güvenliği uyarısı").exists)
        XCTAssertTrue(waitFor("Bu cihazda güvenliği etkileyebilecek sistem değişikliği sinyalleri var: UI test sinyali.").exists)
    }

    func testRealDeviceSupabasePinnedConnection() async throws {
        let probe = SupabasePinnedConnectionProbe(
            pinnedHost: "ppcrzemgiztzcgddbins.supabase.co",
            pinnedCertificateHashes: ["HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="]
        )
        let session = URLSession(configuration: .ephemeral, delegate: probe, delegateQueue: nil)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/health")))
        request.timeoutInterval = 15

        let (_, response) = try await session.data(for: request)
        let statusCode = try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
        XCTAssert((200..<500).contains(statusCode), "Unexpected Supabase health status: \(statusCode)")
        XCTAssertEqual(probe.didMatchPinnedCertificate, true)
    }

    private func launchApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_RESET_STATE"] + extraArguments
        app.launchEnvironment["RD_UI_TEST_RESET_STATE"] = "1"
        launchPreparedApp()
    }

    private func launchMainApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "RD_UI_TEST_MAIN",
            "RD_UI_TEST_COMPANY_FIXTURES",
            "RD_UI_TEST_REPORT_FIXTURES",
            "-UIViewAnimationEnabled", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ] + extraArguments
        app.launchEnvironment["RD_UI_TEST_MAIN"] = "1"
        app.launchEnvironment["RD_UI_TEST_COMPANY_FIXTURES"] = "1"
        app.launchEnvironment["RD_UI_TEST_REPORT_FIXTURES"] = "1"
        for argument in extraArguments where argument.hasPrefix("RD_UI_TEST_") {
            app.launchEnvironment[argument] = "1"
        }
        if extraArguments.contains("RD_UI_TEST_DARK_MODE") {
            app.launchEnvironment["RD_UI_TEST_DARK_MODE"] = "1"
        }
        if extraArguments.contains("RD_UI_TEST_DEVICE_INTEGRITY_WARNING") {
            app.launchEnvironment["RD_UI_TEST_DEVICE_INTEGRITY_WARNING"] = "1"
        }
        launchPreparedApp()
    }

    private func launchPreparedApp() {
        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
    }

    private func completeQuestionsToPersonalPlan() {
        tap("onboarding.splash.start", timeout: 12)

        tap("Devam")

        tap("A Sınıfı İSG Uzmanı")
        tap("Devam")

        tap("Çok Tehlikeli")
        tap("Devam")

        tap("İnşaat")
        tap("Devam")

        tap("6-15")
        tap("Planımı Hazırla")

        XCTAssertTrue(waitFor("Hesabımı Oluştur", timeout: 12).exists)
    }

    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 6) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var firstExisting: XCUIElement?

        repeat {
            for query in matchingQueries(identifier) {
                for index in 0..<query.count {
                    let element = query.element(boundBy: index)
                    guard element.exists else { continue }
                    if element.isHittable { return element }
                    if firstExisting == nil { firstExisting = element }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline

        if let firstExisting { return firstExisting }
        XCTFail("Missing accessibility identifier: \(identifier)")
        return app.otherElements[identifier]
    }

    private func waitForOne(_ identifiers: [String], timeout: TimeInterval = 6) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            for identifier in identifiers {
                for query in matchingQueries(identifier) {
                    for index in 0..<query.count {
                        let element = query.element(boundBy: index)
                        guard element.exists else { continue }
                        if element.isHittable { return element }
                        return element
                    }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline

        XCTFail("Missing any accessibility identifier: \(identifiers.joined(separator: ", "))")
        return app.otherElements[identifiers.first ?? ""]
    }

    private func matchingQueries(_ identifier: String) -> [XCUIElementQuery] {
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@",
            identifier,
            identifier
        )
        return [
            app.buttons.matching(predicate),
            app.otherElements.matching(predicate),
            app.textFields.matching(predicate),
            app.secureTextFields.matching(predicate),
            app.staticTexts.matching(predicate),
            app.images.matching(predicate),
            app.descendants(matching: .any).matching(predicate)
        ]
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(identifier)")
        element.tap()
    }

    private func isEnabled(_ identifier: String, timeout: TimeInterval = 3) -> Bool {
        let element = waitFor(identifier, timeout: timeout)
        return element.isEnabled
    }

    private func exists(_ identifier: String, timeout: TimeInterval = 1.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in matchingQueries(identifier) {
                if query.firstMatch.exists { return true }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        return false
    }

    private func typeInto(_ identifier: String, text: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Text field is not hittable: \(identifier)")
        element.tap()
        element.typeText(text)
    }

    private func clearAndType(_ identifier: String, text: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Text field is not hittable: \(identifier)")
        element.tap()
        let currentValue = (element.value as? String) ?? ""
        if !currentValue.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        element.typeText(text)
    }

    private enum TestTab {
        case home
        case analyses
        case reports
        case profile

        var identifier: String {
            switch self {
            case .home: return "tab.home"
            case .analyses: return "tab.analyses"
            case .reports: return "tab.reports"
            case .profile: return "tab.profile"
            }
        }
    }

    private func tapTab(_ tab: TestTab) {
        tap(tab.identifier, timeout: 8)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func tapScrolling(_ identifier: String, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in matchingQueries(identifier) {
                for index in 0..<query.count {
                    let element = query.element(boundBy: index)
                    guard element.exists else { continue }
                    if element.isHittable {
                        element.tap()
                        return
                    }
                }
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        XCTFail("Element is not hittable after scrolling: \(identifier)")
    }

    private func longPress(_ identifier: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.exists, "Element does not exist: \(identifier)")
        element.press(forDuration: 1.0)
    }

}

private final class SupabasePinnedConnectionProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinnedHost: String
    private let pinnedCertificateHashes: Set<String>
    private let lock = NSLock()
    private var matchedPinnedCertificate = false

    var didMatchPinnedCertificate: Bool {
        lock.withLock { matchedPinnedCertificate }
    }

    init(pinnedHost: String, pinnedCertificateHashes: Set<String>) {
        self.pinnedHost = pinnedHost
        self.pinnedCertificateHashes = pinnedCertificateHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.host == pinnedHost,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError),
              certificateHashes(for: serverTrust).contains(where: pinnedCertificateHashes.contains)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        lock.withLock {
            matchedPinnedCertificate = true
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func certificateHashes(for trust: SecTrust) -> [String] {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return []
        }

        return certificates.map { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            return Data(SHA256.hash(data: data)).base64EncodedString()
        }
    }
}
