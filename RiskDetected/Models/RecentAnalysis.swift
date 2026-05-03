import Foundation

struct RecentFinding: Identifiable, Hashable {
    let id = UUID()
    let level: RiskLevel
    let title: String
}

struct RecentAnalysis: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let meta: String
    let findings: [RecentFinding]
    let count: Int
}

extension RecentAnalysis {
    static let mock: [RecentAnalysis] = [
        .init(title: "3. Kat şantiye girişi",
              meta: "2 dk · KKD analizi",
              findings: [
                .init(level: .critical, title: "Baret yok"),
                .init(level: .high, title: "Reflektif yelek eksik")
              ],
              count: 5),
        .init(title: "Elektrik panosu çevresi",
              meta: "Bugün 09:14 · Genel",
              findings: [
                .init(level: .high, title: "Kablo karmaşası"),
                .init(level: .medium, title: "Etiket eksik")
              ],
              count: 3),
        .init(title: "Depo yangın çıkışı",
              meta: "Dün 16:42 · Acil risk",
              findings: [
                .init(level: .medium, title: "Geçici engel"),
                .init(level: .low, title: "İşaret solmuş")
              ],
              count: 2)
    ]
}
