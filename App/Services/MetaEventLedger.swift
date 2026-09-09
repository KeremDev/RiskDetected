import Foundation
import CryptoKit

/// Local idempotency only. These keys and source identifiers never leave the device.
struct MetaEventLedger {
    let defaults: UserDefaults

    func claim(_ event: String, sourceID: String) -> Bool {
        let digest = SHA256.hash(data: Data("\(event):\(sourceID)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let key = "rd.meta.sent.v1.\(digest)"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return true
    }

    static func isNewRegistration(createdAt: Date, lastSignInAt: Date?, now: Date) -> Bool {
        guard let lastSignInAt else { return false }
        return abs(lastSignInAt.timeIntervalSince(createdAt)) < 60
            && now.timeIntervalSince(createdAt) >= 0
            && now.timeIntervalSince(createdAt) < 600
    }
}
