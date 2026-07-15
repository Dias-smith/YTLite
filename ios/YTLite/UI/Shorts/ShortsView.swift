import SwiftUI
import WebKit

enum ShortsConfig {
    static let url = URL(string: "https://www.youtube.com/shorts/")!
    static let lockScript = """
    (function () {
      if (document.getElementById('ytlite-shorts-lock-css')) return;
      var style = document.createElement('style');
      style.id = 'ytlite-shorts-lock-css';
      style.textContent = [
        'ytd-masthead, #masthead-container, ytm-mobile-topbar-renderer,',
        'ytm-pivot-bar-renderer, #guide-button, ytd-searchbox {',
        '  display: none !important; height: 0 !important; visibility: hidden !important;',
        '}'
      ].join('\\n');
      document.documentElement.appendChild(style);
      window.__ytliteShortsNudge = function(dir) {
        try {
          var dy = dir === 'up' ? -120 : 120;
          window.scrollBy({ top: dy, behavior: 'smooth' });
        } catch (e) {}
      };
    })();
    """
}

struct ShortsView: View {
    @EnvironmentObject private var playback: PlaybackController
    @State private var unlocked = false
    @State private var webView: WKWebView?

    var body: some View {
        ZStack {
            ShortsWebView(
                url: ShortsConfig.url,
                lockScript: ShortsConfig.lockScript,
                isInteractive: unlocked,
                onWebView: { webView = $0 }
            )
            .ignoresSafeArea(edges: .bottom)

            if !unlocked {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Shorts")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Tap play to unmute Shorts. App playback will pause.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        if playback.isPlaying {
                            playback.togglePlayPause()
                        }
                        unlocked = true
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color.orange, in: Circle())
                    }
                    .accessibilityLabel("Play Shorts")
                }
            }
        }
        .onDisappear {
            // Keep web state; lock again when leaving is optional.
        }
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
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        view.isUserInteractionEnabled = isInteractive
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
