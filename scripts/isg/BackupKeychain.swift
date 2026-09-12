import Foundation
import Security

// Secret values enter/leave through pipes, never process arguments or diagnostics.
@main struct BackupKeychain {
    static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let action = CommandLine.arguments[1]
        let service = CommandLine.arguments[2]
        guard service.hasPrefix("riskdetected_backup_20260912_"), service.count < 100,
              service.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { exit(2) }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: NSUserName(), kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false]
        if action == "store" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8),
                  let key = Data(base64Encoded: text), key.count == 32 else { exit(2) }
            query[kSecValueData as String] = data
            query[kSecAttrLabel as String] = "RiskDetected değişim noktası — şifreli yedek anahtarı"
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { fputs("KEYCHAIN_STORE_FAILED\n", stderr); exit(1) }
        } else if action == "get" {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { fputs("KEYCHAIN_READ_FAILED\n", stderr); exit(1) }
            FileHandle.standardOutput.write(data)
        } else { exit(2) }
    }
}
