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
        TextField(placeholder, text: $text)
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
