import SwiftUI

/// "Senin İçin" home section. The server ranks the cards (`isg_home_feed_v1`);
/// this file decodes them, words them from the catalog and draws them. It has
/// no service dependency: the app injects the phase, the kind titles and the
/// actions, the same way it injects the deadline board.
struct NovaForYouFeed: Decodable, Equatable {
    let schema_version: Int
    let role: String
    let segment: String
    var cards: [NovaForYouCard]
    var more: [NovaForYouCard]
    /// True when "Tümü" was cut at its limit; the rest live in the module lists.
    var has_more: Bool? = nil

    /// The same answer without the given cards (dismissed on this device and
    /// not yet confirmed by the server).
    func removing(_ ids: Set<String>) -> NovaForYouFeed {
        guard !ids.isEmpty else { return self }
        var copy = self
        copy.cards = cards.filter { !ids.contains($0.id) }
        copy.more = more.filter { !ids.contains($0.id) }
        return copy
    }
}

struct NovaForYouCard: Decodable, Equatable, Identifiable {
    struct Params: Decodable, Equatable {
        var count: Int?
        var total: Int?
        var delta: Int?
        var sessions: Int?
        var title: String?
        var company_name: String?
        var kind: String?
        var due_on: String?
        var updated_at: String?
    }
    struct Target: Decodable, Equatable {
        let route: String
        var id: UUID?
        var company_id: UUID?
        var kind: String?
        var status: String?
        var ref: String?
        /// Inclusive Istanbul days of the records the card counted.
        var from: String?
        var to: String?
        /// Only the member's own records (organization sessions).
        var mine: Bool?
    }
    let id: String
    let key: String
    let kind: String
    let tone: String
    let dismissible: Bool
    let params: Params
    let target: Target
}

/// Words for one card. A key this build does not know yields nil and the card
/// is skipped, so a newer server can add card types without breaking the page.
/// What a "Senin İçin" card asks the list it opens to show: exactly the
/// records the card counted. The list shows the card's own words as a
/// removable filter and returns to its usual view when it is removed.
struct NovaListPreset: Equatable {
    /// The card's title, shown on the filter chip.
    let title: String
    let status: String?
    /// Inclusive Istanbul days ("yyyy-MM-dd").
    let from: String?
    let to: String?
    /// Only records this member made (organization sessions).
    let mine: UUID?

    init(title: String, target: NovaForYouCard.Target, actor: UUID) {
        self.title = title
        status = target.status
        from = target.from
        to = target.to
        mine = target.mine == true ? actor : nil
    }

    /// Whether the day (an ISO day string) is one of the preset's days.
    func includes(day: String) -> Bool {
        if let from, day < from { return false }
        if let to, day > to { return false }
        return true
    }

    /// Whether the moment falls on one of the preset's days in Istanbul.
    func includes(_ moment: Date?) -> Bool {
        guard from != nil || to != nil else { return true }
        guard let moment else { return false }
        return includes(day: Self.istanbulDay(moment))
    }

    /// Whether a list ordered newest first can stop reading at this moment:
    /// everything after it is older than the first day.
    func isBefore(_ moment: Date?) -> Bool {
        guard let from, let moment else { return false }
        return Self.istanbulDay(moment) < from
    }

    /// A server timestamp, with or without fractional seconds.
    static func moment(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter.novaFractional.date(from: value) ?? ISO8601DateFormatter.novaPlain.date(from: value)
    }

    static func istanbulDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The filter a home card put on a list, in the card's own words; removing
/// it shows the whole list again.
struct NovaListPresetChip: View {
    let preset: NovaListPreset
    let onClear: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                NovaText(text: preset.title, style: .micro, color: NovaColorToken.accentInk.color(in: scheme))
                    .lineLimit(2).multilineTextAlignment(.leading)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
            .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 40)
            .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: Capsule())
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityLabel(Text(String(format: RDLocalization.string("localizable.nova.analysis.list.filter.remove",
            table: .localizable, fallback: "%@ filtresini kaldır"), preset.title)))
        .accessibilityIdentifier("foryou.list.preset")
    }
}

struct NovaForYouCopy: Equatable {
    let label: String
    let title: String
    let detail: String
    let action: String
    let symbol: String

    static func make(_ card: NovaForYouCard, kindTitle: (String) -> String, now: Date = Date()) -> NovaForYouCopy? {
        let p = card.params
        let count = String(p.count ?? 0)
        func joined(_ parts: [String?]) -> String {
            parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        func record(_ fallback: String) -> String {
            let text = joined([p.title, p.company_name])
            return text.isEmpty ? fallback : text
        }
        func more(_ base: String) -> String {
            guard let total = p.count, total > 1 else { return base }
            let rest = RDLocalization.format("localizable.nova.foryou.more", table: .localizable, fallback: "ve %1$@ kayıt daha", arguments: [String(total - 1)])
            return joined([base, rest])
        }
        func delta(_ fallback: String) -> String {
            guard let d = p.delta, d > 0 else { return fallback }
            return RDLocalization.format("localizable.nova.foryou.delta", table: .localizable, fallback: "Önceki 7 güne göre %1$@ daha fazla.", arguments: [String(d)])
        }
        let resume = RDLocalization.string("localizable.nova.foryou.resume", table: .localizable, fallback: "Kaldığın yerden devam edebilirsin.")
        let sessions = RDLocalization.format("localizable.nova.foryou.sessions", table: .localizable, fallback: "%1$@ eğitim oturumu", arguments: [String(p.sessions ?? 0)])
        let continueAction = RDLocalization.string("localizable.nova.foryou.action.continue", table: .localizable, fallback: "Devam et")
        let review = RDLocalization.string("localizable.nova.foryou.action.review", table: .localizable, fallback: "İncele")
        let open = RDLocalization.string("localizable.nova.foryou.action.open", table: .localizable, fallback: "Aç")
        let start = RDLocalization.string("localizable.nova.foryou.action.start", table: .localizable, fallback: "Başla")
        let tryIt = RDLocalization.string("localizable.nova.foryou.action.try", table: .localizable, fallback: "Dene")
        let openList = RDLocalization.string("localizable.nova.foryou.action.open_list", table: .localizable, fallback: "Listeyi aç")
        let total = String(p.total ?? 0)
        let analysesAction = RDLocalization.string("localizable.nova.foryou.action.analyses", table: .localizable, fallback: "Analizleri gör")
        let trainingsAction = RDLocalization.string("localizable.nova.foryou.action.trainings", table: .localizable, fallback: "Eğitimleri gör")
        let label: String
        switch card.kind {
        case "continue": label = RDLocalization.string("localizable.nova.foryou.kind.continue", table: .localizable, fallback: "Devam et")
        case "critical": label = RDLocalization.string("localizable.nova.foryou.kind.critical", table: .localizable, fallback: "Dikkat")
        case "performance": label = RDLocalization.string("localizable.nova.foryou.kind.performance", table: .localizable, fallback: "İlerleme")
        case "discover": label = RDLocalization.string("localizable.nova.foryou.kind.discover", table: .localizable, fallback: "Keşfet")
        case "motivation": label = RDLocalization.string("localizable.nova.foryou.kind.motivation", table: .localizable, fallback: "Başlangıç")
        default: return nil
        }
        func copy(_ title: String, _ detail: String, _ action: String, _ symbol: String) -> NovaForYouCopy {
            .init(label: label, title: title, detail: detail, action: action, symbol: symbol)
        }
        switch card.key {
        case "continue.nonconformity_draft":
            return copy(RDLocalization.string("localizable.nova.foryou.continue.nonconformity_draft.title", table: .localizable, fallback: "Taslak uygunsuzluk kaydın seni bekliyor"),
                record(resume), continueAction, "square.and.pencil")
        case "continue.nonconformity_drafts":
            return copy(RDLocalization.format("localizable.nova.foryou.continue.nonconformity_drafts.title", table: .localizable, fallback: "%1$@ taslak uygunsuzluk daha", arguments: [count]),
                RDLocalization.format("localizable.nova.foryou.continue.nonconformity_drafts.detail", table: .localizable, fallback: "Listede %1$@ taslağın tamamı açılır.", arguments: [total]), openList, "square.and.pencil")
        case "continue.risk_drafts":
            return copy(RDLocalization.format("localizable.nova.foryou.continue.risk_drafts.title", table: .localizable, fallback: "%1$@ taslak risk değerlendirmesi daha", arguments: [count]),
                RDLocalization.format("localizable.nova.foryou.continue.risk_drafts.detail", table: .localizable, fallback: "Listede %1$@ taslağın tamamı açılır.", arguments: [total]), openList, "shield")
        case "continue.checklists_open":
            return copy(RDLocalization.format("localizable.nova.foryou.continue.checklists_open.title", table: .localizable, fallback: "%1$@ açık kontrol listesi daha", arguments: [count]),
                RDLocalization.format("localizable.nova.foryou.continue.checklists_open.detail", table: .localizable, fallback: "Listede %1$@ açık listenin tamamı açılır.", arguments: [total]), openList, "checklist")
        case "continue.drill_results":
            return copy(RDLocalization.format("localizable.nova.foryou.continue.drill_results.title", table: .localizable, fallback: "%1$@ tatbikat sonucu daha bekliyor", arguments: [count]),
                RDLocalization.format("localizable.nova.foryou.continue.drill_results.detail", table: .localizable, fallback: "Listede %1$@ tatbikatın tamamı açılır.", arguments: [total]), openList, "flame")
        case "continue.risk_draft":
            return copy(RDLocalization.string("localizable.nova.foryou.continue.risk_draft.title", table: .localizable, fallback: "Taslak risk değerlendirmene devam et"),
                record(resume), continueAction, "shield")
        case "continue.checklist_open":
            return copy(RDLocalization.string("localizable.nova.foryou.continue.checklist_open.title", table: .localizable, fallback: "Kontrol listesini tamamla"),
                record(resume), continueAction, "checklist")
        case "continue.drill_result":
            let planned = RDLocalization.format("localizable.nova.foryou.continue.drill_result.detail", table: .localizable, fallback: "%1$@ için planlanmıştı",
                arguments: [p.due_on.map(NovaStatisticsSnapshot.dayLabel) ?? ""])
            return copy(RDLocalization.string("localizable.nova.foryou.continue.drill_result.title", table: .localizable, fallback: "Tatbikat sonucunu kaydet"),
                joined([p.company_name, planned]), RDLocalization.string("localizable.nova.foryou.action.save", table: .localizable, fallback: "Kaydet"), "flame")
        case "continue.training_draft":
            let edited = relative(p.updated_at, now: now).map {
                RDLocalization.format("localizable.nova.foryou.edited", table: .localizable, fallback: "Son düzenleme: %1$@", arguments: [$0])
            }
            return copy(RDLocalization.string("localizable.nova.foryou.continue.training_draft.title", table: .localizable, fallback: "Başladığın eğitim kaydını tamamla"),
                joined([p.company_name, edited]).isEmpty ? resume : joined([p.company_name, edited]), continueAction, "graduationcap")
        case "continue.company_create":
            return copy(RDLocalization.string("localizable.nova.foryou.continue.company_create.title", table: .localizable, fallback: "Firma eklemeye devam et"),
                RDLocalization.string("localizable.nova.foryou.continue.company_create.detail", table: .localizable, fallback: "Başladığın firma kaydı tamamlanmadı."),
                continueAction, "building.2")
        case "critical.expired":
            return copy(RDLocalization.format("localizable.nova.foryou.critical.expired.title", table: .localizable, fallback: "%1$@ kaydın süresi geçti", arguments: [count]),
                more(joined([p.kind.map(kindTitle), p.company_name])), review, "exclamationmark.circle")
        case "critical.nonconformity_overdue":
            return copy(RDLocalization.format("localizable.nova.foryou.critical.nonconformity_overdue.title", table: .localizable, fallback: "%1$@ uygunsuzluğun termini geçti", arguments: [count]),
                more(joined([p.title, p.company_name])), review, "exclamationmark.triangle")
        case "critical.soon":
            return copy(RDLocalization.format("localizable.nova.foryou.critical.soon.title", table: .localizable, fallback: "%1$@ kaydın süresi yaklaşıyor", arguments: [count]),
                joined([p.kind.map(kindTitle), p.company_name, p.due_on.map(NovaStatisticsSnapshot.dayLabel)]),
                RDLocalization.string("localizable.nova.foryou.action.view", table: .localizable, fallback: "Gör"), "calendar.badge.clock")
        case "performance.analyses_7d":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.analyses_7d.title", table: .localizable, fallback: "Son 7 günde %1$@ analiz yaptın", arguments: [count]),
                delta(RDLocalization.string("localizable.nova.foryou.performance.analyses_7d.detail", table: .localizable, fallback: "Çalışmalarına devam ediyorsun.")),
                analysesAction, "chart.bar")
        case "performance.trained_people_7d":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.trained_people_7d.title", table: .localizable, fallback: "Son 7 günde %1$@ kişiye eğitim verdin", arguments: [count]),
                delta(sessions), trainingsAction, "person.3")
        case "performance.nonconformities_7d":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.nonconformities_7d.title", table: .localizable, fallback: "Son 7 günde %1$@ uygunsuzluk kaydettin", arguments: [count]),
                delta(RDLocalization.string("localizable.nova.foryou.performance.nonconformities_7d.detail", table: .localizable, fallback: "Takibini tek yerden yapabilirsin.")),
                RDLocalization.string("localizable.nova.foryou.action.nonconformities", table: .localizable, fallback: "Uygunsuzlukları gör"), "list.bullet.clipboard")
        case "performance.analyses_30d":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.analyses_30d.title", table: .localizable, fallback: "Son 30 günde %1$@ analiz yaptın", arguments: [count]),
                RDLocalization.string("localizable.nova.foryou.performance.analyses_30d.detail", table: .localizable, fallback: "Son 30 günün analizleri listede açılır."),
                analysesAction, "chart.bar")
        case "performance.trained_people_30d":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.trained_people_30d.title", table: .localizable, fallback: "Son 30 günde %1$@ kişiye eğitim verdin", arguments: [count]),
                sessions, trainingsAction, "person.3")
        case "performance.first_analysis":
            return copy(RDLocalization.string("localizable.nova.foryou.performance.first_analysis.title", table: .localizable, fallback: "İlk analizin hazır"),
                RDLocalization.string("localizable.nova.foryou.performance.first_analysis.detail", table: .localizable, fallback: "Bulguları inceleyip rapor alabilirsin."),
                RDLocalization.string("localizable.nova.foryou.action.analysis", table: .localizable, fallback: "Analizi gör"), "checkmark.seal")
        case "performance.analyses_total":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.analyses_total.title", table: .localizable, fallback: "Şimdiye kadar %1$@ analiz yaptın", arguments: [count]),
                RDLocalization.string("localizable.nova.foryou.performance.analyses_total.detail", table: .localizable, fallback: "Bütün analizlerin listede açılır."),
                analysesAction, "chart.bar")
        case "performance.trainings_total":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.trainings_total.title", table: .localizable, fallback: "Şimdiye kadar %1$@ eğitim kaydettin", arguments: [count]),
                RDLocalization.string("localizable.nova.foryou.performance.trainings_total.detail", table: .localizable, fallback: "Bütün eğitim kayıtların listede açılır."),
                trainingsAction, "person.3")
        case "performance.nonconformities_total":
            return copy(RDLocalization.format("localizable.nova.foryou.performance.nonconformities_total.title", table: .localizable, fallback: "Şimdiye kadar %1$@ uygunsuzluk kaydettin", arguments: [count]),
                RDLocalization.string("localizable.nova.foryou.performance.nonconformities_7d.detail", table: .localizable, fallback: "Takibini tek yerden yapabilirsin."),
                RDLocalization.string("localizable.nova.foryou.action.nonconformities", table: .localizable, fallback: "Uygunsuzlukları gör"), "list.bullet.clipboard")
        case "discover.photo_analysis":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.photo_analysis.title", table: .localizable, fallback: "Fotoğraftan analizi keşfet"),
                RDLocalization.string("localizable.nova.foryou.discover.photo_analysis.detail", table: .localizable, fallback: "Bir fotoğraf yükle, riskleri hızlıca tespit et."), tryIt, "camera")
        case "discover.risk_wizard":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.risk_wizard.title", table: .localizable, fallback: "Risk Analizi Sihirbazını denedin mi?"),
                RDLocalization.string("localizable.nova.foryou.discover.risk_wizard.detail", table: .localizable, fallback: "Adım adım ilerle, taslak risk değerlendirmeni hazırla."),
                RDLocalization.string("localizable.nova.foryou.action.try_now", table: .localizable, fallback: "Hemen dene"), "sparkles")
        case "discover.nonconformity":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.nonconformity.title", table: .localizable, fallback: "Uygunsuzluk takibini dene"),
                RDLocalization.string("localizable.nova.foryou.discover.nonconformity.detail", table: .localizable, fallback: "Sahada gördüğün eksikleri termin ve sorumluyla takip et."),
                RDLocalization.string("localizable.nova.foryou.action.create_record", table: .localizable, fallback: "Kayıt oluştur"), "exclamationmark.bubble")
        case "discover.training":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.training.title", table: .localizable, fallback: "İlk eğitim kaydını ekle"),
                RDLocalization.string("localizable.nova.foryou.discover.training.detail", table: .localizable, fallback: "Katılımcıları ve geçerlilik tarihlerini tek yerden yönet."),
                RDLocalization.string("localizable.nova.foryou.action.add_training", table: .localizable, fallback: "Eğitim ekle"), "graduationcap")
        case "discover.equipment":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.equipment.title", table: .localizable, fallback: "Periyodik kontrolleri takip et"),
                RDLocalization.string("localizable.nova.foryou.discover.equipment.detail", table: .localizable, fallback: "Ekipmanlarını ekle, kontrol tarihleri yaklaşınca gör."),
                RDLocalization.string("localizable.nova.foryou.action.add_equipment", table: .localizable, fallback: "Ekipman ekle"), "wrench.and.screwdriver")
        case "discover.emergency_wizard":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.emergency_wizard.title", table: .localizable, fallback: "Acil durum planını sihirbazla hazırla"),
                RDLocalization.string("localizable.nova.foryou.discover.emergency_wizard.detail", table: .localizable, fallback: "Birkaç soruyla düzenlenebilir bir taslak oluştur."), tryIt, "sparkles")
        case "discover.checklist":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.checklist.title", table: .localizable, fallback: "Kontrol listelerini dene"),
                RDLocalization.string("localizable.nova.foryou.discover.checklist.detail", table: .localizable, fallback: "Hazır listelerle saha denetimini hızlandır."),
                RDLocalization.string("localizable.nova.foryou.action.open_lists", table: .localizable, fallback: "Listeleri aç"), "checklist")
        case "discover.work_permit_forms":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.work_permit_forms.title", table: .localizable, fallback: "Hazır çalışma izni formları"),
                RDLocalization.string("localizable.nova.foryou.discover.work_permit_forms.detail", table: .localizable, fallback: "Düzenlenebilir örnek formları incele ve indir."),
                RDLocalization.string("localizable.nova.foryou.action.browse_forms", table: .localizable, fallback: "Formlara göz at"), "doc.text")
        case "discover.ppe_form":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.ppe_form.title", table: .localizable, fallback: "KKD zimmet formu hazır"),
                RDLocalization.string("localizable.nova.foryou.discover.ppe_form.detail", table: .localizable, fallback: "Düzenlenebilir Word örneğini indir."),
                RDLocalization.string("localizable.nova.foryou.action.open_form", table: .localizable, fallback: "Formu aç"), "doc.text")
        case "discover.statistics":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.statistics.title", table: .localizable, fallback: "İstatistiklerini gör"),
                RDLocalization.string("localizable.nova.foryou.discover.statistics.detail", table: .localizable, fallback: "Analiz ve eğitim sayılarını aylık grafikte gör."), open, "chart.bar")
        case "discover.followup":
            return copy(RDLocalization.string("localizable.nova.foryou.discover.followup.title", table: .localizable, fallback: "Evrak Takibi ile süreleri kaçırma"),
                RDLocalization.string("localizable.nova.foryou.discover.followup.detail", table: .localizable, fallback: "Bütün belgelerin geçerlilik tarihleri tek listede."), open, "calendar")
        case "motivation.first_company":
            return copy(RDLocalization.string("localizable.nova.foryou.motivation.first_company.title", table: .localizable, fallback: "İlk firmanı ekleyerek başla"),
                RDLocalization.string("localizable.nova.foryou.motivation.first_company.detail", table: .localizable, fallback: "Firma bilgilerini eklediğinde diğer modülleri daha verimli kullanabilirsin."),
                RDLocalization.string("localizable.nova.foryou.action.add_company", table: .localizable, fallback: "Firma ekle"), "building.2")
        case "motivation.first_personnel":
            return copy(RDLocalization.string("localizable.nova.foryou.motivation.first_personnel.title", table: .localizable, fallback: "Personel listeni oluştur"),
                RDLocalization.string("localizable.nova.foryou.motivation.first_personnel.detail", table: .localizable, fallback: "Eğitim kayıtları ve katılımcı listeleri personel üzerinden ilerler."),
                RDLocalization.string("localizable.nova.foryou.action.add_personnel", table: .localizable, fallback: "Personel ekle"), "person.badge.plus")
        case "motivation.first_analysis":
            return copy(RDLocalization.string("localizable.nova.foryou.motivation.first_analysis.title", table: .localizable, fallback: "İlk analizini yap"),
                RDLocalization.string("localizable.nova.foryou.motivation.first_analysis.detail", table: .localizable, fallback: "Bir fotoğraf yükleyerek risk tespit etmeye başla."), start, "camera")
        case "motivation.today_analysis":
            return copy(RDLocalization.string("localizable.nova.foryou.motivation.today_analysis.title", table: .localizable, fallback: "Yeni bir saha analiziyle devam et"),
                RDLocalization.string("localizable.nova.foryou.motivation.today_analysis.detail", table: .localizable, fallback: "Fotoğraftan analizle hızlıca başlayabilirsin."), start, "camera")
        case "motivation.statistics":
            return copy(RDLocalization.string("localizable.nova.foryou.motivation.statistics.title", table: .localizable, fallback: "Gelişimini takip et"),
                RDLocalization.string("localizable.nova.foryou.motivation.statistics.detail", table: .localizable, fallback: "İstatistikler ekranında çalışmalarının güncel görünümünü gör."), open, "chart.bar")
        case "motivation.photo_analysis":
            return copy(RDLocalization.string("localizable.nova.foryou.motivation.photo_analysis.title", table: .localizable, fallback: "Yeni bir analizle başla"),
                RDLocalization.string("localizable.nova.foryou.motivation.photo_analysis.detail", table: .localizable, fallback: "Fotoğraf yükle, bulguları hızlıca gör."), start, "camera")
        default:
            return nil
        }
    }

    /// "2 saat önce" style, in the app language. Nil when the server sent no
    /// usable time.
    static func relative(_ value: String?, now: Date) -> String? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = RDLanguage.current.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

/// Where the ranked cards go on the home page (Android `NovaForYouLayout`).
/// The large area rotates through the feature suggestions. Below it, two boxes:
/// what needs attention (the most urgent, always) and one unfinished item (the
/// visit's turn, see `NovaForYouContinueRotation`); progress runs as a strip
/// under them. When a box is empty, progress takes it and the strip goes; a
/// first-step card fills a box still empty. No two places show the same kind.
/// With no suggestion left, the first steps rotate on top.
struct NovaForYouLayout<Item> {
    var featured: [Item] = []
    /// One or two boxes side by side.
    var boxes: [Item] = []
    /// Progress, when both boxes are taken.
    var strip: Item?
    var count: Int { featured.count + boxes.count + (strip == nil ? 0 : 1) }

    static func make(_ items: [Item], kind: (Item) -> String, id: (Item) -> String = { _ in "" }, continueID: String? = nil) -> Self {
        func all(_ value: String) -> [Item] { items.filter { kind($0) == value } }
        let discover = Array(all("discover").prefix(5))
        let starts = all("motivation")
        let unfinished = all("continue")
        let work = unfinished.first { id($0) == continueID } ?? unfinished.first
        let pair = [all("critical").first, work].compactMap { $0 }
        let progress = all("performance").first
        let progressBoxed = progress != nil && pair.count < 2
        var boxes = pair
        if boxes.count + (progressBoxed ? 1 : 0) < 2, !discover.isEmpty, let start = starts.first { boxes.append(start) }
        if progressBoxed, let progress { boxes.append(progress) }
        return .init(featured: discover.isEmpty ? Array(starts.prefix(5)) : discover, boxes: boxes,
            strip: progressBoxed ? nil : progress)
    }
}

/// Which unfinished item the home page shows (Android `NovaForYouRotation`).
/// Each visit shows the one after the item shown last, kept on this device per
/// user and workspace; within a visit it stays, unless it goes away.
final class NovaForYouContinueRotation {
    let namespace: String
    private let defaults: UserDefaults
    private(set) var current: String?
    private var picked = false

    init(namespace: String, defaults: UserDefaults = .standard) {
        self.namespace = namespace
        self.defaults = defaults
    }

    private var key: String { "nova.foryou.continue.\(namespace)" }

    func newVisit() { picked = false }

    /// The item for this visit among the unfinished ones, in server order.
    func pick(_ ids: [String]) -> String? {
        if picked, let current, ids.contains(current) { return current }
        current = Self.next(after: picked ? current : defaults.string(forKey: key), in: ids)
        if let current {
            picked = true
            defaults.set(current, forKey: key)
        }
        return current
    }

    /// The item after the one shown last; the first when that one is gone.
    static func next(after last: String?, in ids: [String]) -> String? {
        guard let last, let index = ids.firstIndex(of: last) else { return ids.first }
        return ids[(index + 1) % ids.count]
    }
}

struct NovaForYouSection: View {
    enum Phase: Equatable { case loading, failed, ready(NovaForYouFeed) }
    let phase: Phase
    /// Type titles for deadline kinds come from the app (Evrak Takibi owns them).
    var kindTitle: (String) -> String = { $0 }
    /// Cards whose target this session cannot open are skipped.
    var canOpen: (NovaForYouCard.Target) -> Bool = { _ in true }
    let onOpen: (NovaForYouCard) -> Void
    let onDismiss: (NovaForYouCard) -> Void
    let onRetry: () -> Void
    /// The cards actually on screen, reported once they are drawn.
    var onShown: ([NovaForYouCard]) -> Void = { _ in }
    /// The unfinished item this visit shows (`NovaForYouContinueRotation`);
    /// nil or gone means the first one.
    var continueID: String? = nil
    @State private var showingAll = false
    /// The featured card on screen; nil or gone means the first one.
    @State private var featuredID: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private struct Item: Identifiable {
        let card: NovaForYouCard
        let copy: NovaForYouCopy
        var id: String { card.id }
    }
    private func items(_ cards: [NovaForYouCard]) -> [Item] {
        cards.compactMap { card in
            guard canOpen(card.target), let copy = NovaForYouCopy.make(card, kindTitle: kindTitle) else { return nil }
            return Item(card: card, copy: copy)
        }
    }
    /// The server already ranked the cards; the layout places them by kind.
    /// Should this build skip one, the next card of that kind takes its place.
    private func section(_ feed: NovaForYouFeed) -> (layout: NovaForYouLayout<Item>, all: [Item]) {
        let all = items(feed.cards + feed.more)
        return (NovaForYouLayout.make(all, kind: \.card.kind, id: \.card.id, continueID: continueID), all)
    }

    var body: some View {
        switch phase {
        case .loading:
            VStack(alignment: .leading, spacing: 10) {
                header(showsAll: false)
                RoundedRectangle(cornerRadius: 20).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 132)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 18).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 112)
                    RoundedRectangle(cornerRadius: 18).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 112)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RDLocalization.string("localizable.nova.foryou.loading", table: .localizable, fallback: "Öneriler yükleniyor"))
            .accessibilityIdentifier("nova.home.foryou.loading")
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                header(showsAll: false)
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        NovaText(text: RDLocalization.string("localizable.nova.foryou.failed", table: .localizable, fallback: "Öneriler yüklenemedi"), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        Spacer(minLength: 0)
                        NovaText(text: RDLocalization.string("localizable.nova.foryou.retry", table: .localizable, fallback: "Tekrar dene"), style: .meta,
                            color: NovaColorToken.accentInk.color(in: scheme))
                    }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .novaControlBackground(cornerRadius: 18)
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityIdentifier("nova.home.foryou.retry")
            }
        case .ready(let feed):
            let picked = section(feed)
            let layout = picked.layout
            let all = picked.all
            if layout.count > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    header(showsAll: all.count > layout.count)
                    if !layout.featured.isEmpty { featuredArea(layout.featured) }
                    let boxes = layout.boxes
                    let unfinished = all.filter { $0.card.kind == "continue" }
                    if typeSize.isAccessibilitySize {
                        ForEach(boxes) { supportCard($0, among: unfinished) }
                    } else if !boxes.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(boxes) { supportCard($0, among: unfinished).frame(maxHeight: .infinity, alignment: .top) }
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    if let strip = layout.strip { stripCard(strip) }
                }
                // A container of its own, so the cards keep their identifiers.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nova.home.foryou")
                .task(id: (layout.boxes + [layout.strip].compactMap { $0 }).map(\.id)) {
                    onShown((layout.boxes + [layout.strip].compactMap { $0 }).map(\.card))
                }
                .sheet(isPresented: $showingAll) { allList(all, truncated: feed.has_more == true) }
            }
        }
    }

    /// The feature suggestions, one at a time: they move on by themselves
    /// every few seconds and can be swiped. They stay put for VoiceOver and
    /// Reduce Motion. Every card is laid out once, hidden, so the area is as
    /// tall as the tallest and the page does not jump.
    private func featuredArea(_ featured: [Item]) -> some View {
        let current = featured.first { $0.id == featuredID } ?? featured[0]
        let rotates = featured.count > 1 && !voiceOver && !reduceMotion
        return VStack(spacing: 8) {
            ZStack { ForEach(featured) { mainCard($0) } }
                .hidden()
                .accessibilityHidden(true)
                .overlay {
                    TabView(selection: Binding(get: { current.id }, set: { featuredID = $0 })) {
                        ForEach(featured) { mainCard($0).padding(.horizontal, 8).tag($0.id) }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    // Room between cards while swiping, without narrowing them.
                    .padding(.horizontal, -8)
                }
            if featured.count > 1 {
                HStack(spacing: 6) {
                    ForEach(featured) { item in
                        Capsule()
                            .fill(item.id == current.id ? colors(item).ink : NovaColorToken.borderMuted.color(in: scheme))
                            .frame(width: item.id == current.id ? 18 : 6, height: 6)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: current.id)
                .accessibilityHidden(true)
            }
        }
        .task(id: current.id) { onShown([current.card]) }
        .task(id: "\(current.id)|\(featured.map(\.id).joined(separator: ","))|\(rotates)") {
            guard rotates else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let index = featured.firstIndex(where: { $0.id == current.id }) else { return }
            withAnimation(.easeInOut(duration: 0.45)) { featuredID = featured[(index + 1) % featured.count].id }
        }
    }

    private func header(showsAll: Bool) -> some View {
        HStack {
            NovaText(text: RDLocalization.string("localizable.nova.foryou.title", table: .localizable, fallback: "Senin İçin"), style: .sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if showsAll {
                Button { showingAll = true } label: {
                    NovaText(text: RDLocalization.string("localizable.nova.foryou.all", table: .localizable, fallback: "Tümü"), style: .meta,
                        color: NovaColorToken.textMuted.color(in: scheme))
                        .frame(minHeight: 32)
                }
                .accessibilityIdentifier("nova.home.foryou.all")
            }
        }
    }

    private func palette(_ tone: String) -> (ink: Color, soft: Color) {
        switch tone {
        case "danger": return (NovaColorToken.statusDangerInk.color(in: scheme), NovaColorToken.statusDangerBg.color(in: scheme))
        case "warning", "feature": return (NovaColorToken.statusWarningInk.color(in: scheme), NovaColorToken.statusWarningBg.color(in: scheme))
        case "success": return (NovaColorToken.statusSuccessInk.color(in: scheme), NovaColorToken.statusSuccessBg.color(in: scheme))
        default: return (NovaColorToken.statusInfoInk.color(in: scheme), NovaColorToken.statusInfoBg.color(in: scheme))
        }
    }

    private func badge(_ item: Item, size: CGFloat) -> some View {
        let tint = colors(item)
        return HStack(spacing: 7) {
            NovaIcon(symbol: item.copy.symbol, size: size * 0.46)
                .foregroundStyle(tint.ink)
                .frame(width: size, height: size)
                .background(tint.soft, in: Circle())
            NovaText(text: RDLocalization.uppercased(item.copy.label), style: .badge, color: tint.ink).lineLimit(1)
        }
    }

    private func dismissButton(_ item: Item) -> some View {
        Button { onDismiss(item.card) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                .frame(width: 28, height: 28)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RDLocalization.string("localizable.nova.foryou.dismiss", table: .localizable, fallback: "Öneriyi gizle"))
        .accessibilityIdentifier("nova.home.foryou.dismiss.\(item.card.key)")
    }

    private func actionRow(_ item: Item) -> some View {
        HStack(spacing: 5) {
            NovaText(text: item.copy.action, style: .label, color: colors(item).ink).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(colors(item).ink)
        }
    }

    /// The featured card's action, text and arrow on a soft tinted capsule so it reads as a button.
    private func actionPill(_ item: Item) -> some View {
        let ink = colors(item).ink
        return actionRow(item)
            .padding(.horizontal, 14).frame(minHeight: 34)
            // A light base under the tint keeps the art's specks out of the label.
            .background(ink.opacity(0.12), in: Capsule())
            .background(NovaColorToken.surface.color(in: scheme).opacity(0.75), in: Capsule())
            .overlay(Capsule().strokeBorder(ink.opacity(0.18), lineWidth: 1))
    }

    /// A Keşfet card's art, the colours along its top edge (at 0, 30, 50 and
    /// 100 % of the width), which fill the card above the art, and the ink and
    /// soft fill its label, button and dot take on it (nil: the tone's own).
    private struct DiscoverArt {
        let name: String
        let edge: [UInt32]
        var accent: (ink: UInt32, soft: UInt32)? = nil
    }

    /// Each feature's own art (Android `DISCOVER_ART`); the others use the
    /// general Keşfet art.
    private static let discoverArt: [String: DiscoverArt] = [
        "discover.risk_wizard": .init(name: "NovaForYouDiscoverRiskWizard", edge: [0xFCF7E8, 0xFBFBF9, 0xFBEECA, 0xFCE8B0]),
        "discover.photo_analysis": .init(name: "NovaForYouDiscoverPhotoAnalysis", edge: [0xF6FAF1, 0xF7FCFA, 0xC3F1DD, 0xD1EDC0],
            accent: (0x1A6E4C, 0xD8F3E6)),
        "discover.equipment": .init(name: "NovaForYouDiscoverEquipment", edge: [0xEEFAFC, 0xEFFAFD, 0xCFF1FC, 0xBCE6F9],
            accent: (0x0B6E92, 0xD6F0FA)),
        "discover.statistics": .init(name: "NovaForYouDiscoverStatistics", edge: [0xF4F5FA, 0xF8FAFB, 0xD5E0FB, 0xD5DDFA],
            accent: (0x4B4BC0, 0xE2E4FB)),
        "discover.training": .init(name: "NovaForYouDiscoverTraining", edge: [0xF7FCF2, 0xF7FDF4, 0xDFF2D5, 0xDBEED0],
            accent: (0x2E7A38, 0xDDF1D6)),
        "discover.nonconformity": .init(name: "NovaForYouDiscoverNonconformity", edge: [0xFBF1ED, 0xFDF7F4, 0xFCD5CC, 0xFBC9BF],
            accent: (0xB02F24, 0xFCDCD5)),
        "discover.emergency_wizard": .init(name: "NovaForYouDiscoverEmergencyWizard", edge: [0xFCF7EC, 0xFDF9F2, 0xFDE5BE, 0xFBDFB0],
            accent: (0xA94A0C, 0xFDE6CC)),
        "discover.checklist": .init(name: "NovaForYouDiscoverChecklist", edge: [0xFCF4E1, 0xFDFAF3, 0xFCEFCA, 0xFDE8BA]),
    ]
    /// How strongly the Keşfet art shows over the card surface (Android `DISCOVER_ART_ALPHA`).
    private static let discoverArtOpacity = 0.8

    private static let generalDiscoverArt = DiscoverArt(name: "NovaForYouDiscoverBackground",
        edge: [0xFDFCF9, 0xFCFBF9, 0xFDF3DE, 0xFEECC9])

    private func discoverArt(_ item: Item) -> DiscoverArt { Self.discoverArt[item.card.key] ?? Self.generalDiscoverArt }

    private static func color(_ hex: UInt32) -> Color {
        NovaRGBA(red: Int(hex >> 16 & 0xFF), green: Int(hex >> 8 & 0xFF), blue: Int(hex & 0xFF), alpha: 1).color
    }

    /// The card's ink and soft fill: its art's accent while the art shows,
    /// otherwise the tone's.
    private func colors(_ item: Item) -> (ink: Color, soft: Color) {
        if item.card.kind == "discover", artwork(item) != nil, let accent = discoverArt(item).accent {
            return (Self.color(accent.ink), Self.color(accent.soft))
        }
        return palette(item.card.tone)
    }

    /// The pastel artwork behind a kind's cards. Light appearance only: under
    /// dark mode's light text it would wash the copy out.
    private func artwork(_ item: Item) -> String? {
        guard scheme == .light else { return nil }
        switch item.card.kind {
        case "discover": return typeSize.isAccessibilitySize ? nil : discoverArt(item).name
        case "critical": return "NovaForYouCriticalBackground"
        case "continue": return "NovaForYouContinueBackground"
        default: return nil
        }
    }

    /// Drawn behind the content, so it never changes a card's height. The
    /// Keşfet art keeps its illustration whole at the bottom right, over its
    /// own top-edge colours; the Dikkat and Devam et art fill the box from the
    /// right, where their icon sits.
    @ViewBuilder private func artworkLayer(_ item: Item) -> some View {
        if let name = artwork(item) {
            if item.card.kind == "discover" {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(stops: zip(discoverArt(item).edge, [0, 0.3, 0.5, 1]).map { hex, location in
                        .init(color: Self.color(hex), location: location)
                    }, startPoint: .leading, endPoint: .trailing)
                    Image(name).resizable().scaledToFit()
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)],
                            startPoint: .top, endPoint: .bottom))
                }
                // Softened as one layer, so the copy stands out from the art.
                .compositingGroup()
                .opacity(Self.discoverArtOpacity)
            } else {
                Image(name).resizable().scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .trailing)
            }
        }
    }

    private func cardSurface<Content: View>(_ item: Item, radius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let critical = item.card.kind == "critical"
        let shape = RoundedRectangle(cornerRadius: radius)
        return content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    NovaColorToken.surface.color(in: scheme)
                    artworkLayer(item)
                }
                .clipShape(shape)
                .accessibilityHidden(true)
            }
            .overlay(shape
                .strokeBorder(critical ? palette(item.card.tone).ink.opacity(0.35) : NovaColorToken.borderMuted.color(in: scheme), lineWidth: 1))
    }

    private func mainCard(_ item: Item) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { onOpen(item.card) } label: {
                cardSurface(item, radius: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        badge(item, size: 34)
                        NovaText(text: item.copy.title, style: .dialogTitle).lineLimit(3)
                        NovaText(text: item.copy.detail, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(3)
                        actionPill(item).padding(.top, 2)
                    }
                    // The Keşfet art's illustration takes the right side.
                    .padding(16).padding(.trailing, item.card.kind == "discover" && artwork(item) != nil ? 124
                        : item.card.dismissible ? 28 : 0)
                }
            }
            .buttonStyle(NovaRowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nova.home.foryou.featured.\(item.card.key)")
            if item.card.dismissible { dismissButton(item).padding(4) }
        }
    }

    /// A compact box: the kind, the line in regular weight and a coloured
    /// arrow. The unfinished item shows its place among all unfinished items
    /// ("2/5"); the others take turns on later visits and are all in "Tümü".
    private func supportCard(_ item: Item, among unfinished: [Item]) -> some View {
        let place = unfinished.count > 1 ? unfinished.firstIndex { $0.id == item.id }.map { "\($0 + 1)/\(unfinished.count)" } : nil
        return ZStack(alignment: .topTrailing) {
            Button { onOpen(item.card) } label: {
                cardSurface(item, radius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        badge(item, size: 24).padding(.trailing, item.card.dismissible ? 30 : 0)
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 6) {
                            NovaText(text: item.copy.title, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let place {
                                NovaText(text: place, style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                                    .lineLimit(1)
                                    .accessibilityHidden(true)
                            }
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette(item.card.tone).ink)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(12)
                }
            }
            .buttonStyle(NovaRowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(item.copy.detail)
            .accessibilityIdentifier("nova.home.foryou.card.\(item.card.key)")
            if item.card.dismissible { dismissButton(item) }
        }
    }

    /// Progress as a slim full-width strip under the two boxes.
    private func stripCard(_ item: Item) -> some View {
        let colors = palette(item.card.tone)
        return ZStack(alignment: .trailing) {
            Button { onOpen(item.card) } label: {
                cardSurface(item, radius: 18) {
                    HStack(spacing: 12) {
                        NovaIcon(symbol: item.copy.symbol, size: 15)
                            .foregroundStyle(colors.ink)
                            .frame(width: 34, height: 34)
                            .background(colors.soft, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: item.copy.title, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(2)
                            actionRow(item)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12).padding(.trailing, item.card.dismissible ? 32 : 0)
                }
            }
            .buttonStyle(NovaRowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(item.copy.detail)
            .accessibilityIdentifier("nova.home.foryou.strip.\(item.card.key)")
            if item.card.dismissible { dismissButton(item) }
        }
    }

    private func allList(_ all: [Item], truncated: Bool) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(all) { item in
                        Button {
                            showingAll = false
                            onOpen(item.card)
                        } label: {
                            cardSurface(item, radius: 18) {
                                VStack(alignment: .leading, spacing: 6) {
                                    badge(item, size: 26)
                                    NovaText(text: item.copy.title, style: .bodyStrong)
                                    NovaText(text: item.copy.detail, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                                    actionRow(item)
                                }
                                .padding(12)
                            }
                        }
                        .buttonStyle(NovaRowPressStyle())
                        .accessibilityIdentifier("nova.home.foryou.all.\(item.card.key)")
                    }
                    if truncated {
                        NovaText(text: RDLocalization.string("localizable.nova.foryou.more_hint", table: .localizable, fallback: "Diğer kayıtlar ilgili modül listelerinde."),
                            style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(NovaColorToken.canvas.color(in: scheme))
            .navigationTitle(RDLocalization.string("localizable.nova.foryou.title", table: .localizable, fallback: "Senin İçin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(RDLocalization.string("localizable.nova.foryou.close", table: .localizable, fallback: "Kapat")) { showingAll = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
