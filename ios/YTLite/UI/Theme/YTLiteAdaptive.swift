import SwiftUI

/// Size-class + width breakpoints for iPad / Split View adaptive layout.
enum YTLiteAdaptive {
    /// Readable content cap on wide canvases.
    static let contentMaxWidth: CGFloat = 980
    /// Mini player dock width on regular width.
    static let miniPlayerDockWidth: CGFloat = 520
    /// Centered Shorts “phone” frame.
    static let shortsFrameWidth: CGFloat = 420
    static let shortsAspect: CGFloat = 9.0 / 16.0

    static func isRegularWidth(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }

    static func screenPadding(for width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        if isRegularWidth(sizeClass) {
            return width >= 1000 ? 28 : 24
        }
        return YTLiteLayout.screenPadding
    }

    /// Home / You feed columns.
    static func feedColumns(for width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Int {
        guard isRegularWidth(sizeClass) else { return 1 }
        if width >= 1100 { return 3 }
        if width >= 700 { return 2 }
        return 1
    }

    /// Library playlist / channel grid columns.
    static func playlistColumns(for width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Int {
        guard isRegularWidth(sizeClass) else { return 2 }
        if width >= 1100 { return 5 }
        if width >= 900 { return 4 }
        if width >= 700 { return 3 }
        return 2
    }

    /// Search results columns on wide layouts.
    static func searchColumns(for width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Int {
        guard isRegularWidth(sizeClass) else { return 1 }
        return width >= 800 ? 2 : 1
    }

    static func gridItems(count: Int, spacing: CGFloat = 16) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }

    /// True when the player should use a side-by-side landscape layout.
    static func playerUsesSplitLayout(size: CGSize, sizeClass: UserInterfaceSizeClass?) -> Bool {
        guard isRegularWidth(sizeClass) else { return false }
        return size.width > size.height && size.width >= 700
    }

    /// Prefer a taller sheet on regular width so action sheets are usable on iPad.
    static func sheetDetents(
        compact: [PresentationDetent],
        regular: [PresentationDetent] = [.large],
        sizeClass: UserInterfaceSizeClass?
    ) -> Set<PresentationDetent> {
        Set(isRegularWidth(sizeClass) ? regular : compact)
    }
}

extension View {
    /// Center content and cap readable width on regular-size canvases.
    func ytLiteContentWidth(
        _ maxWidth: CGFloat = YTLiteAdaptive.contentMaxWidth,
        enabled: Bool = true
    ) -> some View {
        Group {
            if enabled {
                frame(maxWidth: maxWidth)
                    .frame(maxWidth: .infinity)
            } else {
                self
            }
        }
    }

    /// Extra scroll bottom inset when mini player is visible.
    /// `List` does not reliably inherit `AppChrome` `safeAreaInset`.
    func ytLiteMiniPlayerScrollInset(showsMiniPlayer: Bool) -> some View {
        contentMargins(
            .bottom,
            showsMiniPlayer ? YTLiteLayout.miniPlayerChromeHeight : 0,
            for: .scrollContent
        )
    }
}
