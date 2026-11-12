import SwiftUI

/// Root chrome: bottom tabs on compact width; sidebar + split on regular width
/// (iPad, iPhone Duo inner display, wide Split View).
///
/// Uses one `NavigationSplitView` for both size classes so fold / unfold keeps the
/// detail tab tree (and its `@StateObject`s / scroll position) alive.
struct AppChrome<Content: View>: View {
    @Binding var selectedTab: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var review: ReviewPromptCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    private var isRegular: Bool {
        // Size class only — iPhone Duo inner display is regular width (not `.pad`).
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack {
                AppSidebar(selected: $selectedTab, isAuthenticated: isAuthenticated)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = isRegular ? .all : .detailOnly
        }
        .onChange(of: isRegular) { _, regular in
            columnVisibility = regular ? .all : .detailOnly
        }
        .onChange(of: playerPresentation.isPresented) { _, presented in
            review.setBusy("player", presented)
            AdSceneLifecycle.setUIBlocked("player_detail", blocked: presented)
            if !presented {
                AdSceneLifecycle.cancelPlayStartInterstitial()
            }
        }
    }

    private var detailColumn: some View {
        // Tabs paint their own wallpaper — avoid a second AppBackgroundCanvas that
        // rebuilds (and blurs) on every Duo fold frame.
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(YTLiteColor.background)
            .environment(\.miniPlayerBottomInset, miniPlayerBottomInset)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .modifier(CompactVerticalTabInset(
                selectedTab: $selectedTab,
                isAuthenticated: isAuthenticated,
                isKeyboardVisible: isKeyboardVisible,
                enabled: !isRegular
            ))
            .playerDetailPresentation(isPresented: $playerPresentation.isPresented)
    }

    @ViewBuilder
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            miniPlayerSlot(docked: isRegular)
            if !isRegular, !isKeyboardVisible {
                // Hidden when iOS 27.1 places a vertical system bar — side inset hosts tabs instead.
                MainTabBarHost(
                    selected: $selectedTab,
                    isAuthenticated: isAuthenticated,
                    isKeyboardVisible: isKeyboardVisible
                )
            }
        }
    }

    @ViewBuilder
    private func miniPlayerSlot(docked: Bool) -> some View {
        if showsMiniPlayer {
            MiniPlayerBar()
                .frame(maxWidth: docked ? YTLiteAdaptive.miniPlayerDockWidth : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.bottom, docked && !isKeyboardVisible ? 8 : 0)
                .opacity(isKeyboardVisible ? 0 : 1)
                .allowsHitTesting(!isKeyboardVisible)
                .accessibilityHidden(isKeyboardVisible)
                // Reserve height while keyboard is up so the sheet host stays mounted.
                .frame(maxHeight: isKeyboardVisible ? 0 : nil)
                .clipped()
        }
    }

    private var showsMiniPlayer: Bool {
        playback.nowPlaying != nil
    }

    private var miniPlayerBottomInset: CGFloat {
        guard showsMiniPlayer, !isKeyboardVisible else { return 0 }
        return YTLiteLayout.miniPlayerChromeHeight(displayScale: displayScale) + (isRegular ? 8 : 0)
    }
}

/// Bottom tab bar that hides itself when the system reports a vertical toolbar edge.
private struct MainTabBarHost: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool

    var body: some View {
        if #available(iOS 27.1, *) {
            MainTabBarHostVerticalAware(
                selected: $selected,
                isAuthenticated: isAuthenticated,
                isKeyboardVisible: isKeyboardVisible
            )
        } else if !isKeyboardVisible {
            MainTabBar(selected: $selected, isAuthenticated: isAuthenticated)
        }
    }
}

@available(iOS 27.1, *)
private struct MainTabBarHostVerticalAware: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    var body: some View {
        if toolbarVerticalEdge == nil, !isKeyboardVisible {
            MainTabBar(selected: $selected, isAuthenticated: isAuthenticated)
        }
    }
}

/// Side tab bar for compact width when the system vertical chrome edge is active.
private struct CompactVerticalTabInset: ViewModifier {
    @Binding var selectedTab: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool
    var enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *), enabled {
            CompactVerticalTabInsetAware(
                selectedTab: $selectedTab,
                isAuthenticated: isAuthenticated,
                isKeyboardVisible: isKeyboardVisible,
                content: { content }
            )
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct CompactVerticalTabInsetAware<Content: View>: View {
    @Binding var selectedTab: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    var body: some View {
        content()
            .safeAreaInset(edge: .leading, spacing: 0) {
                if toolbarVerticalEdge == .leading, !isKeyboardVisible {
                    MainTabBar(
                        selected: $selectedTab,
                        isAuthenticated: isAuthenticated,
                        axis: .vertical,
                        separatorAlignment: .trailing
                    )
                    .frame(width: 72)
                }
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if toolbarVerticalEdge == .trailing, !isKeyboardVisible {
                    MainTabBar(
                        selected: $selectedTab,
                        isAuthenticated: isAuthenticated,
                        axis: .vertical,
                        separatorAlignment: .leading
                    )
                    .frame(width: 72)
                }
            }
    }
}

// MARK: - Bubble guide (coach marks)

/// Coach-mark tips.
/// - Release: one-shot — persisted after dismiss, never shown again.
/// - DEBUG: every cold launch shows again (session dismiss only).
@MainActor
final class BubbleGuideStore: ObservableObject {
    static let shared = BubbleGuideStore()

    enum ID: String, Hashable {
        case homeFilter = "bubble_guide.home_filter.v1"
        case searchFilter = "bubble_guide.search_filter.v1"
    }

    /// Named coordinate space shared by `bubbleGuideTarget` + `bubbleGuideLayer`.
    static let coordinateSpaceName = "YTLite.BubbleGuide"

    @Published private(set) var revision = 0
    private var dismissedThisSession: Set<ID> = []

    func isVisible(_ id: ID) -> Bool {
        _ = revision
        if dismissedThisSession.contains(id) { return false }
        #if DEBUG
        return true
        #else
        return !UserDefaults.standard.bool(forKey: id.rawValue)
        #endif
    }

    func dismiss(_ id: ID) {
        guard isVisible(id) else { return }
        dismissedThisSession.insert(id)
        #if !DEBUG
        UserDefaults.standard.set(true, forKey: id.rawValue)
        #endif
        revision += 1
    }
}

// MARK: Frame reporting (CGRect in BubbleGuide coordinate space)

private struct BubbleGuideFrameKey: PreferenceKey {
    static var defaultValue: [BubbleGuideStore.ID: CGRect] = [:]

    static func reduce(
        value: inout [BubbleGuideStore.ID: CGRect],
        nextValue: () -> [BubbleGuideStore.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct BubbleGuideCalloutSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Design-mock callout: green capsule below the target, caret tip on the target's
/// bottom edge. Arrow sits near the trailing side; body extends left.
struct BubbleGuideCallout: View {
    let text: String

    static let arrowWidth: CGFloat = 16
    static let arrowHeight: CGFloat = 8
    /// Distance from callout trailing edge to arrow tip (under filter icon).
    static let arrowTipFromTrailing: CGFloat = 22

    var body: some View {
        Text(text)
            .font(YTLiteType.meta.weight(.semibold))
            .foregroundStyle(YTLiteColor.onAccent)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(YTLiteColor.accent, in: Capsule())
            .overlay(alignment: .topTrailing) {
                BubbleGuideArrow()
                    .fill(YTLiteColor.accent)
                    .frame(width: Self.arrowWidth, height: Self.arrowHeight)
                    .offset(
                        x: -(Self.arrowTipFromTrailing - Self.arrowWidth / 2),
                        y: -Self.arrowHeight
                    )
            }
            // Reserve space above the capsule so the arrow is inside the view bounds
            // (needed for correct absolute offset from the tip point).
            .padding(.top, Self.arrowHeight)
            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            .fixedSize()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct BubbleGuideArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Reports this view's frame in `BubbleGuideStore.coordinateSpaceName`.
    func bubbleGuideTarget(_ id: BubbleGuideStore.ID) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: BubbleGuideFrameKey.self,
                    value: [id: geo.frame(in: .named(BubbleGuideStore.coordinateSpaceName))]
                )
            }
        }
    }

    /// Floating callout layer. Apply on an ancestor of the target that also sets
    /// `.coordinateSpace(name: BubbleGuideStore.coordinateSpaceName)`.
    /// Does not consume layout space in the chips row.
    func bubbleGuideLayer(
        _ id: BubbleGuideStore.ID,
        text: String,
        /// Horizontal inset from the target's leading edge to the caret tip
        /// (filter-icon center). `nil` = target midX.
        tipXFromLeading: CGFloat? = nil
    ) -> some View {
        modifier(BubbleGuideLayerModifier(id: id, text: text, tipXFromLeading: tipXFromLeading))
    }
}

private struct BubbleGuideLayerModifier: ViewModifier {
    let id: BubbleGuideStore.ID
    let text: String
    let tipXFromLeading: CGFloat?
    @ObservedObject private var store = BubbleGuideStore.shared
    @State private var reveal = false
    @State private var targetFrame: CGRect = .null
    @State private var calloutSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(BubbleGuideFrameKey.self) { frames in
                // Clear when the target leaves the tree (e.g. Search leaves results).
                targetFrame = frames[id] ?? .null
            }
            .overlay(alignment: .topLeading) {
                if store.isVisible(id), reveal, !targetFrame.isNull, targetFrame.width > 0 {
                    let tipX = targetFrame.minX + (tipXFromLeading ?? targetFrame.width / 2)
                    let tipY = targetFrame.maxY
                    BubbleGuideCallout(text: text)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: BubbleGuideCalloutSizeKey.self,
                                    value: geo.size
                                )
                            }
                        }
                        .onPreferenceChange(BubbleGuideCalloutSizeKey.self) { calloutSize = $0 }
                        // Pin callout top-leading so arrow tip (top, tipFromTrailing from trailing)
                        // lands exactly on (tipX, tipY).
                        .offset(
                            x: tipX - max(calloutSize.width, 1) + BubbleGuideCallout.arrowTipFromTrailing,
                            y: tipY
                        )
                        .opacity(calloutSize == .zero ? 0 : 1)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing))
                        )
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard store.isVisible(id) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    guard store.isVisible(id) else { return }
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        reveal = true
                    }
                }
            }
            .onChange(of: store.revision) { _, _ in
                if !store.isVisible(id) {
                    reveal = false
                }
            }
    }
}
