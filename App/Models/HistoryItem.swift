import SwiftUI

enum HistoryStatus: String, CaseIterable {
    case open
    case reviewed
    case closed

    var title: String {
        switch self {
        case .open:
            return RDLocalization.string(
                "localizable.history.status.open",
                fallback: "Açık"
            )
        case .reviewed:
            return RDLocalization.string(
                "localizable.history.status.reviewed",
                fallback: "İncelendi"
            )
        case .closed:
            return RDLocalization.string(
                "localizable.history.status.closed",
                fallback: "Kapandı"
            )
        }
    }

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
    #if DEBUG
    static let mock: [HistoryItem] = [
        .init(id: UUID(), title: RDLocalization.string("localizable.history.item.3.kat.santiye.girisi.6d41aebd", table: .localizable, fallback: "3. Kat şantiye girişi"),  date: "Bugün 14:22",  kind: "KKD Bazlı", level: .critical, count: 5, status: .open, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: RDLocalization.string("localizable.history.item.elektrik.panosu.cevresi.dd82fcfd", table: .localizable, fallback: "Elektrik panosu çevresi"), date: "Bugün 09:14",  kind: "Genel",     level: .high,     count: 3, status: .reviewed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: RDLocalization.string("localizable.history.item.depo.yangin.cikisi.338d6412", table: .localizable, fallback: "Depo yangın çıkışı"),      date: "Dün 16:42",     kind: "Acil risk", level: .medium,   count: 2, status: .closed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: RDLocalization.string("localizable.history.item.forklift.trafik.alani.18dce89a", table: .localizable, fallback: "Forklift trafik alanı"),   date: "30 Nis · 14:55", kind: "Sektör",   level: .high,     count: 4, status: .reviewed, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
        .init(id: UUID(), title: RDLocalization.string("localizable.history.item.yuksekte.calisma.platformu.1b3d32bc", table: .localizable, fallback: "Yüksekte çalışma platformu"), date: "29 Nis · 08:30", kind: "KKD Bazlı", level: .critical, count: 6, status: .open, companyID: nil, createdAt: Date(), photoPath: nil, isTextAnalysis: false),
    ]
    #endif
}

extension HistoryItem {
    init(row: AnalysisRow, photoPath: String? = nil) {
        let level = RiskLevel(rawValue: row.highestBandFK ?? row.highestBandM5 ?? "unknown") ?? .unknown
        let canvasTitle: String
        if RDLanguage.current == .english && row.canvas == AnalysisCanvas.legislation.id {
            canvasTitle = RDLocalization.string(
                "analysis.history.historical_analysis",
                table: .analysis,
                fallback: "Geçmiş analiz"
            )
        } else {
            canvasTitle = AnalysisCanvas.all.first { $0.id == row.canvas }?.title
                ?? Self.legacyCanvasTitle(row.canvas)
        }
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
        formatter.locale = .autoupdatingCurrent
        if Calendar.current.isDateInToday(date) {
            let relative = RelativeDateTimeFormatter()
            relative.locale = .autoupdatingCurrent
            relative.dateTimeStyle = .named
            formatter.timeStyle = .short
            return "\(relative.localizedString(for: date, relativeTo: Date())) \(formatter.string(from: date))"
        } else if Calendar.current.isDateInYesterday(date) {
            let relative = RelativeDateTimeFormatter()
            relative.locale = .autoupdatingCurrent
            relative.dateTimeStyle = .named
            formatter.timeStyle = .short
            return "\(relative.localizedString(for: date, relativeTo: Date())) \(formatter.string(from: date))"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private static func legacyCanvasTitle(_ id: String) -> String {
        switch id {
        case "mark":
            return RDLocalization.string("localizable.history.item.isaretleme.c5ca6fd8", table: .localizable, fallback: "İşaretleme")
        case "procedure":
            return RDLocalization.string("localizable.history.item.prosedur.f7660bce", table: .localizable, fallback: "Prosedür")
        case "urgent":
            return RDLocalization.string("localizable.history.item.acil.risk.ed860bf2", table: .localizable, fallback: "Acil Risk")
        case "ppe":
            return "KKD"
        case "general":
            return RDLocalization.string("localizable.history.item.genel.d3c7d2b9", table: .localizable, fallback: "Genel")
        case "sector":
            return RDLocalization.string("localizable.history.item.sektor.e06c368a", table: .localizable, fallback: "Sektör")
        default:
            return id
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
