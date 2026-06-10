import CryptoKit
import Foundation
import OSLog
import SwiftUI
import UIKit

enum LegalDocumentKind: String, CaseIterable, Codable, Identifiable {
    case kvkk
    case consent
    case terms
    case privacy

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .kvkk: return "KVKK"
        case .consent: return "Rıza"
        case .terms: return "Koşullar"
        case .privacy: return "Gizlilik"
        }
    }

    var title: String {
        switch self {
        case .kvkk: return "KVKK Aydınlatma Metni"
        case .consent: return "Açık Rıza Beyanı"
        case .terms: return "Kullanım Koşulları"
        case .privacy: return "Gizlilik Politikası"
        }
    }

    var bundledFileName: String {
        switch self {
        case .kvkk: return "KVKK-Aydinlatma-ve-Acik-Riza-Metni"
        case .consent: return "Acik-Riza-Beyani"
        case .terms: return "Kullanim-Kosullari"
        case .privacy: return "Gizlilik-Politikasi"
        }
    }

    var fallbackVersion: String {
        switch self {
        case .kvkk: return LegalAcceptanceService.kvkkVersion
        case .consent: return LegalAcceptanceService.aiProcessingVersion
        case .terms: return LegalAcceptanceService.termsVersion
        case .privacy: return "privacy-2026-06-10"
        }
    }

    var internalURL: URL {
        URL(string: "riskdetected://legal/\(rawValue)")!
    }

    init?(internalURL url: URL) {
        guard url.scheme == "riskdetected", url.host == "legal" else { return nil }
        let rawValue = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.init(rawValue: rawValue)
    }
}

enum LegalDocumentChangeType: String, Codable, Equatable {
    case baseline
    case info
    case materialTerms = "material_terms"
    case explicitConsent = "explicit_consent"

    var severity: Int {
        switch self {
        case .baseline: return 0
        case .info: return 1
        case .materialTerms: return 2
        case .explicitConsent: return 3
        }
    }
}

struct LegalDocument: Codable, Equatable, Identifiable {
    var id: String { "\(kind.rawValue)-\(version)" }

    let kind: LegalDocumentKind
    let title: String
    let fileName: String
    let version: String
    let updatedAt: String?
    let changeType: LegalDocumentChangeType
    let text: String
    let source: String
}

struct LegalUpdateNotice: Equatable, Identifiable {
    let documents: [LegalDocument]
    let changeType: LegalDocumentChangeType

    var id: String {
        documents
            .map { "\($0.kind.rawValue):\($0.version)" }
            .joined(separator: "|")
    }

    var primaryKind: LegalDocumentKind {
        documents.first?.kind ?? .terms
    }

    var title: String {
        switch changeType {
        case .baseline, .info:
            return "Yasal metinler güncellendi"
        case .materialTerms:
            return "Şartlarımız güncellendi"
        case .explicitConsent:
            return "Açık rıza metni güncellendi"
        }
    }

    var message: String {
        switch changeType {
        case .baseline, .info:
            return "Dilersen güncel metinleri uygulama içinde inceleyebilirsin."
        case .materialTerms:
            return "Uygulamayı kullanmaya devam ederek güncel şartları kabul etmiş olursun."
        case .explicitConsent:
            return "Yeni açık rıza kapsamını uygulama içinde inceleyip ayrıca onaylayabilirsin."
        }
    }
}

@MainActor
final class LegalDocumentService: ObservableObject {
    static let shared = LegalDocumentService()

    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "LegalDocuments")
    private static let cacheKey = "rd.legal.documents.cache.v2"
    private static let lastRefreshKey = "rd.legal.documents.last_refresh_at.v2"
    private static let manifestPath = "manifest.json"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let maxDocumentBytes = 262_144

    @Published private(set) var documents: [LegalDocumentKind: LegalDocument]
    @Published var pendingBanner: LegalUpdateNotice?
    @Published var pendingDecision: LegalUpdateNotice?

    private let supabase = SupabaseService.shared
    private let userDefaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        documents = Self.bundledDocuments()
        loadCachedDocuments()
    }

    func document(for kind: LegalDocumentKind) -> LegalDocument {
        documents[kind] ?? Self.bundledDocument(for: kind)
    }

    func refreshIfNeeded(userID: UUID?) async {
        let now = Date()
        let lastRefresh = userDefaults.object(forKey: Self.lastRefreshKey) as? Date
        let shouldRefresh = lastRefresh.map { now.timeIntervalSince($0) >= Self.refreshInterval } ?? true

        if shouldRefresh {
            let refreshed = await refreshRemoteDocuments()
            if refreshed {
                userDefaults.set(now, forKey: Self.lastRefreshKey)
            }
        }

        await evaluatePendingUpdates(userID: userID)
    }

    func recordSeen(_ notice: LegalUpdateNotice, userID: UUID?) async {
        await upsertAcknowledgements(for: notice.documents, userID: userID, action: .seen, source: "legal_update_notice")
        clear(notice)
    }

    func recordContinuedAcceptance(_ notice: LegalUpdateNotice, userID: UUID?) async {
        await upsertAcknowledgements(for: notice.documents, userID: userID, action: .continuedUseAccepted, source: "legal_update_notice")
        clear(notice)
    }

    func recordExplicitAcceptance(_ notice: LegalUpdateNotice, userID: UUID?) async {
        await upsertAcknowledgements(for: notice.documents, userID: userID, action: .explicitlyAccepted, source: "legal_update_notice")
        clear(notice)
    }

    func dismiss(_ notice: LegalUpdateNotice, userID: UUID?) async {
        await upsertAcknowledgements(for: notice.documents, userID: userID, action: .seen, source: "legal_update_notice")
        clear(notice)
    }

    private func refreshRemoteDocuments() async -> Bool {
        if await refreshWebsiteDocuments() {
            return true
        }
        return await refreshSupabaseDocuments()
    }

    private func refreshWebsiteDocuments() async -> Bool {
        do {
            let manifestData = try await downloadWebsiteLegalData(path: Self.manifestPath)
            let remoteDocuments = try await remoteDocuments(
                manifestData: manifestData,
                sourceName: "website"
            ) { path in
                try await self.downloadWebsiteLegalData(path: path)
            }
            return apply(remoteDocuments: remoteDocuments)
        } catch {
            Self.logger.warning("Website legal refresh failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func refreshSupabaseDocuments() async -> Bool {
        do {
            let manifestData = try await supabase.storage
                .from(RDConfig.Bucket.legalDocuments)
                .download(path: Self.manifestPath)
            let remoteDocuments = try await remoteDocuments(
                manifestData: manifestData,
                sourceName: "supabase"
            ) { path in
                try await self.supabase.storage
                    .from(RDConfig.Bucket.legalDocuments)
                    .download(path: path)
            }
            return apply(remoteDocuments: remoteDocuments)
        } catch {
            Self.logger.warning("Supabase legal refresh failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func remoteDocuments(
        manifestData: Data,
        sourceName: String,
        download: (String) async throws -> Data
    ) async throws -> [LegalDocumentKind: LegalDocument] {
        let manifest = try JSONDecoder().decode(LegalDocumentManifest.self, from: manifestData)
        guard manifest.locale == "tr" else { return [:] }

        var remoteDocuments: [LegalDocumentKind: LegalDocument] = [:]

        for item in manifest.documents {
            guard isSafeMarkdownPath(item.path) else {
                Self.logger.warning("Skipped unsafe \(sourceName, privacy: .public) legal document path: \(item.path, privacy: .public)")
                continue
            }

            do {
                let data = try await download(item.path)
                guard data.count <= Self.maxDocumentBytes else {
                    Self.logger.warning("Skipped oversized \(sourceName, privacy: .public) legal document: \(item.path, privacy: .public)")
                    continue
                }
                guard Self.hashMatches(data: data, expected: item.hash) else {
                    Self.logger.warning("Skipped \(sourceName, privacy: .public) legal document with hash mismatch: \(item.path, privacy: .public)")
                    continue
                }
                guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                remoteDocuments[item.kind] = LegalDocument(
                    kind: item.kind,
                    title: item.title,
                    fileName: item.path,
                    version: item.version,
                    updatedAt: item.updatedAt,
                    changeType: item.changeType,
                    text: text,
                    source: "remote"
                )
            } catch {
                Self.logger.warning("\(sourceName, privacy: .public) legal document download failed: \(item.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        return remoteDocuments
    }

    private func apply(remoteDocuments: [LegalDocumentKind: LegalDocument]) -> Bool {
        guard !remoteDocuments.isEmpty else { return false }
        documents.merge(remoteDocuments) { _, remote in remote }
        cacheDocuments()
        return true
    }

    private func downloadWebsiteLegalData(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: RDConfig.Web.legalDocumentsBaseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func evaluatePendingUpdates(userID: UUID?) async {
        guard let userID else {
            pendingBanner = nil
            pendingDecision = nil
            return
        }

        let remoteDocuments = documents.values
            .filter { $0.source == "remote" && $0.changeType != .baseline }

        guard !remoteDocuments.isEmpty else {
            pendingBanner = nil
            pendingDecision = nil
            return
        }

        do {
            let rows: [LegalDocumentAcknowledgementRow] = try await supabase.client
                .from("legal_document_acknowledgements")
                .select("document_kind,version,change_type,seen_at,continued_use_accepted_at,explicitly_accepted_at")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            let rowsByKey = Dictionary(uniqueKeysWithValues: rows.map { ("\($0.documentKind.rawValue)|\($0.version)", $0) })
            let pendingDocuments = remoteDocuments.filter { document in
                let row = rowsByKey["\(document.kind.rawValue)|\(document.version)"]
                switch document.changeType {
                case .baseline:
                    return false
                case .info:
                    return row?.seenAt == nil && row?.continuedUseAcceptedAt == nil && row?.explicitlyAcceptedAt == nil
                case .materialTerms:
                    return row?.continuedUseAcceptedAt == nil && row?.explicitlyAcceptedAt == nil
                case .explicitConsent:
                    return row?.explicitlyAcceptedAt == nil
                }
            }

            guard !pendingDocuments.isEmpty else {
                pendingBanner = nil
                pendingDecision = nil
                return
            }

            let strongestType = pendingDocuments
                .map(\.changeType)
                .max { $0.severity < $1.severity } ?? .info
            let notice = LegalUpdateNotice(documents: pendingDocuments, changeType: strongestType)

            if strongestType == .info {
                pendingBanner = notice
                pendingDecision = nil
            } else {
                pendingBanner = nil
                pendingDecision = notice
            }
        } catch {
            Self.logger.warning("Legal acknowledgement lookup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsertAcknowledgements(
        for documents: [LegalDocument],
        userID: UUID?,
        action: LegalAcknowledgementAction,
        source: String
    ) async {
        guard let userID else { return }
        let now = Self.isoDate(Date())

        do {
            for document in documents {
                switch action {
                case .seen:
                    try await upsert(LegalSeenPayload(
                        userID: userID.uuidString,
                        documentKind: document.kind.rawValue,
                        version: document.version,
                        changeType: document.changeType.rawValue,
                        seenAt: now,
                        source: source,
                        appVersion: Self.appVersion,
                        deviceID: Self.deviceID
                    ))
                case .continuedUseAccepted:
                    try await upsert(LegalContinuedAcceptancePayload(
                        userID: userID.uuidString,
                        documentKind: document.kind.rawValue,
                        version: document.version,
                        changeType: document.changeType.rawValue,
                        seenAt: now,
                        continuedUseAcceptedAt: now,
                        source: source,
                        appVersion: Self.appVersion,
                        deviceID: Self.deviceID
                    ))
                case .explicitlyAccepted:
                    try await upsert(LegalExplicitAcceptancePayload(
                        userID: userID.uuidString,
                        documentKind: document.kind.rawValue,
                        version: document.version,
                        changeType: document.changeType.rawValue,
                        seenAt: now,
                        explicitlyAcceptedAt: now,
                        source: source,
                        appVersion: Self.appVersion,
                        deviceID: Self.deviceID
                    ))
                }
            }
        } catch {
            Self.logger.error("Legal acknowledgement upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsert<T: Encodable>(_ payload: T) async throws {
        try await supabase.client
            .from("legal_document_acknowledgements")
            .upsert(payload, onConflict: "user_id,document_kind,version")
            .execute()
    }

    private func clear(_ notice: LegalUpdateNotice) {
        if pendingBanner == notice {
            pendingBanner = nil
        }
        if pendingDecision == notice {
            pendingDecision = nil
        }
    }

    private func loadCachedDocuments() {
        guard let data = userDefaults.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([LegalDocument].self, from: data)
        else { return }

        documents.merge(Dictionary(uniqueKeysWithValues: cached.map { ($0.kind, $0) })) { _, cached in cached }
    }

    private func cacheDocuments() {
        let remoteDocuments = documents.values.filter { $0.source == "remote" }
        guard let data = try? JSONEncoder().encode(remoteDocuments) else { return }
        userDefaults.set(data, forKey: Self.cacheKey)
    }

    private func isSafeMarkdownPath(_ path: String) -> Bool {
        path.hasPrefix("tr/") &&
            path.hasSuffix(".md") &&
            !path.contains("..") &&
            !path.hasPrefix("/") &&
            !path.contains("\\")
    }

    private static func bundledDocuments() -> [LegalDocumentKind: LegalDocument] {
        Dictionary(uniqueKeysWithValues: LegalDocumentKind.allCases.map { ($0, bundledDocument(for: $0)) })
    }

    private static func bundledDocument(for kind: LegalDocumentKind) -> LegalDocument {
        LegalDocument(
            kind: kind,
            title: kind.title,
            fileName: "\(kind.bundledFileName).md",
            version: kind.fallbackVersion,
            updatedAt: nil,
            changeType: .baseline,
            text: loadBundledText(fileName: kind.bundledFileName),
            source: "bundle"
        )
    }

    private static func loadBundledText(fileName: String) -> String {
        let nestedURL = Bundle.main.url(
            forResource: fileName,
            withExtension: "md",
            subdirectory: "LegalDocuments"
        )
        let flatURL = Bundle.main.url(forResource: fileName, withExtension: "md")

        guard let url = nestedURL ?? flatURL else {
            return "Belge yüklenemedi. Lütfen daha sonra tekrar deneyin."
        }

        return (try? String(contentsOf: url, encoding: .utf8))
            ?? "Belge okunamadı. Lütfen daha sonra tekrar deneyin."
    }

    private static func hashMatches(data: Data, expected: String) -> Bool {
        let normalized = expected
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "sha256-", with: "")
        guard !normalized.isEmpty else { return false }

        let digest = Data(SHA256.hash(data: data))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let base64 = digest.base64EncodedString()
        return normalized.caseInsensitiveCompare(hex) == .orderedSame || normalized == base64
    }

    private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }

    private static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}

private enum LegalAcknowledgementAction {
    case seen
    case continuedUseAccepted
    case explicitlyAccepted
}

private struct LegalDocumentManifest: Decodable {
    let locale: String
    let documents: [LegalDocumentManifestItem]
}

private struct LegalDocumentManifestItem: Decodable {
    let kind: LegalDocumentKind
    let title: String
    let version: String
    let path: String
    let hash: String
    let updatedAt: String
    let changeType: LegalDocumentChangeType

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case version
        case path
        case hash
        case updatedAt = "updated_at"
        case changeType = "change_type"
    }
}

private struct LegalDocumentAcknowledgementRow: Decodable {
    let documentKind: LegalDocumentKind
    let version: String
    let changeType: LegalDocumentChangeType
    let seenAt: String?
    let continuedUseAcceptedAt: String?
    let explicitlyAcceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case documentKind = "document_kind"
        case version
        case changeType = "change_type"
        case seenAt = "seen_at"
        case continuedUseAcceptedAt = "continued_use_accepted_at"
        case explicitlyAcceptedAt = "explicitly_accepted_at"
    }
}

private struct LegalSeenPayload: Encodable {
    let userID: String
    let documentKind: String
    let version: String
    let changeType: String
    let seenAt: String
    let source: String
    let appVersion: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case documentKind = "document_kind"
        case version
        case changeType = "change_type"
        case seenAt = "seen_at"
        case source
        case appVersion = "app_version"
        case deviceID = "device_id"
    }
}

private struct LegalContinuedAcceptancePayload: Encodable {
    let userID: String
    let documentKind: String
    let version: String
    let changeType: String
    let seenAt: String
    let continuedUseAcceptedAt: String
    let source: String
    let appVersion: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case documentKind = "document_kind"
        case version
        case changeType = "change_type"
        case seenAt = "seen_at"
        case continuedUseAcceptedAt = "continued_use_accepted_at"
        case source
        case appVersion = "app_version"
        case deviceID = "device_id"
    }
}

private struct LegalExplicitAcceptancePayload: Encodable {
    let userID: String
    let documentKind: String
    let version: String
    let changeType: String
    let seenAt: String
    let explicitlyAcceptedAt: String
    let source: String
    let appVersion: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case documentKind = "document_kind"
        case version
        case changeType = "change_type"
        case seenAt = "seen_at"
        case explicitlyAcceptedAt = "explicitly_accepted_at"
        case source
        case appVersion = "app_version"
        case deviceID = "device_id"
    }
}
