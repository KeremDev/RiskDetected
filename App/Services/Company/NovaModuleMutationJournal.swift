import Foundation
import CryptoKit

/// Stable request identity across service recreation and interrupted responses.
/// Only a decoded, session-validated response removes the saved request.
@MainActor struct NovaModuleMutationJournal {
    private struct Receipt: Codable { let operation: UUID; let mutation: UUID }
    static func run<T>(function: String, identity: NovaSessionIdentity, company: UUID, action: String,
                       payload: [String: PersonnelRPCValue],
                       rpc: (String, [String: PersonnelRPCValue]) async throws -> Data,
                       validate: () throws -> Void, decode: (Data) throws -> T,
                       storage injected: PersonnelPendingStorage? = nil) async throws -> T {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(PersonnelRPCValue.object([
            "company": .id(company), "action": .string(action), "payload": .object(payload)]))
        let key = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let storage = injected ?? KeychainPersonnelPendingStorage(service: "com.riskdetected.module.pending." + function)
        let account = identity.userID.uuidString.lowercased() + ":" + key
        let receipt: Receipt
        if let saved = try storage.read(account: account) {
            receipt = try JSONDecoder().decode(Receipt.self, from: saved)
        } else {
            receipt = .init(operation: UUID(), mutation: UUID())
            try storage.write(encoder.encode(receipt), account: account)
        }
        let data = try await rpc(function, ["p_company": .id(company), "p_action": .string(action),
            "p_operation": .id(receipt.operation), "p_mutation": .id(receipt.mutation), "p_payload": .object(payload)])
        try validate()
        let answer = try decode(data)
        try storage.remove(account: account)
        return answer
    }
}
