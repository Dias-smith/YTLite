import AuthenticationServices
import Foundation
import UIKit

/// Presents native Sign in with Apple and returns the identity token + nonce.
@MainActor
final class AppleSignInBridge: NSObject {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var currentNonce: String?

    struct AppleSignInResult {
        let idToken: String
        let rawNonce: String
        let fullName: PersonNameComponents?
    }

    func signIn() async throws -> AppleSignInResult {
        let nonce = AuthNonce.random()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthNonce.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleSignInResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        currentNonce = nil
        continuation.resume(with: result)
    }
}

extension AppleSignInBridge: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            finish(.failure(AppleSignInError.invalidCredential))
            return
        }
        finish(
            .success(
                AppleSignInResult(
                    idToken: idToken,
                    rawNonce: nonce,
                    fullName: credential.fullName
                )
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error))
    }
}

extension AppleSignInBridge: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
    }
}

enum AppleSignInError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Sign in with Apple credential"
        }
    }
}
