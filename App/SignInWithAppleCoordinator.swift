import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Drives the actual `ASAuthorizationController` Sign in with Apple flow:
/// generates a random nonce, hashes it (Apple requires the *hashed* nonce
/// in the request and the *raw* nonce passed back to the backend so it can
/// verify the identity token was issued for this exact request), presents
/// the system sheet, and hands the resulting identity token + raw nonce to
/// a completion handler. Kept out of `Packages/Auth` deliberately — that
/// package is UIKit/AuthenticationServices-free by design (see
/// `AuthSession.swift`) so its state machine stays unit-testable without a
/// device; this coordinator is the one place in the app target that talks
/// to the real API.
@MainActor
final class SignInWithAppleCoordinator: NSObject {
    private var currentNonce: String?
    private var completion: ((Result<(identityToken: Data, nonce: String), Error>) -> Void)?

    enum CoordinatorError: Error, CustomStringConvertible {
        case missingIdentityToken
        case unexpectedCredentialType

        var description: String {
            switch self {
            case .missingIdentityToken: return "Apple did not return an identity token."
            case .unexpectedCredentialType: return "Unexpected Apple authorization credential type."
            }
        }
    }

    func signIn(completion: @escaping (Result<(identityToken: Data, nonce: String), Error>) -> Void) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        self.completion = completion

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// A cryptographically random string, hex-encoded so it's safe to pass
    /// through both Apple's nonce field and a JSON payload untouched.
    private static func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to generate secure nonce bytes.")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

extension SignInWithAppleCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { completion = nil; currentNonce = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion?(.failure(CoordinatorError.unexpectedCredentialType))
            return
        }
        guard let nonce = currentNonce, let tokenData = credential.identityToken else {
            completion?(.failure(CoordinatorError.missingIdentityToken))
            return
        }
        completion?(.success((identityToken: tokenData, nonce: nonce)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { completion = nil; currentNonce = nil }
        completion?(.failure(error))
    }
}

extension SignInWithAppleCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
