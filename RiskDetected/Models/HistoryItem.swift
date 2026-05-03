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
    let id: Int
    let title: String
    let date: String
    let kind: String
    let level: RiskLevel
    let count: Int
    let status: HistoryStatus
}

extension HistoryItem {
    static let mock: [HistoryItem] = [
        .init(id: 1, title: "3. Kat şantiye girişi",  date: "Bugün 14:22",  kind: "KKD Bazlı", level: .critical, count: 5, status: .open),
        .init(id: 2, title: "Elektrik panosu çevresi", date: "Bugün 09:14",  kind: "Genel",     level: .high,     count: 3, status: .reviewed),
        .init(id: 3, title: "Depo yangın çıkışı",      date: "Dün 16:42",     kind: "Acil risk", level: .medium,   count: 2, status: .closed),
        .init(id: 4, title: "Kazan dairesi prosedür kontrol", date: "Dün 11:08", kind: "Prosedür", level: .low,    count: 1, status: .closed),
        .init(id: 5, title: "Forklift trafik alanı",   date: "30 Nis · 14:55", kind: "Sektör",   level: .high,     count: 4, status: .reviewed),
        .init(id: 6, title: "Yüksekte çalışma platformu", date: "29 Nis · 08:30", kind: "KKD Bazlı", level: .critical, count: 6, status: .open),
    ]
}
