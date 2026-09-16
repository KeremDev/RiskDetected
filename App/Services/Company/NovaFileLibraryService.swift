import Foundation

/// Same shape as the personnel, nonconformity and document tracking services: a
/// plain RPC closure, a session check and no SDK type in the design system.
///
/// The upload itself is three steps that must not be collapsed into one: the
/// server opens an intent and hands back a write-only path, the device puts the
/// bytes there, and a worker that the device cannot impersonate decides whether
/// they may leave quarantine. This type drives all three and never pretends the
/// file arrived before the server says it did.
@MainActor struct NovaFileLibraryService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    /// Puts bytes at a path the server chose, in a bucket the client can only
    /// write to. Returns nothing: arriving is not the same as being accepted.
    typealias Upload = (String, String, Data, String) async throws -> Void
    /// Asks the worker to inspect one entry. The device never reports a verdict.
    typealias Inspect = (UUID) async throws -> Void
    typealias Download = (String, String) async throws -> Data

    private let rpc: RPC
    private let upload: Upload
    private let inspect: Inspect
    private let download: Download
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, upload: @escaping Upload, inspect: @escaping Inspect,
         download: @escaping Download, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.upload = upload; self.inspect = inspect
        self.download = download; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaFileFailure.denied }
    }

    // MARK: transport rows

    private struct EntryRow: Decodable {
        let id: UUID
        var asset_id: UUID?
        var company_id: UUID?
        var company_name: String?
        let category: String
        let section: String?
        let title: String
        let file_name: String
        let note: String?
        let tags: [String]?
        let version: Int
        let state: String
        let rejection_code: String?
        let intent_id: UUID?
        let intent_state: String?
        let extension_: String?
        let purpose: String?
        let declared_bytes: Int
        let received_bytes: Int?
        let detected_type: String?
        let upload_bucket: String?
        let upload_path: String?
        let download_bucket: String?
        let download_path: String?
        let scanner: String?
        let scan_finding: String?
        let assurance: String?
        let malware_scanned: Bool
        let created_at: String?

        enum CodingKeys: String, CodingKey {
            case id, asset_id, company_id, company_name, category, section, title, file_name, note, tags, version
            case state, rejection_code, intent_id, intent_state, purpose
            case extension_ = "extension"
            case declared_bytes, received_bytes, detected_type
            case upload_bucket, upload_path, download_bucket, download_path
            case scanner, scan_finding, assurance, malware_scanned, created_at
        }
    }
    private struct CategoryRow: Decodable { let code: String; let ordinal: Int; let section: String }
    private struct AcceptRow: Decodable {
        let purpose: String; let extensions: [String]; let max_bytes: Int; let limit_approved: Bool
    }
    private struct ScannerRow: Decodable { let scanner: String; let detects_malware: Bool }
    private struct CatalogEnvelope: Decodable {
        let categories: [CategoryRow]
        let accepts: [AcceptRow]
        let scanners: [ScannerRow]
        let malware_scanning_available: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [EntryRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let category_counts: [String: [String: Int]]
        let total: Int
        let has_more: Bool
        let limit: Int
        let offset: Int
        let malware_scanning_available: Bool
    }
    private struct DetailEnvelope: Decodable { let row: EntryRow }
    private struct MutationEnvelope: Decodable { let entry_id: UUID; let row: EntryRow }

    /// An unknown state word is reported as a stopped upload rather than being
    /// smoothed into a calm one: the expert should look at the row.
    private func entry(_ row: EntryRow) -> NovaFileEntry {
        .init(id: row.id, assetID: row.asset_id, companyID: row.company_id, companyName: row.company_name,
              category: row.category, section: row.section, title: row.title,
              fileName: row.file_name, note: row.note, version: row.version,
              state: NovaFileState(rawValue: row.state) ?? .scanFailed,
              rejectionCode: row.rejection_code,
              fileExtension: row.extension_ ?? "", declaredBytes: row.declared_bytes,
              receivedBytes: row.received_bytes, detectedType: row.detected_type,
              uploadBucket: row.upload_bucket, uploadPath: row.upload_path,
              downloadBucket: row.download_bucket, downloadPath: row.download_path,
              scanner: row.scanner, scanFinding: row.scan_finding, assurance: row.assurance,
              malwareScanned: row.malware_scanned, createdAt: row.created_at, tags: row.tags ?? [])
    }

    private static func states(_ raw: [String: Int]) -> [NovaFileState: Int] {
        var result: [NovaFileState: Int] = [:]
        for (key, value) in raw {
            guard let state = NovaFileState(rawValue: key) else { continue }
            result[state] = value
        }
        return result
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null,
            "p_category": .null, "p_state": .null, "p_id": .null,
            "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_pilot_file_library_read_v2", payload)
    }

    // MARK: reads

    /// What the server will accept and what the categories mean. Read once per
    /// screen rather than guessed on this side.
    func catalogue(_ identity: NovaSessionIdentity) async throws -> (categories: [NovaFileCategory],
                                                                     accepts: [NovaFileAcceptance],
                                                                     assurance: NovaFileAssurance) {
        try check(identity)
        let data = try await read(["p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return (envelope.categories.map { .init(code: $0.code, ordinal: $0.ordinal, section: $0.section) },
                envelope.accepts.map { .init(purpose: $0.purpose, extensions: $0.extensions,
                                             maxBytes: $0.max_bytes, limitApproved: $0.limit_approved) },
                .init(scanners: envelope.scanners.map(\.scanner),
                      malwareScanningAvailable: envelope.malware_scanning_available))
    }

    /// The whole account in one call. Not scoped to a company, so it checks the
    /// signed-in session itself on both sides of the call.
    func library(_ identity: NovaSessionIdentity, query: NovaFileQuery = .init()) async throws -> NovaFileLibrary {
        try check(identity)
        let trimmed = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_query": trimmed.isEmpty ? .null : .string(trimmed),
            "p_category": query.category.map { .string($0) } ?? .null,
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(counts: Self.states(envelope.counts),
                     companies: envelope.companies.map { entry in
                         .init(id: entry.id, name: entry.name, total: entry.total,
                               counts: Self.states(entry.counts))
                     },
                     categoryCounts: envelope.category_counts.mapValues(Self.states),
                     rows: envelope.rows.map(entry),
                     total: envelope.total, hasMore: envelope.has_more,
                     limit: envelope.limit, offset: envelope.offset,
                     assurance: .init(malwareScanningAvailable: envelope.malware_scanning_available))
    }

    func detail(_ identity: NovaSessionIdentity, entry id: UUID) async throws -> NovaFileEntry {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return entry(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    private func mutate(company: UUID?, action: String, payload: [String: PersonnelRPCValue],
                        operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaFileEntry {
        let data = try await rpc("isg_pilot_file_library_mutate_v2", [
            "p_company": company.map { .id($0) } ?? .null, "p_action": .string(action),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
        return entry(try JSONDecoder().decode(MutationEnvelope.self, from: data).row)
    }

    private static func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Files one document, start to finish.
    ///
    /// The three steps stay separate on purpose. If the put fails the entry is
    /// already on file as an upload that never finished, and if the inspection
    /// cannot run the entry says so instead of showing a file that is not there.
    /// `progress` is called after each step with the row as the server sees it.
    func file(_ identity: NovaSessionIdentity, company: UUID?, draft: NovaFileDraft, data: Data,
              mutationID: UUID = UUID(),
              progress: ((NovaFileEntry) -> Void)? = nil) async throws -> NovaFileEntry {
        try check(identity)
        guard draft.isReady, let category = draft.category else { throw NovaFileFailure.validation }
        let opened = try await mutate(company: company, action: "open_upload", payload: [
            "title": .string(draft.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "category": .string(category),
            "file_name": .string(draft.fileName.trimmingCharacters(in: .whitespacesAndNewlines)),
            "tags": .array(draft.parsedTags.map(PersonnelRPCValue.string)),
            "note": Self.trimmed(draft.note).map { .string($0) } ?? .null,
            "extension": .string(draft.fileExtension.lowercased()),
            "bytes": .number(Int64(draft.bytes)),
            "sha256": .string(draft.sha256)], mutationID: mutationID)
        progress?(opened)
        try check(identity)
        // A replayed open has already been uploaded; putting the bytes again
        // would be refused by the bucket, which has no update policy at all.
        guard let bucket = opened.uploadBucket, let path = opened.uploadPath else {
            if opened.state.isWorking || opened.state.isFiled { return opened }
            throw NovaFileFailure.uploadFailed
        }
        try await upload(bucket, path, data, draft.fileExtension.lowercased())
        try check(identity)
        try await inspect(opened.id)
        try check(identity)
        let filed = try await detail(identity, entry: opened.id)
        if filed.state.isFiled {
            NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
            NotificationCenter.default.post(name: Notification.Name("isgada.mutation.succeeded"), object: identity.userID,
                userInfo: ["message": NovaSuccessMessage.fileAdded])
        }
        return filed
    }

    func rename(_ identity: NovaSessionIdentity, entry target: NovaFileEntry,
                title: String, category: String, note: String) async throws -> NovaFileEntry {
        try check(identity)
        let company = target.companyID
        let result = try await mutate(company: company, action: "rename_entry", payload: [
            "entry_id": .id(target.id), "expected_version": .number(Int64(target.version)),
            "title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "category": .string(category),
            "tags": .array(target.tags.map(PersonnelRPCValue.string)),
            "note": Self.trimmed(note).map { .string($0) } ?? .null])
        try check(identity)
        NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
        NotificationCenter.default.post(name: Notification.Name("isgada.mutation.succeeded"), object: identity.userID,
            userInfo: ["message": NovaSuccessMessage.recordSaved("Dosya")])
        return result
    }

    func archive(_ identity: NovaSessionIdentity, entry target: NovaFileEntry) async throws {
        try check(identity)
        let company = target.companyID
        _ = try await mutate(company: company, action: "archive_entry", payload: [
            "entry_id": .id(target.id), "expected_version": .number(Int64(target.version))])
        try check(identity)
        NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
    }

    /// Abandons an upload that never became a file. A filed document is put away
    /// by archiving it, not by cancelling something that already finished.
    func cancel(_ identity: NovaSessionIdentity, entry target: NovaFileEntry) async throws {
        try check(identity)
        let company = target.companyID
        _ = try await mutate(company: company, action: "cancel_upload", payload: [
            "entry_id": .id(target.id), "expected_version": .number(Int64(target.version))])
        try check(identity)
        NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
    }

    /// Retries the inspection of an upload that is still on its way. It cannot
    /// change a verdict: the worker reads the same bytes and decides again.
    func recheck(_ identity: NovaSessionIdentity, entry target: NovaFileEntry) async throws -> NovaFileEntry {
        try check(identity)
        try await inspect(target.id)
        try check(identity)
        return try await detail(identity, entry: target.id)
    }

    /// The original, exactly as it was filed. Only ever reachable for a row the
    /// server gave a path for.
    func contents(_ identity: NovaSessionIdentity, entry target: NovaFileEntry) async throws -> Data {
        try check(identity)
        guard let bucket = target.downloadBucket, let path = target.downloadPath else {
            throw NovaFileFailure.validation
        }
        let bytes = try await download(bucket, path)
        try check(identity)
        return bytes
    }

    /// The same download a filed row uses, for a caller (the emergency plan
    /// detail, say) that only has the bucket/path a module's own row resolved
    /// rather than the whole library entry.
    func download(_ identity: NovaSessionIdentity, bucket: String, path: String) async throws -> Data {
        try check(identity)
        let bytes = try await download(bucket, path)
        try check(identity)
        return bytes
    }
}
