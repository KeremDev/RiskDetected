import Foundation
import Security

/// Dedicated device-only service; access-group/bundle identity stays unchanged.
@MainActor final class NotebookKeychainStorage: NotebookStorage {
    private let service = "com.riskdetected.notebook.outbox.v1"
    private func query(_ owner: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: owner.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
    }
    func read(owner: UUID) throws -> Data? {
        var q = query(owner); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, data.count <= 2_000_000 else { throw NotebookFailure.unavailable }
        return data
    }
    func write(_ data: Data, owner: UUID) throws {
        guard data.count <= 2_000_000 else { throw NotebookFailure.full }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(owner) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(owner).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw NotebookFailure.unavailable }
        } else if status != errSecSuccess { throw NotebookFailure.unavailable }
    }
}
