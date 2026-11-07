# Phase 1: Watching Ergonomics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring redfruit's watching layout to guoapp-tvos: tabs 剧场 · 追剧 · 搜索 · 我的; 追剧 with 继续观看
cards and 我的追剧; a detail page with a ranged 选集 number grid, also used in the player; 系列 grouping of a drama's
parts (in search, on the detail page and in 继续观看); Play/Pause on any poster plays it; and redfruit's 我的
layout with 清除观看记录.

**Architecture:** Pure rules (episode ranges, cell states, watch captions, resume targets) live in
Foundation-only files under `Core/Logic/`. They compile into the app and into a SwiftPM test package at
`tvos/Package.swift` that runs on the Mac with `swift test`. SwiftUI views consume those rules. A
`PlaybackLauncher` object turns "play this drama" into a detail fetch plus a `PlayerView` full-screen cover,
and every screen shares it.

**Tech Stack:** SwiftUI and UIKit (tvOS 16), Swift 6 language mode, Swift Testing for the logic package,
mpv player unchanged.

**Spec:** `docs/superpowers/specs/2026-11-08-redfruit-layout-design.md` (Phase 1 sections: Shell, 追剧,
Detail, 系列, 我的, plus Owner decisions).

## Global Constraints

- tvOS 16 deployment target, Swift 6 language mode (`SWIFT_VERSION = 6.0`), no new dependencies.
- Don't change `PlayerController`, mpv, `CoreClient` caching, or `PlayerView`'s episode logic. `PlayerView`
  is only presented, with `PlayerView(drama:episodes:startIndex:startPosition:)`.
- Keep the `KeepAliveTabView` (`UITabBarController`) shell. Don't use SwiftUI `TabView`.
- Use `TVTheme` tokens only (`TVTheme.TextSize`, colours, `focusScale` / `chipScale` / `buttonScale`,
  `focusAnimation`). Body text ≥ 29 pt; safe area 80 sides / 60 top-bottom.
- Every new app source file goes into `tvos/GuoAppTV/GuoAppTV.xcodeproj/project.pbxproj` with a
  PBXBuildFile, a PBXFileReference, a group child and a Sources entry. Pick unused IDs of the form
  `A1000000000000000000005X` and grep that each ID is unused first.
- Source files stay under 800 lines.
- Build check: `xcodebuild -project tvos/GuoAppTV/GuoAppTV.xcodeproj -scheme GuoAppTV -sdk appletvos -configuration Debug -derivedDataPath tvos/GuoAppTV/build -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build`
  must print `** BUILD SUCCEEDED **` with zero `.swift:N:N: warning|error` lines. Logic check:
  `swift test --package-path tvos` must report all tests passing.
- UI strings, verbatim from the spec:
  - 继续观看
  - 我的追剧
  - 看到第 N 集 / 共 M 集
  - 看到第 N 集 · 共 M 集
  - 未开始 · 共 M 集
  - 已看完
  - 查看详情
  - 从观看记录中移除
  - 取消追剧
  - 还没有追剧 / 在详情页按「追剧」，或看过的短剧，都会出现在这里
  - 继续观看 第 N 集
  - 立即观看
  - 清除观看记录
  - 清除全部观看记录？ / 「继续观看」会被清空，追剧列表不受影响。
  - 在电视上追短剧

## Review Focus

1. **Unknown episode total** (`Drama.episodes == 0`): captions drop "共 M 集", the series bar stays at a
   finite fraction (never NaN), and nothing claims "已看完". *(Task 2 tests.)*
2. **A saved episode no longer in the detail list** (renumbered or removed): resume falls back to episode 1
   at 0 s and doesn't crash. *(Task 3 test `resumeFallsBackWhenEpisodeMissing`.)*
3. **Edge episode counts** (1, 30, 31, 0): the right ranges, no chip row when there is only one range, and
   no empty grid page. *(Task 1 tests.)*
4. **Repeated clicks or a slow / failing detail fetch from a card or poster**: one fetch at a time,
   inline loading, a Chinese error alert, and never two player covers. *(Task 3 re-entrancy test on
   `PlaybackLauncher.State`, plus a device check.)*
5. **Clearing history while 追剧 is showing**: 继续观看 disappears at once, follows stay, and the empty
   state shows only when both are empty. *(Task 6 device check; `Store.clearHistory()` in Task 6.)*
6. **Series edge titles**: "X第二部" vs "X 第2部" vs "X（第二部）" must group together; "X 第二季" must not
   group with "X 第二部"; "第201部" and a bare "第二部" with an empty base are not series. *(Task 9 tests.)*

---

### Task 1: Logic package, episode ranges and cell states

**Files:**
- Create: `tvos/Package.swift` (package `GuoAppLogic`, macOS 14; target `GuoAppLogic` at
  `GuoAppTV/GuoAppTV/Core/Logic`; test target `GuoAppLogicTests` at `LogicTests`)
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/EpisodeRanges.swift`
- Create: `tvos/LogicTests/EpisodeRangesTests.swift`
- Modify: `project.pbxproj` (register `EpisodeRanges.swift` in the app target)
- Modify: `.gitignore` (add `tvos/.build/` and `tvos/.swiftpm/`)

**Interfaces:**
- Produces:
  - `struct EpisodeRanges: Equatable, Sendable`
    - `init(episodeCount: Int, pageSize: Int = 30)`
    - `let ranges: [ClosedRange<Int>]` (episode numbers, 1-based)
    - `func clampedIndex(containing episode: Int) -> Int`
    - `static func label(for: ClosedRange<Int>) -> String` (en dash, e.g. `"1–30"`; a single episode as
      `"31"`)
  - `enum EpisodeCellState: Equatable, Sendable { case watched, current, unwatched }`
    - `init(episode: Int, currentEpisode: Int?)`: below current → `.watched`, equal → `.current`, otherwise
      or with nil → `.unwatched`.

- [ ] **Step 1:** Write `tvos/LogicTests/EpisodeRangesTests.swift` (Swift Testing, `@testable import GuoAppLogic`):
  - `rangesSplitIntoThirties`: 80 → `[1...30, 31...60, 61...80]`
  - `exactMultiple`: 30 → `[1...30]`
  - `oneOverPage`: 31 → `[1...30, 31...31]`, with `label(for: 31...31) == "31"`
  - `emptyAndSingle`: 0 → `[]`, 1 → `[1...1]`
  - `labels`: `label(for: 1...30) == "1–30"`
  - `clampedIndex`: (80 episodes) 45 → 1; 0 → 0; 999 → 2; with empty ranges → 0
  - `cellStates`: `(3, 5)` → `.watched`, `(5, 5)` → `.current`, `(6, 5)` → `.unwatched`, `(1, nil)` →
    `.unwatched`
- [ ] **Step 2:** Run `swift test --package-path tvos`. Expected: FAIL (`EpisodeRanges` not found).
- [ ] **Step 3:** Implement `EpisodeRanges.swift` (Foundation only, internal access). Write `Package.swift`
  with `// swift-tools-version: 6.0`. Register the file in the pbxproj.
- [ ] **Step 4:** Run `swift test --package-path tvos` (expected: PASS) and the build check (expected:
  BUILD SUCCEEDED, no warnings).
- [ ] **Step 5:** Commit: `feat: episode ranges and cell states with a Mac-runnable logic test package`.

### Task 2: Watch status captions and series progress

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/WatchStatus.swift`
- Create: `tvos/LogicTests/WatchStatusTests.swift`
- Modify: `project.pbxproj` (register)

**Interfaces:**
- Produces: `struct WatchStatus: Equatable, Sendable`
  - `init(latestEpisode: Int?, position: Double, duration: Double, totalEpisodes: Int)`
  - `totalEpisodes ≤ 0` means unknown. `fraction` is `position / duration`, clamped to 0…1; 0 when
    `duration ≤ 0`.
  - `var isFinished: Bool`: total known, `latestEpisode == total`, and `fraction ≥ 0.99`
  - `var seriesFraction: Double`: `(N − 1 + fraction) / M`, clamped to 0…1; 1 when finished; 0 when not
    started or the total is unknown
  - `var cardCaption: String`:
    - `"已看完"` when finished
    - `"看到第 N 集 / 共 M 集"` when the total is known
    - `"看到第 N 集"` when it isn't
    - `""` when not started
  - `var posterCaption: String`:
    - `"已看完 · 共 M 集"` when finished
    - `"看到第 N 集 · 共 M 集"` while watching
    - `"未开始 · 共 M 集"` when not started
    - with the total unknown, drop the `" · 共 M 集"` suffix, so not started is `"未开始"`

- [ ] **Step 1:** Write the tests:
  - `watchingKnownTotal`: (12, 30, 120, 80) → `cardCaption == "看到第 12 集 / 共 80 集"`,
    `posterCaption == "看到第 12 集 · 共 80 集"`, and `seriesFraction` ≈ `(11 + 0.25) / 80`
  - `finishedLastEpisode`: (80, 119.5, 120, 80) → `isFinished`, `cardCaption == "已看完"`,
    `seriesFraction == 1`
  - `lastEpisodeNotDone`: (80, 60, 120, 80) → not finished
  - `unknownTotal`: (5, 10, 100, 0) → `cardCaption == "看到第 5 集"`, `posterCaption == "看到第 5 集"`,
    `seriesFraction == 0`, not finished
  - `notStarted`: (nil, 0, 0, 60) → `posterCaption == "未开始 · 共 60 集"`, `cardCaption == ""`;
    (nil, 0, 0, 0) → `"未开始"`
  - `zeroDurationIsFinite`: (3, 50, 0, 10) → `seriesFraction` is finite and equals `0.2`
- [ ] **Step 2:** Run `swift test --package-path tvos`. Expected: FAIL.
- [ ] **Step 3:** Implement `WatchStatus.swift` and register it.
- [ ] **Step 4:** Run the tests (PASS) and the build check.
- [ ] **Step 5:** Commit: `feat: watch status captions and series progress`.

### Task 3: Resume target and the shared playback launcher

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/ResumeTarget.swift`
- Create: `tvos/LogicTests/ResumeTargetTests.swift`
- Create: `tvos/GuoAppTV/GuoAppTV/Views/PlaybackLauncher.swift`
- Modify: `project.pbxproj` (register both)

**Interfaces:**
- Produces:
  - `struct ResumeTarget: Equatable, Sendable { let index: Int; let position: Double }`
    - `static func resolve(episodeNumbers: [Int], latestEpisode: Int?, position: Double) -> ResumeTarget?`
    - nil when `episodeNumbers` is empty
    - `index` of `latestEpisode` with its `position` when found, otherwise `(0, 0)`
  - `@MainActor final class PlaybackLauncher: ObservableObject` in `PlaybackLauncher.swift`:
    - `@Published private(set) var loadingDramaID: String?`
    - `@Published var presentation: PlaybackPresentation?`
    - `@Published var errorMessage: String?`
    - `func play(_ drama: Drama, store: Store)`: ignored while `loadingDramaID != nil` or `presentation`
      is set. It fetches `CoreClient.shared.detail(drama:)`, resolves with
      `store.latestProgress(for: drama.id)`, and sets `presentation`. On failure it sets
      `errorMessage = error.localizedDescription`. An empty episode list gives "暂无可播放的分集".
  - `struct PlaybackPresentation: Identifiable { let id = UUID(); let drama: Drama; let episodes: [Episode]; let startIndex: Int; let startPosition: Double }`
  - `extension View { func playbackLauncher(_ launcher: PlaybackLauncher) -> some View }` presents
    `.fullScreenCover(item: $launcher.presentation)` with
    `PlayerView(drama:episodes:startIndex:startPosition:)`, plus an `.alert` for `errorMessage` with a
    single 好 button.
  - `PlaybackLauncher.State` (a nested pure enum or func) is the re-entrancy rule:
    `static func canStart(loadingDramaID: String?, presenting: Bool) -> Bool`. If it doesn't fit the logic
    package, inline it and test it by hand.

- [ ] **Step 1:** Write the `ResumeTargetTests`:
  - `resumeFound`: `([1,2,3], 2, 42)` → `(1, 42)`
  - `resumeNil`: `([1,2], nil, 0)` → `(0, 0)`
  - `resumeFallsBackWhenEpisodeMissing`: `([1,2,3], 9, 30)` → `(0, 0)`
  - `noEpisodes`: `([], 1, 0)` → nil

  If `canStart` lives in the logic package, add `launcherReentrancy`: `canStart(nil, false) == true`,
  `canStart("x", false) == false`, `canStart(nil, true) == false`.
- [ ] **Step 2:** Run `swift test --package-path tvos`. Expected: FAIL.
- [ ] **Step 3:** Implement `ResumeTarget.swift`, then `PlaybackLauncher.swift`, using `ResumeTarget` and
  the re-entrancy rule. Register both.
- [ ] **Step 4:** Run the tests (PASS) and the build check.
- [ ] **Step 5:** Commit: `feat: resume target and shared playback launcher`.

### Task 4: Ranged 选集 number grid, in Detail and in the player

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Views/EpisodeNumberGrid.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/DetailView.swift` (`episodesSection`, `episodeProgress`)
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/PlayerControlsView.swift` (`PlayerEpisodeSheet` body)
- Modify: `project.pbxproj`

**Interfaces:**
- Consumes: `EpisodeRanges`, `EpisodeCellState` (Task 1).
- Produces: `struct EpisodeNumberGrid: View`
  - `init(episodes: [Episode], currentEpisode: Int?, progress: @escaping (Episode) -> Double?, columns: Int = 15, onSelect: @escaping (Int) -> Void)`
  - `onSelect` receives the index into `episodes`.
  - Layout:
    - A header row with "选集" in `TextSize.headline` and the range chips (`TVChip(compact: true)`), shown
      only when there is more than one range, in a `.focusSection()`.
    - A non-lazy grid of `columns` cells, 20 apart, also in a `.focusSection()`.
  - Each cell:
    - 80 tall, radius 12, label `episode.number` in `TextSize.callout` bold monospaced.
    - Colours: watched `textPrimary@6%` background with `textPrimary@45%` text; current `TVTheme.accent`;
      unwatched `TVTheme.surface`; focused `textPrimary` with `ink` text, scaled `focusScale`.
    - VIP: a "VIP" tag top-right in `TextSize.caption2` bold.
    - Partial progress (`progress(episode)` > 0.005): a 4 pt accent bar along the bottom inside the cell.
  - The initially selected range is `clampedIndex(containing: currentEpisode ?? 1)`. The current
    episode's cell gets `.prefersDefaultFocus(true, in:)` within a `focusScope`.

- [ ] **Step 1:** Implement `EpisodeNumberGrid.swift` and register it.
- [ ] **Step 2:** In `DetailView`, replace the `TVEpisodeButton` grid with
  `EpisodeNumberGrid(episodes:currentEpisode: store.latestProgress(for:)?.episode, progress: episodeProgress, onSelect:)`.
  `onSelect` sets the existing `playTarget` at position 0. Keep the `warning` text and the "共 N 集" count.
- [ ] **Step 3:** Change `PlayerEpisodeSheet`'s body to a title plus `EpisodeNumberGrid(..., columns: 10)`
  inside the existing 1500×820 frame. Remove its now-unused `rows` / `cell` / `columns` helpers.
- [ ] **Step 4:** Build check. Expected: BUILD SUCCEEDED, no warnings.
- [ ] **Step 5:** Commit: `feat: ranged 选集 number grid on detail page and in player`.

### Task 5: Detail header and primary action

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/DetailView.swift` (header and actions)

**Interfaces:**
- Consumes: `ResumeTarget` (Task 3), the existing `playTarget` / `PlayTarget`.

- [ ] **Step 1:** Re-lay out the header the redfruit way (`redFruit/RedFruit/Features/Detail/DetailHeader.swift`):
  - Poster left; title (`TextSize.title2`, up to 2 lines), the pills (category, 已完结 / 连载中, 共 N 集,
    热度), and the synopsis (`TextSize.body`, `textSecondary`, 3 lines) on the right.
  - Primary button `TVPrimaryButton`:
    - title `"继续观看 第 N 集"` when `store.latestProgress(for:)` matches an episode, otherwise `"立即观看"`
    - icon `play.fill`
    - action `playResume()`, rewritten to use `ResumeTarget.resolve`
  - Keep 追剧 / 已追剧 as `TVSecondaryButton`. Remove the separate "上次看到" line; the button now carries it.
- [ ] **Step 2:** Build check.
- [ ] **Step 3:** Commit: `feat: redfruit-style detail header with resume action`.

### Task 6: 追剧 tab (继续观看 and 我的追剧) and Store.clearHistory

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Views/MyListView.swift`
- Create: `tvos/GuoAppTV/GuoAppTV/Views/ContinueWatchingCard.swift`
- Delete: `Views/FollowingView.swift`, `Views/HistoryView.swift` (and their pbxproj entries)
- Modify: `tvos/GuoAppTV/GuoAppTV/Core/Store.swift` (add `func clearHistory()`)
- Modify: `project.pbxproj`

**Interfaces:**
- Consumes: `WatchStatus` (Task 2), `PlaybackLauncher` / `.playbackLauncher` (Task 3), `store.recentHistory`,
  `store.follows`, `store.latestProgress(for:)`, `store.deleteHistory(for:)`, `store.toggleFollow(_:)`.
- Produces:
  - `struct MyListView: View`, the 追剧 tab root, with its own `NavigationStack` and `DetailView` destination.
  - `struct ContinueWatchingCard: View { init(progress: WatchProgress, isLoading: Bool) }`.
  - `Store.clearHistory()` removes every progress entry, keeps follows, and persists.

- [ ] **Step 1:** Add `Store.clearHistory()`.
- [ ] **Step 2:** Build `ContinueWatchingCard`, ported from redfruit `ContinueWatchingCard.swift`:
  - 500 wide, padding 20, radius 20, background `textPrimary@8%`.
  - A 140×210 poster (the existing poster image view), the title in `TextSize.body` bold over 2 lines.
  - `WatchStatus(...).cardCaption` in `TextSize.caption` at 70 %, and a 290-wide series bar from
    `seriesFraction`, using `TVProgressBar`.
  - A small `ProgressView` overlay when `isLoading`.
- [ ] **Step 3:** Build `MyListView`. It's a vertical `ScrollView` with sections 40 apart:
  - **继续观看 shelf:** a horizontal scroll of `ContinueWatchingCard`s from `store.recentHistory`.
    - Each card is a `Button` that calls `launcher.play(progress.drama, store:)`; Play/Pause does the same.
    - Card focus: `tvFocusEffect(scale: 1.05, cornerRadius: 20)`.
    - Long-press `contextMenu`: 查看详情 (push `DetailView`) and 从观看记录中移除 (`store.deleteHistory`).
  - **我的追剧 shelf:** `TVPosterCard`s whose subtitle is `WatchStatus(...).posterCaption` and whose action
    opens `DetailView`. Play/Pause calls `launcher.play`. Long-press offers 取消追剧.
  - **Empty state:** use `TVStatusView` when both shelves are empty.
  - Attach `.playbackLauncher(launcher)`.
- [ ] **Step 4:** Remove `FollowingView.swift` and `HistoryView.swift` from the disk and the pbxproj.
  `ContentView` is wired in Task 8, so temporarily point the 追剧 tab at `MyListView` and drop the 最近观看
  tab here, keeping the build green.
- [ ] **Step 5:** Build check.
- [ ] **Step 6:** Commit: `feat: 追剧 tab with 继续观看 cards and 我的追剧`.

### Task 7: 我的 (settings) in the redfruit layout, with 清除观看记录

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `Store.clearHistory()` (Task 6).

- [ ] **Step 1:** Two columns, 80 apart:
  - **Left, 560 wide, 120 from the top:**
    - A 320×320 tile, radius 48, filled with `TVTheme.accentGradient`, with a 140 pt `play.fill` icon.
    - The display name (from `Bundle.main` `CFBundleDisplayName`) in `TextSize.title2`.
    - "在电视上追短剧" in `TextSize.body`, `textSecondary`.
  - **Right:** the existing groups (站源, 播放, 关于), unchanged in behaviour, plus a new 观看记录 group.
    Its row 清除观看记录 shows a `confirmationDialog` titled "清除全部观看记录？" with the message
    "「继续观看」会被清空，追剧列表不受影响。" and the buttons 清除 (destructive) / 取消. 清除 calls
    `store.clearHistory()`.
- [ ] **Step 2:** Rewrite the 关于 notes:
  - Remove: ↑/↓ changes speed; Play/Pause deletes in 最近观看; Play/Pause refreshes 首页.
  - Add:
    - "在海报上按播放键直接播放"
    - "继续观看卡片长按可查看详情或移除"
    - "播放时点按或按 ↑↓ 调出控件：倍速、画面、选集；← → 快退 / 快进 10 秒"

  Keep the MPV / Go credit and the Caches note.
- [ ] **Step 3:** Build check.
- [ ] **Step 4:** Commit: `feat: redfruit-style 我的 page with 清除观看记录`.

### Task 8: Shell, launch name, and Play/Pause-plays on posters

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/ContentView.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/PosterView.swift` (`TVPosterGrid` gains `onPlay`)
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/HomeView.swift` (remove Play/Pause refresh, pass `onPlay`)
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/SearchView.swift` (pass `onPlay`)

**Interfaces:**
- Consumes: `PlaybackLauncher` (Task 3), `MyListView` (Task 6).
- Produces: `TVPosterGrid(items:showRank:onReachEnd:onPlay:)`, where `onPlay: ((Drama) -> Void)?` is
  attached as `.onPlayPauseCommand` on each card.

- [ ] **Step 1:** Tabs in order, with 剧场 as the default:
  1. 剧场 `film.stack`: `HomeView`
  2. 追剧 `heart`: `MyListView`
  3. 搜索 `magnifyingglass`: `SearchView`
  4. 我的 `person.crop.circle`: `SettingsView`

  The launch screen title uses the display name, not a hard-coded "红果鉴". 推荐 arrives in phase 2.
- [ ] **Step 2:** Add `onPlay` to `TVPosterGrid`. In `HomeView`, remove the Play/Pause refresh
  (`onPlayPauseCommand` plus `refresh()` if it's now unused), own a `@StateObject` `PlaybackLauncher`, pass
  `onPlay: { launcher.play($0, store: store) }`, and attach `.playbackLauncher`. Do the same in `SearchView`.
- [ ] **Step 3:** Build check. Run the full logic test suite: `swift test --package-path tvos`.
- [ ] **Step 4:** Commit: `feat: redfruit tab shell, display-name launch, Play/Pause plays posters`.

### Task 9: 系列 rule and grouping (logic)

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/Logic/SeriesTitle.swift`
- Create: `tvos/LogicTests/SeriesTitleTests.swift`
- Modify: `project.pbxproj`

**Interfaces:**
- Produces:
  - `struct SeriesTitle: Equatable, Sendable { let base: String; let part: Int; let unit: String; let key: String }`
    - `static func parse(_ title: String) -> SeriesTitle?`: the regex
      `第\s*([0-9零〇一二两兩三四五六七八九十百]+)\s*([季部])[\p{P}\s]*$` applied after NFKC (`precomposedStringWithCompatibilityMapping`).
    - Parse Chinese numerals exactly as the core's `hongguoSearchSeason` does, 1–200.
    - `key = normalize(base) + ":" + unit`.
  - `static func normalize(_ text: String) -> String`: NFKC, lower-case, spaces and punctuation removed;
    if that leaves nothing, the trimmed lower-cased text. This is the core's `hongguoSearchText`.
  - `struct SeriesGroup<Item>: Sendable where Item: Sendable { let key: String; let base: String; let unit: String; let parts: [(part: Int, item: Item)] }`
    - Parts are sorted ascending. A struct with an array of a small `Part` struct is fine instead of tuples,
      if `Sendable` / `Equatable` demands it.
  - `enum SeriesGrouping`
    - `static func group<Item>(_ items: [Item], title: (Item) -> String, source: (Item) -> String) -> [SeriesEntry<Item>]`
    - `enum SeriesEntry<Item> { case single(Item); case series(SeriesGroup<Item>) }`
    - Order follows each entry's first appearance. A group needs ≥ 2 distinct parts. An unsuffixed title
      joins a group as part 1 when `normalize(title) + ":" + unit` matches.
    - Groups never span sources.
  - `static func partsLabel(_ parts: [Int], unit: String) -> String`: `"第 1–3 部"` when contiguous,
    otherwise `"第 1、3 部"`.

- [ ] **Step 1:** Write the tests:
  - `parsesArabicAndChinese`:
    - `"霸总 第2部"` → (base "霸总", part 2, unit "部")
    - `"霸总第二部"` → part 2
    - `"霸总 第十一季"` → 11, unit "季"
    - `"霸总第二十部"` → 20
    - `"霸总第一百部"` → 100
  - `rejectsNonSeries`: `"霸总"`, `"第二部"` (empty base) and `"霸总第201部"` → nil
  - `fullWidthAndPunctuation`: `"霸总（第２部）"` → part 2
  - `groupsSameSeries`: [`"霸总"`, `"霸总 第二部"`, `"别的剧"`, `"霸总第3部"`], all source "hongguo" →
    `[.series(base "霸总", parts [1,2,3]), .single("别的剧")]`
  - `unitsDontMix`: `"霸总 第二部"` and `"霸总 第二季"` → two singles
  - `sourcesDontMix`: the same titles from "hongguo" and "hema" → not grouped together
  - `singlePartIsNotASeries`: [`"霸总 第二部"`] → `.single`
  - `partsLabel`: `[1,2,3]` → `"第 1–3 部"`; `[1,3]` → `"第 1、3 部"`; `[2]` with "季" → `"第 2 季"`
- [ ] **Step 2:** Run `swift test --package-path tvos`. Expected: FAIL.
- [ ] **Step 3:** Implement `SeriesTitle.swift` and register it.
- [ ] **Step 4:** Run the tests (PASS) and the build check.
- [ ] **Step 5:** Commit: `feat: series title rule and grouping, matching the core`.

### Task 10: Grouped search results

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/SearchView.swift`
- Create: `tvos/GuoAppTV/GuoAppTV/Views/SeriesPosterCard.swift`
- Modify: `project.pbxproj`

**Interfaces:**
- Consumes: `SeriesGrouping` (Task 9), `PlaybackLauncher` (Task 3), `TVPosterCard` / `TVPosterGrid` (Task 8
  `onPlay`).
- Produces:
  - `struct SeriesPosterCard: View { init(group: SeriesGroup<Drama>, action: @escaping () -> Void) }`: the
    lowest part's poster, a "共 N 部" badge top-right (redfruit episode-count badge style), the title
    `group.base`, and the subtitle `partsLabel`.
  - `DetailView(drama:series:)` gains an optional `series: SeriesGroup<Drama>?` parameter (default nil),
    used by Task 11.

- [ ] **Step 1:** Run results through `SeriesGrouping.group(results, title: \.title, source: \.source)`.
  - Render `.single` as today and `.series` as `SeriesPosterCard`.
  - Selecting a series pushes `DetailView(drama: target, series: group)`, where `target` is the part with
    the newest `store.latestProgress`, otherwise the lowest part.
  - Play/Pause on a series card calls `launcher.play(target, store:)`.
- [ ] **Step 2:** Build check.
- [ ] **Step 3:** Commit: `feat: group a series' parts in search results`.

### Task 11: 本系列 row and 观看下一部 on Detail

**Files:**
- Create: `tvos/GuoAppTV/GuoAppTV/Core/SeriesLookup.swift` (app-side, needs `CoreClient`)
- Create: `tvos/GuoAppTV/GuoAppTV/Views/SeriesShelf.swift`
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/DetailView.swift`
- Modify: `project.pbxproj`

**Interfaces:**
- Consumes: `SeriesTitle`, `SeriesGrouping` (Task 9), `WatchStatus` (Task 2), `DetailView(drama:series:)` (Task 10).
- Produces:
  - `actor SeriesLookup { static let shared; func parts(of drama: Drama) async -> SeriesGroup<Drama>? }`
    - The key comes from `SeriesTitle.parse(drama.title)`, or `normalize(title) + ":部"` and `":季"` for an
      unsuffixed title.
    - It runs `CoreClient.shared.catalog(source: drama.source, query: base)` once per key and caches the
      result (nil included) for the session.
    - It returns the group that contains `drama.id`, if there is one.
  - `struct SeriesShelf: View { init(group: SeriesGroup<Drama>, currentID: String, onSelect: @escaping (Drama) -> Void) }`
    - A "本系列 · 共 N 部" header (`TextSize.headline`), then 160×240 posters 32 apart.
    - Each poster has the caption `"第X部 · M 集"` plus `WatchStatus(...).posterCaption`, and a badge
      当前 (accent) or 下一部 (surfaceBright).

- [ ] **Step 1:** Implement `SeriesLookup`.
- [ ] **Step 2:** Implement `SeriesShelf`.
- [ ] **Step 3:** In `DetailView`:
  - Use the passed `series`, otherwise `await SeriesLookup.shared.parts(of:)` after the detail loads.
  - Show `SeriesShelf` below `EpisodeNumberGrid`. Selecting a part pushes that part's `DetailView`,
    passing the same `series`.
  - Primary action: when `WatchStatus` for the current part `isFinished` and a next part exists, the title
    becomes `"观看下一部"` and the action opens the next part through `PlaybackLauncher`.
- [ ] **Step 4:** Build check.
- [ ] **Step 5:** Commit: `feat: 本系列 row and 观看下一部 on the detail page`.

### Task 12: 继续观看 one card per series

**Files:**
- Modify: `tvos/GuoAppTV/GuoAppTV/Views/MyListView.swift`, `ContinueWatchingCard.swift`

**Interfaces:**
- Consumes: `SeriesGrouping` (Task 9), `ContinueWatchingCard` (Task 6).

- [ ] **Step 1:** Group `store.recentHistory` by `SeriesGrouping`, keeping only the newest part per series
  (history is already newest first, so the first part seen per key wins).
  - For a series part, the card caption becomes `"第X部 · " + cardCaption`; `ContinueWatchingCard` gains
    `partLabel: String?`.
  - 从观看记录中移除 removes only that part's history.
- [ ] **Step 2:** Build check and run the logic tests.
- [ ] **Step 3:** Commit: `feat: one 继续观看 card per series`.

### Task 13: Docs, device deploy and owner check

**Files:**
- Modify: `README.md` (功能 remote notes), `CHANGELOG.md` (`## 未发布`)

- [ ] **Step 1:** README: replace the outdated remote notes (首页 Play/Pause refresh; 最近观看 Play/Pause
  delete) with the new behaviour. CHANGELOG: one `## 未发布` bullet summarising phase 1.
- [ ] **Step 2:** Deploy with `python3 scripts/deploy_tvos.py`. Expected: "完成。", and the app running
  on Bureau.
- [ ] **Step 3:** Owner checks on the TV, covering Review Focus 4 and 5:
  - 剧场 Play/Pause on a poster plays it.
  - 追剧 card click resumes at the saved second; long-press menus work.
  - Detail ranges and the cell states are right.
  - The in-player 选集 opens on the current episode.
  - 清除观看记录 clears 继续观看 but keeps 我的追剧.
  - Searching a title with several parts shows one series card; Detail shows 本系列; 继续观看 shows one card per
    series.
- [ ] **Step 4:** Commit and push `feature/polish`: `docs: phase 1 watching ergonomics notes`.
