import SwiftUI

/// YouTube-style account menu for Library (and reusable elsewhere).
struct AccountMenuSheet: View {
    @ObservedObject var auth: AuthService

    var onViewChannel: () -> Void
    var onSwitchAccount: () -> Void
    var onSignOut: () -> Void
    var onDeleteAccount: () -> Void

    private var handleText: String {
        guard let email = auth.emailHandle, !email.isEmpty else { return "" }
        let local = email.split(separator: "@").first.map(String.init) ?? email
        return "@\(local.lowercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Divider()
                .background(YTLiteColor.onSurfaceVariant.opacity(0.35))

            VStack(spacing: 0) {
                menuRow(
                    systemImage: "person.crop.rectangle.stack",
                    title: L("you.switch_account"),
                    showsChevron: true
                ) {
                    onSwitchAccount()
                }

                menuRow(
                    systemImage: "rectangle.portrait.and.arrow.right",
                    title: L("common.sign_out"),
                    showsChevron: false
                ) {
                    onSignOut()
                }

                menuRow(
                    systemImage: "trash",
                    title: L("account.delete"),
                    showsChevron: false,
                    isDestructive: true
                ) {
                    onDeleteAccount()
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YTLiteColor.surface)
    }

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            FeedChannelAvatar(
                url: auth.avatarURL,
                channelName: auth.displayName,
                size: 48
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)

                if !handleText.isEmpty {
                    Text(handleText)
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(1)
                }

                Button {
                    onViewChannel()
                } label: {
                    Text(L("account.view_channel"))
                        .font(YTLiteType.labelEmphasized)
                        .foregroundStyle(YTLiteColor.signInBlue)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private func menuRow(
        systemImage: String,
        title: String,
        showsChevron: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(isDestructive ? YTLiteColor.danger : YTLiteColor.onSurface)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(YTLiteType.body)
                    .foregroundStyle(isDestructive ? YTLiteColor.danger : YTLiteColor.onSurface)

                Spacer(minLength: 0)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isBusy)
    }
}
