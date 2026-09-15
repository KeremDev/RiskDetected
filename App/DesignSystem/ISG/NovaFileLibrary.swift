import Foundation

/// Where one filed document has actually got to. The value is always the
/// server's: it is worked out at read time from the upload's own state and from
/// whether a cleared asset exists, so nothing on this side recomputes one.
enum NovaFileState: String, CaseIterable, Identifiable, Equatable {
    case pending, uploaded, scanning, clean, rejected
    case scanFailed = "scan_failed"
    case promoted, expired
    var id: String { rawValue }

    /// The archive holds this file and the expert can open it.
    var isFiled: Bool { self == .promoted }
    /// The upload is still on its way through the checks.
    var isWorking: Bool { [.pending, .uploaded, .scanning, .clean].contains(self) }
    /// Nothing will arrive from this one without starting again.
    var isStopped: Bool { [.rejected, .scanFailed, .expired].contains(self) }
}

/// Which company heading a filed document belongs under. The mapping is the
/// server's, so the company page and the library can never disagree.
struct NovaFileCategory: Identifiable, Equatable {
    let code: String
    let ordinal: Int
    /// A `NovaCompanySection` raw value.
    let section: String
    var id: String { code }
}

/// What the server will accept, declared at runtime. An OS picker that offers a
/// type is a convenience; this is the authority.
struct NovaFileAcceptance: Equatable {
    var purpose: String
    var extensions: [String]
    var maxBytes: Int
    /// The plan's size candidates have not passed their cost gate yet, and the
    /// server says so rather than presenting them as a granted allowance.
    var limitApproved: Bool
}

/// What cleared the archive's files, and what that does and does not mean.
struct NovaFileAssurance: Equatable {
    var scanners: [String] = []
    /// False whenever no registered scanner detects malware. Unknown is not yes.
    var malwareScanningAvailable = false
}

struct NovaFileEntry: Identifiable, Equatable {
    let id: UUID
    /// The underlying asset once a clean upload exists for this entry — the
    /// value a module's own publish call (e.g. emergency plan) attaches.
    var assetID: UUID?
    var companyID: UUID?
    var companyName: String?
    var category: String
    /// The company heading this file is filed under, as the server maps it.
    var section: String?
    var title: String
    var fileName: String
    var note: String?
    var version: Int
    /// The server's answer, never derived here.
    var state: NovaFileState
    var rejectionCode: String?
    var fileExtension: String
    var declaredBytes: Int
    var receivedBytes: Int?
    var detectedType: String?
    /// Offered only while the upload has not started, and only by the server.
    var uploadBucket: String?
    var uploadPath: String?
    /// Present only when a cleared asset exists for these bytes.
    var downloadBucket: String?
    var downloadPath: String?
    var scanner: String?
    var scanFinding: String?
    var assurance: String?
    /// What the server says about this row. It never claims more than ran.
    var malwareScanned: Bool = false
    var createdAt: String?

    var canDownload: Bool { downloadPath != nil && downloadBucket != nil }
    var bytes: Int { receivedBytes ?? declaredBytes }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [title, fileName, category, companyName ?? "", note ?? ""]
            .contains { $0.lowercased().contains(needle) }
    }
}

/// One company's share of the archive, as the server counted it.
struct NovaFileCompanySummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let total: Int
    let counts: [NovaFileState: Int]
    func count(_ state: NovaFileState) -> Int { counts[state] ?? 0 }
    var filed: Int { count(.promoted) }
    /// What this company is carrying that the expert has to look at.
    var needsAttention: Int {
        NovaFileState.allCases.filter(\.isStopped).reduce(0) { $0 + count($1) }
    }
}

/// The whole account in one answer: the tally, the per-company summary, the
/// per-category tally and one page of rows.
struct NovaFileLibrary: Equatable {
    var counts: [NovaFileState: Int] = [:]
    var companies: [NovaFileCompanySummary] = []
    /// Per category, following the company filter alone, so the company page
    /// reads every heading from one call instead of asking once per heading.
    var categoryCounts: [String: [NovaFileState: Int]] = [:]
    var rows: [NovaFileEntry] = []
    var total = 0
    var hasMore = false
    var limit = 10
    var offset = 0
    var assurance = NovaFileAssurance()

    func count(_ state: NovaFileState) -> Int { counts[state] ?? 0 }
    var filed: Int { count(.promoted) }
    var working: Int { NovaFileState.allCases.filter(\.isWorking).reduce(0) { $0 + count($1) } }
    var stopped: Int { NovaFileState.allCases.filter(\.isStopped).reduce(0) { $0 + count($1) } }
    var tracked: Int { NovaFileState.allCases.reduce(0) { $0 + count($1) } }

    /// What one company-page heading is carrying, summed over its own categories.
    func counts(forCategories categories: [String]) -> [NovaFileState: Int] {
        var result: [NovaFileState: Int] = [:]
        for category in categories {
            for (state, value) in categoryCounts[category] ?? [:] { result[state, default: 0] += value }
        }
        return result
    }
}

/// The four counters the archive page shows, and the rows each one covers. The
/// same words are filter values the server accepts, so tapping a counter
/// narrows to exactly the rows that counter counted.
enum NovaFileGroup: String, CaseIterable, Identifiable {
    case filed, working, rejected, unchecked
    var id: String { rawValue }

    var states: [NovaFileState] {
        switch self {
        case .filed: return [.promoted]
        case .working: return [.pending, .uploaded, .scanning, .clean]
        case .rejected: return [.rejected]
        case .unchecked: return [.scanFailed, .expired]
        }
    }
    var title: String {
        switch self {
        case .filed: return RDLocalization.string("localizable.nova.file.group.filed", table: .localizable, fallback: "Dosyada")
        case .working: return RDLocalization.string("localizable.nova.file.group.working", table: .localizable, fallback: "İşleniyor")
        case .rejected: return RDLocalization.string("localizable.nova.file.group.rejected", table: .localizable, fallback: "Kabul edilmedi")
        case .unchecked: return RDLocalization.string("localizable.nova.file.group.unchecked", table: .localizable, fallback: "Denetlenemedi")
        }
    }
    /// A finding about the count, never an instruction.
    var footer: String {
        switch self {
        case .filed: return RDLocalization.string("localizable.nova.file.group.filed.footer", table: .localizable, fallback: "arşivde")
        case .working: return RDLocalization.string("localizable.nova.file.group.working.footer", table: .localizable, fallback: "denetimde")
        case .rejected: return RDLocalization.string("localizable.nova.file.group.rejected.footer", table: .localizable, fallback: "içerik nedeniyle")
        case .unchecked: return RDLocalization.string("localizable.nova.file.group.unchecked.footer", table: .localizable, fallback: "denetim bitmedi")
        }
    }
    var symbol: String {
        switch self {
        case .filed: return "checkmark.circle"
        case .working: return "arrow.up.circle"
        case .rejected: return "exclamationmark.triangle"
        case .unchecked: return "questionmark.circle"
        }
    }
    static func of(_ state: NovaFileState) -> NovaFileGroup {
        allCases.first { $0.states.contains(state) } ?? .unchecked
    }
}

extension NovaFileLibrary {
    func count(_ group: NovaFileGroup) -> Int { group.states.reduce(0) { $0 + count($1) } }
}
extension NovaFileCompanySummary {
    func count(_ group: NovaFileGroup) -> Int { group.states.reduce(0) { $0 + count($1) } }
}

/// Which categories a company heading holds, worked out from the server's own
/// mapping rather than from a second list kept on this side.
enum NovaFileSectionMap {
    static func categories(for section: NovaCompanySection, in catalogue: [NovaFileCategory]) -> [String] {
        catalogue.filter { $0.section == section.rawValue }.map(\.code)
    }
}

/// What the library page is asking for right now.
struct NovaFileQuery: Equatable {
    var query = ""
    /// Either one exact state or one of the four counter groups; the server
    /// accepts both words and the page only ever sends one of them.
    var state: String?
    var company: UUID?
    var category: String?
    /// The page shows ten rows at a time and asks for more on request.
    var limit = 10
    var offset = 0
}

/// What the file form collects before an upload is opened.
struct NovaFileDraft: Equatable {
    var title = ""
    var category: String?
    var note = ""
    /// Chosen on the device. The name is for recognition; the server decides the
    /// real type from the bytes.
    var fileName = ""
    var fileExtension = ""
    var bytes = 0
    var sha256 = ""

    var isReady: Bool {
        guard category != nil, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !fileExtension.isEmpty && bytes > 0 && sha256.count == 64
    }
}

enum NovaFileFailure: Error, Equatable {
    case denied, validation, versionConflict, unavailable, planRequired, conflict
    case unsupportedFormat, tooLarge, uploadFailed, notCancellable, inspectionUnavailable
}

/// The words the library uses, in one place, so a state never reads as more
/// than what actually happened to the file.
enum NovaFileWords {
    static func state(_ state: NovaFileState) -> String {
        switch state {
        case .pending: return RDLocalization.string("localizable.nova.file.state.pending", table: .localizable, fallback: "Yükleniyor")
        case .uploaded, .scanning: return RDLocalization.string("localizable.nova.file.state.checking", table: .localizable, fallback: "Denetleniyor")
        case .clean: return RDLocalization.string("localizable.nova.file.state.filing", table: .localizable, fallback: "Arşivleniyor")
        case .promoted: return RDLocalization.string("localizable.nova.file.state.filed", table: .localizable, fallback: "Dosyada")
        case .rejected: return RDLocalization.string("localizable.nova.file.state.rejected", table: .localizable, fallback: "Kabul edilmedi")
        case .scanFailed: return RDLocalization.string("localizable.nova.file.state.unchecked", table: .localizable, fallback: "Denetlenemedi")
        case .expired: return RDLocalization.string("localizable.nova.file.state.expired", table: .localizable, fallback: "Süre doldu")
        }
    }

    /// The short line under a counter. A finding, never an instruction.
    static func footer(_ state: NovaFileState) -> String {
        switch state {
        case .promoted: return RDLocalization.string("localizable.nova.file.footer.filed", table: .localizable, fallback: "arşivde")
        case .pending, .uploaded, .scanning, .clean:
            return RDLocalization.string("localizable.nova.file.footer.working", table: .localizable, fallback: "işleniyor")
        case .rejected: return RDLocalization.string("localizable.nova.file.footer.rejected", table: .localizable, fallback: "içerik nedeniyle")
        case .scanFailed: return RDLocalization.string("localizable.nova.file.footer.unchecked", table: .localizable, fallback: "denetim bitmedi")
        case .expired: return RDLocalization.string("localizable.nova.file.footer.expired", table: .localizable, fallback: "süresi geçti")
        }
    }

    static func symbol(_ state: NovaFileState) -> String {
        switch state {
        case .promoted: return "checkmark.circle"
        case .pending, .uploaded, .scanning, .clean: return "arrow.up.circle"
        case .rejected: return "exclamationmark.triangle"
        case .scanFailed: return "questionmark.circle"
        case .expired: return "clock"
        }
    }

    /// Why a file was not accepted, in the expert's own terms. An unrecognised
    /// code is reported as unrecognised rather than smoothed into a calm one.
    static func rejection(_ code: String?) -> String {
        switch code {
        case "UNSUPPORTED_FORMAT": return RDLocalization.string("localizable.nova.file.reason.format", table: .localizable, fallback: "Bu dosya türü kabul edilmiyor.")
        case "SIZE_LIMIT": return RDLocalization.string("localizable.nova.file.reason.size", table: .localizable, fallback: "Dosya boyutu sınırın dışında.")
        case "HASH_MISMATCH": return RDLocalization.string("localizable.nova.file.reason.changed", table: .localizable, fallback: "Ulaşan dosya, gönderilen dosyayla aynı değil.")
        case "MIME_MISMATCH": return RDLocalization.string("localizable.nova.file.reason.type", table: .localizable, fallback: "Dosyanın gerçek türü adıyla uyuşmuyor.")
        case "SCAN_REJECTED": return RDLocalization.string("localizable.nova.file.reason.content", table: .localizable, fallback: "Dosya, biçim denetiminden geçmedi.")
        case "SCAN_UNAVAILABLE": return RDLocalization.string("localizable.nova.file.reason.unavailable", table: .localizable, fallback: "Denetim tamamlanamadı. Dosya arşive alınmadı.")
        case "EXPIRED": return RDLocalization.string("localizable.nova.file.reason.expired", table: .localizable, fallback: "Yükleme süresi doldu.")
        case .some(let other):
            return RDLocalization.string("localizable.nova.file.reason.unknown", table: .localizable,
                                         fallback: "Dosya kabul edilmedi.") + " (\(other))"
        case nil: return ""
        }
    }

    /// What the format inspector found, when it named something. These are the
    /// inspector's own codes and they are shown as such.
    static func finding(_ code: String?) -> String {
        switch code {
        case "MACRO_PRESENT": return RDLocalization.string("localizable.nova.file.finding.macro", table: .localizable, fallback: "Belgede makro var.")
        case "ACTIVE_CONTENT": return RDLocalization.string("localizable.nova.file.finding.active", table: .localizable, fallback: "Belgede çalışan içerik var.")
        case "ENCRYPTED_FILE": return RDLocalization.string("localizable.nova.file.finding.encrypted", table: .localizable, fallback: "Dosya şifreli; içeriği denetlenemiyor. Şifresiz nüsha yükleyin.")
        case "EMBEDDED_FILE": return RDLocalization.string("localizable.nova.file.finding.embedded", table: .localizable, fallback: "Belgeye başka bir dosya gömülü.")
        case "EXTERNAL_REFERENCE": return RDLocalization.string("localizable.nova.file.finding.external", table: .localizable, fallback: "Belge dışarıdan içerik çağırıyor.")
        case "XML_ENTITY": return RDLocalization.string("localizable.nova.file.finding.entity", table: .localizable, fallback: "Belgede güvenli olmayan XML tanımı var.")
        case "ARCHIVE_BOMB": return RDLocalization.string("localizable.nova.file.finding.bomb", table: .localizable, fallback: "Dosya, açıldığında sınırların çok üstüne çıkıyor.")
        case "PATH_TRAVERSAL": return RDLocalization.string("localizable.nova.file.finding.path", table: .localizable, fallback: "Belge paketinde geçersiz dosya yolu var.")
        case "IMAGE_TOO_LARGE": return RDLocalization.string("localizable.nova.file.finding.pixels", table: .localizable, fallback: "Görselin çözünürlüğü sınırın üstünde.")
        case "TYPE_MISMATCH": return RDLocalization.string("localizable.nova.file.finding.mismatch", table: .localizable, fallback: "Dosyanın gerçek türü uzantısıyla uyuşmuyor.")
        case "MALFORMED_FILE": return RDLocalization.string("localizable.nova.file.finding.broken", table: .localizable, fallback: "Dosya okunamadı.")
        case .some(let other): return other
        case nil: return ""
        }
    }

    static func category(_ code: String) -> String {
        switch code {
        case "risk_assessment": return RDLocalization.string("localizable.nova.file.category.risk", table: .localizable, fallback: "Risk değerlendirmesi")
        case "emergency_plan": return RDLocalization.string("localizable.nova.file.category.emergency", table: .localizable, fallback: "Acil durum planı")
        case "training_material": return RDLocalization.string("localizable.nova.file.category.training", table: .localizable, fallback: "Eğitim belgesi")
        case "inspection_report": return RDLocalization.string("localizable.nova.file.category.inspection", table: .localizable, fallback: "Periyodik kontrol raporu")
        case "measurement_report": return RDLocalization.string("localizable.nova.file.category.measurement", table: .localizable, fallback: "Ortam ölçüm raporu")
        case "accident_record": return RDLocalization.string("localizable.nova.file.category.accident", table: .localizable, fallback: "İş kazası kaydı")
        case "board_document": return RDLocalization.string("localizable.nova.file.category.board", table: .localizable, fallback: "Kurul belgesi")
        case "handover_form": return RDLocalization.string("localizable.nova.file.category.handover", table: .localizable, fallback: "Zimmet formu")
        case "personnel_document": return RDLocalization.string("localizable.nova.file.category.personnel", table: .localizable, fallback: "Personel belgesi")
        case "contract": return RDLocalization.string("localizable.nova.file.category.contract", table: .localizable, fallback: "Sözleşme")
        case "permit_form": return RDLocalization.string("localizable.nova.file.category.permit", table: .localizable, fallback: "Çalışma izni formu")
        case "contractor_document": return RDLocalization.string("localizable.nova.file.category.contractor", table: .localizable, fallback: "Taşeron belgesi")
        case "other": return RDLocalization.string("localizable.nova.file.category.other", table: .localizable, fallback: "Diğer")
        default: return code
        }
    }

    static func size(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB"]
        var value = Double(bytes), index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return String(format: index == 0 ? "%.0f %@" : "%.1f %@", value, units[index])
    }
}
