import Foundation

struct RecentFinding: Identifiable, Hashable {
    let id = UUID()
    let level: RiskLevel
    let title: String
}

struct RecentAnalysis: Identifiable, Hashable {
    let id: UUID
    let title: String
    let meta: String
    let timestamp: String
    let findings: [RecentFinding]
    let count: Int
    let photoPath: String?
    let isTextAnalysis: Bool

    init(id: UUID = UUID(), title: String, meta: String, timestamp: String = "", findings: [RecentFinding], count: Int, photoPath: String? = nil, isTextAnalysis: Bool = false) {
        self.id = id
        self.title = title
        self.meta = meta
        self.timestamp = timestamp
        self.findings = findings
        self.count = count
        self.photoPath = photoPath
        self.isTextAnalysis = isTextAnalysis
    }
}

extension RecentAnalysis {
    static let mock: [RecentAnalysis] = [
        .init(title: RDLocalization.string("analysis.recent.analysis.3.kat.santiye.girisi.404487da", table: .analysis, fallback: "3. Kat şantiye girişi"),
              meta: RDLocalization.string("analysis.recent.analysis.2.dk.kkd.analizi.b3a97414", table: .analysis, fallback: "2 dk · KKD analizi"),
              findings: [
                .init(level: .critical, title: RDLocalization.string("analysis.recent.analysis.baret.yok.c346548e", table: .analysis, fallback: "Baret yok")),
                .init(level: .high, title: RDLocalization.string("analysis.recent.analysis.reflektif.yelek.eksik.a691a389", table: .analysis, fallback: "Reflektif yelek eksik"))
              ],
              count: 5),
        .init(title: RDLocalization.string("analysis.recent.analysis.elektrik.panosu.cevresi.94d1d0a7", table: .analysis, fallback: "Elektrik panosu çevresi"),
              meta: RDLocalization.string("analysis.recent.analysis.bugun.09.14.genel.cf1a39a7", table: .analysis, fallback: "Bugün 09:14 · Genel"),
              findings: [
                .init(level: .high, title: RDLocalization.string("analysis.recent.analysis.kablo.karmasasi.21adf0c3", table: .analysis, fallback: "Kablo karmaşası")),
                .init(level: .medium, title: RDLocalization.string("analysis.recent.analysis.etiket.eksik.00cf5da7", table: .analysis, fallback: "Etiket eksik"))
              ],
              count: 3),
        .init(title: RDLocalization.string("analysis.recent.analysis.depo.yangin.cikisi.cad9c783", table: .analysis, fallback: "Depo yangın çıkışı"),
              meta: RDLocalization.string("analysis.recent.analysis.dun.16.42.acil.risk.23ec5886", table: .analysis, fallback: "Dün 16:42 · Acil risk"),
              findings: [
                .init(level: .medium, title: RDLocalization.string("analysis.recent.analysis.gecici.engel.0afffb3e", table: .analysis, fallback: "Geçici engel")),
                .init(level: .low, title: RDLocalization.string("analysis.recent.analysis.isaret.solmus.fc60a381", table: .analysis, fallback: "İşaret solmuş"))
              ],
              count: 2)
    ]
}

extension RecentAnalysis {
    init(row: AnalysisRow, photoPath: String? = nil) {
        let canvasTitle: String
        if RDLanguage.current == .english && row.canvas == AnalysisCanvas.legislation.id {
            canvasTitle = RDLocalization.string(
                "analysis.history.historical_analysis",
                table: .analysis,
                fallback: "Geçmiş analiz"
            )
        } else {
            canvasTitle = AnalysisCanvas.all.first { $0.id == row.canvas }?.title
                ?? row.canvas
        }
        let level = RiskLevel(rawValue: row.highestBandFK ?? row.highestBandM5 ?? "unknown") ?? .unknown
        let findingLabel = row.findingCount == 0 ? RDLocalization.string("analysis.recent.analysis.bulgu.yok.fea15340", table: .analysis, fallback: "Bulgu yok") : level.label
        let meta = [Self.relativeDateLabel(row.createdAt), canvasTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        self.init(
            id: row.id,
            title: row.title,
            meta: meta,
            timestamp: Self.absoluteDateLabel(row.createdAt),
            findings: [RecentFinding(level: level, title: findingLabel)],
            count: row.findingCount,
            photoPath: photoPath,
            isTextAnalysis: row.kind == "text"
        )
    }

    private static func relativeDateLabel(_ raw: String?) -> String {
        guard let raw else { return "" }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        guard let date = isoWithFraction.date(from: raw) ?? iso.date(from: raw) else {
            return ""
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func absoluteDateLabel(_ raw: String?) -> String {
        guard let raw else { return "" }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        guard let date = isoWithFraction.date(from: raw) ?? iso.date(from: raw) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
