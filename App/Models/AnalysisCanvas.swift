import SwiftUI

/// AI Odaklı Analiz "canvas" — her biri farklı bir prompt seti ile çalışır.
struct AnalysisCanvas: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let short: String
    let body: String
    let icon: String        // SF Symbol adı
    let minTier: SubscriptionTier

    var isPro: Bool { minTier == .pro }
    var isPaid: Bool { minTier != .free }

    init(
        id: String,
        title: String,
        short: String,
        body: String,
        icon: String,
        isPro: Bool
    ) {
        self.init(
            id: id,
            title: title,
            short: short,
            body: body,
            icon: icon,
            minTier: isPro ? .pro : .free
        )
    }

    init(
        id: String,
        title: String,
        short: String,
        body: String,
        icon: String,
        minTier: SubscriptionTier
    ) {
        self.id = id
        self.title = title
        self.short = short
        self.body = body
        self.icon = icon
        self.minTier = minTier
    }
}

extension AnalysisCanvas {
    static let general = AnalysisCanvas(id: "general", title: RDLocalization.string("analysis.analysis.canvas.genel.1264346b", table: .analysis, fallback: "Genel"), short: "",
                                        body: RDLocalization.string("analysis.analysis.canvas.standart.saha.taramasi.yap.ana.risk.alanlarini.d.bf94a9b4", table: .analysis, fallback: "Standart saha taraması yap; ana risk alanlarını dengeli şekilde değerlendir."),
                                        icon: "sparkles", isPro: false)
    static let ppe = AnalysisCanvas(id: "ppe", title: RDLocalization.string("analysis.analysis.canvas.kkd.b445e9f1", table: .analysis, fallback: "KKD"), short: "",
                                    body: RDLocalization.string("analysis.analysis.canvas.baret.gozluk.eldiven.emniyet.kemeri.ve.yelek.kon.62e26e79", table: .analysis, fallback: "Baret, gözlük, eldiven, emniyet kemeri ve yelek kontrolüne odaklan."),
                                    icon: "shield.lefthalf.filled", isPro: false)
    static let machine = AnalysisCanvas(id: "machine", title: RDLocalization.string("analysis.analysis.canvas.makine.cf3ac61a", table: .analysis, fallback: "Makine"), short: "",
                                        body: RDLocalization.string("analysis.analysis.canvas.makine.koruyuculari.doner.parcalar.sikisma.ve.ba.15c65f6e", table: .analysis, fallback: "Makine koruyucuları, döner parçalar, sıkışma ve bakım-kilit risklerine odaklan."),
                                        icon: "gearshape.2.fill", minTier: .plus)
    static let warningSigns = AnalysisCanvas(id: "warning_signs", title: RDLocalization.string("analysis.analysis.canvas.uyari.levhalari.7bbd4232", table: .analysis, fallback: "Uyarı levhaları"), short: "",
                                             body: RDLocalization.string("analysis.analysis.canvas.uyari.levhalari.yonlendirme.isaretleme.ve.gorunu.4779f7b5", table: .analysis, fallback: "Uyarı levhaları, yönlendirme, işaretleme ve görünürlük eksiklerini analiz et."),
                                             icon: "exclamationmark.triangle.fill", isPro: false)
    static let electrical = AnalysisCanvas(id: "electrical", title: RDLocalization.string("analysis.analysis.canvas.elektrik.02126c7c", table: .analysis, fallback: "Elektrik"), short: "",
                                           body: RDLocalization.string("analysis.analysis.canvas.elektrik.panosu.kablo.kacak.akim.izolasyon.ve.el.005a1e8a", table: .analysis, fallback: "Elektrik panosu, kablo, kaçak akım, izolasyon ve elektrik çarpması risklerine odaklan."),
                                           icon: "bolt.fill", isPro: false)
    static let sector = AnalysisCanvas(id: "sector", title: RDLocalization.string("analysis.analysis.canvas.sektor.29879c2c", table: .analysis, fallback: "Sektör"), short: "",
                                       body: RDLocalization.string("analysis.analysis.canvas.insaat.uretim.depo.veya.ofis.baglamina.gore.sekt.f27bd6d6", table: .analysis, fallback: "İnşaat, üretim, depo veya ofis bağlamına göre sektöre özgü risklere odaklan."),
                                       icon: "building.2.fill", minTier: .plus)
    static let fire = AnalysisCanvas(id: "fire", title: RDLocalization.string("analysis.analysis.canvas.yangin.1707d040", table: .analysis, fallback: "Yangın"), short: "",
                                     body: RDLocalization.string("analysis.analysis.canvas.yanici.maddeler.yangin.sondurme.erisimi.sicak.ca.8ff81b05", table: .analysis, fallback: "Yanıcı maddeler, yangın söndürme erişimi, sıcak çalışma ve tahliye risklerine odaklan."),
                                     icon: "flame.fill", isPro: false)
    static let ergonomics = AnalysisCanvas(id: "ergonomics", title: RDLocalization.string("analysis.analysis.canvas.ozel.ekipman.449e90d1", table: .analysis, fallback: "Özel Ekipman"), short: "",
                                           body: RDLocalization.string("analysis.analysis.canvas.fotograftaki.ekipmani.tanimla.ve.isg.acisindan.d.017d1919", table: .analysis, fallback: "Fotoğraftaki ekipmanı tanımla ve İSG açısından değerlendir. Emin değilsen olasılıkları belirt, varsayım yapma. Kısa başlıklarla şunları ver: ekipman adı, tehlikeler, riskler, önlemler, gerekli KKD, kullanım öncesi kontroller ve durdurma kriterleri. Kritik risk varsa en başta uyar. Eksik bilgi varsa ek fotoğraf veya marka/model iste."),
                                           icon: "wrench.and.screwdriver.fill", isPro: true)
    static let environmentMeasurement = AnalysisCanvas(id: "environment_measurement", title: RDLocalization.string("analysis.analysis.canvas.ortam.olcumu.cb02af2a", table: .analysis, fallback: "Ortam Ölçümü"), short: "",
                                                       body: RDLocalization.string("analysis.analysis.canvas.gurultu.aydinlatma.toz.gaz.sicaklik.ve.ortam.olc.3e445f60", table: .analysis, fallback: "Gürültü, aydınlatma, toz, gaz, sıcaklık ve ortam ölçümü gerektiren riskleri değerlendir."),
                                                       icon: "gauge.with.dots.needle.67percent", minTier: .plus)
    static let explosion = AnalysisCanvas(id: "explosion", title: RDLocalization.string("analysis.analysis.canvas.patlama.dbb525ef", table: .analysis, fallback: "Patlama"), short: "",
                                          body: RDLocalization.string("analysis.analysis.canvas.patlayici.atmosfer.basincli.kaplar.gaz.birikimi..82659f33", table: .analysis, fallback: "Patlayıcı atmosfer, basınçlı kaplar, gaz birikimi ve kıvılcım kaynaklarına odaklan."),
                                          icon: "burst.fill", isPro: false)
    static let environment = AnalysisCanvas(id: "environment", title: RDLocalization.string("analysis.analysis.canvas.cevre.b44af959", table: .analysis, fallback: "Çevre"), short: "",
                                            body: RDLocalization.string("analysis.analysis.canvas.atik.sizinti.dokulme.cevresel.maruziyet.ve.saha..cb35673c", table: .analysis, fallback: "Atık, sızıntı, dökülme, çevresel maruziyet ve saha düzeni etkilerini analiz et."),
                                            icon: "leaf.fill", isPro: false)
    static let legislation = AnalysisCanvas(id: "legislation", title: RDLocalization.string("analysis.analysis.canvas.mevzuat.7632dffc", table: .analysis, fallback: "Mevzuat"), short: "",
                                            body: RDLocalization.string("analysis.analysis.canvas.isg.mevzuati.yasal.yukumluluk.ve.denetim.uyumu.a.b4922ccb", table: .analysis, fallback: "İSG mevzuatı, yasal yükümlülük ve denetim uyumu açısından eksikleri değerlendir."),
                                            icon: "scroll.fill", isPro: true)
    static let workingAtHeight = AnalysisCanvas(id: "working_at_height", title: RDLocalization.string("analysis.analysis.canvas.yuksekte.calisma.90e8004e", table: .analysis, fallback: "Yüksekte Çalışma"), short: "",
                                                body: RDLocalization.string("analysis.analysis.canvas.dusme.korkuluk.iskele.emniyet.kemeri.yasam.hatti.a5d68fd8", table: .analysis, fallback: "Düşme, korkuluk, iskele, emniyet kemeri, yaşam hattı ve yüksekte çalışma risklerine odaklan."),
                                                icon: "figure.climbing", isPro: false)
    static let mobileEquipment = AnalysisCanvas(id: "mobile_equipment", title: RDLocalization.string("analysis.analysis.canvas.hareketli.ekipman.06edda05", table: .analysis, fallback: "Hareketli Ekipman"), short: "",
                                                body: RDLocalization.string("analysis.analysis.canvas.forklift.transpalet.vinc.arac.yaya.ayrimi.ve.har.4e08f2ad", table: .analysis, fallback: "Forklift, transpalet, vinç, araç-yaya ayrımı ve hareketli ekipman risklerini analiz et."),
                                                icon: "truck.box.fill", isPro: false)
    static let generalPremium = AnalysisCanvas(id: "general_premium", title: RDLocalization.string("analysis.analysis.canvas.genel.premium.aabc8df8", table: .analysis, fallback: "Genel Premium"), short: "",
                                               body: RDLocalization.string("analysis.analysis.canvas.tum.gorunur.riskleri.daha.ayrintili.onceliklendi.1b475fd5", table: .analysis, fallback: "Tüm görünür riskleri daha ayrıntılı, önceliklendirilmiş ve denetim odaklı analiz et."),
                                               icon: "star.square.fill", isPro: true)
    static let constructionMachinery = AnalysisCanvas(id: "construction_machinery", title: RDLocalization.string("analysis.analysis.canvas.is.makineleri.0039bf46", table: .analysis, fallback: "İş Makineleri"), short: "",
                                                      body: RDLocalization.string("analysis.analysis.canvas.ekskavator.yukleyici.vinc.ve.saha.is.makineleri..428ad143", table: .analysis, fallback: "Ekskavatör, yükleyici, vinç ve saha iş makineleri kaynaklı risklere odaklan."),
                                                      icon: "wrench.and.screwdriver.fill", isPro: false)

    static let all: [AnalysisCanvas] = [
        .general, .ppe, .machine,
        .warningSigns, .generalPremium, .sector,
        .fire, .ergonomics, .environmentMeasurement,
        .explosion, .environment, .legislation,
        .workingAtHeight, .mobileEquipment, .electrical,
        .constructionMachinery
    ]
}
