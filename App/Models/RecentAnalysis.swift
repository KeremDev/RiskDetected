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

    init(id: UUID = UUID(), title: String, meta: String, timestamp: String = "", findings: [RecentFinding], count: Int, photoPath: String? = nil) {
        self.id = id
        self.title = title
        self.meta = meta
        self.timestamp = timestamp
        self.findings = findings
        self.count = count
        self.photoPath = photoPath
    }
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

extension RecentAnalysis {
    init(row: AnalysisRow, photoPath: String? = nil) {
        let canvasTitle = AnalysisCanvas.all.first { $0.id == row.canvas }?.title ?? row.canvas
        let level = RiskLevel(rawValue: row.highestBandFK ?? row.highestBandM5 ?? "unknown") ?? .unknown
        let findingLabel = row.findingCount == 0 ? "Bulgu yok" : level.label
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
            photoPath: photoPath
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
        formatter.locale = Locale(identifier: "tr_TR")
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
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter.string(from: date)
    }
}
