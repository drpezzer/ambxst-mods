// ==UserScript==
// @name         MPRIS position/length fix for browser media
// @namespace    drpezzer.ambxst-mods
// @version      2.0.0
// @description  Keeps navigator.mediaSession position state populated for whatever <video> or <audio> is playing, so Firefox and Zen publish mpris:length and a live Position over D-Bus on every site. Without it, single-page apps (YouTube, SoundCloud, Twitch, ...) leave the position state empty after navigating and MPRIS consumers (Ambxst, playerctl, waybar) show a stuck playhead.
// @match        *://*/*
// @run-at       document-idle
// @grant        none
// @downloadURL  https://raw.githubusercontent.com/drpezzer/ambxst-mods/main/packages/mpris-player-fixes/extras/youtube-mpris-position.user.js
// @updateURL    https://raw.githubusercontent.com/drpezzer/ambxst-mods/main/packages/mpris-player-fixes/extras/youtube-mpris-position.user.js
// @homepageURL  https://github.com/drpezzer/ambxst-mods/tree/main/packages/mpris-player-fixes
// ==/UserScript==

(function () {
    "use strict";

    if (!("mediaSession" in navigator)) return;

    // The element whose state is being published: the one that most recently
    // played. Several media elements on one page are normal (previews, ads,
    // autoplaying backgrounds), so the last one to actually play wins, and
    // muted ones are ignored - Firefox never exposes those over MPRIS anyway.
    var active = null;
    var bound = new WeakSet();

    function eligible(el) {
        return el && !el.muted && isFinite(el.duration) && el.duration > 0;
    }

    function push() {
        if (!eligible(active)) return;
        try {
            navigator.mediaSession.playbackState = active.paused ? "paused" : "playing";
            navigator.mediaSession.setPositionState({
                duration: active.duration,
                playbackRate: active.playbackRate || 1,
                position: Math.min(active.currentTime, active.duration),
            });
        } catch (e) {
            /* setPositionState throws if position > duration mid-seek; ignore */
        }
    }

    // timeupdate fires ~4x/sec while playing, which is what keeps Position live.
    var EVENTS = ["play", "playing", "pause", "seeked", "ratechange", "durationchange", "loadedmetadata", "timeupdate", "ended"];

    function onEvent(ev) {
        var el = ev.currentTarget;
        // A paused element only reports for itself if it already was the
        // active one; otherwise a paused preview would hijack the session.
        if (!el.paused || el === active) {
            if (!el.muted) active = el;
        }
        if (el === active) push();
    }

    function bind(el) {
        if (!el || bound.has(el)) return;
        bound.add(el);
        EVENTS.forEach(function (e) { el.addEventListener(e, onEvent); });
        if (!el.paused && !el.muted) { active = el; push(); }
    }

    function scan(root) {
        var list = (root.querySelectorAll ? root.querySelectorAll("video, audio") : []);
        for (var i = 0; i < list.length; i++) bind(list[i]);
        if (root.matches && root.matches("video, audio")) bind(root);
    }

    scan(document);

    // Single-page apps swap media elements in and out without a page load.
    new MutationObserver(function (records) {
        for (var i = 0; i < records.length; i++) {
            var added = records[i].addedNodes;
            for (var j = 0; j < added.length; j++) {
                if (added[j].nodeType === 1) scan(added[j]);
            }
        }
    }).observe(document.documentElement, { childList: true, subtree: true });

    // Media created with new Audio()/document.createElement and never attached
    // to the DOM still play; catch their events at the document level.
    document.addEventListener("play", function (ev) {
        var el = ev.target;
        if (el && (el.tagName === "VIDEO" || el.tagName === "AUDIO")) bind(el);
    }, true);
})();
