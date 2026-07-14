package com.ytlite.player.ui.shorts

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.web.EmbeddedWebView
import com.ytlite.player.ui.web.WebViewJsBridge

object ShortsConfig {
    const val URL = "https://www.youtube.com/shorts/"
    const val JS_BRIDGE_NAME = "YTLiteShorts"

    /**
     * Hide YouTube chrome/controls, keep Shorts paused until the user taps play.
     * Vertical swipe still works; after the user starts, player tap toggles play/pause.
     */
    val LOCK_INTERACTION_SCRIPT: String = """
        (function () {
          var CSS_ID = 'ytlite-shorts-lock-css';
          var PLAY_BTN_ID = 'ytlite-shorts-play-btn';
          var CSS_TEXT = [
            '/* Hide YouTube top chrome */',
            'ytd-masthead,',
            '#masthead-container,',
            '#masthead,',
            'ytm-mobile-topbar-renderer,',
            'ytm-pivot-bar-renderer,',
            'ytd-miniapp-header-renderer,',
            '#guide-button,',
            'ytd-searchbox,',
            '#search-icon-legacy,',
            'tp-yt-app-toolbar.ytd-masthead {',
            '  display: none !important;',
            '  height: 0 !important;',
            '  max-height: 0 !important;',
            '  overflow: hidden !important;',
            '  visibility: hidden !important;',
            '  pointer-events: none !important;',
            '}',
            '/* Hide Shorts: more menu, subscribe, right action rail */',
            'ytd-reel-player-overlay-renderer #menu-button,',
            'ytd-reel-player-overlay-renderer #button-bar,',
            'ytd-reel-player-overlay-renderer #actions,',
            'ytd-reel-player-overlay-renderer #like-button,',
            'ytd-reel-player-overlay-renderer #dislike-button,',
            'ytd-reel-player-overlay-renderer #comments-button,',
            'ytd-reel-player-overlay-renderer #share-button,',
            'ytd-reel-player-overlay-renderer #remix-button,',
            'ytd-reel-player-overlay-renderer #sound-button,',
            'ytd-reel-player-overlay-renderer ytd-subscribe-button-renderer,',
            'ytd-reel-player-overlay-renderer #subscribe-button,',
            'ytd-reel-video-renderer #menu-button,',
            'ytd-reel-video-renderer #actions,',
            'reel-player-overlay-actions,',
            'reel-action-bar-view-model,',
            'like-button-view-model,',
            'dislike-button-view-model,',
            'ytd-segmented-like-dislike-button-renderer,',
            'ytd-subscribe-button-renderer,',
            'subscribe-button-view-model,',
            '#subscribe-button,',
            'button[aria-label*="More"],',
            'button[aria-label*="more"],',
            'button[aria-label*="更多"],',
            'button[aria-label*="Subscribe"],',
            'button[aria-label*="subscribe"],',
            'button[aria-label*="订阅"] {',
            '  display: none !important;',
            '  visibility: hidden !important;',
            '  pointer-events: none !important;',
            '  width: 0 !important;',
            '  height: 0 !important;',
            '  margin: 0 !important;',
            '  padding: 0 !important;',
            '  overflow: hidden !important;',
            '}',
            '#' + PLAY_BTN_ID + ' {',
            '  position: fixed !important;',
            '  left: 50% !important;',
            '  top: 50% !important;',
            '  transform: translate(-50%, -50%) !important;',
            '  z-index: 2147483646 !important;',
            '  width: 72px !important;',
            '  height: 72px !important;',
            '  border-radius: 50% !important;',
            '  border: none !important;',
            '  background: rgba(0,0,0,0.55) !important;',
            '  box-shadow: 0 2px 12px rgba(0,0,0,0.35) !important;',
            '  display: flex !important;',
            '  align-items: center !important;',
            '  justify-content: center !important;',
            '  padding: 0 !important;',
            '  margin: 0 !important;',
            '  cursor: pointer !important;',
            '  pointer-events: auto !important;',
            '}',
            '#' + PLAY_BTN_ID + '[hidden] {',
            '  display: none !important;',
            '}',
            '#' + PLAY_BTN_ID + ' svg {',
            '  width: 34px !important;',
            '  height: 34px !important;',
            '  margin-left: 4px !important;',
            '  fill: #ff6d00 !important;',
            '  pointer-events: none !important;',
            '}'
          ].join('\n');

          window.__ytliteShortsCssText = CSS_TEXT;
          if (typeof window.__ytliteShortsArmed !== 'boolean') {
            window.__ytliteShortsArmed = false;
          }

          function hideEl(el) {
            if (!el || !el.style) return;
            el.style.setProperty('display', 'none', 'important');
            el.style.setProperty('visibility', 'hidden', 'important');
            el.style.setProperty('pointer-events', 'none', 'important');
            el.setAttribute('aria-hidden', 'true');
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

          var HIDE_SELECTORS = [
            '#actions',
            '#menu-button',
            '#button-bar',
            '#like-button',
            '#dislike-button',
            '#comments-button',
            '#share-button',
            '#remix-button',
            '#sound-button',
            '#subscribe-button',
            'ytd-subscribe-button-renderer',
            'subscribe-button-view-model',
            'like-button-view-model',
            'dislike-button-view-model',
            'reel-player-overlay-actions',
            'reel-action-bar-view-model',
            'ytd-segmented-like-dislike-button-renderer'
          ];

          var ARIA_HIDE = /like|dislike|comment|share|remix|more options|more actions|subscribe|喜欢|不喜欢|评论|分享|混剪|更多|订阅/i;

          function hideByAriaAndText(root) {
            var nodes = queryDeep(root, 'button, a, [role="button"], yt-button-shape, yt-touch-feedback-shape');
            for (var i = 0; i < nodes.length; i++) {
              var el = nodes[i];
              if (el.id === PLAY_BTN_ID) continue;
              var aria = '';
              try {
                aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
                if (!aria && el.querySelector) {
                  var labeled = el.querySelector('[aria-label]');
                  if (labeled) aria = labeled.getAttribute('aria-label') || '';
                }
              } catch (e) {}
              var text = '';
              try {
                text = ((el.innerText || el.textContent || '') + '').replace(/\s+/g, ' ').trim();
              } catch (e2) {}
              if (ARIA_HIDE.test(aria) || /^(subscribe|订阅)$/i.test(text)) {
                hideEl(el);
              }
            }
          }

          function hideOverlays() {
            var root = document;
            for (var s = 0; s < HIDE_SELECTORS.length; s++) {
              var found = queryDeep(root, HIDE_SELECTORS[s]);
              for (var i = 0; i < found.length; i++) hideEl(found[i]);
            }
            hideByAriaAndText(root);
            var overlays = queryDeep(root, 'ytd-reel-player-overlay-renderer, ytm-reel-player-overlay-renderer');
            for (var o = 0; o < overlays.length; o++) {
              for (var s2 = 0; s2 < HIDE_SELECTORS.length; s2++) {
                var nested = queryDeep(overlays[o], HIDE_SELECTORS[s2]);
                for (var n = 0; n < nested.length; n++) hideEl(nested[n]);
              }
              hideByAriaAndText(overlays[o]);
            }
          }

          function unmuteMedia() {
            var videos = queryDeep(document, 'video');
            for (var i = 0; i < videos.length; i++) {
              try {
                videos[i].muted = false;
                videos[i].defaultMuted = false;
                videos[i].volume = 1;
                videos[i].removeAttribute('muted');
              } catch (e) {}
            }
            var players = queryDeep(document, '#movie_player, .html5-video-player');
            for (var p = 0; p < players.length; p++) {
              var player = players[p];
              try {
                if (typeof player.unMute === 'function') player.unMute();
                if (typeof player.setVolume === 'function') player.setVolume(100);
                if (typeof player.setMuted === 'function') player.setMuted(false);
              } catch (e2) {}
            }
          }

          function pauseAllVideos() {
            var videos = queryDeep(document, 'video');
            for (var i = 0; i < videos.length; i++) {
              try {
                videos[i].pause();
                videos[i].muted = true;
              } catch (e) {}
            }
            var players = queryDeep(document, '#movie_player, .html5-video-player');
            for (var p = 0; p < players.length; p++) {
              var player = players[p];
              try {
                if (typeof player.pauseVideo === 'function') player.pauseVideo();
                if (typeof player.mute === 'function') player.mute();
              } catch (e2) {}
            }
          }

          function playActiveVideo() {
            var videos = queryDeep(document, 'video');
            var target = null;
            for (var i = 0; i < videos.length; i++) {
              var rect = videos[i].getBoundingClientRect();
              if (rect.width > 40 && rect.height > 40 &&
                  rect.top < window.innerHeight && rect.bottom > 0) {
                target = videos[i];
                break;
              }
            }
            if (!target && videos.length) target = videos[0];
            if (target) {
              try {
                target.muted = false;
                var p = target.play();
                if (p && typeof p.catch === 'function') p.catch(function () {});
              } catch (e) {}
            }
            var players = queryDeep(document, '#movie_player, .html5-video-player');
            for (var j = 0; j < players.length; j++) {
              try {
                if (typeof players[j].playVideo === 'function') players[j].playVideo();
                if (typeof players[j].unMute === 'function') players[j].unMute();
              } catch (e2) {}
            }
          }

          function isAnyVideoPlaying() {
            var videos = queryDeep(document, 'video');
            for (var i = 0; i < videos.length; i++) {
              try {
                if (!videos[i].paused && !videos[i].ended) return true;
              } catch (e) {}
            }
            return false;
          }

          function ensurePlayButton() {
            var btn = document.getElementById(PLAY_BTN_ID);
            if (!btn) {
              btn = document.createElement('button');
              btn.id = PLAY_BTN_ID;
              btn.type = 'button';
              btn.setAttribute('aria-label', 'Play');
              btn.innerHTML =
                '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">' +
                '<path d="M8 5v14l11-7z"/></svg>';
              btn.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                startShortsPlayback();
              }, true);
              (document.body || document.documentElement).appendChild(btn);
            }
            return btn;
          }

          function setPlayButtonVisible(visible) {
            var btn = ensurePlayButton();
            if (visible) {
              btn.removeAttribute('hidden');
            } else {
              btn.setAttribute('hidden', 'true');
            }
          }

          function startShortsPlayback() {
            window.__ytliteShortsArmed = true;
            try {
              if (window.YTLiteShorts && typeof window.YTLiteShorts.pauseAppMusic === 'function') {
                window.YTLiteShorts.pauseAppMusic();
              }
            } catch (e) {}
            unmuteMedia();
            playActiveVideo();
            setPlayButtonVisible(false);
          }

          function syncPlaybackUi() {
            if (!window.__ytliteShortsArmed) {
              pauseAllVideos();
              setPlayButtonVisible(true);
              return;
            }
            setPlayButtonVisible(!isAnyVideoPlaying());
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
            syncPlaybackUi();
          }

          window.__ytliteShortsApply = applyCss;
          window.__ytliteShortsStart = startShortsPlayback;
          applyCss();

          if (window.__ytliteShortsLockInstalled) {
            return;
          }
          window.__ytliteShortsLockInstalled = true;

          function isOurPlayButton(node) {
            return !!(node && node.closest && node.closest('#' + PLAY_BTN_ID));
          }

          function isPlayerTarget(node) {
            if (!node || !node.closest) return false;
            return !!(
              node.closest('video') ||
              node.closest('.html5-video-player') ||
              node.closest('#movie_player') ||
              node.closest('#player') ||
              node.closest('ytd-player') ||
              node.closest('.player-container') ||
              node.closest('#player-container')
            );
          }

          function isBlockedControl(node) {
            if (!node || !node.closest) return false;
            if (isOurPlayButton(node)) return false;
            if (isPlayerTarget(node)) return false;
            return !!(
              node.closest('button') ||
              node.closest('a') ||
              node.closest('[role="button"]') ||
              node.closest('yt-button-shape') ||
              node.closest('ytd-button-renderer') ||
              node.closest('ytd-toggle-button-renderer') ||
              node.closest('like-button-view-model') ||
              node.closest('dislike-button-view-model') ||
              node.closest('ytd-subscribe-button-renderer') ||
              node.closest('subscribe-button-view-model') ||
              node.closest('#actions') ||
              node.closest('#menu-button') ||
              node.closest('#button-bar') ||
              node.closest('reel-player-overlay-actions') ||
              node.closest('reel-action-bar-view-model') ||
              node.closest('#masthead-container') ||
              node.closest('ytd-masthead')
            );
          }

          function onClickCapture(event) {
            if (isOurPlayButton(event.target)) return;
            if (!window.__ytliteShortsArmed && isPlayerTarget(event.target)) {
              event.preventDefault();
              event.stopPropagation();
              if (typeof event.stopImmediatePropagation === 'function') {
                event.stopImmediatePropagation();
              }
              startShortsPlayback();
              return;
            }
            if (isPlayerTarget(event.target)) {
              setTimeout(syncPlaybackUi, 0);
              return;
            }
            if (isBlockedControl(event.target)) {
              event.preventDefault();
              event.stopPropagation();
              if (typeof event.stopImmediatePropagation === 'function') {
                event.stopImmediatePropagation();
              }
            }
          }

          document.addEventListener('click', onClickCapture, true);
          document.addEventListener('auxclick', onClickCapture, true);

          document.addEventListener('play', function (event) {
            if (!window.__ytliteShortsArmed && event.target && event.target.tagName === 'VIDEO') {
              try { event.target.pause(); } catch (e) {}
            }
          }, true);

          document.addEventListener('pause', function () {
            setTimeout(syncPlaybackUi, 0);
          }, true);

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
            var observer = new MutationObserver(scheduleApply);
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true
            });
          } catch (e) {}

          setInterval(applyCss, 1500);
        })();
    """.trimIndent()
}

@Composable
fun ShortsScreen(
    modifier: Modifier = Modifier,
) {
    val jsBridge = remember {
        WebViewJsBridge(
            onPauseAppMusic = {
                if (PlaybackManager.isPlaying.value) {
                    PlaybackManager.pause()
                }
            },
        )
    }
    val scripts = remember { listOf(ShortsConfig.LOCK_INTERACTION_SCRIPT) }
    EmbeddedWebView(
        url = ShortsConfig.URL,
        modifier = modifier.fillMaxSize(),
        pageScripts = scripts,
        jsBridgeName = ShortsConfig.JS_BRIDGE_NAME,
        jsBridge = jsBridge,
    )
}
