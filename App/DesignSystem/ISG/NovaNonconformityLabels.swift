import Foundation

/// One place for the words the nonconformity surfaces share, so a band never
/// reads as one thing on the analysis screen and another on the list.
enum NovaNonconformityWords {
    static func severity(_ value: NovaNonconformitySeverity) -> String { band(value.rawValue) }

    static func band(_ value: String?) -> String {
        switch value {
        case "critical": return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
        case "high": return RDLocalization.string("localizable.nova.nonconformity.severity.high", table: .localizable, fallback: "Yüksek")
        case "medium": return RDLocalization.string("localizable.nova.nonconformity.severity.medium", table: .localizable, fallback: "Orta")
        case "low": return RDLocalization.string("localizable.nova.nonconformity.severity.low", table: .localizable, fallback: "Düşük")
        default: return RDLocalization.string("localizable.nova.bridge.band.unknown", table: .localizable, fallback: "Bilinmiyor")
        }
    }

    /// An unreadable band is its own tone. It is never painted as the calmest one.
    static func tone(_ value: String?) -> NovaStatus {
        switch value {
        case "critical", "high": return .danger
        case "medium": return .warning
        case "low": return .neutral
        default: return .info
        }
    }

    static func state(_ value: String) -> String {
        switch value {
        case "open": return RDLocalization.string("localizable.nova.nonconformity.state.open", table: .localizable, fallback: "Açık")
        case "assigned": return RDLocalization.string("localizable.nova.nonconformity.state.assigned", table: .localizable, fallback: "Atandı")
        case "in_progress": return RDLocalization.string("localizable.nova.nonconformity.state.in.progress", table: .localizable, fallback: "Devam ediyor")
        case "pending_verification": return RDLocalization.string("localizable.nova.nonconformity.state.pending", table: .localizable, fallback: "Doğrulama bekliyor")
        case "closed": return RDLocalization.string("localizable.nova.nonconformity.state.closed", table: .localizable, fallback: "Kapandı")
        case "reopened": return RDLocalization.string("localizable.nova.nonconformity.state.reopened", table: .localizable, fallback: "Yeniden açıldı")
        case "cancelled": return RDLocalization.string("localizable.nova.nonconformity.state.cancelled", table: .localizable, fallback: "İptal edildi")
        default: return RDLocalization.string("localizable.nova.nonconformity.state.draft", table: .localizable, fallback: "Taslak")
        }
    }

    static func recordKind(_ value: NovaNonconformityRecordKind) -> String {
        switch value {
        case .nonconformity: return RDLocalization.string("localizable.nova.nonconformity.kind.nonconformity", table: .localizable, fallback: "Uygunsuzluk")
        case .improvement: return RDLocalization.string("localizable.nova.nonconformity.kind.improvement", table: .localizable, fallback: "Geliştirme önerisi")
        }
    }

    static func method(_ value: NovaRiskMethod) -> String {
        switch value {
        case .fineKinney: return RDLocalization.string("localizable.nova.risk.method.fine.kinney", table: .localizable, fallback: "Fine-Kinney")
        case .matrix5x5: return RDLocalization.string("localizable.nova.risk.method.matrix", table: .localizable, fallback: "5×5 Matris")
        }
    }

    /// A score with no trailing zeros. 270 reads as 270, 1.2 reads as 1,2.
    static func score(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func failure(_ value: NovaNonconformityFailure) -> String {
        switch value {
        case .denied:
            return RDLocalization.string("localizable.nova.nonconformity.error.denied", table: .localizable,
                fallback: "Bu firma için uygunsuzluk kaydına erişiminiz yok.")
        case .severityUnknown:
            return RDLocalization.string("localizable.nova.nonconformity.error.severity.unknown", table: .localizable,
                fallback: "Bulgunun risk bandı okunamadı. Önem derecesini kendiniz seçin.")
        case .conflict:
            return RDLocalization.string("localizable.nova.nonconformity.error.conflict", table: .localizable,
                fallback: "Kayıt bu sırada değişti. Listeyi yenileyip tekrar deneyin.")
        case .riskInputIncomplete:
            return RDLocalization.string("localizable.nova.nonconformity.error.risk.incomplete", table: .localizable,
                fallback: "Seçtiğiniz risk metodunun tüm değerlerini girin.")
        case .validation, .payloadRejected:
            return RDLocalization.string("localizable.nova.nonconformity.error.validation", table: .localizable,
                fallback: "Gönderilen bilgiler kabul edilmedi. Alanları kontrol edin.")
        case .unavailable:
            return RDLocalization.string("localizable.nova.nonconformity.error.unavailable", table: .localizable,
                fallback: "Uygunsuzluk modülü şu anda kullanılamıyor.")
        }
    }
}
