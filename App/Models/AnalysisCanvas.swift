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
    static let general   = AnalysisCanvas(id: "general",   title: "Genel",       short: "Geniş kapsamlı tarama",
                                          body: "Tüm iş güvenliği uygunsuzluklarını geniş kapsamlı tara.",
                                          icon: "sparkles", isPro: false)
    static let ppe       = AnalysisCanvas(id: "ppe",       title: "KKD",         short: "Baret, gözlük, eldiven",
                                          body: "Baret, gözlük, eldiven, emniyet kemeri ve yelek kontrolüne odaklan.",
                                          icon: "shield.lefthalf.filled", isPro: false)
    static let mark      = AnalysisCanvas(id: "mark",      title: "İşaretleme",  short: "Seçili alanlar",
                                          body: "Sadece fotoğraf üzerinde işaretlediğin alanları analiz et.",
                                          icon: "pencil.tip", isPro: false)
    static let sector    = AnalysisCanvas(id: "sector",    title: "Sektör",      short: "İnşaat · üretim · ofis",
                                          body: "İnşaat, üretim, depo veya ofis bağlamına göre analiz et.",
                                          icon: "building.2", isPro: false)
    static let urgent    = AnalysisCanvas(id: "urgent",    title: "Acil Risk",   short: "Kritik & yüksek",
                                          body: "Yalnızca kritik ve yüksek seviye riskleri öne çıkar.",
                                          icon: "bolt.fill", isPro: true)
    static let procedure = AnalysisCanvas(id: "procedure", title: "Prosedür",    short: "Şirket uyum kontrolü",
                                          body: "Şirket prosedürüne göre uyumsuzlukları tespit et.",
                                          icon: "list.clipboard.fill", isPro: true)

    static let all: [AnalysisCanvas] = [.general, .ppe, .mark, .sector, .urgent, .procedure]
}
