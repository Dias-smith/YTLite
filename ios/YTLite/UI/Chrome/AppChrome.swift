import SwiftUI

/// Root chrome: bottom tabs on compact width; sidebar + split on regular width
/// (iPad, iPhone Duo inner display, wide Split View).
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
    }

    private var compactChrome: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ytLiteAppBackground()
                .environment(\.miniPlayerBottomInset, miniPlayerBottomInset)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSlot(docked: false)
                }

            if !isKeyboardVisible {
                MainTabBar(selected: $selectedTab, isAuthenticated: isAuthenticated)
            }
        }
    }

    private var regularChrome: some View {
        NavigationSplitView {
            NavigationStack {
                AppSidebar(selected: $selectedTab, isAuthenticated: isAuthenticated)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            // Present the player sheet from the detail column so taps on the mini
            // player (also in this column) reliably drive presentation on iPad.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ytLiteAppBackground()
                .environment(\.miniPlayerBottomInset, miniPlayerBottomInset)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSlot(docked: true)
                }
                .playerDetailPresentation(isPresented: $playerPresentation.isPresented)
        }
        .navigationSplitViewStyle(.balanced)
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

// MARK: - Bubble guide (coach marks)

/// One-shot coach-mark tips. Dismissed permanently after the linked control is used.
@MainActor
final class BubbleGuideStore: ObservableObject {
    static let shared = BubbleGuideStore()

    enum ID: String {
        case homeFilter = "bubble_guide.home_filter.v1"
        case librarySettings = "bubble_guide.library_settings.v1"
    }

    @Published private(set) var revision = 0

    func isVisible(_ id: ID) -> Bool {
        _ = revision
        return !UserDefaults.standard.bool(forKey: id.rawValue)
    }

    func dismiss(_ id: ID) {
        guard isVisible(id) else { return }
        UserDefaults.standard.set(true, forKey: id.rawValue)
        revision += 1
    }
}

/// Accent capsule with a small arrow toward the anchored control.
struct BubbleGuideCallout: View {
    let text: String
    /// Arrow points up toward a control above the callout.
    var pointsUp: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if pointsUp {
                BubbleGuideArrow()
                    .fill(YTLiteColor.accent)
                    .frame(width: 14, height: 7)
            }
            Text(text)
                .font(YTLiteType.meta.weight(.semibold))
                .foregroundStyle(YTLiteColor.onAccent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(YTLiteColor.accent, in: Capsule())
            if !pointsUp {
                BubbleGuideArrow()
                    .fill(YTLiteColor.accent)
                    .frame(width: 14, height: 7)
                    .rotationEffect(.degrees(180))
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
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
    /// Shows a one-shot bubble under the view until `BubbleGuideStore.dismiss` is called.
    func bubbleGuide(
        _ id: BubbleGuideStore.ID,
        text: String,
        alignment: Alignment = .bottomTrailing
    ) -> some View {
        modifier(BubbleGuideOverlayModifier(id: id, text: text, alignment: alignment))
    }
}

private struct BubbleGuideOverlayModifier: ViewModifier {
    let id: BubbleGuideStore.ID
    let text: String
    let alignment: Alignment
    @ObservedObject private var store = BubbleGuideStore.shared
    @State private var reveal = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if store.isVisible(id), reveal {
                    BubbleGuideCallout(text: text)
                        .offset(y: 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                }
            }
            .zIndex(store.isVisible(id) ? 2 : 0)
            .onAppear {
                guard store.isVisible(id) else { return }
                // Let the host layout settle before popping the tip.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        reveal = true
                    }
                }
            }
    }
}
