import SwiftUI
import WebKit

enum ShortsConfig {
    static let url = URL(string: "https://www.youtube.com/shorts/")!
    /// Hides selected Shorts chrome without touching the player surface.
    /// Keep selectors tight — broad aria/text matches previously hid parents and broke playback.
    static let lockScript = """
    (function () {
      var CSS_ID = 'ytlite-shorts-lock-css';
      var CSS_TEXT = [
        'ytd-masthead, #masthead-container, #masthead, ytm-mobile-topbar-renderer,',
        'ytm-pivot-bar-renderer, ytd-miniapp-header-renderer, #guide-button,',
        'ytd-searchbox, #search-icon-legacy, tp-yt-app-toolbar.ytd-masthead {',
        '  display: none !important; height: 0 !important; max-height: 0 !important;',
        '  overflow: hidden !important; visibility: hidden !important; pointer-events: none !important;',
        '}',
        'ytd-reel-player-overlay-renderer #menu-button,',
        'ytd-reel-player-overlay-renderer #menu,',
        'ytd-reel-player-overlay-renderer #button-bar,',
        'ytd-reel-player-overlay-renderer ytd-menu-renderer,',
        'ytd-reel-player-header-renderer #menu,',
        'ytd-reel-player-header-renderer ytd-menu-renderer,',
        'ytd-reel-video-renderer #menu-button,',
        'ytd-reel-video-renderer #menu,',
        'ytd-reel-video-renderer ytd-menu-renderer,',
        'ytm-reel-player-overlay-renderer #menu-button,',
        'ytm-reel-player-overlay-renderer ytm-menu-renderer,',
        'shorts-page #menu-button,',
        '#shorts-panel #menu-button,',
        'ytd-reel-player-overlay-renderer #actions,',
        'ytd-reel-player-overlay-renderer #like-button,',
        'ytd-reel-player-overlay-renderer #dislike-button,',
        'ytd-reel-player-overlay-renderer #comments-button,',
        'ytd-reel-player-overlay-renderer #share-button,',
        'ytd-reel-player-overlay-renderer #remix-button,',
        'ytd-reel-player-overlay-renderer #sound-button,',
        'ytd-reel-player-overlay-renderer ytd-subscribe-button-renderer,',
        'ytd-reel-player-overlay-renderer #subscribe-button,',
        'ytd-reel-video-renderer #actions,',
        'ytm-reel-player-overlay-renderer #actions,',
        'reel-player-overlay-actions, reel-action-bar-view-model,',
        'like-button-view-model, dislike-button-view-model,',
        'comment-button-view-model, share-button-view-model,',
        'ytd-segmented-like-dislike-button-renderer,',
        'ytd-subscribe-button-renderer, subscribe-button-view-model, #subscribe-button,',
        'ytm-shorts-search-suggestion, ytm-searchbox, ytm-mobile-searchbox-v2,',
        'button[aria-label*="More actions"], button[aria-label*="More options"],',
        'button[aria-label*="Action menu"], button[aria-label="More"],',
        'yt-icon-button[aria-label*="More actions"], yt-icon-button[aria-label*="More options"],',
        'yt-icon-button[aria-label*="Action menu"], yt-icon-button[aria-label="More"],',
        'button[aria-label*="Subscribe"], button[aria-label*="subscribe"], button[aria-label*="订阅"],',
        'a[aria-label*="Subscribe"], a[aria-label*="subscribe"], a[aria-label*="订阅"],',
        'button[aria-label^="Search"], a[aria-label^="Search"],',
        'button[aria-label^="搜索"], a[aria-label^="搜索"] {',
        '  display: none !important; visibility: hidden !important; pointer-events: none !important;',
        '  width: 0 !important; height: 0 !important; margin: 0 !important; padding: 0 !important;',
        '  overflow: hidden !important;',
        '}'
      ].join('\\n');

      window.__ytliteShortsCssText = CSS_TEXT;
      if (typeof window.__ytliteShortsArmed !== 'boolean') {
        window.__ytliteShortsArmed = false;
      }

      function queryDeep(root, selector) {
        var out = [];
        function walk(node) {
          if (!node) return;
          if (node.querySelectorAll) {
            try {
              var list = node.querySelectorAll(selector);
              for (var i = 0; i < list.length; i++) out.push(list[i]);
            } catch (e) {}
          }
          var all = node.querySelectorAll ? node.querySelectorAll('*') : [];
          for (var j = 0; j < all.length; j++) {
            if (all[j].shadowRoot) walk(all[j].shadowRoot);
          }
        }
        walk(root);
        return out;
      }

      function hideEl(el) {
        if (!el || !el.style) return;
        try {
          var tag = (el.tagName || '').toLowerCase();
          if (tag === 'video' || tag === 'ytd-player' || tag === 'ytm-player') return;
          if (el.id === 'player' || el.id === 'movie_player') return;
          if (el.classList && el.classList.contains('html5-video-player')) return;
        } catch (e) {}
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
        el.style.setProperty('pointer-events', 'none', 'important');
      }

      function hideOverlays() {
        var selectors = [
          '#actions', '#menu-button', '#menu', '#button-bar',
          '#like-button', '#dislike-button', '#comments-button',
          '#share-button', '#remix-button', '#sound-button',
          '#subscribe-button', 'ytd-subscribe-button-renderer', 'subscribe-button-view-model',
          'like-button-view-model', 'dislike-button-view-model',
          'comment-button-view-model', 'share-button-view-model',
          'reel-player-overlay-actions', 'reel-action-bar-view-model',
          'ytd-menu-renderer', 'ytm-menu-renderer',
          'ytm-shorts-search-suggestion', 'ytm-searchbox'
        ];
        for (var s = 0; s < selectors.length; s++) {
          var found = queryDeep(document, selectors[s]);
          for (var i = 0; i < found.length; i++) hideEl(found[i]);
        }
        hideTopRightOverflowMenu();
        hideSearchChip();
      }

      function hideTopRightOverflowMenu() {
        var MENU_ARIA = /^(more actions|more options|action menu|options|更多|菜单|选项)/i;
        var nodes = queryDeep(document, 'button, yt-icon-button, [role="button"]');
        var vw = window.innerWidth || document.documentElement.clientWidth || 0;
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          var aria = '';
          try {
            aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
          } catch (e) {}
          var byLabel = MENU_ARIA.test(aria);
          var byPos = false;
          try {
            var rect = el.getBoundingClientRect();
            byPos = rect.width > 0 && rect.height > 0 &&
              rect.width <= 56 && rect.height <= 56 &&
              rect.top >= 0 && rect.top < 120 &&
              rect.right > vw - 72 && rect.left > vw * 0.7;
          } catch (e2) {}
          if (byLabel || byPos) hideEl(el);
        }
      }

      function hideSearchChip() {
        var nodes = queryDeep(document, 'button, a, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          var aria = '';
          var text = '';
          try {
            aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
            text = (el.innerText || '').replace(/\\s+/g, ' ').trim();
          } catch (e) {}
          if (text.length > 80) continue;
          var isSearch = /^(search|搜索)\\b/i.test(aria) || /^(search|搜索)\\s*["“]/i.test(text);
          var isSub = /^(subscribe|订阅)\\b/i.test(aria) || /^(subscribe|订阅)$/i.test(text);
          if (isSearch || isSub) hideEl(el);
        }
      }

      function applyCss() {
        var el = document.getElementById(CSS_ID);
        if (!el) {
          el = document.createElement('style');
          el.id = CSS_ID;
          (document.head || document.documentElement).appendChild(el);
        }
        el.textContent = window.__ytliteShortsCssText || CSS_TEXT;
        hideOverlays();
      }

      window.__ytliteShortsBegin = function () {
        window.__ytliteShortsArmed = true;
        function unmuteAndPlay() {
          var videos = queryDeep(document, 'video');
          for (var i = 0; i < videos.length; i++) {
            try {
              videos[i].muted = false;
              videos[i].defaultMuted = false;
              videos[i].volume = 1;
              videos[i].removeAttribute('muted');
              var p = videos[i].play();
              if (p && typeof p.catch === 'function') p.catch(function () {});
            } catch (e) {}
          }
        }
        unmuteAndPlay();
        setTimeout(unmuteAndPlay, 120);
        setTimeout(unmuteAndPlay, 400);
      };

      window.__ytliteShortsNudge = function (dir) {
        try {
          var dy = typeof dir === 'number' ? dir : (dir === 'up' ? -120 : 120);
          window.scrollBy({ top: dy, behavior: 'smooth' });
        } catch (e) {}
      };

      window.__ytliteShortsApply = applyCss;
      applyCss();

      if (window.__ytliteShortsLockInstalled) return;
      window.__ytliteShortsLockInstalled = true;

      var applyScheduled = false;
      function scheduleApply() {
        if (applyScheduled) return;
        applyScheduled = true;
        setTimeout(function () {
          applyScheduled = false;
          applyCss();
        }, 80);
      }

      try {
        new MutationObserver(scheduleApply).observe(document.documentElement, {
          childList: true,
          subtree: true
        });
      } catch (e) {}

      setInterval(applyCss, 600);
    })();
    """
}

struct ShortsView: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var unlocked = false
    @State private var webView: WKWebView?

    private var usesPhoneFrame: Bool {
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
    }

    var body: some View {
        GeometryReader { geo in
            let frame = shortsFrame(in: geo.size)
            ZStack {
                YTLiteColor.background.ignoresSafeArea()

                ZStack {
                    ShortsWebView(
                        url: ShortsConfig.url,
                        lockScript: ShortsConfig.lockScript,
                        isInteractive: unlocked,
                        onWebView: { webView = $0 }
                    )

                    if !unlocked {
                        Color.black.opacity(0.45)
                        VStack(spacing: YTLiteLayout.screenPadding) {
                            Text(L("shorts.title"))
                                .font(YTLiteType.emptyTitle)
                                .foregroundStyle(YTLiteColor.onMedia)
                            Text(L("shorts.unmute_hint"))
                                .font(YTLiteType.body)
                                .foregroundStyle(YTLiteColor.onMediaMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button {
                                if playback.isPlaying {
                                    playback.togglePlayPause()
                                }
                                unlocked = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    webView?.evaluateJavaScript(
                                        "window.__ytliteShortsBegin && window.__ytliteShortsBegin();",
                                        completionHandler: nil
                                    )
                                }
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.title)
                                    .foregroundStyle(YTLiteColor.onAccent)
                                    .frame(width: 72, height: 72)
                                    .background(YTLiteColor.accent, in: Circle())
                            }
                            .accessibilityLabel(L("shorts.play"))
                        }
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .clipShape(RoundedRectangle(cornerRadius: usesPhoneFrame ? 24 : 0, style: .continuous))
                .overlay {
                    if usesPhoneFrame {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(YTLiteColor.chromeDivider, lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(edges: usesPhoneFrame ? [] : .bottom)
    }

    private func shortsFrame(in size: CGSize) -> CGSize {
        guard usesPhoneFrame else {
            return size
        }
        let maxWidth = min(YTLiteAdaptive.shortsFrameWidth, size.width - 48)
        let heightFromWidth = maxWidth / YTLiteAdaptive.shortsAspect
        let maxHeight = size.height - 32
        if heightFromWidth <= maxHeight {
            return CGSize(width: maxWidth, height: heightFromWidth)
        }
        let widthFromHeight = maxHeight * YTLiteAdaptive.shortsAspect
        return CGSize(width: widthFromHeight, height: maxHeight)
    }
}

struct ShortsWebView: UIViewRepresentable {
    let url: URL
    let lockScript: String
    let isInteractive: Bool
    var onWebView: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(lockScript: lockScript)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let userScript = WKUserScript(
            source: lockScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        view.isUserInteractionEnabled = isInteractive
        view.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        view.load(URLRequest(url: url))
        onWebView(view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.isUserInteractionEnabled = isInteractive
        onWebView(uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let lockScript: String
        init(lockScript: String) { self.lockScript = lockScript }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(lockScript, completionHandler: nil)
        }
    }
}
