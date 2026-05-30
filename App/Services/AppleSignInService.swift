import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

@MainActor
final class AppleSignInService: NSObject {
    struct Result {
        let idToken: String
        let nonce: String
        let email: String?
        let fullName: String?
    }

    private var currentNonce: String?
    private var continuation: CheckedContinuation<Result, Error>?

    func signIn() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let nonce = Self.randomNonceString()
            currentNonce = nonce

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        currentNonce = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
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
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AppleSignInError.invalidCredential))
            return
        }

        guard let nonce = currentNonce else {
            finish(.failure(AppleSignInError.missingNonce))
            return
        }

        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            finish(.failure(AppleSignInError.missingIdentityToken))
            return
        }

        let fullName = credential.fullName.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .medium)
        }.flatMap(Self.nonBlank)

        finish(.success(Result(
            idToken: idToken,
            nonce: nonce,
            email: credential.email.flatMap(Self.nonBlank),
            fullName: fullName
        )))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }
}

private extension AppleSignInService {
    static func nonBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingNonce
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Apple kimlik bilgisi okunamadı."
        case .missingNonce:
            return "Apple güvenlik doğrulaması başlatılamadı."
        case .missingIdentityToken:
            return "Apple kimlik tokenı alınamadı."
        }
    }
}
