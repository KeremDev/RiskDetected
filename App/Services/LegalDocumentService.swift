import CryptoKit
import Foundation
import OSLog
import SwiftUI
import UIKit

struct RDLegalSetAuditMetadata: Equatable {
    let documentSetID: String
    let locale: String
    let manifestChecksum: String
}

enum RDLegalReleaseGate {
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let documentSetID: String
        let locale: String
        let releaseStatus: String
        let counselReviewStatus: String
        let reviewedBy: String?
        let reviewedAt: String?
        let publicURLsVerifiedAt: String?
        let publicURLs: [String: String]?
        let documents: [Document]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case documentSetID = "document_set_id"
            case locale
            case releaseStatus = "release_status"
            case counselReviewStatus = "counsel_review_status"
            case reviewedBy = "reviewed_by"
            case reviewedAt = "reviewed_at"
            case publicURLsVerifiedAt = "public_urls_verified_at"
            case publicURLs = "public_urls"
            case documents
        }
    }

    private struct Document: Decodable {
        let kind: String
        let path: String
        let hash: String
    }

    static var englishAuthAndPurchaseApproved: Bool {
        guard let manifestURL = bundledURL(
            fileName: "manifest",
            extension: "json",
            subdirectory: "LegalDocuments/en"
        ),
        let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            return false
        }

        guard manifest.schemaVersion == 1,
              manifest.documentSetID == RDLegalDocumentSetID.englishGlobalV1.rawValue,
              manifest.locale == "en",
              manifest.releaseStatus == "approved",
              manifest.counselReviewStatus == "approved",
              manifest.reviewedBy?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              manifest.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              manifest.publicURLsVerifiedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return false
        }

        let requiredKinds = Set(["terms", "privacy", "consent"])
        guard Set(manifest.documents.map(\.kind)) == requiredKinds else {
            return false
        }

        let requiredURLKeys = Set(["terms", "privacy", "ai_data_processing_notice"])
        guard let publicURLs = manifest.publicURLs,
              Set(publicURLs.keys) == requiredURLKeys,
              publicURLs.values.allSatisfy({ raw in
                  guard let url = URL(string: raw) else { return false }
                  return url.scheme == "https"
                      && url.host?.lowercased() == "riskdetected.com"
                      && url.path != "/"
              })
        else {
            return false
        }

        return manifest.documents.allSatisfy { document in
            guard document.path.hasPrefix("en/"),
                  !document.path.contains(".."),
                  let fileName = document.path.split(separator: "/").last.map(String.init),
                  let fileExtension = fileName.split(separator: ".").last.map(String.init),
                  fileName.count > fileExtension.count + 1,
                  let url = bundledURL(
                    fileName: String(fileName.dropLast(fileExtension.count + 1)),
                    extension: fileExtension,
                    subdirectory: "LegalDocuments/en"
                  ),
                  let data = try? Data(contentsOf: url)
            else {
                return false
            }
            let digest = Data(SHA256.hash(data: data))
                .map { String(format: "%02x", $0) }
                .joined()
            return digest.caseInsensitiveCompare(document.hash) == .orderedSame
        }
    }

    static func requireAuthAndPurchaseAccess(language: RDLanguage = .current) throws {
        guard language == .turkish || englishAuthAndPurchaseApproved else {
            throw NSError(
                domain: "RiskDetected.LegalReleaseGate",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: RDLocalization.string(
                        "legal.english_unavailable.message",
                        table: .legal,
                        fallback: "İngilizce Kullanım Koşulları ve Gizlilik Politikası hukuk ve dil incelemesi tamamlanana kadar bu sürümde yayımlanmaz."
                    )
                ]
            )
        }
    }

    static func acceptanceAuditMetadata(
        language: RDLanguage = .current
    ) -> RDLegalSetAuditMetadata? {
        switch language {
        case .english:
            guard let url = bundledURL(
                fileName: "manifest",
                extension: "json",
                subdirectory: "LegalDocuments/en"
            ),
            let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            return RDLegalSetAuditMetadata(
                documentSetID: RDLegalDocumentSetID.englishGlobalV1.rawValue,
                locale: RDLanguage.english.rawValue,
                manifestChecksum: sha256Hex(data)
            )
        case .turkish:
            let sources = [
                ("kvkk", LegalAcceptanceService.kvkkVersion, "KVKK-Aydinlatma-ve-Acik-Riza-Metni"),
                ("terms", LegalAcceptanceService.termsVersion, "Kullanim-Kosullari"),
                ("privacy", "privacy-2026-06-10", "Gizlilik-Politikasi"),
                ("consent", LegalAcceptanceService.aiProcessingVersion, "Acik-Riza-Beyani"),
            ]
            let entries = sources.compactMap { kind, version, fileName -> String? in
                guard let url = bundledURL(
                    fileName: fileName,
                    extension: "md",
                    subdirectory: "LegalDocuments"
                ),
                let data = try? Data(contentsOf: url)
                else {
                    return nil
                }
                return "\(kind)|\(version)|\(sha256Hex(data))"
            }
            guard entries.count == sources.count,
                  let canonical = entries.sorted().joined(separator: "\n").data(using: .utf8)
            else {
                return nil
            }
            return RDLegalSetAuditMetadata(
                documentSetID: RDLegalDocumentSetID.turkeyCurrent.rawValue,
                locale: RDLanguage.turkish.rawValue,
                manifestChecksum: sha256Hex(canonical)
            )
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func bundledURL(
        fileName: String,
        extension fileExtension: String,
        subdirectory: String
    ) -> URL? {
        Bundle.main.url(
            forResource: fileName,
            withExtension: fileExtension,
            subdirectory: subdirectory
        )
        ?? Bundle.main.url(
            forResource: fileName,
            withExtension: fileExtension,
            subdirectory: subdirectory.replacingOccurrences(of: "LegalDocuments/", with: "")
        )
        ?? Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    }
}

enum LegalDocumentKind: String, CaseIterable, Codable, Identifiable {
    case kvkk
    case consent
    case terms
    case privacy

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .kvkk:
            return RDLocalization.string(
                "legal.document.kvkk.short_title",
                table: .legal,
                fallback: "KVKK"
            )
        case .consent:
            return RDLocalization.string(
                "legal.document.consent.short_title",
                table: .legal,
                fallback: "Rıza"
            )
        case .terms:
            return RDLocalization.string(
                "legal.document.terms.short_title",
                table: .legal,
                fallback: "Koşullar"
            )
        case .privacy:
            return RDLocalization.string(
                "legal.document.privacy.short_title",
                table: .legal,
                fallback: "Gizlilik"
            )
        }
    }

    var title: String {
        switch self {
        case .kvkk:
            return RDLocalization.string(
                "legal.document.kvkk.title",
                table: .legal,
                fallback: "KVKK Aydınlatma Metni"
            )
        case .consent:
            return RDLocalization.string(
                "legal.document.consent.title",
                table: .legal,
                fallback: "Açık Rıza Beyanı"
            )
        case .terms:
            return RDLocalization.string(
                "legal.document.terms.title",
                table: .legal,
                fallback: "Kullanım Koşulları"
            )
        case .privacy:
            return RDLocalization.string(
                "legal.document.privacy.title",
                table: .legal,
                fallback: "Gizlilik Politikası"
            )
        }
    }

    var bundledFileName: String {
        switch self {
        case .kvkk: return RDLocalization.string("legal.legal.document.service.kvkk.aydinlatma.ve.acik.riza.metni.1f045e54", table: .legal, fallback: "KVKK-Aydinlatma-ve-Acik-Riza-Metni")
        case .consent: return RDLocalization.string("legal.legal.document.service.acik.riza.beyani.214a6512", table: .legal, fallback: "Acik-Riza-Beyani")
        case .terms: return RDLocalization.string("legal.legal.document.service.kullanim.kosullari.6d55b3b3", table: .legal, fallback: "Kullanim-Kosullari")
        case .privacy: return RDLocalization.string("legal.legal.document.service.gizlilik.politikasi.84449d4a", table: .legal, fallback: "Gizlilik-Politikasi")
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
    case materialPrivacy = "material_privacy"
    case explicitConsent = "explicit_consent"

    var severity: Int {
        switch self {
        case .baseline: return 0
        case .info: return 1
        case .materialTerms, .materialPrivacy: return 2
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
    let checksum: String?
}

struct LegalUpdateNotice: Equatable, Identifiable {
    let documents: [LegalDocument]
    let changeType: LegalDocumentChangeType

    var id: String {
        documents
            .map {
                [
                    $0.kind.rawValue,
                    $0.version,
                    $0.checksum ?? "no-checksum",
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
    }

    var primaryKind: LegalDocumentKind {
        documents.first?.kind ?? .terms
    }

    var title: String {
        switch changeType {
        case .baseline, .info:
            return RDLocalization.string(
                "legal.update.info.title",
                table: .legal,
                fallback: "Yasal metinler güncellendi"
            )
        case .materialTerms:
            return RDLocalization.string(
                "legal.update.material.title",
                table: .legal,
                fallback: "Şartlarımız güncellendi"
            )
        case .materialPrivacy:
            return RDLocalization.string(
                "legal.update.privacy.title",
                table: .legal,
                fallback: "Gizlilik politikamız güncellendi"
            )
        case .explicitConsent:
            return RDLocalization.string(
                "legal.update.consent.title",
                table: .legal,
                fallback: "Açık rıza metni güncellendi"
            )
        }
    }

    var message: String {
        switch changeType {
        case .baseline, .info:
            return RDLocalization.string(
                "legal.update.info.message",
                table: .legal,
                fallback: "Dilersen güncel metinleri uygulama içinde inceleyebilirsin."
            )
        case .materialTerms:
            return RDLocalization.string(
                "legal.update.material.message",
                table: .legal,
                fallback: "Uygulamayı kullanmaya devam ederek güncel şartları kabul etmiş olursun."
            )
        case .materialPrivacy:
            return RDLocalization.string(
                "legal.update.privacy.message",
                table: .legal,
                fallback: "Güncel gizlilik politikasını inceleyerek uygulamayı kullanmaya devam edebilirsin."
            )
        case .explicitConsent:
            return RDLocalization.string(
                "legal.update.consent.message",
                table: .legal,
                fallback: "Yeni açık rıza kapsamını uygulama içinde inceleyip ayrıca onaylayabilirsin."
            )
        }
    }
}

@MainActor
final class LegalDocumentService: ObservableObject {
    static let shared = LegalDocumentService()

    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "LegalDocuments")
    private static var cacheKey: String {
        "rd.legal.documents.cache.v3.\(RDLanguage.current.rawValue)"
    }
    private static var lastRefreshKey: String {
        "rd.legal.documents.last_refresh_at.v3.\(RDLanguage.current.rawValue)"
    }
    private static var manifestPath: String {
        RDLanguage.current == .english ? "en/manifest.json" : "manifest.json"
    }
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let maxDocumentBytes = 262_144

    @Published private(set) var documents: [LegalDocumentKind: LegalDocument]
    @Published var pendingBanner: LegalUpdateNotice?
    @Published var pendingDecision: LegalUpdateNotice?

    private let supabase = SupabaseService.shared
    private let userDefaults: UserDefaults
    private var presentedInfoNoticeIDs = Set<String>()
    private var refreshInFlight = false

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        documents = Self.bundledDocuments(language: RDLanguage.current)
        loadCachedDocuments()
    }

    func document(for kind: LegalDocumentKind) -> LegalDocument {
        documents[kind] ?? Self.bundledDocument(
            for: kind,
            language: RDLanguage.current
        )
    }

    var availableKinds: [LegalDocumentKind] {
        if RDLanguage.current == .english {
            return [.terms, .privacy, .consent].filter { documents[$0] != nil }
        }
        return LegalDocumentKind.allCases
    }

    func refreshIfNeeded(userID: UUID?, userCreatedAt: Date? = nil) async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        let now = Date()
        let lastRefresh = userDefaults.object(forKey: Self.lastRefreshKey) as? Date
        let shouldRefresh = lastRefresh.map { now.timeIntervalSince($0) >= Self.refreshInterval } ?? true

        if shouldRefresh {
            let refreshed = await refreshRemoteDocuments()
            if refreshed {
                userDefaults.set(now, forKey: Self.lastRefreshKey)
            }
        }

        await evaluatePendingUpdates(userID: userID, userCreatedAt: userCreatedAt)
    }

    func recordPresented(_ notice: LegalUpdateNotice, userID: UUID?) async {
        guard notice.changeType == .info,
              let userID,
              presentedInfoNoticeIDs.insert(notice.id).inserted
        else {
            return
        }

        markInfoDocumentsLocallySeen(notice.documents, userID: userID)
        await upsertAcknowledgements(
            for: notice.documents,
            userID: userID,
            action: .seen,
            source: "legal_update_notice_presented"
        )
    }

    func recordSeen(_ notice: LegalUpdateNotice, userID: UUID?) async {
        if notice.changeType == .info, let userID {
            presentedInfoNoticeIDs.insert(notice.id)
            markInfoDocumentsLocallySeen(notice.documents, userID: userID)
        }
        clear(notice)
        await upsertAcknowledgements(for: notice.documents, userID: userID, action: .seen, source: "legal_update_notice")
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
        let expectedLocale = RDLanguage.current.rawValue
        guard manifest.locale == expectedLocale else { return [:] }
        if expectedLocale == RDLanguage.english.rawValue {
            let requiredURLKeys = Set([
                "terms",
                "privacy",
                "ai_data_processing_notice",
            ])
            guard manifest.schemaVersion == 1,
                  manifest.documentSetID == RDLegalDocumentSetID.englishGlobalV1.rawValue,
                  manifest.releaseStatus == "approved",
                  manifest.counselReviewStatus == "approved",
                  manifest.reviewedBy?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  manifest.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  manifest.publicURLsVerifiedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let publicURLs = manifest.publicURLs,
                  Set(publicURLs.keys) == requiredURLKeys,
                  publicURLs.values.allSatisfy({ raw in
                      guard let url = URL(string: raw) else { return false }
                      return url.scheme == "https"
                          && url.host?.lowercased() == "riskdetected.com"
                          && url.path != "/"
                  })
            else {
                return [:]
            }
        }

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
                    source: "remote",
                    checksum: item.hash
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

    private func evaluatePendingUpdates(userID: UUID?, userCreatedAt: Date?) async {
        guard let userID else {
            pendingBanner = nil
            pendingDecision = nil
            return
        }

        let remoteDocuments = documents.values
            .filter { $0.source == "remote" && $0.changeType != .baseline }
            .filter { !Self.wasAlreadyCurrentAtSignup($0, userCreatedAt: userCreatedAt) }
            .filter {
                $0.changeType != .info
                    || !isInfoDocumentLocallySeen($0, userID: userID)
            }
            .sorted {
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                if $0.version != $1.version {
                    return $0.version < $1.version
                }
                return ($0.checksum ?? "") < ($1.checksum ?? "")
            }

        guard !remoteDocuments.isEmpty else {
            pendingBanner = nil
            pendingDecision = nil
            return
        }

        do {
            guard let audit = RDLegalReleaseGate.acceptanceAuditMetadata() else {
                Self.logger.error("Legal acknowledgement lookup blocked: document-set audit metadata unavailable.")
                return
            }
            let rows: [LegalDocumentAcknowledgementRow] = try await supabase.client
                .from("legal_document_acknowledgements")
                .select("document_kind,version,change_type,document_set_id,document_locale,document_checksum,seen_at,continued_use_accepted_at,explicitly_accepted_at")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            let rowsByKey = Dictionary(
                uniqueKeysWithValues: rows
                    .filter { Self.acknowledgementRow($0, matches: audit) }
                    .map { ("\($0.documentKind.rawValue)|\($0.version)", $0) }
            )
            let pendingDocuments = remoteDocuments.filter { document in
                let row = rowsByKey["\(document.kind.rawValue)|\(document.version)"]
                guard Self.acknowledgementRow(row, matches: document) else {
                    return true
                }
                switch document.changeType {
                case .baseline:
                    return false
                case .info:
                    return row?.seenAt == nil && row?.continuedUseAcceptedAt == nil && row?.explicitlyAcceptedAt == nil
                case .materialTerms:
                    return row?.continuedUseAcceptedAt == nil && row?.explicitlyAcceptedAt == nil
                case .materialPrivacy:
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

    private static func acknowledgementRow(
        _ row: LegalDocumentAcknowledgementRow,
        matches audit: RDLegalSetAuditMetadata
    ) -> Bool {
        let matchesCurrentSet = row.documentSetID == audit.documentSetID
            && row.documentLocale == audit.locale
        let isLegacyTurkishRow = audit.documentSetID == RDLegalDocumentSetID.turkeyCurrent.rawValue
            && audit.locale == RDLanguage.turkish.rawValue
            && row.documentSetID == nil
            && row.documentLocale == nil
        return matchesCurrentSet || isLegacyTurkishRow
    }

    private static func acknowledgementRow(
        _ row: LegalDocumentAcknowledgementRow?,
        matches document: LegalDocument
    ) -> Bool {
        guard let row else { return false }
        guard let rowChecksum = row.documentChecksum,
              let documentChecksum = document.checksum
        else {
            // Legacy Turkish acknowledgements predate checksum persistence.
            return true
        }
        return normalizedChecksum(rowChecksum) == normalizedChecksum(documentChecksum)
    }

    private func isInfoDocumentLocallySeen(
        _ document: LegalDocument,
        userID: UUID
    ) -> Bool {
        guard document.changeType == .info else { return false }
        return Set(
            userDefaults.stringArray(
                forKey: localInfoSeenDefaultsKey(userID: userID)
            ) ?? []
        ).contains(Self.localInfoSeenFingerprint(document))
    }

    private func markInfoDocumentsLocallySeen(
        _ documents: [LegalDocument],
        userID: UUID
    ) {
        let key = localInfoSeenDefaultsKey(userID: userID)
        var fingerprints = userDefaults.stringArray(forKey: key) ?? []
        let additions = documents
            .filter { $0.changeType == .info }
            .map(Self.localInfoSeenFingerprint)
            .filter { !fingerprints.contains($0) }
        fingerprints.append(contentsOf: additions)
        if fingerprints.count > 128 {
            fingerprints.removeFirst(fingerprints.count - 128)
        }
        userDefaults.set(fingerprints, forKey: key)
    }

    private func localInfoSeenDefaultsKey(userID: UUID) -> String {
        [
            "rd.legal.documents.info_seen.v1",
            RDLanguage.current.rawValue,
            userID.uuidString.lowercased(),
        ].joined(separator: ".")
    }

    private static func localInfoSeenFingerprint(
        _ document: LegalDocument
    ) -> String {
        [
            document.kind.rawValue,
            document.version,
            normalizedChecksum(document.checksum ?? "no-checksum"),
        ].joined(separator: "|")
    }

    private static func normalizedChecksum(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "sha256-", with: "")
            .lowercased()
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
            guard let audit = RDLegalReleaseGate.acceptanceAuditMetadata() else {
                Self.logger.error("Legal acknowledgement write blocked: document-set audit metadata unavailable.")
                return
            }
            for document in documents {
                guard let checksum = document.checksum else {
                    Self.logger.error("Legal acknowledgement write blocked: document checksum unavailable for \(document.kind.rawValue, privacy: .public).")
                    continue
                }
                if audit.documentSetID == RDLegalDocumentSetID.englishGlobalV1.rawValue {
                    try await supabase.client
                        .rpc(
                            "acknowledge_legal_document_v1",
                            params: LegalAcknowledgementRPCPayload(
                                documentKind: document.kind.rawValue,
                                version: document.version,
                                changeType: document.changeType.rawValue,
                                documentSetID: audit.documentSetID,
                                documentLocale: audit.locale,
                                documentChecksum: checksum,
                                action: action.rawValue,
                                source: source,
                                appVersion: Self.appVersion,
                                deviceID: Self.deviceID
                            )
                        )
                        .execute()
                    continue
                }
                switch action {
                case .seen:
                    try await upsert(LegalSeenPayload(
                        userID: userID.uuidString,
                        documentKind: document.kind.rawValue,
                        version: document.version,
                        changeType: document.changeType.rawValue,
                        documentSetID: audit.documentSetID,
                        documentLocale: audit.locale,
                        documentChecksum: checksum,
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
                        documentSetID: audit.documentSetID,
                        documentLocale: audit.locale,
                        documentChecksum: checksum,
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
                        documentSetID: audit.documentSetID,
                        documentLocale: audit.locale,
                        documentChecksum: checksum,
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
        let prefix = RDLanguage.current == .english ? "en/" : "tr/"
        return path.hasPrefix(prefix) &&
            path.hasSuffix(".md") &&
            !path.contains("..") &&
            !path.hasPrefix("/") &&
            !path.contains("\\")
    }

    private static func bundledDocuments(
        language: RDLanguage
    ) -> [LegalDocumentKind: LegalDocument] {
        guard language == .english else {
            return Dictionary(
                uniqueKeysWithValues: LegalDocumentKind.allCases.map {
                    ($0, bundledDocument(for: $0, language: .turkish))
                }
            )
        }
        guard RDLegalReleaseGate.englishAuthAndPurchaseApproved,
              let manifestURL = RDLegalReleaseGate.bundledURL(
                fileName: "manifest",
                extension: "json",
                subdirectory: "LegalDocuments/en"
              ),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                LegalDocumentManifest.self,
                from: data
              )
        else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: manifest.documents.compactMap { item in
                guard item.path.hasPrefix("en/"),
                      !item.path.contains(".."),
                      let fileName = item.path.split(separator: "/").last.map(String.init),
                      fileName.hasSuffix(".md"),
                      let url = RDLegalReleaseGate.bundledURL(
                        fileName: String(fileName.dropLast(3)),
                        extension: "md",
                        subdirectory: "LegalDocuments/en"
                      ),
                      let documentData = try? Data(contentsOf: url),
                      hashMatches(data: documentData, expected: item.hash),
                      let text = String(data: documentData, encoding: .utf8)
                else {
                    return nil
                }
                return (
                    item.kind,
                    LegalDocument(
                        kind: item.kind,
                        title: item.title,
                        fileName: item.path,
                        version: item.version,
                        updatedAt: item.updatedAt,
                        changeType: item.changeType,
                        text: text,
                        source: "bundle",
                        checksum: item.hash
                    )
                )
            }
        )
    }

    private static func bundledDocument(
        for kind: LegalDocumentKind,
        language: RDLanguage
    ) -> LegalDocument {
        if language == .english {
            return LegalDocument(
                kind: kind,
                title: kind.title,
                fileName: "unavailable",
                version: "en-global-v1-blocked",
                updatedAt: nil,
                changeType: .baseline,
                text: RDLocalization.string(
                    "legal.english_unavailable.message",
                    table: .legal,
                    fallback: "İngilizce Kullanım Koşulları ve Gizlilik Politikası hukuk ve dil incelemesi tamamlanana kadar bu sürümde yayımlanmaz."
                ),
                source: "blocked",
                checksum: nil
            )
        }
        let text = loadBundledText(fileName: kind.bundledFileName)
        return LegalDocument(
            kind: kind,
            title: kind.title,
            fileName: "\(kind.bundledFileName).md",
            version: kind.fallbackVersion,
            updatedAt: nil,
            changeType: .baseline,
            text: text,
            source: "bundle",
            checksum: text.data(using: .utf8).map(RDLegalReleaseGate.sha256Hex)
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
            return RDLocalization.string("legal.legal.document.service.belge.yuklenemedi.lutfen.daha.sonra.tekrar.deney.093297ee", table: .legal, fallback: "Belge yüklenemedi. Lütfen daha sonra tekrar deneyin.")
        }

        return (try? String(contentsOf: url, encoding: .utf8))
            ?? RDLocalization.string("legal.legal.document.service.belge.okunamadi.lutfen.daha.sonra.tekrar.deneyin.1868c5eb", table: .legal, fallback: "Belge okunamadı. Lütfen daha sonra tekrar deneyin.")
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

    private static func wasAlreadyCurrentAtSignup(_ document: LegalDocument, userCreatedAt: Date?) -> Bool {
        guard let userCreatedAt,
              let documentUpdatedAt = parseRemoteDate(document.updatedAt)
        else { return false }
        return userCreatedAt >= documentUpdatedAt
    }

    private static func parseRemoteDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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

private enum LegalAcknowledgementAction: String {
    case seen
    case continuedUseAccepted = "continued_use_accepted"
    case explicitlyAccepted = "explicitly_accepted"
}

private struct LegalDocumentManifest: Decodable {
    let schemaVersion: Int?
    let locale: String
    let documentSetID: String?
    let releaseStatus: String?
    let counselReviewStatus: String?
    let reviewedBy: String?
    let reviewedAt: String?
    let publicURLsVerifiedAt: String?
    let publicURLs: [String: String]?
    let documents: [LegalDocumentManifestItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case locale
        case documentSetID = "document_set_id"
        case releaseStatus = "release_status"
        case counselReviewStatus = "counsel_review_status"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case publicURLsVerifiedAt = "public_urls_verified_at"
        case publicURLs = "public_urls"
        case documents
    }
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
    let documentSetID: String?
    let documentLocale: String?
    let documentChecksum: String?
    let seenAt: String?
    let continuedUseAcceptedAt: String?
    let explicitlyAcceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case documentKind = "document_kind"
        case version
        case changeType = "change_type"
        case documentSetID = "document_set_id"
        case documentLocale = "document_locale"
        case documentChecksum = "document_checksum"
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
    let documentSetID: String
    let documentLocale: String
    let documentChecksum: String
    let seenAt: String
    let source: String
    let appVersion: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case documentKind = "document_kind"
        case version
        case changeType = "change_type"
        case documentSetID = "document_set_id"
        case documentLocale = "document_locale"
        case documentChecksum = "document_checksum"
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
    let documentSetID: String
    let documentLocale: String
    let documentChecksum: String
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
        case documentSetID = "document_set_id"
        case documentLocale = "document_locale"
        case documentChecksum = "document_checksum"
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
    let documentSetID: String
    let documentLocale: String
    let documentChecksum: String
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
        case documentSetID = "document_set_id"
        case documentLocale = "document_locale"
        case documentChecksum = "document_checksum"
        case seenAt = "seen_at"
        case explicitlyAcceptedAt = "explicitly_accepted_at"
        case source
        case appVersion = "app_version"
        case deviceID = "device_id"
    }
}

private struct LegalAcknowledgementRPCPayload: Encodable {
    let documentKind: String
    let version: String
    let changeType: String
    let documentSetID: String
    let documentLocale: String
    let documentChecksum: String
    let action: String
    let source: String
    let appVersion: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case documentKind = "p_document_kind"
        case version = "p_version"
        case changeType = "p_change_type"
        case documentSetID = "p_document_set_id"
        case documentLocale = "p_document_locale"
        case documentChecksum = "p_document_checksum"
        case action = "p_action"
        case source = "p_source"
        case appVersion = "p_app_version"
        case deviceID = "p_device_id"
    }
}
