# Phase 2: 推荐 Hero and 剧场 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add redfruit's 推荐 hero home: the 红果 推荐 feed, live vertical video on the right, an info column
on the left, and a 接下来 row with 1 s hover preview. Restyle 剧场 with a 今日主推 banner and redfruit
posters. The episode logic moves out of `PlayerView` into one shared `PlaybackSession`, so the hero and the
full-screen player can never behave differently.

**Architecture:**
- `PlaybackSession` (@MainActor ObservableObject) owns everything `PlayerView` does today between "play
  this episode list" and mpv: resolve, prefetched-plan reuse, next-episode prefetch, auto-advance, fallback,
  progress saving and session release. `PlayerView` keeps only UI (focus, controls, sheets) and calls the
  session.
- The hero owns a second `PlayerController` and `PlaybackSession`, plus a `FeedModel` over the core's
  `recommendations` action.
- Pure rules (prefetch trigger, save throttle, 30 s watch gate, up-next window, hero panel geometry,
  status text, hover preview) live in `Core/Logic` and are tested with `swift test --package-path tvos`.

**Tech Stack:** SwiftUI and UIKit (tvOS 16), Swift 6, mpv via the existing `PlayerController`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-08-redfruit-layout-design.md` (sections 剧场, 推荐 hero, and Owner
decisions dated 2026-11-08). Phase 1's plan, `docs/superpowers/plans/2026-11-08-phase1-watching-ergonomics.md`,
established the logic package, `PlaybackLauncher`, `EpisodeNumberGrid` and the tab shell this plan builds on.

## Global Constraints

- tvOS 16, Swift 6, no new dependencies. Keep the `KeepAliveTabView` shell and the explicit Store / AppState
  injection.
- **Sanctioned exception (owner, 2026-11-08):** `PlayerView`'s episode logic may move into
  `PlaybackSession` *with behaviour unchanged*. Two things stay as they are: mpv internals and `CoreClient`
  caching. Only small additive hooks go into `PlayerController`: `pause()`, `resume()` and `videoSize`.
- **Hero saves progress only after 30 s of actual watching** in the hero session (autoplay and previews
  don't count until then). The full-screen player saves exactly as today.
- Body text ≥ 29 pt; safe area 80 / 60; the 1920×1080 layout uses `TVTheme` tokens. Add
  `TVTheme.TextSize.hero = 84`.
- Build check: `.superpowers/sdd/2026-11-08-phase2-hero-theater/check.sh`, a copy of phase 1's script with the
  workspace path changed. It runs the logic tests plus the Debug build and fails on any Swift warning.
- Register every new source file in `project.pbxproj` (phase 1 `pbx_add.py` / `pbx_remove.py`, copied into
  this plan's workspace).
- UI strings, verbatim:
  - 热播
  - 预览
  - 正在播放 第 N 集
  - 正在加载…
  - MM:SS 后自动播放下一集
  - MM:SS 后播放下一部
  - 已暂停 · 按播放键继续
  - 全屏观看
  - 追剧 / 已追剧
  - 选集
  - 接下来 · 停留预览，按下切换
  - 今日主推
  - 立即观看
  - 详情
  - 暂时没有可播放的短剧 / 稍后再来看看吧

## Review Focus

1. **Behaviour parity after the extraction:** auto-advance at the end of an episode, prefetch 10 s before
   the end, fallback to another route on failure, and progress every 5 s plus on exit must all work exactly
   as before in the full-screen player. *(Task 1 characterization tests on the extracted rules; device
   check in Task 10.)*
2. **The hero never pollutes or rewinds 继续观看:** opening the app and leaving it on 推荐 for less than 30 s
   writes nothing. Coming back from the full-screen player never moves the resume point backwards.
   *(Task 3 `WatchGate` tests; Task 7 reload-on-appear.)*
3. **Hover preview churn:** sweeping across 接下来 quickly must not start ten resolves. Only a poster held for
   1 s previews, and leaving the row restores the current drama. *(Task 6 `PreviewSelection` tests.)*
4. **Feed failure or empty feed:** an empty-state message, no spinner forever, and 重试 works. *(Task 4.)*
5. **Leaving the tab mid-resolve:** no audio keeps playing on another tab, and sessions are released.
   *(Task 7 uses the session's cancellation; device check.)*

---

### Task 1: Extract PlaybackSession (behaviour unchanged)

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/PlaybackRules.swift`
- Create: `tvos/LogicTests/PlaybackRulesTests.swift`
- Create: `tvos/GuoAppTV/GuoAppTV/Views/PlaybackSession.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/PlayerView.swift` (state and logic move out; UI stays)

**Interfaces:**
- Produces:
  - `enum PlaybackRules` (pure):
    - `static func prefetchIndex(position: Double, duration: Double, currentIndex: Int, episodeCount: Int, prefetchedIndex: Int?, prefetchInFlight: Bool) -> Int?`:
      returns `currentIndex + 1` when `0 < duration − position ≤ 10`, the next index exists, it differs from
      `prefetchedIndex`, and no prefetch is in flight. Otherwise nil. This is today's `maybePrefetchNext`
      guard.
    - `static func shouldSaveProgress(position: Double, lastSaved: Double) -> Bool`: `abs(position − lastSaved) ≥ 5`.
    - `static func keepsPrefetch(prefetchedIndex: Int?, target: Int) -> Bool`: `prefetchedIndex == target || prefetchedIndex == target + 1`.
  - `@MainActor final class PlaybackSession: ObservableObject` (`PlaybackSession.swift`)
    - `init(drama: Drama, episodes: [Episode], startIndex: Int, startPosition: Double, store: Store, controller: PlayerController)`
    - `@Published private(set) var currentIndex: Int`, `plan: PlaybackPlan?`, `error: String?`
    - `var saveGate: (Double) -> Bool = { _ in true }`: called before each progress save with the
      position; the hero swaps in its 30 s gate.
    - `var onReachedEnd: (() -> Void)?`: called when the last episode ends (or `autoAdvance` is off). The
      full-screen player passes `dismiss`.
    - Methods:
      - `start()` is today's `load()` entry.
      - `retry()`
      - `playEpisode(at:)` moves over as-is from `PlayerView`.
      - `handleEnded()`, `handleFailed()`, `handleProgress(position:duration:)`, `saveProgress()`
      - `stop()` is today's `onDisappear` body: save, `controller.stop()`, cancel tasks, release sessions.
    - Preferences are read at call time from `UserDefaults` with the same keys and defaults as the
      `@AppStorage` they replace: `autoAdvance` true, `danmakuEnabled` true, `preferredQuality` 0,
      `playbackSpeed` 1.0. Use `object(forKey:) as? T ?? default` so an unset key keeps its default.

- [ ] **Step 1:** Write `PlaybackRulesTests`. These are characterization tests for today's behaviour:
  - `prefetchTriggersTenSecondsBeforeEnd`:
    - `(position: 90, duration: 100, current: 0, count: 3, prefetched: nil, inFlight: false)` → `1`
    - `(85, 100, …)` → nil (15 s left)
  - `prefetchNotForLastEpisode`: `(95, 100, current: 2, count: 3, …)` → nil
  - `prefetchNotTwice`:
    - `prefetched: 1` → nil
    - `inFlight: true` → nil
  - `prefetchNotAtZeroDuration`: `(0, 0, …)` → nil
  - `saveThrottle`: `(4.9, 0)` → false; `(5, 0)` → true; `(10, -1)` → true
  - `keepsPrefetch`: `(3, 3)` → true; `(4, 3)` → true; `(5, 3)` → false; `(nil, 3)` → false
- [ ] **Step 2:** Run `swift test --package-path tvos`. Expected: FAIL (`PlaybackRules` not found).
- [ ] **Step 3:** Implement `PlaybackRules.swift`.
- [ ] **Step 4:** Move the logic into `PlaybackSession`:
  - `load`, `handleEnded`, `handleFailed`, `handleProgress`, `maybePrefetchNext`, `saveProgress`,
    `playEpisode`, `startLoad` / `loadTask`, the release in `onDisappear`, and the prefetch state.
  - Keep the code; replace the inlined guards with `PlaybackRules` calls.
  - `PlayerView` holds `@StateObject var session` (built in `init` from its parameters plus its
    `@StateObject` controller). It routes `.task`, the `onChange` hooks, Retry, the 选集 sheet and
    `onDisappear` to the session, and passes `dismiss` via `onReachedEnd`.
  - The `.onChange(of: error)` halt moves into the session (`error`'s `didSet`).
- [ ] **Step 5:** Run the tests (PASS) and `check.sh`.
- [ ] **Step 6:** Commit: `refactor: move PlayerView episode logic into a shared PlaybackSession`.

### Task 2: PlayerController hooks and an internal host view

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/PlayerController.swift`
- Create: `tvos/GuoAppTV/GuoAppTV/Views/PlayerHostView.swift` (move the `private struct PlayerHostView` out of
  `PlayerView.swift` and make it internal)

**Interfaces:**
- Produces:
  - `func pause()` and `func resume()`: set mpv `pause` explicitly, then `isPaused` and the idle timer.
  - `@Published private(set) var videoSize: CGSize?`: from `video-params/w` / `video-params/h` in `tick()`,
    published only on change and reset in `startPlayback` / `halt()`.
  - `struct PlayerHostView: UIViewRepresentable { init(controller: PlayerController) }`

- [ ] **Step 1:** Add the hooks (additive, no change to existing paths). Move `PlayerHostView`.
- [ ] **Step 2:** `check.sh`.
- [ ] **Step 3:** Commit: `feat: PlayerController pause/resume/videoSize hooks; shareable PlayerHostView`.

### Task 3: The hero's 30 s watch gate

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/WatchGate.swift`
- Create: `tvos/LogicTests/WatchGateTests.swift`

**Interfaces:**
- Produces: `struct WatchGate: Sendable`
  - `init(threshold: Double = 30)`
  - `mutating func observe(position: Double, paused: Bool)`: accumulates forward deltas between 0 and 2 s
    while not paused. Seeks and jumps don't count.
  - `var isOpen: Bool` (accumulated ≥ threshold)
  - `mutating func reset()`

- [ ] **Step 1:** Write the tests:
  - `closedBeforeThirtySeconds`: 29 observations 1 s apart → not open
  - `opensAtThirty`: 31 observations → open
  - `pausedTimeDoesNotCount`: 40 observations with `paused: true` → not open
  - `seekJumpDoesNotCount`: 0 → 25 → 26 → not open
  - `resetCloses`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `WatchGate.swift`.
- [ ] **Step 4:** Run (PASS).
- [ ] **Step 5:** Commit: `feat: 30-second watch gate for hero progress saving`.

### Task 4: 推荐 feed model

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Core/Client.swift` (add `recommendations(feed:more:force:)`, additive)
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/UpNext.swift`, `tvos/LogicTests/UpNextTests.swift`
- Create: `tvos/GuoAppTV/GuoAppTV/Views/Feed/FeedModel.swift`

**Interfaces:**
- Produces:
  - `CoreClient.recommendations(feed: String = "home_feed", more: Bool = false, force: Bool = false) async throws -> CatalogPage`
    - Action `"recommendations"`, `category: feed`, `command: more ? "more" : ""`, `force`.
    - The core returns the cumulative list.
  - `enum UpNext { static func window(count: Int, current: Int, limit: Int = 10) -> [Int] }`: the next
    `limit` indices after `current`, wrapping around and excluding `current`.
  - `@MainActor final class FeedModel: ObservableObject`
    - `@Published private(set) var dramas: [Drama]`, `currentIndex: Int`, `state: LoadState`
      (`.loading` / `.loaded` / `.empty` / `.failed(String)`)
    - `func load() async`: first page, then `more` until ≥ 11 dramas or `!hasMore`, at most 4 requests.
    - `func advance()`
    - `func select(_ drama: Drama)`
    - `var upNext: [Drama]`

- [ ] **Step 1:** Write the `UpNextTests`:
  - `(count: 15, current: 0)` → `1...10`
  - `(count: 5, current: 3)` → `[4, 0, 1, 2]`
  - `(1, 0)` → `[]`
  - `(0, 0)` → `[]`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `UpNext`, the client call and `FeedModel`.
- [ ] **Step 4:** Run (PASS) and `check.sh`.
- [ ] **Step 5:** Commit: `feat: 推荐 feed model over the core recommendations action`.

### Task 5: Hero layout and status text (logic)

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/HeroLayout.swift`, `tvos/LogicTests/HeroLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum HeroLayout`
    - `static func panel(videoSize: CGSize?) -> (frame: CGRect, vertical: Bool)`: nil or height ≥ width
      → `(1192, 0, 608, 1080)`, vertical. Otherwise `(860, 150, 1060, 596)`, landscape.
    - `static func infoWidth(vertical: Bool) -> CGFloat`: 1040 / 760.
  - `enum HeroStatus`
    - `static func line(episode: Int?, remaining: Double?, isLastEpisode: Bool, paused: Bool, autoAdvance: Bool) -> String`
      - `episode == nil` → `"正在加载…"`
      - paused → `"已暂停 · 按播放键继续"`
      - not last → `"MM:SS 后自动播放下一集"`
      - last → `"MM:SS 后播放下一部"`
      - autoAdvance off → `"正在播放 第 N 集"`
    - `static func playing(episode: Int) -> String`: `"正在播放 第 N 集"`

- [ ] **Step 1:** Write the tests:
  - `verticalDefault`: nil → vertical 608×1080 at x 1192
  - `landscape`: 1920×1080 → 1060×596 at (860, 150)
  - `statusPaused`, `statusNextEpisode`: remaining 67 → `"01:07 后自动播放下一集"`
  - `statusNextDrama`: last episode → `"…后播放下一部"`
  - `statusLoading`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `HeroLayout.swift`.
- [ ] **Step 4:** Run (PASS).
- [ ] **Step 5:** Commit: `feat: hero panel geometry and status text`.

### Task 6: Hover preview rule (logic)

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/PreviewSelection.swift`, `tvos/LogicTests/PreviewSelectionTests.swift`

**Interfaces:**
- Produces: `struct PreviewSelection: Equatable, Sendable`
  - `var committedID: String`
  - `var focusedID: String?`
  - `var previewID: String?`
  - `mutating func focus(_ id: String?)`: sets `focusedID`. nil (the row lost focus) also clears
    `previewID`.
  - `mutating func dwellElapsed(for id: String)`: becomes `previewID = id` only if `focusedID == id` still
    and `id != committedID`.
  - `mutating func commit(_ id: String)`: `committedID = id`, clears the preview.
  - `var heroID: String { previewID ?? committedID }`
  - `static let dwell: Duration = .milliseconds(1000)`

- [ ] **Step 1:** Write the tests:
  - `dwellPreviews`
  - `staleDwellIgnored`: focus A, focus B, dwell(A) → no preview
  - `leavingRowRestores`: preview A, then `focus(nil)` → `heroID == committed`
  - `commitClearsPreview`
  - `committedNotPreviewed`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `PreviewSelection.swift`.
- [ ] **Step 4:** Run (PASS).
- [ ] **Step 5:** Commit: `feat: 接下来 hover-preview rule`.

### Task 7: 推荐 hero screen

**Files:**
- Create in `tvos/GuoAppTV/GuoAppTV/Views/Feed/`:
  - `FeedHeroView.swift`: the screen; it owns `FeedModel`, the hero `PlayerController` and the session
  - `HeroVideoPanel.swift`
  - `HeroInfoPanel.swift`
  - `UpNextRow.swift`
- Modify: `TVDesign.swift` (`TextSize.hero = 84`)

**Interfaces:**
- Consumes: `PlaybackSession` and `saveGate` (Task 1), `pause`/`resume`/`videoSize`/`PlayerHostView`
  (Task 2), `WatchGate` (Task 3), `FeedModel`/`UpNext` (Task 4), `HeroLayout`/`HeroStatus` (Task 5),
  `PreviewSelection` (Task 6), `PlaybackPresentation` (phase 1), `DetailView`.

- [ ] **Step 1:** Build `HeroVideoPanel`:
  - `PlayerHostView` framed by `HeroLayout.panel(videoSize:)`.
  - The edges fade over 140 pt: left and right for vertical, all four edges (98 pt top and bottom) for
    landscape, via a gradient mask.
  - `TVPosterImage` underneath until `progress.duration > 0`.
  - Ambient backdrop behind everything: the same cover scaled 1.25×, `.blur(radius: 60)`, black at 28 %.
  - A left scrim: `TVTheme.background` at 92 % → 70 % at 72 % → clear at the panel's left edge.
- [ ] **Step 2:** Build `HeroInfoPanel` at x 80, y 250, width `infoWidth`, stacked 22 apart:
  - Badge 热播 / 预览.
  - Tags plus status in `TextSize.caption`.
  - Title in `TextSize.hero` heavy, 2 lines, `minimumScaleFactor(0.6)`.
  - Synopsis in `TextSize.body`, 78 %, 2 lines, max 900 wide.
  - Progress row: `HeroStatus.playing`, a 320-wide bar, `HeroStatus.line`.
  - Buttons: 全屏观看 (`TVPrimaryButton`, default focus), 追剧 / 已追剧, 选集 (pushes `DetailView`).
- [ ] **Step 3:** Build `UpNextRow`:
  - Header "接下来" (callout bold) and " · 停留预览，按下切换" (caption, tertiary).
  - 160×240 `TVPosterCard`s, 32 apart, in a 1192-wide clipped row.
  - The row peeks 70 pt below the screen edge, slides up 40 pt over 0.3 s when a poster has focus, and
    the info column fades to 55 %.
  - Focus changes drive `PreviewSelection.focus` plus a `Task.sleep(for: .dwell)` that calls
    `dwellElapsed`. Selecting a poster calls `commit`.
- [ ] **Step 4:** Assemble `FeedHeroView`:
  - When the hero drama (`heroID`) changes, stop the old session and start a new one for that drama. It
    fetches detail and starts at the store's resume point (`ResumeTarget`).
    - The session's `saveGate` is a `WatchGate` fed from `controller.progress` / `isPaused`, reset per drama.
    - `onReachedEnd` calls `feed.advance()`.
  - Play/Pause anywhere toggles the hero (`pause` / `resume`).
  - `onDisappear` (tab switch, Detail push) → `controller.pause()`.
  - `onAppear` → reload: restart the session from the store's resume point, so progress made in the
    full-screen player is never rolled back.
  - 全屏观看:
    - Stop the hero session and present `PlayerView` at the hero's current episode and position, through a
      `PlaybackPresentation` and its own `.fullScreenCover`.
    - When it's dismissed, reload.
  - States:
    - Loading: the redfruit feed skeleton (simple grey blocks for now; the shimmer comes in phase 3).
    - `.empty`: 暂时没有可播放的短剧 / 稍后再来看看吧.
    - `.failed`: a `TVStatusView` with 重试.
- [ ] **Step 5:** `check.sh`.
- [ ] **Step 6:** Commit: `feat: 推荐 hero with live video, info panel and 接下来 preview row`.

### Task 8: 剧场 restyle

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Views/FeaturedBanner.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/HomeView.swift`, `PosterView.swift`

**Interfaces:**
- Produces:
  - `struct FeaturedBanner: View { init(drama: Drama, onPlay: () -> Void) }`
    - 340 tall, radius 24, inset 80.
    - Left column: "今日主推" (caption2, tracking 2), the title (`title2`), tags and status, then 立即观看
      (calls `onPlay`) and 详情 (a `NavigationLink` with the drama as value).
    - Right side: the cover enlarged 1.6×, blurred 40, at 80 %, with the sharp 190×285 cover on top.
  - `TVPosterCard` shows the episode-count badge `"\(episodes)集"` top-right when `drama.episodes > 0` and
    no other badge is set. Rank badges stay top-left.

- [ ] **Step 1:** Build `FeaturedBanner`. In `HomeView`, show it above the grid using `items.first`, which
  then stays out of the grid. 立即观看 calls `launcher.play`.
- [ ] **Step 2:** While a chip change is loading the first page, dim the grid to 50 % (0.2 s) and show a
  spinner 56 pt under the chips, instead of replacing the grid with a loading view.
- [ ] **Step 3:** `check.sh`.
- [ ] **Step 4:** Commit: `feat: 剧场 featured banner and redfruit poster badges`.

### Task 9: Shell, with 推荐 first

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/ContentView.swift`

- [ ] **Step 1:** Tabs: 推荐 (`sparkles`, `FeedHeroView`, default) · 剧场 · 追剧 · 搜索 · 我的.
- [ ] **Step 2:** `check.sh`.
- [ ] **Step 3:** Commit: `feat: 推荐 tab first`.

### Task 10: 重新观看 for finished dramas (owner decision 2026-11-08)

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/ResumeAction.swift`, `tvos/LogicTests/ResumeActionTests.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/DetailView.swift` (`resumeLabel` / `playResume` use `ResumeAction`)

**Interfaces:**
- Produces: `enum ResumeAction: Equatable, Sendable { case start, resume(episode: Int), nextPart, restart }`
  - `static func make(target: ResumeTarget?, episodeNumbers: [Int], isFinished: Bool, hasNextPart: Bool) -> ResumeAction`
    - finished with a next part → `.nextPart`
    - finished with none → `.restart`
    - a saved point (`index > 0 || position > 0`) → `.resume(episode:)`
    - otherwise → `.start`
  - `var title: String`: "立即观看", "继续观看 第 N 集", "观看下一部", "重新观看"

- [ ] **Step 1:** Write the tests:
  - `finishedWithNext` → `.nextPart`
  - `finishedNoNext` → `.restart`, title "重新观看"
  - `resumeMidway`: target (2, 30) over [1, 2, 3] → `.resume(episode: 3)`
  - `freshStart`: nil target → `.start`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. In `DetailView`, `.restart` presents from index 0 at 0 s.
- [ ] **Step 4:** Run (PASS) and `check.sh`.
- [ ] **Step 5:** Commit: `feat: 重新观看 for fully watched dramas without a next part`.

### Task 11: Docs, deploy and owner check

- [ ] **Step 1:** README (功能) and CHANGELOG (`## 未发布`).
- [ ] **Step 2:** `python3 scripts/deploy_tvos.py` → "完成。".
- [ ] **Step 3:** Owner checks:
  - **Full-screen parity** (Review Focus 1): auto-advance, the 10 s prefetch hand-off, progress saved.
  - **Hero:** autoplay with sound; less than 30 s on 推荐 adds nothing to 继续观看, more than 30 s does.
  - **Previews:** a 1 s hover previews, leaving the row restores, clicking commits.
  - **Leaving:** switching tabs pauses; 全屏观看 continues at the same spot; coming back resumes from saved
    progress.
  - **剧场:** the banner and badges.
- [ ] **Step 4:** Commit and push `feature/polish`.
