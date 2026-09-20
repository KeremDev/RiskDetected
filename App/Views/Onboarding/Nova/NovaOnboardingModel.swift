#if DEBUG && NOVA_PILOT_BUILD
import Foundation
import SwiftUI

/// The eleven-question catalogue from the prototype, verbatim: same ids, same
/// order, same copy, same icon geometry.
enum NovaOBIcon {
    static let doc = "M8 3h6l4 4v14H8zM14 3v4h4"
    static let building = "M4 21V6l8-3 8 3v15M10 21v-5h4v5"
    static let list = "M4 7h4M4 12h4M4 17h4M11 7h9M11 12h9M11 17h9"
    static let cal = "M4 6h16v15H4zM4 11h16M8 3v4M16 3v4"
    static let shield = "M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6z"
    static let chat = "M4 5h16v11H9l-5 4z"
    static let rule = "M4 4h16v16H4zM8 9h8M8 14h5"
    static let flame = "M12 3c4 5 6 7 6 10a6 6 0 01-12 0c0-3 3-4 3-7 1 2 3 2 3 4"
    static let tools = "M4 20l7-7M14 4l6 6-3 3-6-6zM7 4l3 3-3 3-3-3z"
    static let chart = "M4 20V9M10 20V4M16 20v-8M22 20H2"
    static let spark = "M12 3v5M12 16v5M3 12h5M16 12h5M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3"
    static let truck = "M2 7h11v8H2zM13 11h5l3 4v0h-8M6 19a2 2 0 100-4 2 2 0 000 4zM17 19a2 2 0 100-4 2 2 0 000 4z"
    static let bolt = "M13 3L5 14h6l-1 7 8-11h-6z"
    static let flask = "M9 3h6M10 3v6l-5 9a2 2 0 002 3h10a2 2 0 002-3l-5-9V3"
    static let bell = "M6 16V11a6 6 0 1112 0v5l2 3H4zM10 19a2 2 0 004 0"
    static let users = "M9 11a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM2 20c0-3.5 3.2-5.5 7-5.5s7 2 7 5.5M17 6.5a3 3 0 010 6M18 20h4c0-2.6-1.4-4.3-3.5-5"
    static let file = "M7 3h7l4 4v14H7zM10 12h6M10 16h4"
    static let dots = "M6 12h.01M12 12h.01M18 12h.01"
    static let ban = "M4 12a8 8 0 1016 0 8 8 0 00-16 0zM6.5 6.5l11 11"
    static let certA = "M12 3l7 3v5.5c0 4.2-2.9 7.3-7 8.5-4.1-1.2-7-4.3-7-8.5V6zM9 11.5l2.2 2.2L15.5 9"
    static let certB = "M12 3.5a4.5 4.5 0 100 9 4.5 4.5 0 000-9zM9.6 12.2L8 21l4-2 4 2-1.6-8.8"
    static let certC = "M4 6h16v12H4zM7.5 10.5h5M7.5 14h3.5M17 14.5a2 2 0 100-4 2 2 0 000 4z"
    static let helmetPro = "M4 12a8 8 0 0116 0zM2.5 12h19M9 12V9a3 3 0 016 0v3"
    static let briefcase = "M3 8.5h18V20H3zM9 8.5V5.5h6v3M3 13.5h18M11 14h2v2h-2z"
    static let wrench = "M14.5 6.5l3 3-8.5 8.5H5.5v-3.5zM16 4l4 4M6 20.5h12"
    static let officeLead = "M5 21V5h10v16M8.5 9h3M8.5 13h3M18 21v-6.5a2 2 0 00-2-2M3 21h18"
    static let multiBuilding = "M4 21V8l6-2.5V21M10 11l7-2.5V21M17 13.5l3-1V21M2.5 21h19"
    static let oneBuilding = "M6 21V4h12v17M10 8h4M10 12h4M10 16h4M3.5 21h17"
    static let freelance = "M12 10a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM5 21v-1.5A5.5 5.5 0 0110.5 14h3a5.5 5.5 0 015.5 5.5V21"
    static let pickaxe = "M4 20l7.5-7.5M3.5 9.5c3-4.5 9.5-5.5 12.5-3M15 3c2.5 3 1.5 9.5-3 12.5"
    static let crane = "M5 21h14M7 21V4h9M7 8h11l-2.5 4.5M16 4l4.5 4.5"
    static let factory = "M3 21V11l5 3V11l5 3V9l6 4v8zM3 21h18M9.5 21v-3h3v3"
    static let health = "M12 20.5S4.5 16 4.5 10.8A4.3 4.3 0 0112 8a4.3 4.3 0 017.5 2.8c0 5.2-7.5 9.7-7.5 9.7zM12 11.5v4M10 13.5h4"
    static let spool = "M7 3h10v3l-3 2v10a2 2 0 01-4 0V8L7 6zM10 12h4"
    static let wheat = "M8 3v7.5a2 2 0 004 0V3M10 12v9M16.5 3c2 2.2 2 6.3 0 8.5-2-2.2-2-6.3 0-8.5M16.5 11.5V21"
    static let anvil = "M4 9h13l3 3-3 1.5H9L7 19h7M9 9V6h5.5v3"
    static let headset = "M5 14v-2a7 7 0 0114 0v2M5 14h3v5.5H6.5A1.5 1.5 0 015 18zM19 14h-3v5.5h1.5A1.5 1.5 0 0019 18z"
    static let gavel = "M4 20h9M6.5 12.5l6-6M9.5 3.5l6 6-3 3-6-6zM13.5 11.5L19 17l-2 2-5.5-5.5"
    static let docChart = "M7 3h10v18H7zM10 17v-5M13.5 17V9"
    static let clipboard = "M8 4.5h8V21H8zM10 2.5h4v3h-4zM10.5 12l1.8 1.8L15.5 10"
    static let magnifier = "M11 12a4.5 4.5 0 100-9 4.5 4.5 0 000 9zM14.5 11l6 6M3 20.5h7"
    static let exit = "M4 4h6v16H4zM13 12h7M16.5 8.5L20 12l-3.5 3.5"
    static let gear = "M12 15a3 3 0 100-6 3 3 0 000 6zM12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.5 5.5l2 2M16.5 16.5l2 2M18.5 5.5l-2 2M7.5 16.5l-2 2"
    static let speak = "M4 5h16v10H10l-4 3.5V15H4zM8 9h8M8 12h5"
    static let meeting = "M12 7.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5M4.5 20a7.5 7.5 0 0115 0M6.5 12.5a2 2 0 100-4M17.5 12.5a2 2 0 100-4"
}

struct NovaOBOption: Identifiable, Equatable {
    let value: String
    let label: String
    var sub: String = ""
    let icon: String
    /// Full-width in the two-column grid (the prototype's `small` flag).
    var small = false
    /// Suggests this option when the matching growth area was picked.
    var suggestedBy: String? = nil
    var id: String { value }
}

struct NovaOBQuestion: Identifiable {
    enum Kind { case text, single, multi, slider, counter }
    let id: String
    let kind: Kind
    let title: String
    var desc: String = ""
    var skippable = true
    var options: [NovaOBOption] = []
    var max: Int? = nil
    var searchable = false
    var grid = false
    /// The option value that clears every other choice when picked.
    var exclusive: String? = nil
    /// The option value that reveals the free-text field.
    var other: String? = nil
}

enum NovaOBCatalogue {
    static let sections: [(label: String, range: ClosedRange<Int>)] = [
        ("SENİ TANIYALIM", 0...3),
        ("DENEYİMİN VE ÇALIŞMA ALANIN", 4...6),
        ("İHTİYAÇLARIN VE TERCİHLERİN", 7...10)
    ]

    static let experienceStops: [(label: String, sub: String)] = [
        ("1–3 yıl", "1 yıl ile 3 yıl arası deneyim"),
        ("3–7 yıl", "3 yıl dahil, 7 yıla kadar"),
        ("7–10 yıl", "7 yıl dahil, 10 yıla kadar"),
        ("10+ yıl", "10 yıl ve üzeri")
    ]

    static let questions: [NovaOBQuestion] = [
        NovaOBQuestion(
            id: "name", kind: .text,
            title: "Sana nasıl hitap edelim?",
            desc: "Çalışma alanını senin için kişiselleştirelim.",
            skippable: false
        ),
        NovaOBQuestion(
            id: "cert", kind: .single,
            title: "Hangi sertifikaya sahipsin?",
            desc: "Bu kapsamda bilgiler/belgeler sunacağız.",
            options: [
                .init(value: "A", label: "A Sınıfı", icon: NovaOBIcon.certA),
                .init(value: "B", label: "B Sınıfı", icon: NovaOBIcon.certB),
                .init(value: "C", label: "C Sınıfı", icon: NovaOBIcon.certC),
                .init(value: "none", label: "Henüz sertifikam yok", icon: NovaOBIcon.dots, small: true)
            ]
        ),
        NovaOBQuestion(
            id: "work", kind: .single,
            title: "Çalışma şeklin nedir?",
            options: [
                .init(value: "osgb", label: "OSGB", sub: "Birden fazla firmayla çalışıyorum", icon: NovaOBIcon.multiBuilding),
                .init(value: "tek", label: "Tek firma", sub: "Bir firmanın bünyesinde çalışıyorum", icon: NovaOBIcon.oneBuilding),
                .init(value: "serbest", label: "Serbest çalışma", sub: "Bağımsız hizmet veriyorum", icon: NovaOBIcon.freelance),
                .init(value: "yok", label: "Şu an çalışmıyorum", icon: NovaOBIcon.dots, small: true)
            ]
        ),
        NovaOBQuestion(
            id: "role", kind: .single,
            title: "Çalıştığın yerdeki pozisyonun nedir?",
            desc: "Bu bilgi yalnızca kişiselleştirme içindir; hesap yetkisi vermez.",
            options: [
                .init(value: "uzman", label: "İş Güvenliği Uzmanı", icon: NovaOBIcon.helmetPro),
                .init(value: "mudur", label: "İş Güvenliği Müdürü", icon: NovaOBIcon.briefcase),
                .init(value: "tekniker", label: "İş Güvenliği Teknikeri", icon: NovaOBIcon.wrench),
                .init(value: "koordinator", label: "İSG Koordinatörü", icon: NovaOBIcon.users),
                .init(value: "osgbyonetici", label: "OSGB Yöneticisi / Sorumlusu", icon: NovaOBIcon.officeLead),
                .init(value: "diger", label: "Diğer", icon: NovaOBIcon.dots)
            ],
            other: "diger"
        ),
        NovaOBQuestion(
            id: "exp", kind: .slider,
            title: "Toplam mesleki tecrüben ne kadar?",
            desc: "Aralığı sürükleyerek veya duraklara dokunarak seç."
        ),
        NovaOBQuestion(
            id: "sectors", kind: .multi,
            title: "Hangi sektörlerde çalışıyorsun?",
            desc: "Birden fazla sektör seçebilirsin.",
            options: [
                .init(value: "maden", label: "Maden", icon: NovaOBIcon.pickaxe),
                .init(value: "insaat", label: "İnşaat", icon: NovaOBIcon.crane),
                .init(value: "imalat", label: "İmalat", icon: NovaOBIcon.factory),
                .init(value: "saglik", label: "Sağlık", icon: NovaOBIcon.health),
                .init(value: "enerji", label: "Enerji", icon: NovaOBIcon.bolt),
                .init(value: "tekstil", label: "Tekstil", icon: NovaOBIcon.spool),
                .init(value: "gida", label: "Gıda", icon: NovaOBIcon.wheat),
                .init(value: "lojistik", label: "Lojistik", icon: NovaOBIcon.truck),
                .init(value: "kimya", label: "Kimya", icon: NovaOBIcon.flask),
                .init(value: "metal", label: "Metal", icon: NovaOBIcon.anvil),
                .init(value: "hizmet", label: "Hizmet", icon: NovaOBIcon.headset),
                .init(value: "diger", label: "Diğer", icon: NovaOBIcon.dots)
            ],
            searchable: true, grid: true, other: "diger"
        ),
        NovaOBQuestion(
            id: "trainings", kind: .multi,
            title: "Hangi eğitimleri aldın?",
            desc: "Birden fazla seçebilirsin.",
            options: [
                .init(value: "nebosh", label: "NEBOSH", icon: NovaOBIcon.doc),
                .init(value: "acil", label: "Acil Durum", icon: NovaOBIcon.bell),
                .init(value: "yangin", label: "Yangın", icon: NovaOBIcon.flame),
                .init(value: "kokneden", label: "Kök Neden Analizi", icon: NovaOBIcon.chart),
                .init(value: "makine", label: "Makine Emniyeti", icon: NovaOBIcon.tools),
                .init(value: "diger", label: "Diğer", icon: NovaOBIcon.dots),
                .init(value: "yok", label: "Henüz bu eğitimlerden birini almadım", icon: NovaOBIcon.ban, small: true)
            ],
            exclusive: "yok", other: "diger"
        ),
        NovaOBQuestion(
            id: "approach", kind: .multi,
            title: "İş güvenliğini yönetirken yaklaşımın nasıl?",
            desc: "Sana en yakın iki yaklaşımı seçebilirsin.",
            options: [
                .init(value: "iletisim", label: "İletişim odaklı", sub: "Diyalog ve katılım", icon: NovaOBIcon.chat),
                .init(value: "kuralci", label: "Kuralcı", sub: "Net kurallar ve uygulama", icon: NovaOBIcon.rule),
                .init(value: "mevzuat", label: "Mevzuat odaklı", sub: "Gereklilikleri yakından takip", icon: NovaOBIcon.file),
                .init(value: "disiplinli", label: "Disiplinli", sub: "Düzenli kontrol ve takip", icon: NovaOBIcon.list),
                .init(value: "esnek", label: "Rahat / esnek", sub: "Duruma uyum sağlayan iletişim", icon: NovaOBIcon.spark)
            ],
            max: 2
        ),
        NovaOBQuestion(
            id: "inspections", kind: .counter,
            title: "Son 1 yılda kaç kez Bakanlık teftişi geçirdin?",
            desc: "Görev aldığın işyerlerinde katıldığın teftişleri düşün."
        ),
        NovaOBQuestion(
            id: "growth", kind: .multi,
            title: "Hangi konularda güçlenmek istersin?",
            desc: "Daha fazla destek istediğin alanları seç.",
            options: [
                .init(value: "risk", label: "Risk analizi", icon: NovaOBIcon.shield),
                .init(value: "mevzuat", label: "Mevzuat takibi", icon: NovaOBIcon.gavel),
                .init(value: "rapor", label: "Raporlama ve dokümantasyon", icon: NovaOBIcon.docChart),
                .init(value: "saha", label: "Saha denetimleri", icon: NovaOBIcon.clipboard),
                .init(value: "egitim", label: "Eğitim planlama", icon: NovaOBIcon.cal),
                .init(value: "kaza", label: "Kaza / kök neden analizi", icon: NovaOBIcon.magnifier),
                .init(value: "acil", label: "Acil durum planları", icon: NovaOBIcon.exit),
                .init(value: "makine", label: "Makine emniyeti", icon: NovaOBIcon.gear),
                .init(value: "calisan", label: "Çalışanlarla iletişim", icon: NovaOBIcon.speak),
                .init(value: "diger", label: "Diğer", icon: NovaOBIcon.dots),
                .init(value: "yok", label: "Belirli bir alan yok", icon: NovaOBIcon.ban, small: true)
            ],
            grid: true, exclusive: "yok", other: "diger"
        ),
        NovaOBQuestion(
            id: "assist", kind: .multi,
            title: "Hangi konularda asistanlık yapalım?",
            desc: "Önce en çok ihtiyaç duyduğun üç alanı belirleyelim.",
            options: [
                .init(value: "risk", label: "Risk Analizi", sub: "Analiz taslakları, revizyon hatırlatmaları", icon: NovaOBIcon.shield, suggestedBy: "risk"),
                .init(value: "kontrol", label: "Kontrol Listeleri", sub: "Sahaya göre hazır listeler", icon: NovaOBIcon.clipboard, suggestedBy: "saha"),
                .init(value: "egitim", label: "Eğitim Takibi", sub: "Tarih ve tekrar takibi", icon: NovaOBIcon.cal, suggestedBy: "egitim"),
                .init(value: "firma", label: "Firma Yönetimi", sub: "Firma dosyaları tek yerde", icon: NovaOBIcon.oneBuilding),
                .init(value: "osgb", label: "OSGB Yönetimi", sub: "Atama ve görev dağılımı", icon: NovaOBIcon.multiBuilding),
                .init(value: "acil", label: "Acil Durum Planları", sub: "Plan şablonu, tatbikat takvimi", icon: NovaOBIcon.exit, suggestedBy: "acil"),
                .init(value: "toplanti", label: "Toplantılar", sub: "Gündem ve karar kaydı", icon: NovaOBIcon.meeting),
                .init(value: "mevzuat", label: "Mevzuat Takibi", sub: "Değişiklik bildirimleri", icon: NovaOBIcon.gavel, suggestedBy: "mevzuat"),
                .init(value: "rapor", label: "Raporlama", sub: "Dönemsel rapor çıktıları", icon: NovaOBIcon.docChart, suggestedBy: "rapor")
            ],
            max: 3, grid: true
        )
    ]

    static func question(_ id: String) -> NovaOBQuestion? { questions.first { $0.id == id } }

    static func label(_ questionID: String, _ value: String) -> String {
        question(questionID)?.options.first { $0.value == value }?.label ?? ""
    }
}

/// Every answer the funnel collects, mirroring the prototype's `EMPTY` shape.
struct NovaOBAnswers: Equatable {
    var name = ""
    var cert: String?
    var work: String?
    var role: String?
    var roleOther = ""
    /// Index into `experienceStops`, or nil when unanswered.
    var exp: Int?
    var expLess = false
    var sectors: [String] = []
    var sectorsOther = ""
    var trainings: [String] = []
    var trainingsOther = ""
    var approach: [String] = []
    var inspections = 0
    var growth: [String] = []
    var growthOther = ""
    var assist: [String] = []

    func list(_ questionID: String) -> [String] {
        switch questionID {
        case "sectors": return sectors
        case "trainings": return trainings
        case "approach": return approach
        case "growth": return growth
        case "assist": return assist
        default: return []
        }
    }

    mutating func setList(_ questionID: String, _ values: [String]) {
        switch questionID {
        case "sectors": sectors = values
        case "trainings": trainings = values
        case "approach": approach = values
        case "growth": growth = values
        case "assist": assist = values
        default: break
        }
    }

    func single(_ questionID: String) -> String? {
        switch questionID {
        case "cert": return cert
        case "work": return work
        case "role": return role
        default: return nil
        }
    }

    mutating func setSingle(_ questionID: String, _ value: String?) {
        switch questionID {
        case "cert": cert = value
        case "work": work = value
        case "role": role = value
        default: break
        }
    }

    func other(_ questionID: String) -> String {
        switch questionID {
        case "sectors": return sectorsOther
        case "trainings": return trainingsOther
        case "growth": return growthOther
        default: return roleOther
        }
    }

    mutating func setOther(_ questionID: String, _ value: String) {
        switch questionID {
        case "sectors": sectorsOther = value
        case "trainings": trainingsOther = value
        case "growth": growthOther = value
        default: roleOther = value
        }
    }
}

// MARK: - Answer persistence

extension NovaOBAnswers {
    private func choice(_ questionID: String, _ value: String) -> OnboardingAnswerChoice {
        OnboardingAnswerChoice(value: value, label: NovaOBCatalogue.label(questionID, value))
    }

    /// Maps the funnel onto the draft the rest of the app already syncs
    /// (`OnboardingAnswersService`), so a Nova profile lands in the same place
    /// a V2 profile would.
    func makeDraft() -> OnboardingAnswersDraft {
        OnboardingAnswersDraft(
            onboardingVersion: "nova-v1",
            certificateClass: cert.map { choice("cert", $0) },
            hazardClasses: [],
            professionalRole: role.map { value in
                value == "diger" && !roleOther.novaTrimmed.isEmpty
                    ? OnboardingAnswerChoice(value: value, label: roleOther.novaTrimmed)
                    : choice("role", value)
            },
            safetyProfileID: nil,
            sectors: sectors.map { value in
                value == "diger" && !sectorsOther.novaTrimmed.isEmpty
                    ? OnboardingAnswerChoice(value: value, label: sectorsOther.novaTrimmed)
                    : choice("sectors", value)
            },
            auditFrequency: OnboardingAnswerChoice(
                value: "inspections_\(inspections)",
                label: inspections == 0 ? "Teftiş deneyimi yok" : "\(inspections) teftiş"
            ),
            selectedPlan: nil
        )
    }

    /// The answers the draft schema has no column for. Kept locally so the app
    /// can personalise without inventing server fields the backend never agreed to.
    var localProfileSnapshot: [String: String] {
        var snapshot: [String: String] = [:]
        snapshot["name"] = name.novaTrimmed
        snapshot["work"] = work ?? ""
        snapshot["experience"] = expLess ? "less_than_year" : exp.map { NovaOBCatalogue.experienceStops[$0].label } ?? ""
        snapshot["trainings"] = trainings.joined(separator: ",")
        snapshot["approach"] = approach.joined(separator: ",")
        snapshot["growth"] = growth.joined(separator: ",")
        snapshot["assist"] = assist.joined(separator: ",")
        snapshot["inspections"] = String(inspections)
        return snapshot
    }
}

extension String {
    var novaTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
