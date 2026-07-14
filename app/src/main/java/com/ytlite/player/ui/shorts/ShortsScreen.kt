package com.ytlite.player.ui.shorts

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.web.EmbeddedWebView

object ShortsConfig {
    const val URL = "https://www.youtube.com/shorts/"

    /**
     * Hide YouTube chrome/controls, lock overlay clicks, and try to unmute autoplay media.
     * Keeps vertical swipe and player tap (play/pause) working.
     *
     * Note: some WebViews still keep muted until a real user gesture; unmute is best-effort.
     */
    val LOCK_INTERACTION_SCRIPT: String = """
        (function () {
          var CSS_ID = 'ytlite-shorts-lock-css';
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
            '}'
          ].join('\n');

          window.__ytliteShortsCssText = CSS_TEXT;

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

          /* Best-effort unmute; some WebViews still require a real user gesture. */
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

          function applyCss() {
            var el = document.getElementById(CSS_ID);
            if (!el) {
              el = document.createElement('style');
              el.id = CSS_ID;
              (document.head || document.documentElement).appendChild(el);
            }
            el.textContent = window.__ytliteShortsCssText || CSS_TEXT;
            hideOverlays();
            unmuteMedia();
          }

          window.__ytliteShortsApply = applyCss;
          applyCss();

          if (window.__ytliteShortsLockInstalled) {
            return;
          }
          window.__ytliteShortsLockInstalled = true;

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
            if (isPlayerTarget(event.target)) {
              unmuteMedia();
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
    DisposableEffect(Unit) {
        val pausedForShorts = PlaybackManager.isPlaying.value
        if (pausedForShorts) {
            PlaybackManager.pause()
        }
        onDispose {
            if (pausedForShorts) {
                PlaybackManager.play()
            }
        }
    }

    val scripts = remember { listOf(ShortsConfig.LOCK_INTERACTION_SCRIPT) }
    EmbeddedWebView(
        url = ShortsConfig.URL,
        modifier = modifier.fillMaxSize(),
        pageScripts = scripts,
    )
}
