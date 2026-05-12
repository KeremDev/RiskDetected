import Foundation
import GoogleSignIn
import CryptoKit
import Security
import UIKit

struct GoogleSignInResult {
    let idToken: String
    let accessToken: String
    let nonce: String
    let email: String?
    let fullName: String?
}

@MainActor
final class GoogleSignInService {
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func signIn() async throws -> GoogleSignInResult {
        try configureIfNeeded()

        guard let presentingViewController = UIApplication.shared.rdTopMostViewController else {
            throw NSError(
                domain: "RiskDetected.GoogleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Google giriş penceresi açılamadı."]
            )
        }

        let nonce = Self.randomNonceString()
        let result = try await signIn(withPresenting: presentingViewController, nonce: Self.sha256(nonce))
        guard let idToken = result.user.idToken?.tokenString.nilIfBlank else {
            throw NSError(
                domain: "RiskDetected.GoogleSignIn",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Google kimlik token'ı alınamadı."]
            )
        }

        return GoogleSignInResult(
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString,
            nonce: nonce,
            email: result.user.profile?.email,
            fullName: result.user.profile?.name
        )
    }

    private func signIn(withPresenting presentingViewController: UIViewController, nonce: String) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "RiskDetected.GoogleSignIn",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "Google giriş sonucu alınamadı."]
                    ))
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              clientID.nilIfBlank != nil,
              !clientID.contains("REPLACE_WITH")
        else {
            throw NSError(
                domain: "RiskDetected.GoogleSignIn",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Google iOS Client ID eksik. Google Cloud'dan alınan Client ID Info.plist içine eklenmeli."]
            )
        }

        let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String
        let resolvedServerClientID = serverClientID?.nilIfBlank

        if resolvedServerClientID == nil {
            throw NSError(
                domain: "RiskDetected.GoogleSignIn",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Google server client ID eksik. Google Cloud Console'da Web OAuth client ID oluşturup Info.plist içindeki GIDServerClientID alanına eklemelisin."]
            )
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: resolvedServerClientID)
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension UIApplication {
    var rdTopMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .rdTopMostPresentedViewController
    }
}

private extension UIViewController {
    var rdTopMostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.rdTopMostPresentedViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController
        {
            return visibleViewController.rdTopMostPresentedViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController
        {
            return selectedViewController.rdTopMostPresentedViewController
        }
        return self
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
