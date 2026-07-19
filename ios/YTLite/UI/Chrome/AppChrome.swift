import SwiftUI
import UIKit

/// Root chrome: bottom tabs on compact width; sidebar + split on regular (iPad).
struct AppChrome<Content: View>: View {
    @Binding var selectedTab: AppTab
    var isAuthenticated: Bool
    var isKeyboardVisible: Bool
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var review: ReviewPromptCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool {
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
        }
        // Shorts is unavailable on regular width (iPad) — leave the tab if we land there.
        .onChange(of: isRegular) { _, regular in
            if regular, selectedTab == .shorts {
                selectedTab = .home
            }
        }
        .onAppear {
            if isRegular, selectedTab == .shorts {
                selectedTab = .home
            }
        }
    }

    private var compactChrome: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(YTLiteColor.background)
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
                .background(YTLiteColor.background)
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
        playback.nowPlaying != nil && selectedTab != .shorts
    }
}
