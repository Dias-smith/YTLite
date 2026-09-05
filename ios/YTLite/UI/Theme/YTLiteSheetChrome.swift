import SwiftUI
import UIKit

/// Shared chrome matching `TrackActionSheet` (grab handle, row metrics, dark elevated surface).
enum YTLiteSheetChrome {
    static let grabWidth: CGFloat = 36
    static let grabHeight: CGFloat = 4
    static let iconColumn: CGFloat = 28
    static let iconSize: CGFloat = 18
    static let rowVertical: CGFloat = 14
}

struct YTLiteSheetGrabHandle: View {
    var body: some View {
        Capsule()
            .fill(YTLiteColor.onSurfaceVariant.opacity(0.45))
            .frame(width: YTLiteSheetChrome.grabWidth, height: YTLiteSheetChrome.grabHeight)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }
}

struct YTLiteSheetTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(YTLiteType.sectionTitle)
            .foregroundStyle(YTLiteColor.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.bottom, 8)
    }
}

struct YTLiteSheetActionRow: View {
    let systemImage: String?
    let title: String
    var isSelected: Bool = false
    var isDestructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: YTLiteLayout.stackLoose) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: YTLiteSheetChrome.iconSize, weight: .regular))
                        .foregroundStyle(isDestructive ? YTLiteColor.danger : YTLiteColor.onSurface)
                        .frame(width: YTLiteSheetChrome.iconColumn, alignment: .center)
                }
                Text(title)
                    .font(YTLiteType.body)
                    .foregroundStyle(isDestructive ? YTLiteColor.danger : YTLiteColor.onSurface)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YTLiteColor.accent)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteSheetChrome.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct YTLiteSheetField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disableAutocorrection: Bool = false

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(YTLiteColor.onSurfaceVariant)
        )
            .font(YTLiteType.body)
            .foregroundStyle(YTLiteColor.onSurface)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, 12)
            .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, YTLiteLayout.screenPadding)
    }
}

struct YTLiteSheetPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var destructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(enabled ? YTLiteColor.onAccent : YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    (destructive ? YTLiteColor.danger : YTLiteColor.accent).opacity(enabled ? 1 : 0.35),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }
}

struct YTLiteSheetSecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }
}

// MARK: - Toast

/// Shared in-app toast — always dark snackbar (independent of app theme).
struct YTLiteToastBanner: View {
    let message: String

    /// Keep presenter timers and local auto-dismiss in sync.
    static let displayNanoseconds: UInt64 = 2_200_000_000

    private static let fill = Color(red: 0.11, green: 0.11, blue: 0.12) // #1C1C1F
    private static let fillElevated = Color(red: 0.16, green: 0.16, blue: 0.18)
    private static let label = Color.white.opacity(0.95)
    private static let stroke = Color.white.opacity(0.12)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(YTLiteColor.accent)
                .accessibilityHidden(true)

            Text(message)
                .font(YTLiteType.body.weight(.semibold))
                .foregroundStyle(Self.label)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Self.fillElevated, Self.fill],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.55), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Self.stroke, lineWidth: 1)
        )
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Bottom-aligned toast overlay. Pass `nil` to hide.
    /// - Parameter ownsDismiss: when true, clears `message` after `YTLiteToastBanner.displayNanoseconds`.
    func ytLiteToast(
        _ message: Binding<String?>,
        bottomPadding: CGFloat = 88,
        ownsDismiss: Bool = true
    ) -> some View {
        modifier(
            YTLiteToastOverlayModifier(
                message: message,
                bottomPadding: bottomPadding,
                ownsDismiss: ownsDismiss
            )
        )
    }

    /// Read-only toast (presenter owns dismiss timing).
    func ytLiteToast(
        _ message: String?,
        bottomPadding: CGFloat = 88
    ) -> some View {
        overlay(alignment: .bottom) {
            if let message, !message.isEmpty {
                YTLiteToastBanner(message: message)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: message)
                    .allowsHitTesting(false)
                    .zIndex(999)
            }
        }
    }
}

private struct YTLiteToastOverlayModifier: ViewModifier {
    @Binding var message: String?
    var bottomPadding: CGFloat
    var ownsDismiss: Bool

    func body(content: Content) -> some View {
        content
            .ytLiteToast(message, bottomPadding: bottomPadding)
            .task(id: message) {
                guard ownsDismiss, let current = message, !current.isEmpty else { return }
                try? await Task.sleep(nanoseconds: YTLiteToastBanner.displayNanoseconds)
                if message == current {
                    withAnimation(.easeOut(duration: 0.2)) {
                        message = nil
                    }
                }
            }
    }
}
