import SwiftUI

enum HistoryStatus: String, CaseIterable {
    case open       = "Açık"
    case reviewed   = "İncelendi"
    case closed     = "Kapandı"

    var bgColor: Color {
        switch self {
        case .open:     return .rdCriticalBg
        case .reviewed: return .rdMediumBg
        case .closed:   return .rdLowBg
        }
    }
    var textColor: Color {
        switch self {
        case .open:     return .rdCriticalText
        case .reviewed: return .rdMediumText
        case .closed:   return .rdLowText
        }
    }
}

struct HistoryItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let date: String
    let kind: String
    let level: RiskLevel
    let count: Int
    let status: HistoryStatus
    let companyID: UUID?
    let createdAt: Date?
    let photoPath: String?
    let isTextAnalysis: Bool
}

extension HistoryItem {
    static let mock: [HistoryItem] = [
        .init(id: UUID(), title: "3. Kat şantiye girişi",  date: "Bugün 14:22",  kind: "KKD Bazlı", level: .critical, count: 5, status: .open, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: "Elektrik panosu çevresi", date: "Bugün 09:14",  kind: "Genel",     level: .high,     count: 3, status: .reviewed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: "Depo yangın çıkışı",      date: "Dün 16:42",     kind: "Acil risk", level: .medium,   count: 2, status: .closed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: "Kazan dairesi prosedür kontrol", date: "Dün 11:08", kind: "Prosedür", level: .low,    count: 1, status: .closed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: true),
        .init(id: UUID(), title: "Forklift trafik alanı",   date: "30 Nis · 14:55", kind: "Sektör",   level: .high,     count: 4, status: .reviewed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: "Yüksekte çalışma platformu", date: "29 Nis · 08:30", kind: "KKD Bazlı", level: .critical, count: 6, status: .open, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
    ]
}

extension HistoryItem {
    init(row: AnalysisRow, photoPath: String? = nil) {
        let level = RiskLevel(rawValue: row.highestBandFK ?? row.highestBandM5 ?? "unknown") ?? .unknown
        let canvasTitle = AnalysisCanvas.all.first { $0.id == row.canvas }?.title
            ?? Self.legacyCanvasTitle(row.canvas)
        let status: HistoryStatus = row.status == "completed" ? .reviewed : .open
        let createdAt = Self.parseDate(row.createdAt)

        self.init(
            id: row.id,
            title: row.title,
            date: Self.dateLabel(createdAt),
            kind: canvasTitle,
            level: level,
            count: row.findingCount,
            status: status,
            companyID: row.companyID,
            createdAt: createdAt,
            photoPath: photoPath,
            isTextAnalysis: row.kind == "text"
        )
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: raw) ?? plain.date(from: raw)
    }

    private static func dateLabel(_ date: Date?) -> String {
        guard let date else { return "" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Bugün' HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Dün' HH:mm"
        } else {
            formatter.dateFormat = "d MMM · HH:mm"
        }
        return formatter.string(from: date)
    }

    private static func legacyCanvasTitle(_ id: String) -> String {
        switch id {
        case "mark":
            return "İşaretleme"
        case "procedure":
            return "Prosedür"
        case "urgent":
            return "Acil Risk"
        case "ppe":
            return "KKD"
        case "general":
            return "Genel"
        case "sector":
            return "Sektör"
        default:
            return id
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
