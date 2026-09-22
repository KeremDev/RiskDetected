import Foundation

/// Device-only queue for accepted field answers. It contains no attachment
/// bytes and never invents a server success: a queued answer remains pending
/// until the same server mutation succeeds or the user resolves a conflict.
@MainActor final class NovaChecklistOfflineQueue {
    static let shared = NovaChecklistOfflineQueue()

    private struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let companyID: UUID?
        let runID: UUID
        let itemCode: String
        let prompt: String
        let allowsNotApplicable: Bool
        let verificationMethod: String?
        let helpText: String?
        let naReasonRequired: Bool
        let evidenceRecommended: Bool
        let photoRequired: Bool
        let result: String
        let note: String
        let evidenceAssetID: UUID?
        let openNonconformity: Bool
        let severity: String
        let dueOn: String
        var expectedRevision: Int64
        var conflict: Bool
    }

    private let storage: any PersonnelPendingStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storage: (any PersonnelPendingStorage)? = nil) {
        self.storage = storage ?? KeychainPersonnelPendingStorage(
            service: "com.riskdetected.checklists.pending.v1", maximumBytes: 262_144)
    }

    private func account(_ identity: NovaSessionIdentity) -> String {
        identity.userID.uuidString.lowercased()
    }

    private func read(_ identity: NovaSessionIdentity) -> [Entry] {
        guard let data = try? storage.read(account: account(identity)) else { return [] }
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private func write(_ entries: [Entry], identity: NovaSessionIdentity) throws {
        if entries.isEmpty { try storage.remove(account: account(identity)); return }
        try storage.write(encoder.encode(entries), account: account(identity))
    }

    func count(_ identity: NovaSessionIdentity) -> Int { read(identity).count }
    func conflictCount(_ identity: NovaSessionIdentity) -> Int { read(identity).filter(\.conflict).count }

    func enqueue(_ identity: NovaSessionIdentity, company: UUID?,
                 draft: NovaChecklistAnswerDraft) throws {
        guard draft.attachment == nil, let runID = draft.runID else { throw NovaChecklistFailure.unavailable }
        var entries = read(identity)
        let entry = Entry(id: UUID(), companyID: company, runID: runID,
            itemCode: draft.itemCode, prompt: draft.prompt,
            allowsNotApplicable: draft.allowsNotApplicable,
            verificationMethod: draft.verificationMethod, helpText: draft.helpText,
            naReasonRequired: draft.naReasonRequired,
            evidenceRecommended: draft.evidenceRecommended, photoRequired: draft.photoRequired,
            result: draft.result.rawValue, note: draft.note,
            evidenceAssetID: draft.evidenceAssetID, openNonconformity: draft.openNonconformity,
            severity: draft.severity.rawValue, dueOn: draft.dueOn,
            expectedRevision: draft.expectedRevision, conflict: false)
        // The newest local edit replaces an older unsent edit for the same
        // question; it does not create a second business mutation.
        entries.removeAll { $0.companyID == company && $0.runID == runID && $0.itemCode == draft.itemCode }
        entries.append(entry)
        try write(entries, identity: identity)
    }

    /// Returns the remaining count. Conflicts are retained and skipped until
    /// the screen is refreshed and the user explicitly answers again.
    func flush(_ identity: NovaSessionIdentity,
               send: (UUID?, NovaChecklistAnswerDraft) async throws -> NovaChecklistRun?) async -> Int {
        var entries = read(identity)
        var index = 0
        while index < entries.count {
            if entries[index].conflict { index += 1; continue }
            let entry = entries[index]
            guard let result = NovaChecklistResult(rawValue: entry.result),
                  let severity = NovaChecklistSeverity(rawValue: entry.severity) else {
                entries.remove(at: index); continue
            }
            let draft = NovaChecklistAnswerDraft(runID: entry.runID, itemCode: entry.itemCode,
                prompt: entry.prompt, allowsNotApplicable: entry.allowsNotApplicable,
                verificationMethod: entry.verificationMethod, helpText: entry.helpText,
                naReasonRequired: entry.naReasonRequired,
                evidenceRecommended: entry.evidenceRecommended, photoRequired: entry.photoRequired,
                result: result, note: entry.note, evidenceAssetID: entry.evidenceAssetID,
                openNonconformity: entry.openNonconformity, severity: severity,
                dueOn: entry.dueOn, expectedRevision: entry.expectedRevision)
            do {
                let updated = try await send(entry.companyID, draft)
                let nextRevision = updated?.revision
                entries.remove(at: index)
                if let nextRevision {
                    for remaining in entries.indices where entries[remaining].runID == entry.runID {
                        entries[remaining].expectedRevision = nextRevision
                    }
                }
            } catch NovaChecklistFailure.conflict {
                entries[index].conflict = true; index += 1
            } catch NovaChecklistFailure.runSubmitted {
                entries.remove(at: index)
            } catch {
                break
            }
        }
        try? write(entries, identity: identity)
        return entries.count
    }
}
