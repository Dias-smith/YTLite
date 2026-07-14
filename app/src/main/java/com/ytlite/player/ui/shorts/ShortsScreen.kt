package com.ytlite.player.ui.shorts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.theme.Orange40
import com.ytlite.player.ui.web.EmbeddedWebView
import com.ytlite.player.ui.web.EmbeddedWebViewHandle
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

object ShortsConfig {
    const val URL = "https://www.youtube.com/shorts/"

    /**
     * Hide YouTube chrome/controls and aggressively freeze media until native play begins.
     * Vertical swipe while idle is forwarded from Compose via [__ytliteShortsNudge].
     */
    val LOCK_INTERACTION_SCRIPT: String = """
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
            'ytd-reel-player-overlay-renderer yt-icon-button,',
            'ytd-reel-player-overlay-renderer button-view-model,',
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
            'reel-player-overlay-actions, reel-action-bar-view-model,',
            'like-button-view-model, dislike-button-view-model,',
            'ytd-segmented-like-dislike-button-renderer,',
            'ytd-subscribe-button-renderer, subscribe-button-view-model, #subscribe-button,',
            'button[aria-label*="More"], button[aria-label*="more"], button[aria-label*="更多"],',
            'button[aria-label*="Action menu"], button[aria-label*="Options"],',
            'button[aria-label*="选项"], button[aria-label*="菜单"],',
            'yt-icon-button[aria-label*="More"], yt-icon-button[aria-label*="more"],',
            'yt-icon-button[aria-label*="更多"], yt-icon-button[aria-label*="Action menu"],',
            'button[aria-label*="Subscribe"], button[aria-label*="subscribe"], button[aria-label*="订阅"] {',
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
              'reel-player-overlay-actions', 'reel-action-bar-view-model',
              'ytd-menu-renderer', 'ytm-menu-renderer'
            ];
            for (var s = 0; s < selectors.length; s++) {
              var found = queryDeep(document, selectors[s]);
              for (var i = 0; i < found.length; i++) hideEl(found[i]);
            }
            hideTopRightOverflowMenu();
          }

          function hideTopRightOverflowMenu() {
            var MENU_ARIA = /more|menu|options|action menu|overflow|更多|菜单|选项/i;
            var nodes = queryDeep(
              document,
              'button, yt-icon-button, yt-button-shape, button-view-model, [role="button"]'
            );
            var vw = window.innerWidth || document.documentElement.clientWidth || 0;
            for (var i = 0; i < nodes.length; i++) {
              var el = nodes[i];
              var aria = '';
              try {
                aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
                if (!aria && el.querySelector) {
                  var labeled = el.querySelector('[aria-label]');
                  if (labeled) aria = labeled.getAttribute('aria-label') || '';
                }
              } catch (e) {}
              var byLabel = MENU_ARIA.test(aria);
              var byPos = false;
              try {
                var rect = el.getBoundingClientRect();
                // Top-right kebab / overflow control on Shorts overlay.
                byPos = rect.width > 0 && rect.height > 0 &&
                  rect.width <= 64 && rect.height <= 64 &&
                  rect.top >= 0 && rect.top < 140 &&
                  rect.right > vw - 96 && rect.left > vw * 0.55;
              } catch (e2) {}
              if (byLabel || byPos) {
                hideEl(el);
                try {
                  var host = el.closest && (
                    el.closest('ytd-menu-renderer') ||
                    el.closest('ytm-menu-renderer') ||
                    el.closest('yt-button-shape') ||
                    el.closest('button-view-model') ||
                    el.closest('#menu-button') ||
                    el.closest('#menu')
                  );
                  if (host) hideEl(host);
                } catch (e3) {}
              }
            }
          }

          function freezeIdleMedia() {
            if (window.__ytliteShortsArmed) return;
            var videos = queryDeep(document, 'video');
            for (var i = 0; i < videos.length; i++) {
              var v = videos[i];
              try {
                v.autoplay = false;
                v.removeAttribute('autoplay');
                v.muted = true;
                if (!v.paused) v.pause();
              } catch (e) {}
            }
            var players = queryDeep(document, '#movie_player, .html5-video-player');
            for (var p = 0; p < players.length; p++) {
              try {
                if (typeof players[p].pauseVideo === 'function') players[p].pauseVideo();
                if (typeof players[p].mute === 'function') players[p].mute();
              } catch (e2) {}
            }
          }

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
            var players = queryDeep(document, '#movie_player, .html5-video-player');
            for (var j = 0; j < players.length; j++) {
              try {
                if (typeof players[j].unMute === 'function') players[j].unMute();
                if (typeof players[j].setMuted === 'function') players[j].setMuted(false);
                if (typeof players[j].setVolume === 'function') players[j].setVolume(100);
                if (typeof players[j].playVideo === 'function') players[j].playVideo();
              } catch (e2) {}
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
            freezeIdleMedia();
          }

          window.__ytliteShortsBegin = function () {
            window.__ytliteShortsArmed = true;
            unmuteAndPlay();
            setTimeout(unmuteAndPlay, 100);
            setTimeout(unmuteAndPlay, 300);
            setTimeout(unmuteAndPlay, 700);
          };

          window.__ytliteShortsNudge = function (dy) {
            if (window.__ytliteShortsArmed) return;
            var delta = -Number(dy || 0);
            if (!delta) return;
            var roots = [
              document.querySelector('#shorts-container'),
              document.querySelector('#shorts-inner-container'),
              document.querySelector('ytd-shorts'),
              document.scrollingElement,
              document.documentElement,
              document.body
            ];
            for (var i = 0; i < roots.length; i++) {
              var root = roots[i];
              if (!root) continue;
              try {
                if (root.scrollHeight > root.clientHeight + 8) {
                  root.scrollTop += delta;
                  return;
                }
              } catch (e) {}
            }
            try { window.scrollBy(0, delta); } catch (e2) {}
          };

          window.__ytliteShortsApply = applyCss;
          applyCss();

          if (window.__ytliteShortsLockInstalled) return;
          window.__ytliteShortsLockInstalled = true;

          document.addEventListener('play', function (event) {
            if (!window.__ytliteShortsArmed && event.target && event.target.tagName === 'VIDEO') {
              try {
                event.target.pause();
                event.target.muted = true;
              } catch (e) {}
            }
          }, true);

          document.addEventListener('click', function (event) {
            if (window.__ytliteShortsArmed) return;
            event.preventDefault();
            event.stopPropagation();
            if (typeof event.stopImmediatePropagation === 'function') {
              event.stopImmediatePropagation();
            }
          }, true);

          var applyScheduled = false;
          function scheduleApply() {
            if (applyScheduled) return;
            applyScheduled = true;
            setTimeout(function () {
              applyScheduled = false;
              applyCss();
            }, 60);
          }

          try {
            new MutationObserver(scheduleApply).observe(document.documentElement, {
              childList: true,
              subtree: true
            });
          } catch (e) {}

          setInterval(applyCss, 400);

          (function freezeLoop() {
            freezeIdleMedia();
            if (!window.__ytliteShortsArmed) {
              requestAnimationFrame(freezeLoop);
            }
          })();
        })();
    """.trimIndent()
}

@Composable
fun ShortsScreen(
    modifier: Modifier = Modifier,
) {
    val webHandle = remember { EmbeddedWebViewHandle() }
    val scripts = remember { listOf(ShortsConfig.LOCK_INTERACTION_SCRIPT) }
    val scope = rememberCoroutineScope()
    var awaitingUserPlay by remember { mutableStateOf(true) }

    Box(modifier = modifier.fillMaxSize()) {
        EmbeddedWebView(
            url = ShortsConfig.URL,
            modifier = Modifier.fillMaxSize(),
            pageScripts = scripts,
            handle = webHandle,
            mediaPlaybackRequiresUserGesture = true,
        )

        if (awaitingUserPlay) {
            // Blocks WebView taps (prevents YouTube mute-autoplay / silent UI) while still
            // allowing vertical swipes via JS nudge.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.18f))
                    .pointerInput(Unit) {
                        detectVerticalDragGestures { _, dragAmount ->
                            webHandle.evaluateJavascript(
                                "window.__ytliteShortsNudge && window.__ytliteShortsNudge($dragAmount)",
                            )
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.55f))
                        .clickable {
                            scope.launch {
                                if (PlaybackManager.isPlaying.value) {
                                    PlaybackManager.pause()
                                    withTimeoutOrNull(500) {
                                        PlaybackManager.isPlaying.first { !it }
                                    }
                                    delay(120)
                                }
                                // Focus released: now enable media and start with sound in one shot.
                                webHandle.setMediaPlaybackRequiresUserGesture(false)
                                webHandle.evaluateJavascript(
                                    "(function(){ if (window.__ytliteShortsBegin) window.__ytliteShortsBegin(); })();",
                                )
                                awaitingUserPlay = false
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.PlayArrow,
                        contentDescription = null,
                        tint = Orange40,
                        modifier = Modifier.size(40.dp),
                    )
                }
            }
        }
    }
}
