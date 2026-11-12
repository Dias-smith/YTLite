import SwiftUI

/// Size-class + width breakpoints for iPad, Split View, and iPhone Duo adaptive layout.
/// Prefer size classes / available width — never branch on `userInterfaceIdiom` or orientation.
enum YTLiteAdaptive {
    /// Readable content cap on wide canvases.
    static let contentMaxWidth: CGFloat = 980
    /// Mini player dock width on regular width.
    static let miniPlayerDockWidth: CGFloat = 520

    static func isRegularWidth(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }

    static func screenPadding(for width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        if isRegularWidth(sizeClass) {
            return stableWidth(width) >= 1000 ? 28 : 24
        }
        return YTLiteLayout.screenPadding
    }

    /// Home / You feed columns.
    /// - Parameter preferEvenColumns: When a Duo fold / division region is present,
    ///   prefer an even column count so cards don't straddle the hinge.
    static func feedColumns(
        for width: CGFloat,
        sizeClass: UserInterfaceSizeClass?,
        preferEvenColumns: Bool = false
    ) -> Int {
        guard isRegularWidth(sizeClass) else { return 1 }
        let width = stableWidth(width)
        var columns = 1
        if width >= 1100 {
            columns = 3
        } else if width >= 700 {
            columns = 2
        }
        return preferEvenColumns ? evenColumnCount(columns) : columns
    }

    /// Library playlist / channel grid columns.
    static func playlistColumns(
        for width: CGFloat,
        sizeClass: UserInterfaceSizeClass?,
        preferEvenColumns: Bool = false
    ) -> Int {
        guard isRegularWidth(sizeClass) else { return 2 }
        let width = stableWidth(width)
        var columns = 2
        if width >= 1100 {
            columns = 5
        } else if width >= 900 {
            columns = 4
        } else if width >= 700 {
            columns = 3
        }
        return preferEvenColumns ? evenColumnCount(columns) : columns
    }

    /// Search results columns on wide layouts.
    static func searchColumns(
        for width: CGFloat,
        sizeClass: UserInterfaceSizeClass?,
        preferEvenColumns: Bool = false
    ) -> Int {
        guard isRegularWidth(sizeClass) else { return 1 }
        let columns = stableWidth(width) >= 800 ? 2 : 1
        return preferEvenColumns ? evenColumnCount(columns) : columns
    }

    /// Drop an odd column count by one so a Duo hinge sits between columns.
    private static func evenColumnCount(_ columns: Int) -> Int {
        guard columns > 1, columns % 2 == 1 else { return columns }
        return columns - 1
    }

    /// Quantize width so mid-fold resize frames don't thrash LazyVGrid column counts.
    private static func stableWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        let step: CGFloat = 64
        return (width / step).rounded() * step
    }

    /// True when GeometryProxy reports a Duo fold / division (active or inactive).
    /// Skip the query on compact width — columns are already 1.
    static func prefersEvenColumns(in proxy: GeometryProxy, sizeClass: UserInterfaceSizeClass?) -> Bool {
        guard isRegularWidth(sizeClass) else { return false }
        if #available(iOS 27.1, *) {
            return !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
        }
        return false
    }

    static func gridItems(count: Int, spacing: CGFloat = 16) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }

    /// True when the player should use a side-by-side landscape layout.
    static func playerUsesSplitLayout(size: CGSize, sizeClass: UserInterfaceSizeClass?) -> Bool {
        guard isRegularWidth(sizeClass) else { return false }
        return size.width > size.height && size.width >= 700
    }

    /// Prefer a taller sheet on regular width (iPad / Duo inner / wide Split View).
    static func sheetDetents(
        compact: [PresentationDetent],
        regular: [PresentationDetent] = [.large],
        sizeClass: UserInterfaceSizeClass?
    ) -> Set<PresentationDetent> {
        Set(isRegularWidth(sizeClass) ? regular : compact)
    }
}

private struct MiniPlayerBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height reserved for the mini player above the tab bar (0 when hidden).
    var miniPlayerBottomInset: CGFloat {
        get { self[MiniPlayerBottomInsetKey.self] }
        set { self[MiniPlayerBottomInsetKey.self] = newValue }
    }
}

private struct MiniPlayerScrollInsetModifier: ViewModifier {
    @Environment(\.miniPlayerBottomInset) private var inset

    func body(content: Content) -> some View {
        content.contentMargins(.bottom, inset, for: .scrollContent)
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
    /// `List` / `GeometryReader` do not reliably inherit `AppChrome` `safeAreaInset`.
    func ytLiteMiniPlayerScrollInset() -> some View {
        modifier(MiniPlayerScrollInsetModifier())
    }

    func ytLiteMiniPlayerScrollInset(showsMiniPlayer: Bool) -> some View {
        modifier(MiniPlayerScrollInsetShowsModifier(showsMiniPlayer: showsMiniPlayer))
    }
}

private struct MiniPlayerScrollInsetShowsModifier: ViewModifier {
    let showsMiniPlayer: Bool
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content.contentMargins(
            .bottom,
            showsMiniPlayer ? YTLiteLayout.miniPlayerChromeHeight(displayScale: displayScale) : 0,
            for: .scrollContent
        )
    }
}
