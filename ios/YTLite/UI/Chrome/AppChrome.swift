import SwiftUI

/// Root chrome: bottom tabs on compact width (stock iPhone); sidebar + split only on
/// regular width (iPad, iPhone Duo inner display, wide Split View).
/// Compact path must stay a plain VStack + `MainTabBar` — never wrap iPhone in
/// `NavigationSplitView`, or the sidebar list replaces the normal tab UI.
struct AppChrome<Content: View>: View {
    @Binding var selectedTab: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var review: ReviewPromptCoordinator
    @ObservedObject private var librarySavePrompt = LibrarySavePromptStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale

    private var isRegular: Bool {
        // Size class only — iPhone Duo inner display is regular width (not `.pad`).
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
    }

    var body: some View {
        Group {
            if isRegular {
                regularChrome
            } else {
                compactChrome
                    .playerDetailPresentation(isPresented: $playerPresentation.isPresented)
            }
        }
        .onChange(of: playerPresentation.isPresented) { _, presented in
            review.setBusy("player", presented)
            AdSceneLifecycle.setUIBlocked("player_detail", blocked: presented)
            if !presented {
                AdSceneLifecycle.cancelPlayStartInterstitial()
            }
        }
        .ytLiteToast(playback.playbackNotice, bottomPadding: 120)
    }

    private var compactChrome: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(YTLiteColor.background)
                .environment(\.miniPlayerBottomInset, miniPlayerBottomInset)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSlot(docked: false)
                }

            if !isKeyboardVisible {
                MainTabBar(selected: $selectedTab, isAuthenticated: isAuthenticated)
            }
        }
        .coordinateSpace(name: BubbleGuideStore.coordinateSpaceName)
        .bubbleGuideLayer(
            .miniPlayerSwipe,
            text: L("guide.mini_player_swipe"),
            placement: .above,
            isActive: showsMiniPlayer && !playerPresentation.isPresented && !isKeyboardVisible
        )
    }

    private var regularChrome: some View {
        NavigationSplitView {
            NavigationStack {
                AppSidebar(selected: $selectedTab, isAuthenticated: isAuthenticated)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(YTLiteColor.background)
                .environment(\.miniPlayerBottomInset, miniPlayerBottomInset)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSlot(docked: docksMiniPlayer)
                }
                .coordinateSpace(name: BubbleGuideStore.coordinateSpaceName)
                .bubbleGuideLayer(
                    .miniPlayerSwipe,
                    text: L("guide.mini_player_swipe"),
                    placement: .above,
                    isActive: showsMiniPlayer && !playerPresentation.isPresented && !isKeyboardVisible
                )
                .playerDetailPresentation(isPresented: $playerPresentation.isPresented)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func miniPlayerSlot(docked: Bool) -> some View {
        if showsMiniPlayer {
            VStack(spacing: 0) {
                if showsPlaybackLoginPrompt {
                    PlaybackLoginBanner()
                }
                if showsLibrarySavePrompt {
                    LibrarySavePromptBanner()
                }
                MiniPlayerBar()
            }
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

    private var showsLibrarySavePrompt: Bool {
        guard showsMiniPlayer, !isKeyboardVisible, !playerPresentation.isPresented else { return false }
        guard librarySavePrompt.offerVideoId == playback.nowPlaying?.videoId else { return false }
        return !playback.isFavorite
    }

    private var showsPlaybackLoginPrompt: Bool {
        guard showsMiniPlayer, !isKeyboardVisible, !playerPresentation.isPresented else { return false }
        return playback.needsLoginForPlayback && !playback.isPlaying && !playback.isBuffering
    }

    private var miniPlayerBottomInset: CGFloat {
        guard showsMiniPlayer, !isKeyboardVisible else { return 0 }
        let saveBanner = showsLibrarySavePrompt ? LibrarySavePromptBanner.reservedHeight : 0
        let loginBanner = showsPlaybackLoginPrompt ? PlaybackLoginBanner.reservedHeight : 0
        return YTLiteLayout.miniPlayerChromeHeight(displayScale: displayScale)
            + saveBanner
            + loginBanner
            + (docksMiniPlayer ? 8 : 0)
    }

    /// iPad floats a short dock. Mac uses a full-width bar so list rows do not show beside it.
    private var docksMiniPlayer: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        isRegular
        #endif
    }
}

// MARK: - Bubble guide (coach marks)

/// Coach-mark tips — one-shot: persisted after dismiss, never shown again.
@MainActor
final class BubbleGuideStore: ObservableObject {
    static let shared = BubbleGuideStore()

    enum ID: String, Hashable {
        case homeFilter = "bubble_guide.home_filter.v1"
        case searchFilter = "bubble_guide.search_filter.v1"
        case miniPlayerSwipe = "bubble_guide.mini_player_swipe.v1"
    }

    enum Placement: Hashable {
        /// Callout below the target (Home / Search filter chips).
        case below
        /// Callout above the target (mini player near the tab bar).
        case above
    }

    /// Named coordinate space shared by `bubbleGuideTarget` + `bubbleGuideLayer`.
    static let coordinateSpaceName = "YTLite.BubbleGuide"

    @Published private(set) var revision = 0
    private var dismissedThisSession: Set<ID> = []

    func isVisible(_ id: ID) -> Bool {
        _ = revision
        if dismissedThisSession.contains(id) { return false }
        return !UserDefaults.standard.bool(forKey: id.rawValue)
    }

    func dismiss(_ id: ID) {
        guard isVisible(id) else { return }
        dismissedThisSession.insert(id)
        UserDefaults.standard.set(true, forKey: id.rawValue)
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

/// Design-mock callout: accent capsule with caret tip aimed at the target.
/// Arrow sits near the trailing side; body extends left.
struct BubbleGuideCallout: View {
    let text: String
    var placement: BubbleGuideStore.Placement = .below

    static let arrowWidth: CGFloat = 16
    static let arrowHeight: CGFloat = 8
    /// Distance from callout trailing edge to arrow tip (under filter icon).
    static let arrowTipFromTrailing: CGFloat = 22

    private var arrowOnTop: Bool { placement == .below }

    var body: some View {
        Text(text)
            .font(YTLiteType.meta.weight(.semibold))
            .foregroundStyle(YTLiteColor.onAccent)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(YTLiteColor.accent, in: Capsule())
            .overlay(alignment: arrowOnTop ? .topTrailing : .bottomTrailing) {
                BubbleGuideArrow()
                    .fill(YTLiteColor.accent)
                    .frame(width: Self.arrowWidth, height: Self.arrowHeight)
                    .rotationEffect(.degrees(arrowOnTop ? 0 : 180))
                    .offset(
                        x: -(Self.arrowTipFromTrailing - Self.arrowWidth / 2),
                        y: arrowOnTop ? -Self.arrowHeight : Self.arrowHeight
                    )
            }
            // Reserve space so the arrow stays inside the view bounds for tip math.
            .padding(.top, arrowOnTop ? Self.arrowHeight : 0)
            .padding(.bottom, arrowOnTop ? 0 : Self.arrowHeight)
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
        tipXFromLeading: CGFloat? = nil,
        placement: BubbleGuideStore.Placement = .below,
        isActive: Bool = true
    ) -> some View {
        modifier(
            BubbleGuideLayerModifier(
                id: id,
                text: text,
                tipXFromLeading: tipXFromLeading,
                placement: placement,
                isActive: isActive
            )
        )
    }
}

private struct BubbleGuideLayerModifier: ViewModifier {
    let id: BubbleGuideStore.ID
    let text: String
    let tipXFromLeading: CGFloat?
    let placement: BubbleGuideStore.Placement
    let isActive: Bool
    @ObservedObject private var store = BubbleGuideStore.shared
    @State private var reveal = false
    @State private var targetFrame: CGRect = .null
    @State private var calloutSize: CGSize = .zero

    private var shouldShow: Bool {
        isActive && store.isVisible(id) && reveal && !targetFrame.isNull && targetFrame.width > 0
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(BubbleGuideFrameKey.self) { frames in
                // Clear when the target leaves the tree (e.g. Search leaves results).
                targetFrame = frames[id] ?? .null
            }
            .overlay(alignment: .topLeading) {
                if shouldShow {
                    let tipX = targetFrame.minX + (tipXFromLeading ?? targetFrame.width / 2)
                    let tipY = placement == .below ? targetFrame.maxY : targetFrame.minY
                    BubbleGuideCallout(text: text, placement: placement)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: BubbleGuideCalloutSizeKey.self,
                                    value: geo.size
                                )
                            }
                        }
                        .onPreferenceChange(BubbleGuideCalloutSizeKey.self) { calloutSize = $0 }
                        // Pin callout so the arrow tip lands on (tipX, tipY).
                        .offset(
                            x: tipX - max(calloutSize.width, 1) + BubbleGuideCallout.arrowTipFromTrailing,
                            y: placement == .below
                                ? tipY
                                : tipY - max(calloutSize.height, 1)
                        )
                        .opacity(calloutSize == .zero ? 0 : 1)
                        .transition(
                            .opacity.combined(
                                with: .scale(
                                    scale: 0.92,
                                    anchor: placement == .below ? .topTrailing : .bottomTrailing
                                )
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                scheduleRevealIfNeeded()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    scheduleRevealIfNeeded()
                } else {
                    reveal = false
                }
            }
            .onChange(of: store.revision) { _, _ in
                if !store.isVisible(id) {
                    reveal = false
                }
            }
    }

    private func scheduleRevealIfNeeded() {
        guard store.isVisible(id) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard store.isVisible(id) else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                reveal = true
            }
        }
    }
}
