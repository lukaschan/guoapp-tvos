# guoapp-tvos: redfruit layout and watching ergonomics

Status: approved by owner 2026-11-08 · branch `feature/polish`

## Intent

The owner had an earlier tvOS short-drama app, **redfruit** (`~/Project/src/redFruit`), whose layout and
ergonomics they liked. guoapp-tvos already has a stronger content and playback layer: multiple sources,
rankings, decrypting mpv playback, and native-style player controls. It still uses a plain poster-grid
layout, though. The goal is to **take redfruit's design for the whole app and keep every guoapp-tvos
feature that redfruit doesn't have.** Watching ergonomics come first: getting back into what you're
watching quickly, and finding episodes quickly.

The redfruit colours, type scale and focus treatment are already in (`657cc2f`, `TVTheme`). This document
covers layout, screens and behaviour.

## Goals

1. redfruit's tab structure and screens: **推荐 · 剧场 · 追剧 · 搜索 · 我的**.
2. Continue watching is one press away, from 追剧 and from a poster's Play/Pause, and resumes at the exact
   episode and second.
3. Faster episode finding: a ranged number grid (1–30, 31–60…) on the detail page and in the player.
4. A 推荐 hero home with live vertical video, as in redfruit.
5. First-class loading, empty and error states: skeletons, short Chinese messages, 重试.

## Non-goals and anti-goals

- **Don't touch playback logic or caching.** The hero and the player reuse `PlayerController` / mpv as they
  are, with the same resolve, prefetch and caching paths. Adding call sites is fine; changing
  `PlayerController` internals is not, apart from small additive hooks that don't change behaviour.
- **Don't change the Go core (`upstream/`).** Use only existing core actions.
- Out of scope: redfruit's QR handoff to the phone app (guoapp plays every episode), its swipe-up/down
  next-episode mapping (the owner chose ↑↓ = show controls), the ambient *video* backdrop inside the
  full-screen player, the Top Shelf extension, and "更新" badges for followed dramas.
- **Anti-goal:** losing any guoapp-tvos feature during the port (list below). A layout that looks like
  redfruit but drops sources, rankings, danmaku or quality settings is a failure.

## Constraints

- tvOS 16 deployment target, Swift 6 language mode, no new dependencies. Keep the `UITabBarController`
  keep-alive shell (`KeepAliveTabView`); don't switch to SwiftUI `TabView`, which tears down tabs.
- tvOS HIG: safe area 80 sides / 60 top-bottom, body ≥ 29 pt, and spacing that absorbs focus growth.
- Use the existing `TVTheme` tokens and components. Port redfruit components rather than reinventing them.
- Source files stay under about 800 lines. Add new files to `project.pbxproj` (explicit file references).
- Deploy each phase to the owner's Apple TV with `scripts/deploy_tvos.py` for feedback before the next.

## Keep list: guoapp-tvos features redfruit doesn't have (all must survive)

- **Sources:** source switching (红果 / 河马 / 星芽 / 黄豆… on all-sources builds), the source chip row, and
  the source picker in settings.
- **Rankings:** ranking boards (热播榜…) with rank badges; categories; infinite-scroll catalog pages.
- **Search:** the custom search field with live suggestions (300 ms debounce, 8 rows).
- **Settings:** 弹幕, 播完自动连播, 清晰度 (自动 / 1080 / 720 / 480), 播放倍速, 播放诊断, version, notes.
- **Detail:** heat, release status and episode-count pills; VIP episodes; per-episode partial progress.
- **Player:** native-style controls (progress, 倍速, 画面 Fit / Fill / Stretch, 选集), next-episode prefetch,
  auto-advance, instant speed change.
- **History:** removing a drama's history (it moves from Play/Pause to a long-press menu; see 追剧).
- ~~**Refresh:** refreshing the catalog~~. **Dropped for now by the owner (2026-11-08).** Play/Pause on a
  poster plays it instead (see 剧场).

## Screens

Unless a section says otherwise, take sizes, fonts, strings and behaviour from the redfruit files named
there.

### Shell
- Tabs: 推荐 (default), 剧场, 追剧, 搜索, 我的. `HistoryView` and `FollowingView` merge into 追剧;
  `SettingsView` becomes 我的.
- Launch screen: show the build's display name (红果鉴 / 真果鉴, from `CFBundleDisplayName`) instead of the
  hard-coded "红果鉴".

### 追剧 (phase 1). redfruit: `Features/MyList/MyListScreen.swift`, `ContinueWatchingCard.swift`
- **继续观看 shelf:** one card per drama from `store.recentHistory`, newest first, 500 wide. Each card has a
  140×210 poster, the title, "看到第 N 集 / 共 M 集" and a whole-series progress bar
  (`(N−1 + fraction) / M`).
  - Selecting a card or pressing Play/Pause opens `PlayerView` directly, at the saved episode and position.
    The player needs the episode list, so the card first fetches `detail` (show a small inline loading state
    on the card, and an error alert on failure).
  - Long-press menu: 查看详情 / 从观看记录中移除. 移除 calls `store.deleteHistory`. This replaces the
    Play/Pause delete dialog.
  - M is `drama.episodes` when it's above 0, otherwise the detail episode count once it's known. Hide
    "/ 共 M 集" while unknown. When the last episode is ≥ 99 % watched, show "已看完".
- **我的追剧 shelf:** poster cards showing "看到第 N 集 · 共 M 集", "未开始 · 共 M 集" or
  "已看完 · 共 M 集". Selecting one opens Detail. Long-press offers 取消追剧.
- **Empty state:** 还没有追剧 / 在详情页按「追剧」，或看过的短剧，都会出现在这里.

### Detail (phase 1). redfruit: `Features/Detail/DetailHeader.swift`, `DetailPrimaryAction.swift`, `EpisodeGrid.swift`, `EpisodeRanges.swift`
- **Header:** the redfruit layout (poster left; title, tags and status, synopsis right). Keep guoapp's pills:
  category, 已完结 / 连载中, 共 N 集, 热度.
- **Primary action:** "继续观看 第 N 集" (resumes at the saved second) or "立即观看". Keep 追剧 / 已追剧.
- **选集:** range chips of 30 above a 15-column grid of episode numbers.
  - Cell states: watched (dim), current (accent), unwatched, focused (white).
  - Keep VIP as a small corner tag, like redfruit's lock tag. Keep per-episode partial progress as a thin
    bar along the bottom of the cell.
  - The chip opens on the range containing the current episode. Selecting a cell plays from 0, as today.
- **In the player:** `PlayerEpisodeSheet` uses the same ranged grid component. It opens on the current
  episode's range and focuses that episode.

### 我的 (phase 1). redfruit: `Features/Settings/SettingsScreen.swift`
- **Layout:** two columns. Left: an app icon tile with the display name and "在电视上追短剧". Right: grouped
  rows.
- **Rows:** keep every existing settings row (站源, 播放, 关于). Add **清除观看记录**: a confirm dialog
  "清除全部观看记录？" / "「继续观看」会被清空，追剧列表不受影响。", then clear all progress, keeping follows.
- **About notes:** remove the stale ones (↑↓ changes speed; Play/Pause deletes in 最近观看) and describe the
  current remote mapping.

### 系列: grouping a drama's parts (phase 1; owner request 2026-11-08, design delegated to the builder)
- **Rule** (mirrors the core, `upstream/native/core/provider_hongguo_search_seasons.go` and `hongguoSearchText`):
  - A title ending in `第N部` or `第N季` belongs to series `base`. N is Arabic or Chinese numerals (零〇一二两兩三…十百),
    1–200, optionally followed by punctuation or spaces.
  - The group key is `normalize(base) + ":" + unit`, where normalize is NFKC, lower-case, spaces and
    punctuation removed. So 部 and 季 are different series.
  - A title whose normalised form equals the key is part 1.
  - Only dramas from the same source are grouped.
- **搜索:** one card per series group of 2 or more parts.
  - The card has the lowest part's poster, the title `base`, a badge "共 N 部" (or "共 N 季"), and the
    subtitle "第 1–N 部" (the actual part numbers when not contiguous, e.g. "第 1、3 部").
  - Selecting it opens the most recently watched part, otherwise the lowest part. Play/Pause resumes it.
- **Detail, 本系列 row** (directly below the 选集 grid):
  - One card per part: the poster, "第二部 · 80 集" and the poster caption from `WatchStatus`.
  - Tags: 当前 on the part being viewed, 下一部 on the following part.
  - Selecting a card opens that part's detail.
  - Hidden when the drama has no other parts.
- **Detail, primary action:** "观看下一部" when the current part is 已看完 and a next part exists.
- **Finding the parts:** when Detail isn't handed the series by Search, it runs one background
  `catalog(source:, query: base)` (the core completes missing parts). Results are cached in memory per group
  key for the app session.
- **继续观看:** one card per series, for the most recently watched part. Its caption is prefixed with the
  part, e.g. "第二部 · 看到第 5 集 / 共 80 集".
- **Out of scope:** auto-continuing into the next part at the end of the last episode (phase 2, with the
  shared player logic), and grouping in 剧场 rankings, which stay one entry per part.

### 剧场 (phase 2). redfruit: `Features/Theater/`
- Today's 首页 becomes 剧场, restyled the redfruit way.
  - **Chip row(s):** the source chips (all-sources builds) and the board / category chips, as today.
  - **Featured banner "今日主推":** the first item of the current list. It has 立即观看 and 详情 buttons, and
    the blurred enlarged poster on the right.
  - **Poster grid:** 200×300 posters, with the episode-count badge top-right and the rank badge top-left
    (ranking mode). Infinite scroll as today.
  - **Loading:** dim to 50 % plus a spinner under the chips while a new chip's page loads.
- **Play/Pause on a focused poster:** plays it immediately in `PlayerView`, at the saved episode and second
  if there is one, otherwise episode 1. Like 继续观看, it fetches `detail` first. (Owner decision
  2026-11-08; the old Play/Pause-to-refresh is removed.)

### 推荐 hero (phase 2). redfruit: `Features/Feed/` (FeedHeroScreen, HeroVideo, HeroInfoPanel, UpNextRow)
- **Feed source:** the core's `recommendations` action (红果 推荐 feed: `{action: "recommendations",
  category: <feed key>, command: "more"?}` → catalog result; feed keys are in
  `upstream/native/core/provider_hongguo_recommendations.go`). For a non-红果 source, use that source's
  first catalog page.
- **Layout:** as redfruit.
  - Info column on the left: badge, tags and status, title, synopsis, "正在播放 第 N 集" with a progress bar
    and "MM:SS 后自动播放下一集", then the buttons 全屏观看 / 追剧 / 选集.
  - Video on the right: a 608×1080 panel for vertical video, 1060×596 for landscape, with edges feathered
    over 140 pt.
  - The **接下来** row peeks from the bottom: the next 10 dramas, 160×240 posters. Rest on one for 1 s to
    preview it in the hero; click to commit.
- **Video:** a second `PlayerController` instance hosted in the hero panel. Episode logic comes from the
  shared type extracted from `PlayerView` (see Owner decisions); the only hero-specific addition is the
  30 s save gate.
  - Audio plays, as in redfruit.
  - Pause when leaving the tab, opening Detail or opening the full-screen player.
  - Starts at the drama's saved episode and second, otherwise episode 1. The episode advances when it ends,
    and the last episode moves on to the next drama.
- **Ambient backdrop:** redfruit uses a blurred second video layer. mpv has a single render layer, so use
  the **blurred enlarged cover image** plus a dim and a left-side scrim (the builder's call).
- **全屏观看:** stop the hero's player and open `PlayerView` at the hero's current episode and position.
  That costs one extra resolve, which is accepted for simplicity.
- Play/Pause anywhere on the hero toggles the hero video.
- When 推荐 comes back into view, the hero reloads the drama's resume point from the store instead of
  resuming its paused player, so progress made in the full-screen player is never rolled back.
  *(Builder's call.)*
- `PlayerController` has no plain `pause()` / `play()` and doesn't expose the video size. Small additive
  hooks for these are allowed (see Non-goals).

### 搜索 (phase 3). redfruit: `Features/Search/`
- Keep guoapp's custom field and suggestions.
- Before any search, show a "大家都在看" poster grid (the first 14 of the 推荐 feed).
- Results: "找到 N 部短剧" above a poster grid with episode-count badges. Play/Pause on a poster plays it, the same as 剧场.

### Loading, empty and error states (phase 3). redfruit: `DesignSystem/Components/Skeleton.swift`, `StatusViews.swift`
- A skeleton per screen (推荐, 剧场, 搜索, 追剧), shaped like the real layout, with a 1.4 s shimmer that stops
  when Reduce Motion is on.
- Failure view: "出了点问题" with a short message and 重试. Map network errors to
  "网络连接失败，请检查网络后重试".

## Phases (deploy and get owner feedback after each)

1. **Watching ergonomics:** shell tabs (推荐 can be a placeholder that shows 剧场's content until phase 2),
   追剧, Detail with the ranged 选集 grid, the in-player picker, and 我的.
2. **剧场 and the 推荐 hero.**
3. **Search refresh, skeletons and error states, plus image downsampling and prefetch-on-focus.**
   Prefetch-on-focus covers **posters and detail only**, with no stream warming. A `resolve` per focused
   poster would open playback sessions and change the playback paths. *(Builder's call.)*

## Owner decisions

- 2026-11-08: Play/Pause on a focused poster (剧场 / 搜索) **plays it**. The catalog refresh is not needed
  for now.
- 2026-11-08: the 推荐 hero saves watch progress **only after 30 s of actual watching** in the hero, so
  autoplay on launch and 1 s previews never land in 继续观看.
- 2026-11-08: the episode logic now inside `PlayerView` (resolve, prefetched-plan reuse, next-episode
  prefetch, auto-advance, fallback, progress saving, session release) may be **moved into one shared type**
  used by both the full-screen player and the hero (phase 2). Behaviour stays unchanged and is verified on
  the device. This is the one sanctioned exception to "don't touch playback logic"; mpv, `PlayerController`
  internals and caching stay as they are.

- 2026-11-08: a fully watched drama with no next part shows **重新观看** and starts again from episode 1
  (instead of resuming the last second).

## Builder's calls already made

- `CoreClient` keeps its single serial queue in phase 2. If hero previews feel slow on the device, revisit
  it with the owner then.
- Prefetch-on-focus covers posters and detail only (phase 3).
- The hero reloads its resume point from the store on reappear.

## Left to the builder

Exact component structure and file split; how the hero hosts its `PlayerController`; the ambient-backdrop
technique; skeleton geometry beyond redfruit's; the feed key used for 推荐; error copy beyond the strings
above.
