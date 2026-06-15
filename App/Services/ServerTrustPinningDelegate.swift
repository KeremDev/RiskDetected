import CryptoKit
import Foundation
import OSLog
import Security

final class ServerTrustPinningDelegate: NSObject, URLSessionDelegate {
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "ServerTrustPinning")

    private let pinnedHosts: Set<String>
    private let pinnedCertificateHashes: Set<String>

    init(
        pinnedHosts: Set<String> = RDConfig.Security.pinnedHosts,
        pinnedCertificateHashes: Set<String> = RDConfig.Security.pinnedCertificateSHA256Hashes
    ) {
        self.pinnedHosts = pinnedHosts
        self.pinnedCertificateHashes = pinnedCertificateHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        guard RDConfig.Security.certificatePinningEnabled,
              pinnedHosts.contains(host),
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            Self.logger.error("Server trust evaluation failed host=\(host, privacy: .public) error=\(String(describing: trustError), privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard certificateHashes(for: serverTrust).contains(where: pinnedCertificateHashes.contains) else {
            Self.logger.error("Pinned certificate hash mismatch host=\(host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func certificateHashes(for trust: SecTrust) -> [String] {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return []
        }

        return certificates.map { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            return Data(SHA256.hash(data: data)).base64EncodedString()
        }
    }
}
