import SwiftUI

// MARK: - Risk metodolojisi

enum RiskMethod: String, CaseIterable, Identifiable {
    case fineKinney = "fk"
    case matrix5x5  = "m5"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fineKinney: return "Fine-Kinney"
        case .matrix5x5:  return "5×5 L-Tipi"
        }
    }

    var formula: String {
        switch self {
        case .fineKinney: return "O × F × Ş"
        case .matrix5x5:  return "O × Ş"
        }
    }

    var fullName: String {
        switch self {
        case .fineKinney: return "Fine-Kinney metodu"
        case .matrix5x5:  return "5×5 L-Tipi Matris"
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
            return RiskBand(level: .critical, label: "Tolerans dışı",
                            action: "Çalışma derhal durdurulmalı", color: .rdCritical)
        case 201...400:
            return RiskBand(level: .high, label: "Yüksek risk",
                            action: "Kısa vadede önlem", color: .rdHigh)
        case 71...200:
            return RiskBand(level: .medium, label: "Önemli risk",
                            action: "Düzeltici plan gerekli", color: .rdMedium)
        case 21...70:
            return RiskBand(level: .low, label: "Olası risk",
                            action: "Gözetim altında izle", color: .rdLow)
        default:
            return RiskBand(level: .low, label: "Önemsiz",
                            action: "İzleme yeterli", color: .rdLow)
        }
    }

    static func matrix5x5(_ score: Int) -> RiskBand {
        switch score {
        case 20...:
            return RiskBand(level: .critical, label: "Tolerans dışı",
                            action: "Çalışma derhal durdurulmalı", color: .rdCritical)
        case 10...19:
            return RiskBand(level: .high, label: "Yüksek risk",
                            action: "En kısa sürede önlem", color: .rdHigh)
        case 5...9:
            return RiskBand(level: .medium, label: "Orta risk",
                            action: "Plan dahilinde önlem", color: .rdMedium)
        case 3...4:
            return RiskBand(level: .low, label: "Düşük risk",
                            action: "Gözetim altında izle", color: .rdLow)
        default:
            return RiskBand(level: .low, label: "Önemsiz",
                            action: "İzleme yeterli", color: .rdLow)
        }
    }
}

// MARK: - Finding

struct Finding: Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let confidence: Double // 0..1
    let description: String
    let action: String
    let references: String
    let rootCause: String
    let fk: FineKinneyParams
    let m5: FiveByFiveParams

    var fkScore: Double { fk.score }
    var m5Score: Int { m5.score }

    var fkBand: RiskBand { RiskBands.fineKinney(fkScore) }
    var m5Band: RiskBand { RiskBands.matrix5x5(m5Score) }

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
            return "O \(formattedFK(fk.probability)) × F \(formattedFK(fk.frequency)) × Ş \(Int(fk.severity))"
        case .matrix5x5:
            return "O \(m5.probability) × Ş \(m5.severity)"
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
                title: "Yüksekte çalışmada emniyet kemeri kullanılmıyor",
                category: "Düşme riski",
                confidence: 0.94,
                description: "İşçi 3 metre üzerinde çalışıyor; paraşüt tipi emniyet kemeri ve sabitleme noktası görünmüyor.",
                action: "Çalışmayı derhal durdur. Uygun emniyet kemeri ve çift kancalı lanyard temin et. Sertifikalı sabitleme noktası belirle.",
                references: "6331/4857 · ÇSGB Yüksekte Çalışma",
                rootCause: "Yüksekte çalışma alanında toplu koruma ve ankraj planı eksik.",
                fk: FineKinneyParams(probability: 6, frequency: 6, severity: 40),
                m5: FiveByFiveParams(probability: 4, severity: 5)),
        Finding(id: 2,
                title: "Reflektif yelek eksikliği",
                category: "KKD uyumsuzluğu",
                confidence: 0.88,
                description: "Forklift trafiğinin olduğu alanda iki çalışanda yüksek görünürlüklü yelek bulunmuyor.",
                action: "Tüm çalışanlara EN ISO 20471 sınıf 2 yelek dağıt. Vardiya başında KKD kontrol formu işlet.",
                references: "EN ISO 20471",
                rootCause: "KKD dağıtımı ve vardiya başlangıç kontrolü düzenli işletilmiyor.",
                fk: FineKinneyParams(probability: 3, frequency: 6, severity: 15),
                m5: FiveByFiveParams(probability: 4, severity: 4)),
        Finding(id: 3,
                title: "Geçiş yolunda malzeme istifi",
                category: "Çevresel düzen",
                confidence: 0.81,
                description: "Yangın çıkış güzergâhı üzerinde geçici olarak istiflenmiş paletler tespit edildi.",
                action: "Paletleri 24 saat içinde belirlenmiş depolama alanına taşı. Geçiş yolunu sarı şerit ile işaretle.",
                references: "İSG-PRO-12",
                rootCause: "Geçici istif alanı ve sorumluluk düzeni net tanımlanmamış.",
                fk: FineKinneyParams(probability: 3, frequency: 3, severity: 15),
                m5: FiveByFiveParams(probability: 3, severity: 3)),
        Finding(id: 4,
                title: "Yetersiz aydınlatma",
                category: "Çevresel risk",
                confidence: 0.72,
                description: "Çalışma alanının arka kısmında 200 lüks altında ışık seviyesi gözleniyor; net algı düşük.",
                action: "Geçici LED projektör yerleştir. Kalıcı aydınlatma planı için elektrik ekibine bildir.",
                references: "EN 12464-1",
                rootCause: "Aydınlatma periyodik kontrolü ve saha değişiklikleri birlikte yönetilmiyor.",
                fk: FineKinneyParams(probability: 3, frequency: 6, severity: 7),
                m5: FiveByFiveParams(probability: 3, severity: 2)),
        Finding(id: 5,
                title: "Uyarı tabelası solmuş",
                category: "Görsel iletişim",
                confidence: 0.66,
                description: "Elektrik panosu yanındaki \"Yüksek Gerilim\" tabelasının okunabilirliği düşmüş.",
                action: "Tabelayı 1 hafta içinde yenisiyle değiştir. Periyodik kontrol planına ekle.",
                references: "TS EN 7010",
                rootCause: "Saha işaretleri için düzenli görünürlük kontrolü yapılmıyor.",
                fk: FineKinneyParams(probability: 1, frequency: 6, severity: 7),
                m5: FiveByFiveParams(probability: 2, severity: 2))
    ]
}
