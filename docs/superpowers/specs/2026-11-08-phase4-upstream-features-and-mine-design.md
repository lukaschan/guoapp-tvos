# Phase 4: upstream core features, instant start and 我的 — Design

Follows `2026-11-08-redfruit-layout-design.md` (phases 1–3, shipped on `feature/polish`). Same app and constraints.

## Intent

The Go core (`upstream/native/core`) already implements things the upstream Flutter app uses and our tvOS app doesn't:
- cached content for an instant start;
- background update checks for followed dramas;
- fuller drama metadata;
- cancellable, concurrent reads.

Phase 4 adopts them so the app:
- opens with content on screen immediately instead of a skeleton;
- tells you when a drama you follow has new episodes;
- shows fuller drama info;
- loads posters and search results faster.

It also turns 我的 into a profile dashboard.

## Owner decisions (2026-11-08)

- Adopt four core features:
  - `followCheck` (追剧更新)
  - `metadata` (fuller info)
  - `cached` instant start, including 推荐 through `cachedRecommendations`
  - parallel + cancellable requests
- 我的 uses **layout A** (profile dashboard), from the 2026-11-08 mockup.
- The player's 画面 option (适应 / 填充 / 拉伸) is **removed** (done in `6940ef4`). 我的 has no default-screen-mode setting.
- Not adopted:
  - downloads / local playback, device registration UI, update check, usage reporting, proxy settings;
  - `preload`, because the app already prefetches the next episode;
  - `storage`, because it only measures the downloads folder;
  - Top Shelf (dropped earlier: it needs App Groups).

## Measured facts (live 红果 data, Mac harness)

- `cachedRecommendations` returns the saved 推荐 feed (20 dramas) in about 0 ms.
- A forced fresh feed: the first page takes 3.6 s with only 2 dramas. Two more pages take 7.4 s more, reaching 12.
- The core's 红果 ranking boards are cached only in memory (`rankingCacheTTL`), so after launch they need the network. `cached` covers category catalogs, not ranking boards.
- A newer playback request cancels the in-flight one (`nativeBeginPlayback`). Today this never fires because requests are serial.
- Read sessions:
  - A request with a `session` key and a higher `sequence` cancels the in-flight read with the same key.
  - Supported for `catalog`, `categories`, `suggestions`, `recommendations` and `metadata`.
  - At most 16 reads run at once.
  - `cancelRead` cancels a read explicitly.
- `followCheck(drama)` is a background detail fetch (20 s timeout) that returns the drama with its current episode count.
- `metadata(drama)` returns the drama with score, release date and heat filled in, and saves them in the core.

## Design

### 1. Requests to the core: two lanes
- **Playback lane:** `initialize`, `resolve`, `fallback`, `release`, `cancelPlayback`.
  - Serial, exactly as today, so no playback request can cancel another.
- **Read lane:** everything else (covers, catalog, rankings, detail, search, suggestions, recommendations, metadata, followCheck, danmaku).
  - Up to 4 requests at once.
- **Read sessions** come from one increasing counter in `CoreClient`:
  - `search` (catalog with a query) and `suggestions`: each new keystroke cancels the previous one in the core.
  - `feed-<key>` for 推荐 recommendations.
  - A cancelled read surfaces as a cancellation, never as 出了点问题.
- `CoreClient`'s in-memory caches are unchanged.
- The playback paths and `PlaybackSession` logic are unchanged.

### 2. 推荐 opens instantly
- At launch, show `cachedRecommendations` straight away, then fetch a fresh feed in the background (forced first page, then `more`).
- The hero starts on the first cached drama. Its cover and info show immediately; the video follows its own detail and resolve.
- When fresh dramas arrive:
  - Keep what's already shown, up to and including the current hero.
  - Replace the rest of the list with the fresh dramas, de-duplicated.
  - Playback is never interrupted, and 接下来 becomes the fresh feed. While the row has focus it keeps its frozen set (existing rule).
- Then keep paging with `more` (existing `FeedPaging`).
- With no cache (first ever launch), the current path is unchanged: skeleton, then the first page.
- 搜索's 大家都在看 also starts from the cached feed (first 14).

### 3. 剧场 opens instantly
- **Category view:** show `cached` for the source and category immediately, then refresh.
- **Ranking view** (红果's default): the app saves page 1 of each board it shows, as JSON in Caches, and shows it at launch while the fresh page loads.
- In both views, a refresh replaces the grid in place and keeps focus on the same drama if it's still there. No dim and no spinner for this background refresh.

### 4. 追剧更新
- **Per followed drama** the app stores:
  - `knownEpisodes`: the count the user has acknowledged.
  - `latestEpisodes`: from the last check.
  - `checkedAt`
  - These are optional fields, so existing saved data still loads.
- **Has an update** when `latestEpisodes > knownEpisodes`.
  - If `knownEpisodes` is unknown (for example 0 from a ranking item), the first check only sets the baseline and shows no badge.
- **Checking:**
  - after launch, once 推荐 has loaded;
  - one drama at a time, on the read lane;
  - skipping dramas checked within the last 6 hours.
  - 我的 → 检查追剧更新 checks all of them now.
- **Shown as:**
  - "更新至 N 集" on 我的追剧 posters and on 继续观看 cards for that drama;
  - "N 部有更新" in 我的.
- **Acknowledged** (badge cleared) when the user opens that drama's detail page or plays it: `knownEpisodes = latestEpisodes`.

### 5. Fuller drama info (`metadata`)
- Upstream's rule: on the detail page, for a 红果 drama missing its score or release date, call `metadata` once and merge what comes back.
- `Drama` gains `score`.
- The detail header line adds 评分 N, YYYY-MM 上线 and 热度 when known.

### 6. 我的 — layout A
- **Header:** the app icon tile, 火龙果短剧, and "在电视上追短剧 · 版本 X · 核心 <short commit>". The build passes the upstream submodule's short commit into Info.plist.
- **Four stat tiles**, computed from the local store:
  - 在追: the number of follows.
  - 看过的剧: distinct dramas with any progress.
  - 看完的集: episodes watched to at least 90 %.
  - 累计观看: the sum of saved positions, in hours with one decimal.
- **Groups, in two columns:**
  - 播放: 播完自动连播下一集, 清晰度 · 倍速, 弹幕, 播放诊断.
  - 推荐: 进入推荐页自动播放. When off, the hero shows the cover and info but doesn't play; the 暂停 button reads 播放, and it or Play/Pause starts it.
  - 追剧: 检查追剧更新 (shows "N 部有更新" or "刚刚检查"), 清除观看记录.
  - 存储与关于: 已用空间 (the size of the app's Caches folder, computed in the background), 站源, 关于.

## Constraints and non-goals

- No change to the Go core.
- No change to `PlaybackSession` playback logic, `PlayerController` internals, resolve paths or `CoreClient` caching.
- The lane split above is the sanctioned exception for request dispatch.
- Swift 6, tvOS 16, 0 warnings, Logic tests on the Mac.
- Deploy only on the owner's signal. Don't push while PR #1 is open, unless the owner says so.

## Left to the builder

- File split and type names.
- How the lane limit is enforced.
- The ranking-cache file format.
- The exact stat-tile styling: follow the mockup.
- Copy beyond the strings above.
