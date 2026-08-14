import Foundation

struct AppErrorMessage: Equatable {
    enum Category: String {
        case authRequired
        case quotaExceeded
        case networkUnavailable
        case storageDenied
        case aiRateLimited
        case aiUnavailable
        case aiInvalidResponse
        case reportArchiveFailed
        case pdfRenderFailed
        case validationFailed
        case backgroundAnalysisPending
        case databaseFailed
        case unknown
    }

    let title: String
    let message: String
    let action: String
    let category: Category
    let supportID: String

    static let existingAppStoreSubscriptionMessage = RDLocalization.string("localizable.app.error.message.bu.app.store.hesabinda.aktif.bir.riskdetected.ab.c415da59", table: .localizable, fallback: "Bu App Store hesabında aktif bir RiskDetected aboneliği görünüyor. Abonelik başka bir RiskDetected hesabına bağlıysa ücretli plan bu kullanıcıya otomatik açılmaz.")

    static let subscriptionReceiptConflictMessage = RDLocalization.string("localizable.app.error.message.bu.app.store.aboneligi.baska.bir.riskdetected.he.c60cd61a", table: .localizable, fallback: "Bu App Store aboneliği başka bir RiskDetected hesabına bağlı. Lütfen aboneliği satın aldığın hesapla giriş yap veya destekle iletişime geç.")

    static func subscriptionActiveHigherTierMessage(_ tier: SubscriptionTier) -> String {
        RDLocalization.format("localizable.app.error.message.bu.app.store.hesabinda.zaten.1.plan.aktif.gorunu.5ae8b022", table: .localizable, fallback: "Bu App Store hesabında zaten %1$@ plan aktif görünüyor. Bu planı bu kullanıcıya bağlamak için Geri yükle seçeneğini kullanabilir veya App Store aboneliğini yönetebilirsin.", arguments: [String(describing: tier.title)])
    }

    static func subscriptionActiveHigherTierMessage(current: SubscriptionTier, selected: SubscriptionTier) -> String {
        RDLocalization.format("localizable.app.error.message.1.aboneligin.aktif.gorunuyor.2.planina.gecis.ya..92b296f7", table: .localizable, fallback: "%1$@ aboneliğin aktif görünüyor. %2$@ planına geçiş ya da downgrade işlemi App Store abonelik yönetimi üzerinden yapılmalı; uygulama bunu %3$@ satın alma başarısı olarak işaretlemedi.", arguments: [String(describing: current.title), String(describing: selected.title), String(describing: selected.title)])
    }

    var fullText: String {
        RDLocalization.format("localizable.app.error.message.1.ne.yapabilirsin.2.destek.kodu.3.f116407c", table: .localizable, fallback: "%1$@\n\nNe yapabilirsin: %2$@\n\nDestek kodu: %3$@", arguments: [String(describing: message), String(describing: action), String(describing: supportID)])
    }

    static func makePurchase(
        _ error: Error,
        context: String? = RDLocalization.string("localizable.app.error.message.abonelik.baslatilamadi.fb130c83", table: .localizable, fallback: "Abonelik başlatılamadı"),
        fallbackTitle: String = RDLocalization.string("localizable.app.error.message.abonelik.baslatilamadi.3a6e3053", table: .localizable, fallback: "Abonelik başlatılamadı")
    ) -> AppErrorMessage {
        makePurchase(
            classification: PurchaseErrorClassifier.classify(error),
            context: context,
            fallbackTitle: fallbackTitle
        )
    }

    static func makePurchase(
        rawMessage: String,
        context: String? = RDLocalization.string("localizable.app.error.message.abonelik.baslatilamadi.adeaf45b", table: .localizable, fallback: "Abonelik başlatılamadı"),
        fallbackTitle: String = RDLocalization.string("localizable.app.error.message.abonelik.baslatilamadi.09c75b95", table: .localizable, fallback: "Abonelik başlatılamadı")
    ) -> AppErrorMessage {
        makePurchase(
            classification: PurchaseErrorClassifier.classify(rawMessage: rawMessage),
            context: context,
            fallbackTitle: fallbackTitle
        )
    }

    static func makePurchase(
        classification: PurchaseErrorClassification,
        context: String? = RDLocalization.string("localizable.app.error.message.abonelik.baslatilamadi.334949cd", table: .localizable, fallback: "Abonelik başlatılamadı"),
        fallbackTitle: String = RDLocalization.string("localizable.app.error.message.abonelik.baslatilamadi.a5be685e", table: .localizable, fallback: "Abonelik başlatılamadı")
    ) -> AppErrorMessage {
        let raw = classification.rawMessage
        let supportID = Self.existingSupportID(in: raw) ?? Self.newSupportID()

        switch classification.kind {
        case .cancelled:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: "",
                action: "",
                category: .unknown,
                supportID: supportID
            )

        case .network:
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.baglanti.sorunu.ea386016", table: .localizable, fallback: "Bağlantı sorunu"),
                message: RDLocalization.string("localizable.app.error.message.internet.baglantisi.veya.abonelik.servisi.erisim.5d8392cd", table: .localizable, fallback: "İnternet bağlantısı veya abonelik servisi erişimi kesildiği için işlem tamamlanamadı."),
                action: RDLocalization.string("localizable.app.error.message.baglantini.kontrol.edip.tekrar.dene.54856b68", table: .localizable, fallback: "Bağlantını kontrol edip tekrar dene."),
                category: .networkUnavailable,
                supportID: supportID
            )

        case .existingSubscription:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: existingAppStoreSubscriptionMessage,
                action: RDLocalization.string("localizable.app.error.message.aboneligi.satin.aldigin.riskdetected.hesabiyla.g.8b2d83af", table: .localizable, fallback: "Aboneliği satın aldığın RiskDetected hesabıyla giriş yapıp Geri yükle seçeneğini kullan veya destekle iletişime geç."),
                category: .validationFailed,
                supportID: supportID
            )

        case .receiptConflict:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: subscriptionReceiptConflictMessage,
                action: RDLocalization.string("localizable.app.error.message.dogru.riskdetected.hesabiyla.giris.yapip.geri.yu.5abc8663", table: .localizable, fallback: "Doğru RiskDetected hesabıyla giriş yapıp Geri yükle seçeneğini kullan. Emin değilsen destek koduyla bize ulaş."),
                category: .validationFailed,
                supportID: supportID
            )

        case .backendVerification:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: raw.isEmpty ? RDLocalization.string("localizable.app.error.message.app.store.aboneligi.dogrulandi.ancak.uygulama.pl.b63e6132", table: .localizable, fallback: "App Store aboneliği doğrulandı ancak uygulama planı güvenli şekilde eşleştirilemedi.") : raw,
                action: RDLocalization.string("localizable.app.error.message.birkac.saniye.sonra.tekrar.dene.veya.geri.yukle..bea87dd4", table: .localizable, fallback: "Birkaç saniye sonra tekrar dene veya Geri yükle seçeneğiyle aboneliği doğrula."),
                category: .validationFailed,
                supportID: supportID
            )

        case .packageUnavailable:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.secilen.abonelik.paketi.su.an.hazirlanamadi.7f87747b", table: .localizable, fallback: "Seçilen abonelik paketi şu an hazırlanamadı."),
                action: RDLocalization.string("localizable.app.error.message.kisa.sure.sonra.tekrar.dene.sorun.devam.ederse.g.86a37aea", table: .localizable, fallback: "Kısa süre sonra tekrar dene. Sorun devam ederse Geri yükle veya destek ile iletişime geç."),
                category: .validationFailed,
                supportID: supportID
            )

        case .storeUnavailable:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.app.store.abonelik.servisi.su.anda.satin.alma.is.95796adc", table: .localizable, fallback: "App Store abonelik servisi şu anda satın alma işlemini tamamlayamadı."),
                action: RDLocalization.string("localizable.app.error.message.kisa.sure.sonra.tekrar.dene.app.store.odeme.penc.43a70372", table: .localizable, fallback: "Kısa süre sonra tekrar dene. App Store ödeme penceresi açılmıyorsa abonelik durumunu kontrol et."),
                category: .validationFailed,
                supportID: supportID
            )

        case .productUnavailable:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.secilen.abonelik.urunu.app.store.tarafindan.sati.4b2d0afe", table: .localizable, fallback: "Seçilen abonelik ürünü App Store tarafından satın almaya uygun görünmüyor."),
                action: RDLocalization.string("localizable.app.error.message.biraz.sonra.tekrar.dene.sorun.devam.ederse.urun..db5143aa", table: .localizable, fallback: "Biraz sonra tekrar dene. Sorun devam ederse ürün yapılandırması kontrol edilmelidir."),
                category: .validationFailed,
                supportID: supportID
            )

        case .purchaseNotAllowed:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.bu.cihaz.veya.app.store.hesabi.su.anda.uygulama..2811292c", table: .localizable, fallback: "Bu cihaz veya App Store hesabı şu anda uygulama içi satın almaya izin vermiyor."),
                action: RDLocalization.string("localizable.app.error.message.app.store.hesap.odeme.ve.ekran.suresi.ayarlarini.9ed04b2a", table: .localizable, fallback: "App Store hesap, ödeme ve ekran süresi ayarlarını kontrol edip tekrar dene."),
                category: .validationFailed,
                supportID: supportID
            )

        case .configuration:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.abonelik.dogrulamasi.icin.gerekli.app.store.veya.520bbd78", table: .localizable, fallback: "Abonelik doğrulaması için gerekli App Store veya RevenueCat yapılandırması tamamlanamadı."),
                action: RDLocalization.string("localizable.app.error.message.uygulamayi.kapatip.acarak.tekrar.dene.devam.eder.6f3c3b37", table: .localizable, fallback: "Uygulamayı kapatıp açarak tekrar dene. Devam ederse destek koduyla bildir."),
                category: .validationFailed,
                supportID: supportID
            )

        case .operationInProgress:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.bu.abonelik.icin.baska.bir.satin.alma.islemi.hal.37d20436", table: .localizable, fallback: "Bu abonelik için başka bir satın alma işlemi hâlâ devam ediyor."),
                action: RDLocalization.string("localizable.app.error.message.app.store.penceresinin.tamamlanmasini.bekle.veya.9c2386b3", table: .localizable, fallback: "App Store penceresinin tamamlanmasını bekle veya birkaç saniye sonra tekrar dene."),
                category: .validationFailed,
                supportID: supportID
            )

        case .paymentPending:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: RDLocalization.string("localizable.app.error.message.satin.alma.app.store.tarafinda.beklemede.gorunuy.dd4dd273", table: .localizable, fallback: "Satın alma App Store tarafında beklemede görünüyor."),
                action: RDLocalization.string("localizable.app.error.message.odeme.onayi.tamamlandiginda.aboneligin.otomatik..61ab78c8", table: .localizable, fallback: "Ödeme onayı tamamlandığında aboneliğin otomatik güncellenir. Gerekirse Geri yükle seçeneğini kullan."),
                category: .validationFailed,
                supportID: supportID
            )

        case .unknown:
            return AppErrorMessage(
                title: context ?? fallbackTitle,
                message: raw.isEmpty ? RDLocalization.string("localizable.app.error.message.satin.alma.islemi.tamamlanamadi.f22e2cd2", table: .localizable, fallback: "Satın alma işlemi tamamlanamadı.") : raw,
                action: RDLocalization.string("localizable.app.error.message.tekrar.dene.sorun.devam.ederse.destek.koduyla.bi.1e9cb968", table: .localizable, fallback: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bize ulaş."),
                category: .unknown,
                supportID: supportID
            )
        }
    }

    static func make(
        _ error: Error,
        context: String? = nil,
        fallbackTitle: String = RDLocalization.string("localizable.app.error.message.islem.tamamlanamadi.0c4b3c07", table: .localizable, fallback: "İşlem tamamlanamadı")
    ) -> AppErrorMessage {
        if let analysisError = error as? AnalysisService.AnalysisError {
            return make(analysisError, context: context, fallbackTitle: fallbackTitle)
        }
        return make(rawMessage: error.localizedDescription, context: context, fallbackTitle: fallbackTitle)
    }

    static func make(
        rawMessage: String,
        context: String? = nil,
        fallbackTitle: String = RDLocalization.string("localizable.app.error.message.islem.tamamlanamadi.95d24aee", table: .localizable, fallback: "İşlem tamamlanamadı")
    ) -> AppErrorMessage {
        let raw = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased(with: .autoupdatingCurrent)
        let supportID = Self.existingSupportID(in: raw) ?? Self.newSupportID()

        if isFreeRiskAnalysisTrialExhausted(rawMessage) {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.risk.analizi.hakki.kullanildi.250c0860", table: .localizable, fallback: "Risk analizi hakkı kullanıldı"),
                message: RDLocalization.string("localizable.app.error.message.bir.kez.tanimlanan.risk.analizi.tablosu.hakkini..821d2cac", table: .localizable, fallback: "Bir kez tanımlanan risk analizi tablosu hakkını kullandın."),
                action: RDLocalization.string("localizable.app.error.message.risk.analizi.tablolarini.kullanmaya.devam.etmek..2d062178", table: .localizable, fallback: "Risk analizi tablolarını kullanmaya devam etmek için Plus veya Pro'ya geç."),
                category: .quotaExceeded,
                supportID: supportID
            )
        }

        if isReportQuotaExceeded(rawMessage) {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.rapor.limiti.doldu.bf196591", table: .localizable, fallback: "Rapor limiti doldu"),
                message: RDLocalization.string("localizable.app.error.message.bu.plan.icin.rapor.olusturma.limitin.dolmus.goru.818771ec", table: .localizable, fallback: "Bu plan için rapor oluşturma limitin dolmuş görünüyor."),
                action: RDLocalization.string("localizable.app.error.message.bir.ust.plana.yukselt.veya.yeni.kota.donemini.be.421ef220", table: .localizable, fallback: "Bir üst plana yükselt veya yeni kota dönemini bekle."),
                category: .quotaExceeded,
                supportID: supportID
            )
        }

        if lower.contains("arka planda devam ediyor") ||
            lower.contains("geçmiş analizler") ||
            lower.contains("gecmis analizler")
        {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.analiz.arka.planda.devam.ediyor.bc67b9f7", table: .localizable, fallback: "Analiz arka planda devam ediyor"),
                message: raw.components(separatedBy: "\n").first ?? RDLocalization.string("localizable.app.error.message.analiz.arka.planda.devam.ediyor.f2849b0c", table: .localizable, fallback: "Analiz arka planda devam ediyor."),
                action: RDLocalization.string("localizable.app.error.message.ayni.analizi.tekrar.baslatmadan.once.gecmis.anal.0eb2a0c7", table: .localizable, fallback: "Aynı analizi tekrar başlatmadan önce Geçmiş analizler ekranını birkaç dakika sonra yenile."),
                category: .backgroundAnalysisPending,
                supportID: supportID
            )
        }

        let isDailyQuota = lower.contains("günlük kota") ||
            lower.contains("günlük analiz kot") ||
            lower.contains("günlük detaylı analiz kot") ||
            lower.contains("analiz kotan doldu") ||
            lower.contains("analiz/gün") ||
            lower.contains("quota_exceeded") ||
            lower.contains("ücretsiz analiz hakk")
        if isDailyQuota {
            let isFreeQuota = lower.contains("ücretsiz")
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.analiz.hakki.doldu.5a3d3836", table: .localizable, fallback: "Analiz hakkı doldu"),
                message: raw.components(separatedBy: "\n").first ?? RDLocalization.string("localizable.app.error.message.analiz.kotan.dolmus.gorunuyor.46571696", table: .localizable, fallback: "Analiz kotan dolmuş görünüyor."),
                action: isFreeQuota ? RDLocalization.string("localizable.app.error.message.plus.veya.pro.ile.devam.edebilirsin.3d6633d3", table: .localizable, fallback: "Plus veya Pro ile devam edebilirsin.") : RDLocalization.string("localizable.app.error.message.plan.kotan.yenilenene.kadar.bekle.veya.daha.ust..3da992c7", table: .localizable, fallback: "Plan kotan yenilenene kadar bekle veya daha üst plana geç."),
                category: .quotaExceeded,
                supportID: supportID
            )
        }

        if lower.contains("email_address_invalid") ||
            lower.contains("invalid email") ||
            lower.contains("email address") && lower.contains("invalid")
        {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.e.posta.adresi.gecerli.degil.52f2f1ae", table: .localizable, fallback: "E-posta adresi geçerli değil"),
                message: RDLocalization.string("localizable.app.error.message.e.posta.adresi.dogrulanamadi.6dcd8fb2", table: .localizable, fallback: "E-posta adresi doğrulanamadı."),
                action: RDLocalization.string("localizable.app.error.message.gecerli.ve.erisebildigin.bir.e.posta.adresi.giri.eac5effc", table: .localizable, fallback: "Geçerli ve erişebildiğin bir e-posta adresi girip tekrar kod gönder."),
                category: .validationFailed,
                supportID: supportID
            )
        }

        if lower.contains("over_email_send_rate_limit") ||
            lower.contains("email rate limit") ||
            lower.contains("email send rate") ||
            lower.contains("too many requests") && lower.contains("email")
        {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.kod.gonderme.siniri.aa82c7f9", table: .localizable, fallback: "Kod gönderme sınırı"),
                message: RDLocalization.string("localizable.app.error.message.kisa.sure.icinde.cok.fazla.e.posta.kodu.istendig.9be5c33b", table: .localizable, fallback: "Kısa süre içinde çok fazla e-posta kodu istendiği için yeni kod gönderilemiyor."),
                action: RDLocalization.string("localizable.app.error.message.birkac.dakika.bekleyip.tekrar.dene.gerekirse.son.89397d73", table: .localizable, fallback: "Birkaç dakika bekleyip tekrar dene. Gerekirse son gönderilen kodu kontrol et."),
                category: .validationFailed,
                supportID: supportID
            )
        }

        if lower.contains("otp_expired") ||
            lower.contains("token expired") ||
            lower.contains("token has expired") ||
            lower.contains("expired or is invalid") ||
            lower.contains("expired") && lower.contains("otp")
        {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.kodun.suresi.doldu.9331deac", table: .localizable, fallback: "Kodun süresi doldu"),
                message: RDLocalization.string("localizable.app.error.message.girdigin.dogrulama.kodu.artik.gecerli.degil.7141eff8", table: .localizable, fallback: "Girdiğin doğrulama kodu artık geçerli değil."),
                action: RDLocalization.string("localizable.app.error.message.yeni.bir.kod.isteyip.e.postana.gelen.son.kodla.t.df92f986", table: .localizable, fallback: "Yeni bir kod isteyip e-postana gelen son kodla tekrar dene."),
                category: .authRequired,
                supportID: supportID
            )
        }

        if lower.contains("invalid token") ||
            lower.contains("token_invalid") ||
            lower.contains("invalid otp") ||
            lower.contains("otp") && lower.contains("invalid")
        {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.kod.dogrulanamadi.b4167cf6", table: .localizable, fallback: "Kod doğrulanamadı"),
                message: RDLocalization.string("localizable.app.error.message.girdigin.dogrulama.kodu.eslesmedi.a05f0d37", table: .localizable, fallback: "Girdiğin doğrulama kodu eşleşmedi."),
                action: RDLocalization.string("localizable.app.error.message.kodu.e.postadaki.son.haliyle.kontrol.et.veya.yen.3f2da92c", table: .localizable, fallback: "Kodu e-postadaki son haliyle kontrol et veya yeni kod iste."),
                category: .authRequired,
                supportID: supportID
            )
        }

        if lower.contains("429") ||
            lower.contains("rate") ||
            lower.contains("resource_exhausted") ||
            lower.contains("gemini kotası") ||
            lower.contains("ai sağlayıcısı")
        {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.ai.servisi.yogun.95477ca2", table: .localizable, fallback: "AI servisi yoğun"),
                message: RDLocalization.string("localizable.app.error.message.ai.saglayicisi.su.anda.istegi.kabul.etmedi.bu.ge.642cffc7", table: .localizable, fallback: "AI sağlayıcısı şu anda isteği kabul etmedi. Bu genellikle geçici kota veya yoğunluk durumlarında olur."),
                action: RDLocalization.string("localizable.app.error.message.biraz.bekleyip.tekrar.dene.tekrar.ederse.farkli..18f94d2e", table: .localizable, fallback: "Biraz bekleyip tekrar dene. Tekrar ederse farklı analiz odağıyla veya daha küçük fotoğrafla deneyebilirsin."),
                category: .aiRateLimited,
                supportID: supportID
            )
        }

        if lower.contains("503") || lower.contains("unavailable") || lower.contains("yoğun") || lower.contains("timeout") || lower.contains("timed out") {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.ai.servisi.gecici.olarak.yanit.vermiyor.c9101c9b", table: .localizable, fallback: "AI servisi geçici olarak yanıt vermiyor"),
                message: RDLocalization.string("localizable.app.error.message.analiz.modeli.su.anda.yogun.veya.gecici.olarak.e.45ac273b", table: .localizable, fallback: "Analiz modeli şu anda yoğun veya geçici olarak erişilemiyor."),
                action: RDLocalization.string("localizable.app.error.message.kisa.sure.sonra.tekrar.dene.fotograf.ve.sectigin.aa6b2dbb", table: .localizable, fallback: "Kısa süre sonra tekrar dene. Fotoğraf ve seçtiğin analiz odağı korunuyorsa işlemi yeniden başlatabilirsin."),
                category: .aiUnavailable,
                supportID: supportID
            )
        }

        if lower.contains("output_language_contract_failed") {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.ai.yaniti.islenemedi.25a3092b", table: .localizable, fallback: "AI yanıtı işlenemedi"),
                message: RDLocalization.string("analysis.analysis.service.output.language.contract.failed", table: .analysis, fallback: "Analiz, seçilen çıktı diliyle güvenli biçimde tamamlanamadı. Lütfen tekrar dene."),
                action: RDLocalization.string("localizable.app.error.message.ayni.analizi.tekrar.dene.tekrar.ederse.destek.ko.39507cc2", table: .localizable, fallback: "Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir."),
                category: .aiInvalidResponse,
                supportID: supportID
            )
        }

        if lower.contains("yanıtı işlenemedi") ||
            lower.contains("yaniti islenemedi") ||
            lower.contains("ai_invalid_response") ||
            lower.contains("json") && lower.contains("ai")
        {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.ai.yaniti.islenemedi.25a3092b", table: .localizable, fallback: "AI yanıtı işlenemedi"),
                message: RDLocalization.string("localizable.app.error.message.analiz.modeli.yanit.verdi.ancak.sonuc.beklenen.f.6a7ef0e6", table: .localizable, fallback: "Analiz modeli yanıt verdi ancak sonuç beklenen formatta işlenemedi."),
                action: RDLocalization.string("localizable.app.error.message.ayni.analizi.tekrar.dene.tekrar.ederse.destek.ko.39507cc2", table: .localizable, fallback: "Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir."),
                category: .aiInvalidResponse,
                supportID: supportID
            )
        }

        if lower.contains("row-level security") || lower.contains("rls") || lower.contains("unauthorized") || lower.contains("403") {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.yetki.kontrolu.nedeniyle.islem.yapilamadi.9f16e1bd", table: .localizable, fallback: "Yetki kontrolü nedeniyle işlem yapılamadı"),
                message: RDLocalization.string("localizable.app.error.message.bu.islem.icin.oturum.veya.veri.erisim.izni.dogru.5877333b", table: .localizable, fallback: "Bu işlem için oturum veya veri erişim izni doğrulanamadı."),
                action: RDLocalization.string("localizable.app.error.message.cikis.yapip.tekrar.giris.yap.sorun.devam.ederse..a82f1466", table: .localizable, fallback: "Çıkış yapıp tekrar giriş yap. Sorun devam ederse destek koduyla birlikte bildir."),
                category: .storageDenied,
                supportID: supportID
            )
        }

        if lower.contains("network") || lower.contains("internet") || lower.contains("offline") || lower.contains("connection") {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.baglanti.sorunu.8fe67f35", table: .localizable, fallback: "Bağlantı sorunu"),
                message: RDLocalization.string("localizable.app.error.message.internet.baglantisi.veya.servis.erisimi.kesildig.551c2efe", table: .localizable, fallback: "İnternet bağlantısı veya servis erişimi kesildiği için işlem tamamlanamadı."),
                action: RDLocalization.string("localizable.app.error.message.baglantini.kontrol.edip.tekrar.dene.79541b65", table: .localizable, fallback: "Bağlantını kontrol edip tekrar dene."),
                category: .networkUnavailable,
                supportID: supportID
            )
        }

        if lower.contains("fotoğraf") && (lower.contains("indirilemedi") || lower.contains("download")) {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.fotograf.yuklenemedi.aad5adda", table: .localizable, fallback: "Fotoğraf yüklenemedi"),
                message: RDLocalization.string("localizable.app.error.message.analiz.fotografi.su.anda.indirilemedi.ekran.yede.6f290308", table: .localizable, fallback: "Analiz fotoğrafı şu anda indirilemedi. Ekran yedek görselle açılabilir."),
                action: RDLocalization.string("localizable.app.error.message.baglantini.kontrol.edip.tekrar.dene.sorun.devam..a47ab1ad", table: .localizable, fallback: "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir."),
                category: .storageDenied,
                supportID: supportID
            )
        }

        if lower.contains("veri dışa aktar") || lower.contains("dışa aktarımı") || lower.contains("export") {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.veri.disa.aktarimi.olusturulamadi.41172160", table: .localizable, fallback: "Veri dışa aktarımı oluşturulamadı"),
                message: RDLocalization.string("localizable.app.error.message.verilerinin.disa.aktarim.dosyasi.hazirlanamadi.63c02b19", table: .localizable, fallback: "Verilerinin dışa aktarım dosyası hazırlanamadı."),
                action: RDLocalization.string("localizable.app.error.message.baglantini.kontrol.edip.tekrar.dene.sorun.devam..be569751", table: .localizable, fallback: "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir."),
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if lower.contains("hesap silme talebi") || lower.contains("account deletion") {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.hesap.silme.talebi.kaydedilemedi.5b2bff6e", table: .localizable, fallback: "Hesap silme talebi kaydedilemedi"),
                message: RDLocalization.string("localizable.app.error.message.hesap.silme.talebin.sunucuya.kaydedilemedi.1432196e", table: .localizable, fallback: "Hesap silme talebin sunucuya kaydedilemedi."),
                action: RDLocalization.string("localizable.app.error.message.kisa.sure.sonra.tekrar.dene.sorun.devam.ederse.d.c17c2530", table: .localizable, fallback: "Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir."),
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if lower.contains("indirilemedi") || lower.contains("download") {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.rapor.indirilemedi.532e2c7e", table: .localizable, fallback: "Rapor indirilemedi"),
                message: RDLocalization.string("localizable.app.error.message.kayitli.pdf.raporu.indirilemedi.veya.paylasim.ic.51c3794e", table: .localizable, fallback: "Kayıtlı PDF raporu indirilemedi veya paylaşım için hazırlanamadı."),
                action: RDLocalization.string("localizable.app.error.message.baglantini.kontrol.edip.tekrar.dene.sorun.devam..3fbe18b8", table: .localizable, fallback: "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir."),
                category: .reportArchiveFailed,
                supportID: supportID
            )
        }

        if lower.contains("analiz") && (lower.contains("silinemedi") || lower.contains("delete")) {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.analiz.silinemedi.57ff28b3", table: .localizable, fallback: "Analiz silinemedi"),
                message: RDLocalization.string("localizable.app.error.message.analiz.ve.iliskili.kayitlar.silinemedi.73a2421e", table: .localizable, fallback: "Analiz ve ilişkili kayıtlar silinemedi."),
                action: RDLocalization.string("localizable.app.error.message.liste.korunur.kisa.sure.sonra.tekrar.dene.sorun..b1270500", table: .localizable, fallback: "Liste korunur. Kısa süre sonra tekrar dene; sorun devam ederse destek koduyla bildir."),
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if lower.contains("rapor") && (lower.contains("silinemedi") || lower.contains("delete")) {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.rapor.silinemedi.95c95529", table: .localizable, fallback: "Rapor silinemedi"),
                message: RDLocalization.string("localizable.app.error.message.pdf.raporu.veya.rapor.arsiv.kaydi.silinemedi.93b4d0c8", table: .localizable, fallback: "PDF raporu veya rapor arşiv kaydı silinemedi."),
                action: RDLocalization.string("localizable.app.error.message.kisa.sure.sonra.tekrar.dene.sorun.devam.ederse.d.68c209c5", table: .localizable, fallback: "Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir."),
                category: .reportArchiveFailed,
                supportID: supportID
            )
        }

        if lower.contains("arşiv") || lower.contains("archive") || lower.contains("kaydedilemedi") {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.rapor.arsive.kaydedilemedi.f5ab4e63", table: .localizable, fallback: "Rapor arşive kaydedilemedi"),
                message: RDLocalization.string("localizable.app.error.message.pdf.olusturuldu.ancak.rapor.arsivine.kaydedileme.f449fef8", table: .localizable, fallback: "PDF oluşturuldu ancak rapor arşivine kaydedilemedi."),
                action: RDLocalization.string("localizable.app.error.message.pdf.acildiysa.dosyayi.paylasabilir.arsiv.kaydi.i.35ca14ae", table: .localizable, fallback: "PDF açıldıysa dosyayı paylaşabilir, arşiv kaydı için daha sonra yeniden oluşturabilirsin."),
                category: .reportArchiveFailed,
                supportID: supportID
            )
        }

        if lower.contains("pdf") || lower.contains("rapor") {
            return AppErrorMessage(
                title: context ?? RDLocalization.string("localizable.app.error.message.pdf.olusturulamadi.dbc68e78", table: .localizable, fallback: "PDF oluşturulamadı"),
                message: RDLocalization.string("localizable.app.error.message.pdf.hazirlanirken.bir.sorun.olustu.cba3c7bd", table: .localizable, fallback: "PDF hazırlanırken bir sorun oluştu."),
                action: RDLocalization.string("localizable.app.error.message.tekrar.dene.sorun.devam.ederse.destek.koduyla.bi.628d9e06", table: .localizable, fallback: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir."),
                category: .pdfRenderFailed,
                supportID: supportID
            )
        }

        if lower.contains("veritaban") || lower.contains("database") || lower.contains("schema") || lower.contains("constraint") || lower.contains("enum") {
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.veri.kaydi.tamamlanamadi.68e4544e", table: .localizable, fallback: "Veri kaydı tamamlanamadı"),
                message: RDLocalization.string("localizable.app.error.message.sunucuda.veri.kaydi.veya.veri.okuma.sirasinda.bi.627f7217", table: .localizable, fallback: "Sunucuda veri kaydı veya veri okuma sırasında bir sorun oluştu."),
                action: RDLocalization.string("localizable.app.error.message.tekrar.dene.sorun.devam.ederse.destek.koduyla.bi.7688c7f0", table: .localizable, fallback: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir."),
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if !raw.isEmpty && raw.count < 140 && !raw.contains("{") && !raw.contains("HTTP") {
            return AppErrorMessage(
                title: fallbackTitle,
                message: raw,
                action: RDLocalization.string("localizable.app.error.message.girdigini.kontrol.edip.tekrar.dene.eb143028", table: .localizable, fallback: "Girdiğini kontrol edip tekrar dene."),
                category: .validationFailed,
                supportID: supportID
            )
        }

        return AppErrorMessage(
            title: fallbackTitle,
            message: RDLocalization.string("localizable.app.error.message.beklenmeyen.bir.sorun.olustu.ve.islem.tamamlanam.abec1e1f", table: .localizable, fallback: "Beklenmeyen bir sorun oluştu ve işlem tamamlanamadı."),
            action: RDLocalization.string("localizable.app.error.message.tekrar.dene.sorun.devam.ederse.destek.koduyla.bi.44ac835d", table: .localizable, fallback: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir."),
            category: .unknown,
            supportID: supportID
        )
    }

    static func isReportQuotaExceeded(_ rawMessage: String) -> Bool {
        let lower = rawMessage.lowercased(with: .autoupdatingCurrent)
        return lower.contains("report_quota_exceeded") ||
            lower.contains("free_risk_analysis_trial_exhausted") ||
            lower.contains("risk analizi") && lower.contains("deneme hakk") ||
            lower.contains("aylık rapor kot") ||
            lower.contains("standart rapor hakk") ||
            lower.contains("rapor") && lower.contains("limit") && lower.contains("dol")
    }

    static func isFreeRiskAnalysisTrialExhausted(_ rawMessage: String) -> Bool {
        let lower = rawMessage.lowercased(with: .autoupdatingCurrent)
        return lower.contains("free_risk_analysis_trial_exhausted") ||
            lower.contains("risk analizi") && lower.contains("deneme hakk")
    }

    private static func make(
        _ error: AnalysisService.AnalysisError,
        context: String?,
        fallbackTitle: String
    ) -> AppErrorMessage {
        let supportID = Self.existingSupportID(in: error.localizedDescription) ?? Self.newSupportID()
        switch error {
        case .notAuthenticated:
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.oturum.gerekli.79f7f03c", table: .localizable, fallback: "Oturum gerekli"),
                message: RDLocalization.string("localizable.app.error.message.bu.islem.icin.aktif.bir.kullanici.oturumu.buluna.56fecfee", table: .localizable, fallback: "Bu işlem için aktif bir kullanıcı oturumu bulunamadı."),
                action: RDLocalization.string("localizable.app.error.message.tekrar.giris.yapip.islemi.yeniden.baslat.c6568e8e", table: .localizable, fallback: "Tekrar giriş yapıp işlemi yeniden başlat."),
                category: .authRequired,
                supportID: supportID
            )
        case .quotaExceeded(let message, let tier):
            let isFree = tier == "free" || message.localizedCaseInsensitiveContains("ücretsiz")
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.analiz.hakki.doldu.ae2015d8", table: .localizable, fallback: "Analiz hakkı doldu"),
                message: message,
                action: isFree ? RDLocalization.string("localizable.app.error.message.plus.veya.pro.ile.devam.edebilirsin.6b54d027", table: .localizable, fallback: "Plus veya Pro ile devam edebilirsin.") : RDLocalization.string("localizable.app.error.message.plan.kotan.yenilenene.kadar.bekle.veya.daha.ust..f9de9a71", table: .localizable, fallback: "Plan kotan yenilenene kadar bekle veya daha üst plana geç."),
                category: .quotaExceeded,
                supportID: supportID
            )
        case .alreadyCompleted:
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.analiz.zaten.tamamlandi.a3476bde", table: .localizable, fallback: "Analiz zaten tamamlandı"),
                message: RDLocalization.string("localizable.app.error.message.bu.analiz.daha.once.tamamlanmis.244761ee", table: .localizable, fallback: "Bu analiz daha önce tamamlanmış."),
                action: RDLocalization.string("localizable.app.error.message.sonuclar.ekranindan.analizi.acabilir.veya.yeni.b.2d85c13a", table: .localizable, fallback: "Sonuçlar ekranından analizi açabilir veya yeni bir analiz başlatabilirsin."),
                category: .validationFailed,
                supportID: supportID
            )
        case .invalidInput(let message):
            return AppErrorMessage(
                title: RDLocalization.string("localizable.app.error.message.eksik.bilgi.00ae47fe", table: .localizable, fallback: "Eksik bilgi"),
                message: message,
                action: RDLocalization.string("localizable.app.error.message.girdiyi.tamamlayip.tekrar.dene.383a85e3", table: .localizable, fallback: "Girdiyi tamamlayıp tekrar dene."),
                category: .validationFailed,
                supportID: supportID
            )
        case .aiFailed(let message):
            return make(rawMessage: message, context: context ?? RDLocalization.string("localizable.app.error.message.ai.analizi.tamamlanamadi.6eae808e", table: .localizable, fallback: "AI analizi tamamlanamadı"), fallbackTitle: RDLocalization.string("localizable.app.error.message.ai.analizi.tamamlanamadi.6eae808e", table: .localizable, fallback: "AI analizi tamamlanamadı"))
        case .networkFailed(let message):
            return make(rawMessage: message, context: context ?? RDLocalization.string("localizable.app.error.message.analiz.istegi.gonderilemedi.da2d5f5e", table: .localizable, fallback: "Analiz isteği gönderilemedi"), fallbackTitle: RDLocalization.string("localizable.app.error.message.analiz.istegi.gonderilemedi.da2d5f5e", table: .localizable, fallback: "Analiz isteği gönderilemedi"))
        case .storageFailed(let message):
            return make(rawMessage: message, context: context ?? RDLocalization.string("localizable.app.error.message.dosya.islemi.tamamlanamadi.4a5f3744", table: .localizable, fallback: "Dosya işlemi tamamlanamadı"), fallbackTitle: RDLocalization.string("localizable.app.error.message.dosya.islemi.tamamlanamadi.4a5f3744", table: .localizable, fallback: "Dosya işlemi tamamlanamadı"))
        case .databaseFailed(let message):
            return make(rawMessage: message, context: context ?? RDLocalization.string("localizable.app.error.message.veri.islemi.tamamlanamadi.1d52dbde", table: .localizable, fallback: "Veri işlemi tamamlanamadı"), fallbackTitle: RDLocalization.string("localizable.app.error.message.veri.islemi.tamamlanamadi.1d52dbde", table: .localizable, fallback: "Veri işlemi tamamlanamadı"))
        }
    }

    static func newSupportID() -> String {
        "RD-\(UUID().uuidString.prefix(8).uppercased())"
    }

    private static func existingSupportID(in text: String) -> String? {
        let upper = text.uppercased()
        let pattern = #"RD-[A-Z0-9]{8}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
        guard let match = regex.firstMatch(in: upper, range: range),
              let swiftRange = Range(match.range, in: upper) else {
            return nil
        }
        return String(upper[swiftRange])
    }
}
