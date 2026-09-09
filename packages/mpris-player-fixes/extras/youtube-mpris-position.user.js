// ==UserScript==
// @name         YouTube MPRIS position/length fix
// @namespace    drpezzer.ambxst-mods
// @version      1.0.1
// @downloadURL  https://raw.githubusercontent.com/drpezzer/ambxst-mods/main/packages/mpris-player-fixes/extras/youtube-mpris-position.user.js
// @updateURL    https://raw.githubusercontent.com/drpezzer/ambxst-mods/main/packages/mpris-player-fixes/extras/youtube-mpris-position.user.js
// @homepageURL  https://github.com/drpezzer/ambxst-mods/tree/main/packages/mpris-player-fixes
// @description  Keeps navigator.mediaSession position state populated so Firefox/Zen publishes mpris:length and a live Position over D-Bus. Without this, YouTube's SPA navigation leaves the position state empty and MPRIS consumers (Ambxst notch, playerctl, waybar) show a stuck playhead.
// @match        https://www.youtube.com/*
// @match        https://music.youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
    "use strict";

    if (!("mediaSession" in navigator)) return;

    var video = null;

    function push() {
        if (!video || !isFinite(video.duration) || video.duration <= 0) return;
        try {
            navigator.mediaSession.playbackState = video.paused ? "paused" : "playing";
            navigator.mediaSession.setPositionState({
                duration: video.duration,
                playbackRate: video.playbackRate || 1,
                position: Math.min(video.currentTime, video.duration),
            });
        } catch (e) {
            /* setPositionState throws if position > duration mid-seek; ignore */
        }
    }

    // timeupdate fires ~4x/sec while playing, which is what keeps Position live.
    var EVENTS = ["play", "pause", "seeked", "ratechange", "durationchange", "loadedmetadata", "timeupdate"];

    function bind(el) {
        if (!el || el === video) return;
        if (video) EVENTS.forEach(function (e) { video.removeEventListener(e, push); });
        video = el;
        EVENTS.forEach(function (e) { video.addEventListener(e, push); });
        push();
    }

    function scan() {
        // The watch page can hold several <video> elements (previews, ads); prefer the one
        // that actually has a duration and is playing.
        var candidates = Array.prototype.slice.call(document.querySelectorAll("video"));
        var best = candidates.find(function (v) { return !v.paused && isFinite(v.duration) && v.duration > 0; })
            || candidates.find(function (v) { return isFinite(v.duration) && v.duration > 0; });
        if (best) bind(best);
    }

    // YouTube swaps videos without a page load, so re-scan on DOM churn and on its own
    // navigation event, and keep a slow poll as a backstop.
    new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
    window.addEventListener("yt-navigate-finish", scan);
    setInterval(scan, 2000);
    scan();
})();
