# Phase 4: upstream core features, instant start and 我的 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use the Go core's existing features so the app:
- starts with content on screen;
- loads faster in parallel and cancels stale searches;
- shows 追剧更新 badges and fuller drama info;
- plays 弹幕 again;

and give 我的 the approved profile-dashboard layout.

**Architecture:**
- `CoreClient` dispatches on two lanes:
  - playback actions stay serial;
  - reads run up to 4 at once through an `AsyncLimiter`, and tag cancellable reads with a core read session.
- New pure rules in `Core/Logic`, tested on the Mac: limiter, routing, feed splice, ranking snapshot, follow-update rules, metadata header, viewing stats, size formatting.
- App-side objects:
  - `FollowUpdateChecker`: background `followCheck`.
  - `RankingSnapshotStore`: saves ranking page 1 per board.
- Store fields for update badges.
- A rebuilt `SettingsView` (我的).

**Tech Stack:** Swift 6 language mode, SwiftUI + UIKit on tvOS 16+, Xcode 27 / tvOS 27 SDK, Swift Testing (`swift test --package-path tvos`).

**Spec:** `docs/superpowers/specs/2026-11-08-phase4-upstream-features-and-mine-design.md` (mockup: `docs/superpowers/specs/assets/phase4-mine-layout-a.html`).

## Global Constraints

- Swift 6, tvOS 16 deployment target.
- Every task ends green on the phase 4 workspace `check.sh`: logic tests, plus a Debug build with **0 warnings**.
- No change to the Go core (`upstream/`), `PlaybackSession` playback logic, `PlayerController` internals, resolve paths, or `CoreClient`'s in-memory caches.
- The lane split is the only sanctioned change to request dispatch.
- Playback lane is serial: `initialize`, `resolve`, `fallback`, `release`, `cancelPlayback`. A newer playback request cancels the in-flight one in the core (`nativeBeginPlayback`).
- Read lane: at most **4** concurrent requests.
- Read sessions (core `session` + increasing `sequence`, both required):
  - `search` for catalog with a query;
  - `suggestions`;
  - `feed-<key>` for recommendations;
  - `danmaku`;
  - `metadata`.
- Exact copy:
  - badge "更新至 N 集"
  - "N 部有更新"
  - "检查追剧更新"
  - "进入推荐页自动播放"
  - "已用空间"
  - stat labels "在追", "看过的剧", "看完的集", "累计观看"
- New Swift files are registered with `pbx_add.py <Core|Views> <relpath>`.
- `Core/Logic` files import only Foundation, CoreGraphics or ImageIO.
- Owner's workflow rules:
  - Deploy only on the owner's signal.
  - Don't push `feature/polish` while PR #1 is open, unless the owner says so.
- Commits: conventional messages, no attribution trailer.

## Review Focus

1. **A playback request cancelled by a read, or reads starving playback.**
   - Expected: resolve, fallback and release never share the read lane, and episode prefetch still never cancels the current episode.
   - Pinned by `CoreRouteTests.playbackActionsStaySerial` (Task 1).
2. **A cancelled (superseded) read shown as 出了点问题.**
   - Expected: the core's cancellation reply becomes a cancellation and is never shown.
   - Pinned by `CoreRouteTests.cancelledReplyIsCancellation` (Task 1).
3. **False or stuck 更新 badges.**
   - Expected cases:
     - an upgrade from pre-phase-4 data shows no badges;
     - a follow from a ranking item (0 episodes) gets its baseline at the first check;
     - opening the detail page clears the badge.
   - Pinned by `FollowUpdateTests` (Task 4).
4. **The fresh 推荐 splice jumping the hero or shrinking 接下来.**
   - Expected: the hero and everything before it stay put, and the rest is replaced by the fresh feed.
   - Pinned by `FeedSpliceTests` (Task 2).
5. **Old store files failing to decode.**
   - Expected: new `FollowedDrama` / `Drama` fields are optional, and old JSON loads.
   - Pinned by `FollowUpdateTests.legacyFollowDecodes` and `DramaMetadataTests.legacyDramaDecodes` (Tasks 4–5).

---

### Task 0: Workspace

- [ ] Run `sdd-workspace` for this plan. Copy `check.sh`, `pbx_add.py` and `pbx_remove.py` from the phase 3 workspace, and point `check.sh`'s `W=` at the new directory. Run it. Expected: 132 tests pass, 0 warnings.

### Task 1: Two request lanes, read sessions, 弹幕

**Files:**
- Create: `Core/Logic/AsyncLimiter.swift`, `Core/Logic/CoreRoute.swift`, `LogicTests/AsyncLimiterTests.swift`, `LogicTests/CoreRouteTests.swift`
- Modify: `Core/Client.swift`, `Views/SearchModel.swift`, `Views/Feed/FeedModel.swift` (cancellation never shown)

**Interfaces:**
- Produces:
  - `actor AsyncLimiter`
    - `init(limit: Int)`
    - `func acquire() async`
    - `func release()`
    - FIFO waiters; the limit is never exceeded.
  - `enum CoreLane { case playback, read }`
  - `enum CoreRoute`
    - `static func lane(for action: String) -> CoreLane`
    - `static let playbackActions: Set<String> = ["initialize", "resolve", "fallback", "release", "cancelPlayback"]`
    - `static func isCancellation(message: String) -> Bool`: true for the core's `context canceled`.
  - `CoreClient`:
    - `call(_:session:)` takes an optional read-session key. When set, it adds `session` and `sequence` (one increasing `Int64` counter per client).
    - Playback-lane actions run on the existing serial queue.
    - Read-lane actions run on a concurrent queue gated by `AsyncLimiter(limit: 4)`.
    - A core error whose message `isCancellation` throws `CancellationError`.
  - Session keys:
    - `catalog` with a non-empty query → `search`
    - `suggestions` → `suggestions`
    - `recommendations` → `feed-<feed>`
    - `danmaku` → `danmaku`: this is the 弹幕 fix
    - `metadata` → `metadata` (Task 5)
  - `SearchModel` and `FeedModel` ignore `CancellationError` in their `catch` blocks: no state change, no error.

- [ ] **Step 1: Write the tests.**
  - `AsyncLimiterTests.neverExceedsLimit`: 10 tasks, limit 4, each holding 30 ms. A shared counter's peak is ≤ 4, and all 10 finish.
  - `AsyncLimiterTests.fifoOrder`: with limit 1, waiters run in the order they arrived.
  - `CoreRouteTests.playbackActionsStaySerial`: each of the 5 playback actions → `.playback`; `cover`, `catalog`, `detail`, `danmaku`, `followCheck`, `metadata` → `.read`.
  - `CoreRouteTests.cancelledReplyIsCancellation`: `context canceled` → true; `该剧暂时没有可播放的分集` → false.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `AsyncLimiter`, `CoreRoute` and the `CoreClient` lanes and sessions. Ignore cancellation in `SearchModel` and `FeedModel`.
- [ ] **Step 4:** Run (PASS), then `check.sh`.
- [ ] **Step 5:** Commit `perf: parallel, cancellable core reads on their own lane; fix 弹幕`.

### Task 2: 推荐 and 大家都在看 open instantly

**Files:**
- Create: `Core/Logic/FeedSplice.swift`, `LogicTests/FeedSpliceTests.swift`
- Modify: `Core/Client.swift`, `Views/Feed/FeedLoader.swift`, `Views/Feed/FeedModel.swift`, `Views/Feed/FeedHeroView.swift`, `Views/SearchModel.swift`

**Interfaces:**
- Consumes: Task 1's lanes and cancellation.
- Produces:
  - `CoreClient.cachedRecommendations(feed: String = "home_feed") async throws -> CatalogPage`: action `cachedRecommendations`, `category: feed`.
  - `FeedLoader.cached(source: String) async -> [Drama]`: 红果 → `cachedRecommendations`, de-duplicated. Other sources → `[]`. Errors → `[]`.
  - `enum FeedSplice { static func splice<Item>(existing: [Item], currentIndex: Int, fresh: [Item], id: (Item) -> String) -> [Item] }`:
    1. Keep `existing[0...currentIndex]`.
    2. Then add `fresh` items not already kept, in fresh order.
    3. Drop items without an id.
    4. If `currentIndex` is out of range, return `fresh` de-duplicated.
  - `FeedModel.load(source:force:)`:
    1. If `FeedLoader.cached` is non-empty and `dramas` is empty, `apply` it at once (state `.loaded`).
    2. Then fetch `FeedLoader.dramas(source:target: targetCount, force: true)`.
    3. On success, `dramas = FeedSplice.splice(existing: dramas, currentIndex: currentIndex, fresh: batch.dramas, id: \.id)`, `currentIndex` unchanged, `hasMore` from the batch.
    4. On failure with a cache shown, keep the cache. Without a cache, today's failure path applies.
    - The splice happens after the fill loop, never at the 2-drama first page (spec).
    - `FeedHeroView.loadFeed` calls `load(source:force:)` with `force: true` on the first load of each source in a run.
  - `SearchModel.loadPopular`: show `FeedLoader.cached` first 14 at once when non-empty, then load as today.

- [ ] **Step 1: Write the tests.**
  - `keepsHeroAndEarlierThenFresh`: `existing` [a,b,c,d,e], current 1, `fresh` [x,b,y,z] → [a,b,x,y,z]
  - `outOfRangeIndexTakesFresh`: `existing` [], current 0, `fresh` [x,x,y] → [x,y]
  - `dropsEmptyIDs`: `fresh` with "" is skipped
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement and wire it up. Run `check.sh`.
- [ ] **Step 4:** Commit `feat: 推荐 and 大家都在看 open on the saved feed; fresh feed spliced in behind the hero`.

### Task 3: 剧场 opens instantly

**Files:**
- Create: `Core/Logic/RankingSnapshot.swift`, `LogicTests/RankingSnapshotTests.swift`, `Core/RankingSnapshotStore.swift`
- Modify: `Core/Client.swift`, `Views/HomeView.swift`

**Interfaces:**
- Produces:
  - `struct RankingSnapshot<Item: Codable & Sendable>: Codable, Sendable { let board: String; let items: [Item]; let savedAt: Date }` and `static func isUsable(savedAt: Date, now: Date) -> Bool`: less than 7 days old.
  - `RankingSnapshotStore` (`@MainActor`, JSON at `Caches/ranking-snapshots.json`):
    - `func snapshot(board: String) -> [Drama]?`
    - `func save(board: String, items: [Drama])`
    - page 1 only.
  - `CoreClient.cached(source: String, category: String) async throws -> CatalogPage`: action `cached`. It's read-lane, not cached in the client.
  - `HomeView` first load:
    - Ranking mode: show the board's snapshot immediately.
    - Category mode: show `cached` immediately.
    - Then reload as today, without `firstPageLoads` dimming for this background refresh.
    - Save page 1 of every ranking board after it loads.
    - The skeleton shows only when neither exists.

- [ ] **Step 1: Write the tests.**
  - `roundTrips`: encode then decode keeps board, items and date.
  - `staleAfterSevenDays`: 6.9 days → usable; 7.1 days → not.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement and wire it up. Run `check.sh`.
- [ ] **Step 4:** Commit `feat: 剧场 opens on the last ranking page or the core's cached catalog`.

### Task 4: 追剧更新 (followCheck)

**Files:**
- Create: `Core/Logic/FollowUpdate.swift`, `LogicTests/FollowUpdateTests.swift`, `Core/FollowUpdateChecker.swift`
- Modify: `Core/Store.swift`, `Core/Client.swift`, `Views/MyListView.swift`, `Views/ContinueWatchingCard.swift`, `Views/DetailView.swift`, `Views/PlaybackLauncher.swift`, `Views/Feed/FeedHeroView.swift`, `Views/ContentView.swift` (foreground trigger)

**Interfaces:**
- Produces:
  - `FollowedDrama` gains optional `knownEpisodes: Int?`, `latestEpisodes: Int?` and `checkedAt: Date?`. Old JSON still decodes.
  - `enum FollowUpdate`:
    - `static let recheckInterval: TimeInterval = 6 * 3600`
    - `static func hasUpdate(known: Int?, latest: Int?) -> Bool`: both present, known > 0, and latest > known.
    - `static func afterCheck(known: Int?, latest: Int) -> (known: Int, latest: Int)`: an unknown or 0 `known` becomes `latest` (baseline, no badge); otherwise `known` stays.
    - `static func shouldCheck(checkedAt: Date?, now: Date, finished: Bool, force: Bool) -> Bool`
    - `static func badge(latest: Int) -> String`: "更新至 N 集"
  - `CoreClient.followCheck(drama: Drama) async throws -> Drama`: action `followCheck`, read lane.
  - `Store`:
    - `func recordCheck(dramaID: String, latestEpisodes: Int, at: Date)`, applying `afterCheck`.
    - `func acknowledgeUpdate(dramaID: String)`: `known = latest`.
    - `toggleFollow(_:knownEpisodes:)`: the detail page passes `detail.episodes.count`; others pass nil.
    - `var updatedFollows: [FollowedDrama]`
  - `@MainActor final class FollowUpdateChecker`:
    - `static let shared`
    - `func checkIfDue(store: Store, force: Bool = false)`: sequential over follows, skipping per `shouldCheck`. `finished` = the follow's latest progress `WatchStatus.isFinished` with its known count. Errors are skipped silently.
  - Triggers:
    - `FeedHeroView` once its first list shows;
    - app foreground (`UIApplication.didBecomeActiveNotification`) in `ContentView`;
    - 我的's 检查追剧更新 (`force: true`, Task 6).
  - Acknowledge:
    - `DetailView` on appear;
    - `PlaybackLauncher.play` / `present`;
    - 全屏观看 in `FeedHeroView`.
  - Badges: the `TVPosterCard` badge `FollowUpdate.badge` on 我的追剧 posters, and on 继续观看 cards whose drama has an update.

- [ ] **Step 1: Write the tests.**
  - `noBadgeWithoutBaseline`: (nil, 80) and (0, 80) → false
  - `badgeWhenMoreEpisodes`: (80, 85) → true; (80, 80) → false
  - `firstCheckSetsBaseline`: `afterCheck(nil, 85)` → (85, 85); `afterCheck(80, 85)` → (80, 85)
  - `rechecksAfterSixHours`: 5 h → false; 7 h → true; never checked → true; finished → false unless `force`
  - `badgeText`: 85 → "更新至 85 集"
  - `legacyFollowDecodes`: JSON without the new keys decodes, with nil fields
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement and wire it up. Run `check.sh`.
- [ ] **Step 4:** Commit `feat: 追剧更新 badges from the core's followCheck`.

### Task 5: Fuller drama info (metadata)

**Files:**
- Create: `Core/Logic/DramaMetadata.swift`, `LogicTests/DramaMetadataTests.swift`
- Modify: `Core/Models.swift` (`Drama.score: String?`), `Core/Client.swift`, `Views/DetailView.swift`

**Interfaces:**
- Produces:
  - `Drama.score: String?`, parsed from `score`. Old saved dramas decode with nil.
  - `CoreClient.metadata(drama: Drama) async throws -> Drama`: action `metadata`, session `metadata`.
  - `enum DramaMetadata`
    - `static func needsSupplement(source: String, score: String?, onlineDate: String) -> Bool`: 红果 with an empty score or empty date.
    - `static func headerParts(score: String?, onlineDate: String, heat: String) -> [String]`: "评分 9.5", "2026-10 上线" (first 7 characters of an ISO date), "热度 X"; empty values skipped.
  - `DetailView`: after the detail loads, if `needsSupplement`, fetch `metadata` once and merge score, `onlineDate` and heat into the shown drama. The header uses `headerParts`.

- [ ] **Step 1: Write the tests.**
  - `supplementsHongguoMissingScore`
  - `noSupplementWhenComplete`
  - `noSupplementForOtherSources`
  - `headerParts`: ("9.5", "2026-10-03", "1.3亿") → ["评分 9.5", "2026-10 上线", "热度 1.3亿"]
  - `legacyDramaDecodes`: a `Drama` JSON without `score` decodes
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement and wire it up. Run `check.sh`.
- [ ] **Step 4:** Commit `feat: fill in score, release date and heat on the detail page`.

### Task 6: 我的 — layout A

**Files:**
- Create:
  - `Core/Logic/ViewingStats.swift`, `Core/Logic/StorageSize.swift`
  - `LogicTests/ViewingStatsTests.swift`, `LogicTests/StorageSizeTests.swift`
- Modify:
  - `Views/SettingsView.swift` (rebuilt)
  - `Views/Feed/FeedHeroView.swift`, `Views/Feed/HeroInfoPanel.swift` (autoplay off)
  - `scripts/build_tvos.py`, `tvos/GuoAppTV/GuoAppTV/Info.plist`, `project.pbxproj` (core revision)

**Interfaces:**
- Produces:
  - `struct ViewingStats: Equatable { following, dramasWatched, episodesFinished: Int; hoursWatched: Double }` and `static func make(follows: Int, entries: [(dramaID: String, position: Double, duration: Double)]) -> ViewingStats`:
    - `dramasWatched` = distinct dramas with position > 0;
    - `episodesFinished` = entries with duration > 0 and position / duration ≥ 0.9;
    - `hoursWatched` = sum of positions / 3600, rounded to one decimal.
    - The store keeps the last 500 entries, which the 累计观看 label doesn't claim to exceed.
  - `enum StorageSize { static func label(bytes: Int64) -> String }`: "412 MB", "1.2 GB", "820 KB" (1000-based, as the system shows).
  - `SettingsView` per the mockup:
    - Header: icon tile, 火龙果短剧, "在电视上追短剧 · 版本 X · 核心 R". R comes from Info.plist `GUOAppCoreRevision`, or "—".
    - Four stat tiles.
    - Two columns of groups:
      - 播放: 播完自动连播下一集, 清晰度 · 倍速, 弹幕, 播放诊断.
      - 推荐: 进入推荐页自动播放.
      - 追剧: 检查追剧更新 with "N 部有更新" / "刚刚检查", and 清除观看记录 with its confirmation.
      - 存储与关于: 已用空间 (Caches size, computed off the main actor), 站源 (all-sources builds keep the picker), 关于.
  - `@AppStorage("heroAutoplay")`, default true. When false:
    - `FeedHeroView.startHero` doesn't call `hero.play` until `userStartedHero`.
    - The 暂停 button reads 播放 while no session exists.
    - It or Play/Pause sets `userStartedHero = true` and starts.
    - `onDisappear` resets it.
  - The build passes `GUOAPP_CORE_REVISION=<git -C upstream rev-parse --short HEAD>`; Info.plist `GUOAppCoreRevision = $(GUOAPP_CORE_REVISION)`; pbxproj defaults it to empty.

- [ ] **Step 1: Write the tests.**
  - `statsCountDistinctDramasAndFinishedEpisodes`: entries
    - (a, 50, 100)
    - (a, 95, 100)
    - (b, 3600, 3600)
    - (c, 0, 100)

    → watched 2, finished 2, hours 1.0 (50 + 95 + 3600 = 3745 s → 1.0).
  - `storageLabels`: 412_000_000 → "412 MB"; 1_200_000_000 → "1.2 GB"; 820_000 → "820 KB"
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. Rebuild `SettingsView` to the mockup, add the autoplay-off path and the core revision. Run `check.sh`.
- [ ] **Step 4:** Commit `feat: 我的 profile dashboard with stats, 追剧更新 and 推荐 autoplay`.

### Task 7: Docs, review and owner check

- [ ] README (功能: 弹幕 works again, 追剧更新, instant start, 我的) and CHANGELOG (`## 未发布`). Commit `docs: phase 4 notes`.
- [ ] Final whole-branch review (fresh reviewer, model fable) from the phase 4 base, then one fix pass.
- [ ] On the owner's signal, deploy. Owner checks:
  - 推荐 and 剧场 show content instantly after a relaunch, and 接下来 turns fresh within about 10 s.
  - 弹幕 scrolls in the full-screen player and the toggle works.
  - A followed drama with new episodes shows 更新至 N 集, and the badge clears after opening it.
  - The detail page shows 评分 / 上线 when available.
  - 我的 matches layout A, its stats look plausible, and 已用空间 and the core revision show.
  - Autoplay off keeps 推荐 still until 播放.
  - Typing fast in 搜索 stays responsive, and posters load faster.
