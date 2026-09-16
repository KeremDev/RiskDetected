import SwiftUI

struct NovaVisitPeriodCard: View {
    let identity: NovaSessionIdentity
    let company: UUID?
    let months: Int
    @State private var summary: NovaVisitSummary?
    @State private var failed = false
    @State private var revision = 0
    var body: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Dönemdeki ziyaretler", systemImage: "figure.walk").font(NovaFont.font(.cardTitle))
                if let summary {
                    HStack(spacing: 18) {
                        NovaText(text: "\(summary.visits) ziyaret", style: .label)
                        NovaText(text: summary.recorded_minutes.map { "\($0 / 60) sa \($0 % 60) dk" } ?? "Süre belirtilmedi", style: .label)
                    }
                    NovaText(text: "\(summary.timed_visits) ziyaretin süresi kayıtlı. Tarih aralığı üstteki dönem seçimine göre hesaplanır.", style: .meta)
                } else if failed { Button("Ziyaret özetini yeniden yükle") { revision += 1 }.font(NovaFont.font(.meta)) }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(company?.uuidString ?? "all"):\(months):\(revision)") {
            summary = nil; failed = false
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let from = calendar.date(byAdding: .month, value: 1 - months, to: monthStart) ?? monthStart
            do {
                let value = try await NovaProcessService(identity: identity).visitSummary(company: company, from: NovaDayField.text(from), to: NovaDayField.text(Date()))
                try Task.checkCancellation(); summary = value
            } catch { if !Task.isCancelled { failed = true } }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { _ in revision += 1 }
    }
}
