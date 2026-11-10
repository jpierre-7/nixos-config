// ==UserScript==
// @name        YouTube ads
// @description Hide YouTube's ad slots and skip its video ads
// @match       *://www.youtube.com/*
// @match       *://m.youtube.com/*
// @run-at      document-start
// ==/UserScript==

// qutebrowser's adblock only blocks requests, and YouTube serves its ads from
// its own servers, so the filter lists can't catch them; uBlock Origin uses
// scriptlets for this, which qutebrowser doesn't run. This does the visible
// part: it hides ad slots and fast-forwards video ads. YouTube changes its
// markup often, so expect to update the selectors (modules/home/qutebrowser.nix).
(() => {
  const css = `
    ytd-ad-slot-renderer,
    ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
    ytd-in-feed-ad-layout-renderer,
    ytd-promoted-sparkles-web-renderer,
    ytd-display-ad-renderer,
    ytd-companion-slot-renderer,
    ytd-action-companion-ad-renderer,
    ytd-banner-promo-renderer,
    ytd-statement-banner-renderer,
    ytd-merch-shelf-renderer,
    #masthead-ad,
    #player-ads,
    .ytp-ad-overlay-container,
    .ytp-featured-product,
    ad-slot-renderer,
    ytm-promoted-sparkles-web-renderer { display: none !important; }
  `;
  // At document-start the page has no <html> yet, so the style goes in on
  // the first tick that finds one, and back in if the page drops it.
  const style = document.createElement("style");
  style.textContent = css;

  const skipSelectors = [
    ".ytp-skip-ad-button",
    ".ytp-ad-skip-button",
    ".ytp-ad-skip-button-modern",
  ].join(",");

  // Mute and jump to the end while the player shows an ad, then give the
  // sound back. Only undo a mute this script made, not one the user chose.
  let mutedByUs = false;
  setInterval(() => {
    if (!style.isConnected) {
      const root = document.head || document.documentElement;
      if (root) root.appendChild(style);
    }

    const player = document.querySelector(".html5-video-player");
    const video = player && player.querySelector("video");
    if (!video) return;

    if (player.classList.contains("ad-showing")) {
      if (!video.muted) {
        video.muted = true;
        mutedByUs = true;
      }
      if (Number.isFinite(video.duration) && video.currentTime < video.duration) {
        video.currentTime = video.duration;
      }
      const skip = document.querySelector(skipSelectors);
      if (skip) skip.click();
    } else if (mutedByUs) {
      video.muted = false;
      mutedByUs = false;
    }
  }, 300);
})();
