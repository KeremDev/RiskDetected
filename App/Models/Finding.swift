import SwiftUI

// MARK: - Risk metodolojisi

enum RiskMethod: String, CaseIterable, Identifiable {
    case fineKinney = "fk"
    case matrix5x5  = "m5"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fineKinney: return RDLocalization.string("analysis.finding.fine.kinney.224a34d8", table: .analysis, fallback: "Fine-Kinney")
        case .matrix5x5:  return RDLocalization.string("analysis.finding.5.5.l.tipi.f434fdf5", table: .analysis, fallback: "5×5 L-Tipi")
        }
    }

    var formula: String {
        switch self {
        case .fineKinney: return RDLocalization.string("analysis.finding.o.f.s.1a128241", table: .analysis, fallback: "O × F × Ş")
        case .matrix5x5:  return RDLocalization.string("analysis.finding.o.s.e9e53958", table: .analysis, fallback: "O × Ş")
        }
    }

    var fullName: String {
        switch self {
        case .fineKinney: return RDLocalization.string("analysis.finding.fine.kinney.metodu.e0bb76e1", table: .analysis, fallback: "Fine-Kinney metodu")
        case .matrix5x5:  return RDLocalization.string("analysis.finding.5.5.l.tipi.matris.048b5aa8", table: .analysis, fallback: "5×5 L-Tipi Matris")
        }
    }
}

// Fine-Kinney parametreleri
struct FineKinneyParams: Equatable, Hashable {
    let probability: Double // O: 0.2, 0.5, 1, 3, 6, 10
    let frequency: Double   // F: 0.5, 1, 2, 3, 6, 10
    let severity: Double    // Ş: 1, 3, 7, 15, 40, 100

    var score: Double { probability * frequency * severity }
}

// 5×5 L-Tipi
struct FiveByFiveParams: Equatable, Hashable {
    let probability: Int // 1-5
    let severity: Int    // 1-5

    var score: Int { probability * severity }
}

// MARK: - Risk band hesaplamaları

struct RiskBand {
    let level: RiskLevel
    let label: String
    let action: String
    let color: Color
}

enum RiskBands {
    static func fineKinney(_ score: Double) -> RiskBand {
        switch score {
        case 401...:
            return RiskBand(level: .critical, label: RDLocalization.string("analysis.finding.tolerans.disi.3f8f17ca", table: .analysis, fallback: "Tolerans dışı"),
                            action: RDLocalization.string("analysis.finding.calisma.derhal.durdurulmali.63183249", table: .analysis, fallback: "Çalışma derhal durdurulmalı"), color: .rdCritical)
        case 201...400:
            return RiskBand(level: .high, label: RDLocalization.string("analysis.finding.yuksek.risk.7384eb4f", table: .analysis, fallback: "Yüksek risk"),
                            action: RDLocalization.string("analysis.finding.kisa.vadede.onlem.8afb5ba2", table: .analysis, fallback: "Kısa vadede önlem"), color: .rdHigh)
        case 71...200:
            return RiskBand(level: .medium, label: RDLocalization.string("analysis.finding.onemli.risk.e4e46a8b", table: .analysis, fallback: "Önemli risk"),
                            action: RDLocalization.string("analysis.finding.duzeltici.plan.gerekli.e523f981", table: .analysis, fallback: "Düzeltici plan gerekli"), color: .rdMedium)
        case 21...70:
            return RiskBand(level: .low, label: RDLocalization.string("analysis.finding.olasi.risk.61fdb63e", table: .analysis, fallback: "Olası risk"),
                            action: RDLocalization.string("analysis.finding.gozetim.altinda.izle.50e72c41", table: .analysis, fallback: "Gözetim altında izle"), color: .rdLow)
        default:
            return RiskBand(level: .low, label: RDLocalization.string("analysis.finding.onemsiz.ca1e144e", table: .analysis, fallback: "Önemsiz"),
                            action: RDLocalization.string("analysis.finding.izleme.yeterli.a9ae63e4", table: .analysis, fallback: "İzleme yeterli"), color: .rdLow)
        }
    }

    static func matrix5x5(_ score: Int) -> RiskBand {
        switch score {
        case 20...:
            return RiskBand(level: .critical, label: RDLocalization.string("analysis.finding.tolerans.disi.d50498c6", table: .analysis, fallback: "Tolerans dışı"),
                            action: RDLocalization.string("analysis.finding.calisma.derhal.durdurulmali.6ab27940", table: .analysis, fallback: "Çalışma derhal durdurulmalı"), color: .rdCritical)
        case 10...19:
            return RiskBand(level: .high, label: RDLocalization.string("analysis.finding.yuksek.risk.56653260", table: .analysis, fallback: "Yüksek risk"),
                            action: RDLocalization.string("analysis.finding.en.kisa.surede.onlem.2b0202e7", table: .analysis, fallback: "En kısa sürede önlem"), color: .rdHigh)
        case 5...9:
            return RiskBand(level: .medium, label: RDLocalization.string("analysis.finding.orta.risk.6902fcc6", table: .analysis, fallback: "Orta risk"),
                            action: RDLocalization.string("analysis.finding.plan.dahilinde.onlem.9e4f0c32", table: .analysis, fallback: "Plan dahilinde önlem"), color: .rdMedium)
        case 3...4:
            return RiskBand(level: .low, label: RDLocalization.string("analysis.finding.dusuk.risk.cca91a7e", table: .analysis, fallback: "Düşük risk"),
                            action: RDLocalization.string("analysis.finding.gozetim.altinda.izle.8a959e54", table: .analysis, fallback: "Gözetim altında izle"), color: .rdLow)
        default:
            return RiskBand(level: .low, label: RDLocalization.string("analysis.finding.onemsiz.9db630ac", table: .analysis, fallback: "Önemsiz"),
                            action: RDLocalization.string("analysis.finding.izleme.yeterli.9d551384", table: .analysis, fallback: "İzleme yeterli"), color: .rdLow)
        }
    }
}

// MARK: - Finding

struct FindingMeasure: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case corrective
        case preventive
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = Kind(rawValue: rawValue) ?? .unknown
        }
    }

    let kind: Kind
    let title: String
    let text: String

    var id: String { "\(kind.rawValue)-\(title)-\(text)" }

    var displayTitle: String {
        switch kind {
        case .corrective: return RDLocalization.string("analysis.finding.duzeltici.onlem.9a6a809b", table: .analysis, fallback: "Düzeltici Önlem")
        case .preventive: return RDLocalization.string("analysis.finding.onleyici.kontrol.30d3828c", table: .analysis, fallback: "Önleyici Kontrol")
        case .unknown:
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? RDLocalization.string("analysis.finding.kontrol.tedbiri.a070ade2", table: .analysis, fallback: "Kontrol Tedbiri") : trimmed
        }
    }
}

struct Finding: Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let confidence: Double // 0..1
    let description: String
    let action: String
    let measures: [FindingMeasure]
    let references: String
    let rootCause: String
    let needsFieldVerification: Bool
    let isScored: Bool
    let fk: FineKinneyParams
    let m5: FiveByFiveParams

    init(
        id: Int,
        title: String,
        category: String,
        confidence: Double,
        description: String,
        action: String,
        measures: [FindingMeasure] = [],
        references: String,
        rootCause: String,
        needsFieldVerification: Bool = false,
        isScored: Bool = true,
        fk: FineKinneyParams,
        m5: FiveByFiveParams
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.confidence = confidence
        self.description = description
        self.action = action
        self.measures = measures
        self.references = references
        self.rootCause = rootCause
        self.needsFieldVerification = needsFieldVerification
        self.isScored = isScored
        self.fk = fk
        self.m5 = m5
    }

    var fkScore: Double { fk.score }
    var m5Score: Int { m5.score }

    var displayTitle: String {
        let qualifiers = [
            "(sahada doğrulanmalı)",
            "(sahada dogrulanmali)",
            "(sahada doğrulanmalıdır)",
            "(sahada dogrulanmalidir)",
            "sahada doğrulanmalı",
            "sahada dogrulanmali",
            "sahada doğrulanmalıdır",
            "sahada dogrulanmalidir",
        ]
        var cleaned = title
        for qualifier in qualifiers {
            cleaned = cleaned.replacingOccurrences(
                of: qualifier,
                with: "",
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        cleaned = cleaned.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned
            .replacingOccurrences(of: " ()", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—·,;: "))
        return cleaned.isEmpty ? title : cleaned
    }

    var fkBand: RiskBand { RiskBands.fineKinney(fkScore) }
    var m5Band: RiskBand { RiskBands.matrix5x5(m5Score) }

    var controlMeasures: [FindingMeasure] {
        let validMeasures = measures.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !validMeasures.isEmpty { return validMeasures }
        let fallback = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return [] }
        return [
            FindingMeasure(
                kind: .corrective,
                title: RDLocalization.string(
                    "analysis.finding.duzeltici.onlem.bbba0d3a",
                    table: .analysis,
                    fallback: "Düzeltici Önlem"
                ),
                text: fallback
            )
        ]
    }

    var controlMeasuresText: String {
        controlMeasures
            .map { measure in
                "\(measure.displayTitle): \(measure.text)"
            }
            .joined(separator: "\n")
    }

    func score(for method: RiskMethod) -> Double {
        switch method {
        case .fineKinney: return fkScore
        case .matrix5x5:  return Double(m5Score)
        }
    }

    func band(for method: RiskMethod) -> RiskBand {
        switch method {
        case .fineKinney: return fkBand
        case .matrix5x5:  return m5Band
        }
    }

    func formula(for method: RiskMethod) -> String {
        switch method {
        case .fineKinney:
            return RDLocalization.format("analysis.finding.o.1.f.2.s.3.d1f790bc", table: .analysis, fallback: "O %1$@ × F %2$@ × Ş %3$@", arguments: [String(describing: formattedFK(fk.probability)), String(describing: formattedFK(fk.frequency)), String(describing: Int(fk.severity))])
        case .matrix5x5:
            return RDLocalization.format("analysis.finding.o.1.s.2.cd44f90d", table: .analysis, fallback: "O %1$@ × Ş %2$@", arguments: [String(describing: m5.probability), String(describing: m5.severity)])
        }
    }

    private func formattedFK(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - Mock data

extension Finding {
    static let mock: [Finding] = [
        Finding(id: 1,
                title: RDLocalization.string("analysis.finding.yuksekte.calismada.emniyet.kemeri.kullanilmiyor.d3cc6656", table: .analysis, fallback: "Yüksekte çalışmada emniyet kemeri kullanılmıyor"),
                category: RDLocalization.string("analysis.finding.dusme.riski.88f661e4", table: .analysis, fallback: "Düşme riski"),
                confidence: 0.94,
                description: RDLocalization.string("analysis.finding.isci.3.metre.uzerinde.calisiyor.parasut.tipi.emn.3ef9d38c", table: .analysis, fallback: "İşçi 3 metre üzerinde çalışıyor; paraşüt tipi emniyet kemeri ve sabitleme noktası görünmüyor."),
                action: RDLocalization.string("analysis.finding.calismayi.derhal.durdur.uygun.emniyet.kemeri.ve..7dc9e5cf", table: .analysis, fallback: "Çalışmayı derhal durdur. Uygun emniyet kemeri ve çift kancalı lanyard temin et. Sertifikalı sabitleme noktası belirle."),
                measures: [
                    FindingMeasure(kind: .corrective, title: RDLocalization.string("analysis.finding.duzeltici.onlem.bbba0d3a", table: .analysis, fallback: "Düzeltici Önlem"), text: RDLocalization.string("analysis.finding.calismayi.derhal.durdur.uygun.emniyet.kemeri.ve..24b118f1", table: .analysis, fallback: "Çalışmayı derhal durdur. Uygun emniyet kemeri ve çift kancalı lanyard temin et. Sertifikalı sabitleme noktası belirle.")),
                    FindingMeasure(kind: .preventive, title: RDLocalization.string("analysis.finding.onleyici.kontrol.594b3182", table: .analysis, fallback: "Önleyici Kontrol"), text: RDLocalization.string("analysis.finding.yuksekte.calisma.izin.formuna.ankraj.ve.kkd.kont.232b38e3", table: .analysis, fallback: "Yüksekte çalışma izin formuna ankraj ve KKD kontrol adımı ekle; vardiya başlangıcında saha sorumlusu doğrulaması iste."))
                ],
                references: RDLocalization.string("analysis.finding.6331.4857.csgb.yuksekte.calisma.eaa40dbd", table: .analysis, fallback: "6331/4857 · ÇSGB Yüksekte Çalışma"),
                rootCause: RDLocalization.string("analysis.finding.yuksekte.calisma.alaninda.toplu.koruma.ve.ankraj.4ca66593", table: .analysis, fallback: "Yüksekte çalışma alanında toplu koruma ve ankraj planı eksik."),
                fk: FineKinneyParams(probability: 6, frequency: 6, severity: 40),
                m5: FiveByFiveParams(probability: 4, severity: 5)),
        Finding(id: 2,
                title: RDLocalization.string("analysis.finding.reflektif.yelek.eksikligi.f3d0ca8d", table: .analysis, fallback: "Reflektif yelek eksikliği"),
                category: RDLocalization.string("analysis.finding.kkd.uyumsuzlugu.322db487", table: .analysis, fallback: "KKD uyumsuzluğu"),
                confidence: 0.88,
                description: RDLocalization.string("analysis.finding.forklift.trafiginin.oldugu.alanda.iki.calisanda..f7b5fde7", table: .analysis, fallback: "Forklift trafiğinin olduğu alanda iki çalışanda yüksek görünürlüklü yelek bulunmuyor."),
                action: RDLocalization.string("analysis.finding.tum.calisanlara.en.iso.20471.sinif.2.yelek.dagit.16f96548", table: .analysis, fallback: "Tüm çalışanlara EN ISO 20471 sınıf 2 yelek dağıt. Vardiya başında KKD kontrol formu işlet."),
                measures: [
                    FindingMeasure(kind: .corrective, title: RDLocalization.string("analysis.finding.duzeltici.onlem.fc8a8ded", table: .analysis, fallback: "Düzeltici Önlem"), text: RDLocalization.string("analysis.finding.forklift.trafigi.olan.alandaki.calisanlara.en.is.189c1e0b", table: .analysis, fallback: "Forklift trafiği olan alandaki çalışanlara EN ISO 20471 sınıf 2 reflektif yelek ver ve kullanımı hemen başlat.")),
                    FindingMeasure(kind: .preventive, title: RDLocalization.string("analysis.finding.onleyici.kontrol.2cbc424e", table: .analysis, fallback: "Önleyici Kontrol"), text: RDLocalization.string("analysis.finding.vardiya.girisinde.kkd.kontrol.listesini.islet.ye.63d913de", table: .analysis, fallback: "Vardiya girişinde KKD kontrol listesini işlet; yelek uygunluğunu saha turunda sorumlu kişi tarafından doğrulat."))
                ],
                references: "EN ISO 20471",
                rootCause: RDLocalization.string("analysis.finding.kkd.dagitimi.ve.vardiya.baslangic.kontrolu.duzen.58cb5805", table: .analysis, fallback: "KKD dağıtımı ve vardiya başlangıç kontrolü düzenli işletilmiyor."),
                fk: FineKinneyParams(probability: 3, frequency: 6, severity: 15),
                m5: FiveByFiveParams(probability: 4, severity: 4)),
        Finding(id: 3,
                title: RDLocalization.string("analysis.finding.gecis.yolunda.malzeme.istifi.7f3c4ee7", table: .analysis, fallback: "Geçiş yolunda malzeme istifi"),
                category: RDLocalization.string("analysis.finding.cevresel.duzen.75f97bc9", table: .analysis, fallback: "Çevresel düzen"),
                confidence: 0.81,
                description: RDLocalization.string("analysis.finding.yangin.cikis.guzergahi.uzerinde.gecici.olarak.is.821e1b70", table: .analysis, fallback: "Yangın çıkış güzergâhı üzerinde geçici olarak istiflenmiş paletler tespit edildi."),
                action: RDLocalization.string("analysis.finding.paletleri.24.saat.icinde.belirlenmis.depolama.al.4620d455", table: .analysis, fallback: "Paletleri 24 saat içinde belirlenmiş depolama alanına taşı. Geçiş yolunu sarı şerit ile işaretle."),
                measures: [
                    FindingMeasure(kind: .corrective, title: RDLocalization.string("analysis.finding.duzeltici.onlem.bbba0d3a", table: .analysis, fallback: "Düzeltici Önlem"), text: RDLocalization.string("analysis.finding.paletleri.belirlenmis.depolama.alanina.tasi.ve.y.08eb31e0", table: .analysis, fallback: "Paletleri belirlenmiş depolama alanına taşı ve yangın çıkış güzergahını hemen boşalt.")),
                    FindingMeasure(kind: .preventive, title: RDLocalization.string("analysis.finding.onleyici.kontrol.594b3182", table: .analysis, fallback: "Önleyici Kontrol"), text: RDLocalization.string("analysis.finding.gecis.yolu.kontrolunu.gunluk.5s.saha.turu.listes.a7f8f085", table: .analysis, fallback: "Geçiş yolu kontrolünü günlük 5S/saha turu listesine ekle; geçici istif sorumluluğunu vardiya bazında ata."))
                ],
                references: "İSG-PRO-12",
                rootCause: RDLocalization.string("analysis.finding.gecici.istif.alani.ve.sorumluluk.duzeni.net.tani.0d03210c", table: .analysis, fallback: "Geçici istif alanı ve sorumluluk düzeni net tanımlanmamış."),
                fk: FineKinneyParams(probability: 3, frequency: 3, severity: 15),
                m5: FiveByFiveParams(probability: 3, severity: 3)),
        Finding(id: 4,
                title: RDLocalization.string("analysis.finding.yetersiz.aydinlatma.1adf35ad", table: .analysis, fallback: "Yetersiz aydınlatma"),
                category: RDLocalization.string("analysis.finding.cevresel.risk.bed57d51", table: .analysis, fallback: "Çevresel risk"),
                confidence: 0.72,
                description: RDLocalization.string("analysis.finding.calisma.alaninin.arka.kisminda.200.luks.altinda..c1d69b0d", table: .analysis, fallback: "Çalışma alanının arka kısmında 200 lüks altında ışık seviyesi gözleniyor; net algı düşük."),
                action: RDLocalization.string("analysis.finding.gecici.led.projektor.yerlestir.kalici.aydinlatma.487287b9", table: .analysis, fallback: "Geçici LED projektör yerleştir. Kalıcı aydınlatma planı için elektrik ekibine bildir."),
                measures: [
                    FindingMeasure(kind: .corrective, title: RDLocalization.string("analysis.finding.duzeltici.onlem.b7787f59", table: .analysis, fallback: "Düzeltici Önlem"), text: RDLocalization.string("analysis.finding.calisma.alanina.gecici.led.projektor.yerlestir.v.644c2760", table: .analysis, fallback: "Çalışma alanına geçici LED projektör yerleştir ve düşük aydınlatmalı bölgede işi güvenli seviyeye gelene kadar sınırla.")),
                    FindingMeasure(kind: .preventive, title: RDLocalization.string("analysis.finding.onleyici.kontrol.9c2f513f", table: .analysis, fallback: "Önleyici Kontrol"), text: RDLocalization.string("analysis.finding.aydinlatma.olcumunu.periyodik.kontrol.planina.ek.3afa7a39", table: .analysis, fallback: "Aydınlatma ölçümünü periyodik kontrol planına ekle; saha değişikliklerinde elektrik ekibine kontrol tetikleyicisi tanımla."))
                ],
                references: "EN 12464-1",
                rootCause: RDLocalization.string("analysis.finding.aydinlatma.periyodik.kontrolu.ve.saha.degisiklik.5b768361", table: .analysis, fallback: "Aydınlatma periyodik kontrolü ve saha değişiklikleri birlikte yönetilmiyor."),
                fk: FineKinneyParams(probability: 3, frequency: 6, severity: 7),
                m5: FiveByFiveParams(probability: 3, severity: 2)),
        Finding(id: 5,
                title: RDLocalization.string("analysis.finding.uyari.tabelasi.solmus.4933aa7e", table: .analysis, fallback: "Uyarı tabelası solmuş"),
                category: RDLocalization.string("analysis.finding.gorsel.iletisim.a08cbaa2", table: .analysis, fallback: "Görsel iletişim"),
                confidence: 0.66,
                description: RDLocalization.string("analysis.finding.elektrik.panosu.yanindaki.yuksek.gerilim.tabelas.f524680a", table: .analysis, fallback: "Elektrik panosu yanındaki \"Yüksek Gerilim\" tabelasının okunabilirliği düşmüş."),
                action: RDLocalization.string("analysis.finding.tabelayi.1.hafta.icinde.yenisiyle.degistir.periy.67fa9436", table: .analysis, fallback: "Tabelayı 1 hafta içinde yenisiyle değiştir. Periyodik kontrol planına ekle."),
                measures: [
                    FindingMeasure(kind: .corrective, title: RDLocalization.string("analysis.finding.duzeltici.onlem.1a96a230", table: .analysis, fallback: "Düzeltici Önlem"), text: RDLocalization.string("analysis.finding.okunabilirligi.dusen.yuksek.gerilim.tabelasini.y.40adafd5", table: .analysis, fallback: "Okunabilirliği düşen yüksek gerilim tabelasını yenisiyle değiştir ve pano çevresindeki uyarıyı görünür hale getir.")),
                    FindingMeasure(kind: .preventive, title: RDLocalization.string("analysis.finding.onleyici.kontrol.5841a28d", table: .analysis, fallback: "Önleyici Kontrol"), text: RDLocalization.string("analysis.finding.saha.isaretleri.icin.aylik.gorunurluk.kontrolu.t.ae2146b9", table: .analysis, fallback: "Saha işaretleri için aylık görünürlük kontrolü tanımla; solmuş veya hasarlı tabela değişimini kayıt altına al."))
                ],
                references: "TS EN 7010",
                rootCause: RDLocalization.string("analysis.finding.saha.isaretleri.icin.duzenli.gorunurluk.kontrolu.4e7e9dfd", table: .analysis, fallback: "Saha işaretleri için düzenli görünürlük kontrolü yapılmıyor."),
                fk: FineKinneyParams(probability: 1, frequency: 6, severity: 7),
                m5: FiveByFiveParams(probability: 2, severity: 2))
    ]
}
