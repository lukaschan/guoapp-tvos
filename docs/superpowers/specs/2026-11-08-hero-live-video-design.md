# 推荐 hero live video — final design (LOCKED)

**Status: locked by the owner on 2026-11-08** ("now is good, please write down this design, don't change this
live video design anymore"). Do not change anything in this document without the owner's explicit approval:
the layout, the look, or the mechanism. That covers bug fixes that would alter what is on screen.

Implemented on `feature/polish` at `1443a7a` (on top of `49012dd`). Supersedes the 推荐 hero layout notes in
`2026-11-08-redfruit-layout-design.md`.

## What the owner sees

Canvas: 1920×1080 pt.

- **Vertical video** (for example 1080×1920): a 608×1080 panel on the right, from x 1192 to x 1800 (120 pt from
  the right edge), full height. Its left and right edges are feathered over 140 pt, so it blends into the page.
- **Landscape video** (for example 1920×1080): a 1060×596 box at (860, 150), flush with the right edge of the
  screen. It is feathered over 140 pt left and right, and 98 pt top and bottom. The picture fills the box, with no
  black areas and no visible borders.
- **Before the video size is known** (loading): the vertical panel, showing the drama's cover.
- **Cover:** shown in the panel until the video has a duration, then fades out over 0.4 s. Switching between the
  vertical and landscape layouts animates over 0.35 s.
- **Ambient backdrop:** the same cover, scaled 1.25×, blurred (radius 60) and dimmed 28 %, fills the screen
  behind the panel.
- **Scrims:**
  - Left: page background at 92 %, 70 % at 72 % of the way, transparent at the panel's left edge.
  - Bottom: a 360 pt gradient from transparent to 85 %, under the info column and 接下来.
- **Info column** on the left (x 80): badge, tags, title, synopsis, progress line, buttons
  全屏观看 / 暂停 / 追剧 / 选集. 1040 pt wide with a vertical video, 760 pt with a landscape one.

## Behaviour (current, owner-approved)

- The hero plays continuously, with sound and without 弹幕. It moves to the next episode, and to the next drama
  after the last episode, with the "MM:SS 后自动播放下一集" countdown.
- The hero **never saves watch progress** (owner change, 2026-11-08). 看过的剧, 继续观看, 观看记录 and the 我的 stats
  count only what was watched in the full-screen player. The hero still starts from full-screen progress, and
  全屏观看 continues from the hero's current position. This replaced the earlier 30 s save gate.
- Two players:
  - **main**, the selected drama;
  - **preview**: resting on a 接下来 poster for 1 s plays that drama live while main pauses in place.
  - Leaving the row brings main back. Pressing the previewed poster promotes it without reloading.
- **Pause is sticky** (`HeroPauseIntent`): once the user pauses, every preview opens paused on its first frame,
  and leaving the row keeps main paused, until 继续 / Play is pressed. Pressing a poster plays it.
- Switching tabs stops the hero at once. It pauses before destroying a player, so there is no audio tail.

## Mechanism (must be kept)

- mpv (vo `gpu-next`, MoltenVK, `wid` = the view's CAMetalLayer) fixes its render size when it starts and
  **does not follow later layer resizes**.
  - Resizing the player layer to change the layout draws the picture misplaced: corner-anchored, with visible
    edges and black areas.
  - This was the landscape bug from phase 2 until `1443a7a`.
- Therefore **the hero's player layer always covers the full 1920×1080 canvas and never changes size.**
  - mpv places the picture on the panel with `video-margin-ratio-left/right/top/bottom`, computed by
    `HeroLayout.mpvMargins(videoSize:)` from `HeroLayout.panel(videoSize:)`.
  - `PlayerController.framing` applies them before `mpv_initialize` (unknown size, so the vertical panel), and
    again on `MPV_EVENT_VIDEO_RECONFIG` with the real size.
  - `HeroVideoPanel` masks everything outside the panel with the same feathered edges.
- The full-screen player does not set `framing`, and is unaffected.
- Tests: `HeroLayoutTests`, and `HeroMarginsTests` (the margins place a 9:16 video exactly on the vertical panel
  and a 16:9 video on the landscape box).

## Tried and rejected — do not retry

- **Landscape video full screen** (behind the info column): the owner rejected it.
- **Resizing the mpv layer per layout**, or a seek to force a redraw after a resize: the picture stays misplaced.
- **A 10 s teaser instead of continuous play**, with background preloading: rolled back by the owner
  (`30be1d6`).

## How to check a change on the TV

Screenshots: `xcrun devicectl device capture screenshot --device <your Apple TV> --destination shot.png`. tvOS has no
screen recording.

Dev-only launch arguments, valid for one launch and passed after `--`:
`xcrun devicectl device process launch --device <your Apple TV> --terminate-existing <bundle-id> -- -GUOAppHeroIndex N`.
- `-GUOAppHeroIndex N` starts the hero on feed item N.
- `-GUOAppInitialTab N` opens tab N.
- `-GUOAppShowHistory YES` opens 观看记录.

Check at least one vertical and one landscape drama.
