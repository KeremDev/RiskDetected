import SwiftUI

/// AI Odaklı Analiz "canvas" — her biri farklı bir prompt seti ile çalışır.
struct AnalysisCanvas: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let short: String
    let body: String
    let icon: String        // SF Symbol adı
    let isPro: Bool
}

extension AnalysisCanvas {
    static let general = AnalysisCanvas(id: "general", title: "Genel", short: "",
                                        body: "Tüm iş güvenliği uygunsuzluklarını geniş kapsamlı tara.",
                                        icon: "sparkles", isPro: false)
    static let ppe = AnalysisCanvas(id: "ppe", title: "KKD", short: "",
                                    body: "Baret, gözlük, eldiven, emniyet kemeri ve yelek kontrolüne odaklan.",
                                    icon: "shield.lefthalf.filled", isPro: false)
    static let machine = AnalysisCanvas(id: "machine", title: "Makine", short: "",
                                        body: "Makine koruyucuları, döner parçalar, sıkışma ve bakım-kilit risklerine odaklan.",
                                        icon: "gearshape.2.fill", isPro: true)
    static let warningSigns = AnalysisCanvas(id: "warning_signs", title: "Uyarı levhaları", short: "",
                                             body: "Uyarı levhaları, yönlendirme, işaretleme ve görünürlük eksiklerini analiz et.",
                                             icon: "exclamationmark.triangle.fill", isPro: false)
    static let electrical = AnalysisCanvas(id: "electrical", title: "Elektrik", short: "",
                                           body: "Elektrik panosu, kablo, kaçak akım, izolasyon ve elektrik çarpması risklerine odaklan.",
                                           icon: "bolt.fill", isPro: false)
    static let sector = AnalysisCanvas(id: "sector", title: "Sektör", short: "",
                                       body: "İnşaat, üretim, depo veya ofis bağlamına göre sektöre özgü risklere odaklan.",
                                       icon: "building.2.fill", isPro: true)
    static let fire = AnalysisCanvas(id: "fire", title: "Yangın", short: "",
                                     body: "Yanıcı maddeler, yangın söndürme erişimi, sıcak çalışma ve tahliye risklerine odaklan.",
                                     icon: "flame.fill", isPro: false)
    static let ergonomics = AnalysisCanvas(id: "ergonomics", title: "Ergonomi", short: "",
                                           body: "Duruş, kaldırma-taşıma, tekrar eden hareket ve ergonomik zorlanma risklerini analiz et.",
                                           icon: "figure.strengthtraining.traditional", isPro: false)
    static let environmentMeasurement = AnalysisCanvas(id: "environment_measurement", title: "Ortam Ölçümü", short: "",
                                                       body: "Gürültü, aydınlatma, toz, gaz, sıcaklık ve ortam ölçümü gerektiren riskleri değerlendir.",
                                                       icon: "gauge.with.dots.needle.67percent", isPro: true)
    static let explosion = AnalysisCanvas(id: "explosion", title: "Patlama", short: "",
                                          body: "Patlayıcı atmosfer, basınçlı kaplar, gaz birikimi ve kıvılcım kaynaklarına odaklan.",
                                          icon: "burst.fill", isPro: false)
    static let environment = AnalysisCanvas(id: "environment", title: "Çevre", short: "",
                                            body: "Atık, sızıntı, dökülme, çevresel maruziyet ve saha düzeni etkilerini analiz et.",
                                            icon: "leaf.fill", isPro: false)
    static let legislation = AnalysisCanvas(id: "legislation", title: "Mevzuat", short: "",
                                            body: "İSG mevzuatı, yasal yükümlülük ve denetim uyumu açısından eksikleri değerlendir.",
                                            icon: "scroll.fill", isPro: true)
    static let workingAtHeight = AnalysisCanvas(id: "working_at_height", title: "Yüksekte Çalışma", short: "",
                                                body: "Düşme, korkuluk, iskele, emniyet kemeri, yaşam hattı ve yüksekte çalışma risklerine odaklan.",
                                                icon: "figure.climbing", isPro: false)
    static let mobileEquipment = AnalysisCanvas(id: "mobile_equipment", title: "Hareketli Ekipman", short: "",
                                                body: "Forklift, transpalet, vinç, araç-yaya ayrımı ve hareketli ekipman risklerini analiz et.",
                                                icon: "truck.box.fill", isPro: false)
    static let generalPremium = AnalysisCanvas(id: "general_premium", title: "Genel Premium", short: "",
                                               body: "Tüm görünür riskleri daha ayrıntılı, önceliklendirilmiş ve denetim odaklı analiz et.",
                                               icon: "star.square.fill", isPro: true)
    static let constructionMachinery = AnalysisCanvas(id: "construction_machinery", title: "İş Makineleri", short: "",
                                                      body: "Ekskavatör, yükleyici, vinç ve saha iş makineleri kaynaklı risklere odaklan.",
                                                      icon: "wrench.and.screwdriver.fill", isPro: false)

    static let all: [AnalysisCanvas] = [
        .general, .ppe, .machine,
        .warningSigns, .electrical, .sector,
        .fire, .ergonomics, .environmentMeasurement,
        .explosion, .environment, .legislation,
        .workingAtHeight, .mobileEquipment, .generalPremium,
        .constructionMachinery
    ]
}
