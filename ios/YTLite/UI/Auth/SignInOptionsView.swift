import SwiftUI

/// Equal-prominence Google + Sign in with Apple (App Store Guideline 4.8).
struct SignInOptionsView: View {
    @ObservedObject var auth: AuthService
    /// When false, only Google is offered (e.g. playback needs catalog OAuth).
    /// Mac Catalyst Developer ID (website DMG) cannot include Sign in with Apple entitlement.
    var showsAppleSignIn: Bool = {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }()
    /// Analytics `source` for sign_in_* events.
    var analyticsSource: String = "unknown"
    var onSignedIn: (() async -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            if showsAppleSignIn {
                Button {
                    Task {
                        await auth.signInWithApple(source: analyticsSource)
                        if auth.isAuthenticated {
                            await onSignedIn?()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.logo")
                        Text(L("auth.sign_in_with_apple"))
                    }
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: 280)
                    .frame(height: 44)
                    .background(
                        colorScheme == .dark ? Color.white : Color.black,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(auth.isBusy || !auth.isConfigured)
            }

            Button {
                Task {
                    await auth.signInWithGoogle(source: analyticsSource)
                    if auth.isAuthenticated {
                        await onSignedIn?()
                    }
                }
            } label: {
                Text(auth.isBusy ? L("common.signing_in") : L("auth.continue_with_google"))
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .frame(maxWidth: 280)
                    .frame(height: 44)
                    .background(YTLiteColor.accent, in: Capsule())
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
