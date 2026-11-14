# Phase 3: Search refresh, loading/error states, images and focus prefetch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the redfruit layout:
- 搜索 opens on a 大家都在看 grid and headlines its results.
- Every loading screen shows a shimmering skeleton, and every failure shows one friendly 重试 view.
- Covers are downsampled into a bounded cache.
- A rested poster focus warms the covers around it and that drama's detail.

**Architecture:**
- Pure rules go in `Core/Logic` and are tested on the Mac: downsampling maths, error copy, timed cache, prefetch slot and plan, shimmer, search copy, playback start.
- The app side wires them into the existing views.
- Two new app objects:
  - `DetailPrefetch`: a timed detail cache plus a single-flight focus prefetch. It lives outside `CoreClient`, which keeps its caching unchanged.
  - `FeedLoader`: the 推荐 loading loop, shared by the hero and 大家都在看.
- No core, mpv or resolve changes.

**Tech Stack:** Swift 6 language mode, SwiftUI + UIKit on tvOS 16+, Xcode 27 / tvOS 27 SDK, ImageIO, Swift Testing (`swift test --package-path tvos`).

**Spec:** `docs/superpowers/specs/2026-11-08-redfruit-layout-design.md` (sections 搜索 (phase 3); Loading, empty and error states (phase 3); Phases → 3; Builder's calls).

**Owner decision carried in (2026-11-08):** 搜索 uses the native tvOS search screen (`NativeSearchContainer`, UIKit `UISearchController`) instead of guoapp's custom field. The owner tested it on the TV ("design is ok", Chinese input works). This supersedes the spec's "Keep guoapp's custom field and suggestions". Task 7 records it in the spec.

## Global Constraints

- Swift 6 language mode, tvOS 16 deployment target, Xcode 27.
- Every task ends green on `.superpowers/sdd/2026-11-08-phase3-search-states-images/check.sh`: logic tests, plus a Debug build with **0 warnings**.
- Don't change the Go core (`upstream/`), `PlayerController` internals, `PlaybackSession` playback logic, resolve paths or `CoreClient` caching. New caches live in new types.
- Prefetch-on-focus covers **posters and detail only**: no `resolve`, no stream warming.
- Exact copy:
  - "大家都在看"
  - "找到 N 部短剧"
  - "出了点问题"
  - "网络连接失败，请检查网络后重试"
  - "重试"
- Shimmer: 1.4 s linear sweep, still when Reduce Motion is on.
- New Swift files are registered with `pbx_add.py <Core|Views> <relpath>` from the workspace.
- `Core/Logic` files import only Foundation, CoreGraphics or ImageIO.
- Commits: conventional messages, no attribution trailer.
- Owner's workflow rules:
  - Deploy to the TV **only on the owner's signal**.
  - Don't push `feature/polish` while PR #1 (MP2) is open, unless the owner says so.

## Review Focus

1. **Focus prefetch flooding the serial core queue.**
   - Expected: sweeping across a grid costs nothing, and resting costs at most one detail fetch in flight. Covers and playback start never wait behind a pile of prefetches.
   - Pinned by `PrefetchSlotTests` (Task 4).
2. **Stale prefetched detail.**
   - Expected: an ongoing drama that just gained episodes shows them within `DetailPrefetch.maxAge` (180 s), and a failed fetch is never cached.
   - Pinned by `TimedCacheTests.refetchesAfterMaxAge` and `.failureNotCached` (Task 4).
3. **Blurry covers on a 4K TV after downsampling.**
   - Expected: the pixel budget accounts for display scale × focus scale.
   - Pinned by `ImageDownsamplerTests.pixelSizeForScale` (Task 1).
4. **Error copy hiding an actionable core message.**
   - Expected: Chinese core messages (for example 该剧暂时没有可播放的分集) pass through. Only network and technical English errors are rewritten.
   - Pinned by `UserFacingErrorTests` (Task 3).
5. **大家都在看 when the feed is cold, failed, or the source isn't 红果.**
   - Expected: a skeleton, then up to 14 posters, or the failure view with 重试. Never an endless spinner.
   - Pinned by Task 5's states plus `SearchCopyTests`.

---

### Task 0: Workspace

- [ ] **Step 1:** Run `sdd-workspace` for this plan. Copy `check.sh`, `pbx_add.py` and `pbx_remove.py` from `.superpowers/sdd/2026-11-08-phase2-hero-theater/`, and point `check.sh`'s `W=` at the new directory.
- [ ] **Step 2:** Run `check.sh`. Expected: `83 tests … passed`, `BUILD SUCCEEDED, 0 warnings`.

### Task 1: Downsampled, bounded cover cache

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/ImageDownsampler.swift`, `tvos/LogicTests/ImageDownsamplerTests.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/PosterView.swift` (`PosterCache`, `TVPosterImage`), `Views/Feed/HeroVideoPanel.swift` (`HeroCoverImage`), `Views/FeaturedBanner.swift`

**Interfaces:**
- Produces:
  - `enum ImageDownsampler`
    - `static func downsample(fileURL: URL, maxPixelSize: Int) -> CGImage?`
      - ImageIO thumbnail options: `CreateThumbnailFromImageAlways`, `ShouldCacheImmediately`, `CreateThumbnailWithTransform`, `ThumbnailMaxPixelSize`.
      - Returns nil for an unreadable file or `maxPixelSize <= 0`.
    - `static func maxPixelSize(forPoints points: CGFloat, scale: CGFloat) -> Int`: `ceil(points × max(scale, 1))`.
  - `PosterCache.image(for drama: Drama, maxPixelSize: Int) async -> UIImage?`
    - Key: `id\0cover\0maxPixelSize`.
    - Decoded images go in an `NSCache` with `totalCostLimit` 96 MB and cost `bytesPerRow × height`.
    - Decodes inside `Task.detached` and still shares in-flight work.
    - Replaces the unbounded dictionary.
  - `PosterCache.prefetch(_ dramas: [Drama], maxPixelSize: Int)`: utility priority, errors ignored. Used in Task 4.
  - `TVPosterImage(drama:, maxPointSize: CGFloat = 462)`: 462 = 420 pt poster × 1.10 focus; the detail poster is 300×450. Reads `@Environment(\.displayScale)`.
  - `HeroCoverImage(drama:, maxPointSize: CGFloat = 1080)`.
    - The blurred backdrops (`HeroVideoPanel` ambient, `FeaturedBanner` artwork) pass 540.
    - The hero panel cover keeps 1080.

- [ ] **Step 1: Write the tests.**
  - `downsampleBoundsLongestSide`: write a 1200×1800 PNG to a temp file and downsample it to 600 → 400×600.
  - `smallImageKeepsItsSize`: 300×450 with max 924 → 300×450.
  - `unreadableFileIsNil`
  - `pixelSizeForScale`: `(462, 2)` → 924, `(462, 1)` → 462, `(462, 0)` → 462.
- [ ] **Step 2:** Run `swift test --package-path tvos`. Expected: FAIL (`ImageDownsampler` not found).
- [ ] **Step 3:** Implement `ImageDownsampler`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Rework `PosterCache` and give the image views their sizes. Run `check.sh`.
- [ ] **Step 6:** Commit `perf: downsample covers into a bounded memory cache`.

### Task 2: Skeletons with shimmer

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/Shimmer.swift`, `tvos/LogicTests/ShimmerTests.swift`, `tvos/GuoAppTV/GuoAppTV/Views/Skeleton.swift`
- Modify: `Views/Feed/FeedHeroView.swift` (`FeedSkeleton`), `Views/HomeView.swift` (first load)

**Interfaces:**
- Produces:
  - `enum Shimmer`
    - `static let period: Double = 1.4`
    - `static func animates(reduceMotion: Bool) -> Bool`
  - `struct SkeletonBlock: View { init(width: CGFloat?, height: CGFloat, cornerRadius: CGFloat = 10) }`, filled with `TVTheme.textPrimary.opacity(0.08)`.
  - `extension View { func shimmering() -> some View }` (redfruit's `ShimmerModifier`):
    - a gradient of clear → `textPrimary` 7 % → clear, 40 % of the width wide;
    - the phase sweeps −1 → 1.2 over `Shimmer.period`, linear, repeating forever;
    - masked to the content, no hit testing;
    - the accessibility label is 正在加载;
    - still when `accessibilityReduceMotion` is on.
  - `struct PosterGridSkeleton: View { init(count: Int = 14, showsTitle: Bool = true) }`
    - An optional 220×38 title block.
    - `TVTheme.posterColumns()` cells: a 2:3 block (radius `TVTheme.posterRadius`) and a 70 %-wide 22 pt caption block.
    - Shimmering, with nothing focusable.
  - `struct TheaterSkeleton: View`: six 132×56 capsule chips, a full-width banner block 340 tall with radius 24 at the banner inset, then `PosterGridSkeleton(count: 14, showsTitle: false)`.

- [ ] **Step 1: Write the tests.**
  - `periodIsOnePointFourSeconds`
  - `stillWithReduceMotion`: `!animates(reduceMotion: true)`, `animates(reduceMotion: false)`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `Shimmer` and `Skeleton.swift`.
- [ ] **Step 4:** Apply them:
  - `FeedSkeleton` gets `.shimmering()`.
  - `HomeView`'s first load (`loading && items.isEmpty`) shows `TheaterSkeleton` instead of `TVLoadingView`.
  - 搜索 uses `PosterGridSkeleton` in Task 5.
  - 追剧 needs none (see the ruling below).
- [ ] **Step 5:** `check.sh`, then commit `feat: shimmering skeletons for 推荐 and 剧场`.
- Ruling to ledger: 追剧 renders straight from the local `Store` with no asynchronous load, so the spec's 追剧 skeleton has no loading state to cover. Cost if wrong: one skeleton later.

### Task 3: One failure view and friendly error copy

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/UserFacingError.swift`, `tvos/LogicTests/UserFacingErrorTests.swift`
- Modify:
  - `Views/TVDesign.swift` (`TVFailureView`)
  - `Views/Feed/FeedHeroView.swift`, `Views/Feed/HeroPlayback.swift`, `Views/Feed/HeroInfoPanel.swift`
  - `Views/HomeView.swift`, `Views/SearchView.swift`, `Views/DetailView.swift`, `Views/PlaybackLauncher.swift`, `Views/PlayerView.swift` (displayed message only)

**Interfaces:**
- Produces:
  - `enum UserFacingError`
    - `static let network = "网络连接失败，请检查网络后重试"`
    - `static let generic = "加载失败，请稍后重试"`
    - `static func message(for text: String) -> String`, in this order:
      1. A lowercased network marker → `network`. Markers: `dial tcp`, `no such host`, `i/o timeout`, `timeout`, `deadline exceeded`, `connection refused`, `connection reset`, `network is unreachable`, `tls handshake`, `eof`, `offline`, `网络`.
      2. Text containing CJK → unchanged.
      3. Otherwise → `generic`.
    - `static func message(for error: any Error) -> String`: a `URLError` → `network`; otherwise `message(for: error.localizedDescription)`.
  - `struct TVFailureView: View { init(message: String, retry: @escaping () -> Void) }`: icon `exclamationmark.triangle`, title "出了点问题", the message, and a `TVPrimaryButton` "重试" with `arrow.clockwise`.

- [ ] **Step 1: Write the tests.**
  - `networkGoErrors`: three Go errors map to `network`:
    - `Get "https://x": dial tcp: lookup x: no such host`
    - `context deadline exceeded (Client.Timeout exceeded while awaiting headers)`
    - `read tcp …: connection reset by peer`
  - `chineseCoreMessageKept`: `该剧暂时没有可播放的分集` comes back unchanged.
  - `technicalEnglishBecomesGeneric`: `json: cannot unmarshal number` → `generic`.
  - `emptyBecomesGeneric`
  - `urlErrorIsNetwork`: `URLError(.notConnectedToInternet)`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `UserFacingError` and `TVFailureView`.
- [ ] **Step 4:** Apply them:
  - 推荐: `failure()` → `TVFailureView`. `.empty` keeps 暂时没有可播放的短剧 / 稍后再来看看吧 and gains a 重试 button that calls `loadFeed(force: true)`.
  - Hero: `HeroPlayback.fail` and the status line's `session.error` go through `UserFacingError`. While `status.error != nil`, the primary button reads 重试 and restarts the hero (a new `onRetry` on `HeroInfoPanel`, wired to `startHero`).
  - 剧场: the catalog error → `TVFailureView` (retry `reload(firstPage: true)`).
  - 搜索: the error → `TVFailureView` (retry `model.retry()`).
  - 详情: the error → `TVFailureView` (retry `load()`).
  - Messages: `PlaybackLauncher.errorMessage` and the player overlay's displayed message go through `UserFacingError`. The player keeps its 播放失败 title and its 重试 / 返回 buttons.
- [ ] **Step 5:** `check.sh`, then commit `feat: one 出了点问题 failure view with friendly error copy`.

### Task 4: Prefetch on poster focus (covers and detail)

**Files:**
- Create:
  - `tvos/GuoAppTV/GuoAppTV/Core/Logic/TimedCache.swift`, `tvos/GuoAppTV/GuoAppTV/Core/Logic/Prefetch.swift`
  - `tvos/LogicTests/TimedCacheTests.swift`, `tvos/LogicTests/PrefetchTests.swift`
  - `tvos/GuoAppTV/GuoAppTV/Core/DetailPrefetch.swift`
- Modify: `Views/PosterView.swift` (focus hook and environment), `Views/SearchView.swift` (grids), `Views/DetailView.swift`, `Views/PlaybackLauncher.swift`

**Interfaces:**
- Consumes: `PosterCache.prefetch` (Task 1).
- Produces:
  - `actor TimedCache<Value: Sendable>`
    - `init(maxAge: TimeInterval, now: @escaping @Sendable () -> Date = { Date() })`
    - `func value(for key: String, fetch: @escaping @Sendable () async throws -> Value) async throws -> Value`
      - A fresh entry (age < `maxAge`) is returned without fetching.
      - Concurrent callers share one fetch.
      - Failures aren't stored.
    - `func cachedValue(for key: String) -> Value?` (fresh only)
  - `struct PrefetchSlot: Equatable, Sendable`, which keeps at most one prefetch in flight with only the newest request waiting:
    - `mutating func request(_ id: String) -> String?`: when idle it returns `id` to start now and becomes busy. When busy it queues `id`, replacing any earlier one, and returns nil.
    - `mutating func finished() -> String?`: returns the queued id (staying busy), or nil and becomes idle.
  - `enum PosterPrefetchPlan`
    - `static let ahead = 8`
    - `static func items<Item>(after id: String, in items: [Item], id: (Item) -> String) -> [Item]`: the next `ahead` after the focused one; empty if it's not found.
  - `@MainActor final class DetailPrefetch`
    - `static let shared`
    - `static let maxAge: TimeInterval = 180`
    - `static let debounce: Duration = .milliseconds(500)`
    - `func detail(for drama: Drama) async throws -> DramaDetail`: goes through a `TimedCache<DramaDetail>` keyed by `drama.id`.
    - `func focused(_ drama: Drama, nearby: [Drama], scale: CGFloat)`:
      - covers: `PosterCache.prefetch(nearby, maxPixelSize: ImageDownsampler.maxPixelSize(forPoints: 462, scale:))` straight away;
      - detail: cancel the pending debounce, wait `debounce`, then `PrefetchSlot.request`, and on finish run whatever `finished()` returns. Skip a drama whose `cachedValue` is already fresh.
  - `struct PosterFocusAction: Equatable`: `key: Int` and `perform: @MainActor (Drama) -> Void`, equal by key. Environment key `onPosterFocus` uses a classic `EnvironmentKey` rather than `@Entry`, for the tvOS 16 floor.
  - `TVPosterCard` calls `onPosterFocus?.perform(drama)` when it gains focus.
  - `TVPosterGrid` and the 搜索 grids install the action with `nearby = PosterPrefetchPlan.items(after:in:id:)` over the grid's items, `key` = hash of the item ids.
  - `DetailView.load()` and `PlaybackLauncher.play` fetch detail through `DetailPrefetch.shared.detail(for:)`. `HeroPlayback` stays on `CoreClient.detail`.

- [ ] **Step 1: Write the tests.**
  - `TimedCacheTests`, with a counting fetch and an injected clock:
    - `reusesFreshValue`: 2 calls → 1 fetch
    - `refetchesAfterMaxAge`: advance 181 s → 2 fetches
    - `sharesInFlight`: 2 concurrent → 1 fetch
    - `failureNotCached`: throw, then succeed → 2 fetches
  - `PrefetchTests`:
    - `idleStartsImmediately`
    - `busyQueuesOnlyTheNewest`: request a, b, c → finished returns c, then nil
    - `finishedWhenIdleReturnsNil`
    - `planTakesTheNextEight`: 12 items, focus index 2 → indices 3…10
    - `planEmptyForUnknownID`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `TimedCache`, `PrefetchSlot`, `PosterPrefetchPlan` and `DetailPrefetch`.
- [ ] **Step 4:** Run (PASS). Wire the focus hook, the grids, `DetailView` and `PlaybackLauncher`. Run `check.sh`.
- [ ] **Step 5:** Commit `perf: prefetch covers and detail when a poster rests in focus`.

### Task 5: 搜索 refresh — 大家都在看 and result headline

**Files:**
- Create:
  - `tvos/GuoAppTV/GuoAppTV/Views/Feed/FeedLoader.swift`
  - `tvos/GuoAppTV/GuoAppTV/Core/Logic/SearchCopy.swift`, `tvos/LogicTests/SearchCopyTests.swift`
- Modify: `Views/Feed/FeedModel.swift`, `Views/SearchModel.swift`, `Views/SearchView.swift`

**Interfaces:**
- Consumes: `PosterGridSkeleton` (Task 2), `TVFailureView` and `UserFacingError` (Task 3), the grid focus action (Task 4).
- Produces:
  - `enum FeedLoader { static func dramas(source: String, target: Int) async throws -> [Drama] }`
    - This is `FeedModel.loadRecommendations` moved verbatim, plus the non-红果 catalog page and the id de-duplication.
    - `FeedModel.load` calls it with `FeedModel.targetCount` (11). Its behaviour is unchanged.
  - `enum SearchCopy`
    - `static let popularTitle = "大家都在看"`
    - `static let popularCount = 14`
    - `static func found(_ count: Int) -> String`: "找到 N 部短剧"
    - `static func notFound(_ query: String) -> String`: "没有找到「query」"
    - `static let notFoundHint = "换个关键词试试，比如剧名里的几个字或「都市」「古装」"`
  - `SearchModel`:
    - Adds `@Published private(set) var popular: [Drama]`, `popularLoading: Bool` and `popularError: String?`.
    - Adds `func loadPopular(force: Bool = false)`. It loads `FeedLoader.dramas(source:target: 14)` and keeps the first 14. It runs on appear when `popular` is empty or the source changed, and the failure view's 重试 calls it with `force`.
- Results view:
  - Empty query: the "大家都在看" header (callout, bold) above the popular grid. Popular posters use `onSelect` and Play/Pause, the same as results.
  - Popular still loading: `PosterGridSkeleton()`.
  - Popular failed: `TVFailureView`.
  - Results: the `SearchCopy.found(model.results.count)` header above the grid.
  - Searching with no results yet: `PosterGridSkeleton(showsTitle: false)`.
  - No results: `notFound(query)` and `notFoundHint`.

- [ ] **Step 1: Write the tests.**
  - `foundHeadline`: 3 → "找到 3 部短剧"
  - `notFoundQuotesQuery`: "霸总" → "没有找到「霸总」"
  - `popularIsFourteen`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `SearchCopy` and `FeedLoader` (move the loop out of `FeedModel`). Then wire `SearchModel` and the results view.
- [ ] **Step 4:** `check.sh`, then commit `feat: 搜索 opens on 大家都在看 and headlines its results`.
- Ruling to ledger: N counts dramas (`results.count`), not cards. A grouped series card says 共 N 部, so the numbers add up. Cost if wrong: one property.

### Task 6: Phase 2 leftovers that follow existing owner decisions

**Files:**
- Modify:
  - `tvos/GuoAppTV/GuoAppTV/Core/Logic/ResumeTarget.swift`, `tvos/LogicTests/ResumeTargetTests.swift`
  - `Views/PlaybackLauncher.swift`, `Views/Feed/HeroPlayback.swift`, `Views/Feed/FeedHeroView.swift`, `Views/FeaturedBanner.swift`

**Interfaces:**
- Produces: `ResumeTarget.playbackStart(episodeNumbers: [Int], latestEpisode: Int?, position: Double, duration: Double) -> ResumeTarget?`
  - When `WatchStatus(latestEpisode:position:duration:totalEpisodes: episodeNumbers.count).isFinished` → `ResumeTarget(index: 0, position: 0)`. This is the 重新观看 decision applied to Play/Pause launches and the hero.
  - Otherwise `resolve(...)`.

- [ ] **Step 1: Write the tests.**
  - `finishedRestartsFromFirstEpisode`: [1, 2, 3], latest 3 at 99.5 / 100 → (0, 0)
  - `midwayResumes`: latest 2 at 30 / 100 → (1, 30)
  - `noHistoryStarts`: → (0, 0)
  - `noEpisodes`: → nil
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement it. Use it in `PlaybackLauncher.play` and `HeroPlayback.play`, passing the latest progress's `duration`.
- [ ] **Step 4:** 全屏观看 while the hero is still loading:
  - `FeedHeroView` keeps `@State var pendingFullScreen`. Pressing with no `fullScreenPresentation` sets it.
  - When `hero.session` becomes non-nil while it's set (`onReceive(hero.$session)`), call `watchFullScreen()`.
  - Clear it when `selection.heroID` changes or on disappear.
- [ ] **Step 5:** `FeaturedBanner` gets `.onPlayPauseCommand(perform: onPlay)`.
- [ ] **Step 6:** `check.sh`, then commit `fix: finished dramas restart from episode 1 everywhere; 全屏观看 waits for the hero`.
- Not in scope, owner to decide: what the hero should do at an episode's end when 播完自动连播 is off, and releasing a resolve that was cancelled after it returned (playback logic).

### Task 7: Docs and owner check

- [ ] **Step 1:** README (功能) and CHANGELOG (`## 未发布`) cover 大家都在看, skeletons, 出了点问题, downsampled covers and focus prefetch.
- [ ] **Step 2:** In the spec's Owner decisions, add the 2026-11-08 native search decision. Commit `docs: phase 3 notes`.
- [ ] **Step 3:** Run the final whole-branch review (fresh reviewer) and one fix pass.
- [ ] **Step 4:** On the owner's signal: `python3 scripts/deploy_tvos.py` → "完成。". Owner checks:
  - 搜索 opens on 大家都在看 (14 posters).
  - Results say "找到 N 部短剧", and no results says "没有找到「…」".
  - Skeletons shimmer on 推荐 / 剧场 / 搜索.
  - Pulling the network gives 出了点问题 / 网络连接失败… and 重试 recovers.
  - Covers stay sharp at focus.
  - Opening 详情 after resting on a poster is instant.
  - A finished drama started with Play/Pause starts at episode 1.
- [ ] **Step 5:** Push only once PR #1 is merged, or on the owner's word.
