import AuthenticationServices
import SwiftUI

/// Equal-prominence Google + Sign in with Apple (App Store Guideline 4.8).
struct SignInOptionsView: View {
    @ObservedObject var auth: AuthService
    var onSignedIn: (() async -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var appleNonce: String?

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = AuthNonce.random()
                appleNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AuthNonce.sha256(nonce)
            } onCompletion: { result in
                Task {
                    await auth.completeAppleSignIn(result: result, rawNonce: appleNonce)
                    if auth.isAuthenticated {
                        await onSignedIn?()
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: 280)
            .frame(height: 44)
            .disabled(auth.isBusy || !auth.isConfigured)

            Button {
                Task {
                    await auth.signInWithGoogle()
                    if auth.isAuthenticated {
                        await onSignedIn?()
                    }
                }
            } label: {
                Text(auth.isBusy ? L("common.signing_in") : L("auth.continue_with_google"))
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: 280)
                    .frame(height: 44)
                    .background(YTLiteColor.signInBlue, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(auth.isBusy || !auth.isConfigured)

            if let err = auth.lastError, !err.isEmpty {
                Text(err)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}
