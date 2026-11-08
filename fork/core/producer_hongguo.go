package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// 红果出品方片单：按出品方名搜多页，只保留 copyright 与之精确相等的剧
// （copyright 由 hongguoDramaFromAny 解析到 Drama.Producer），再用网页
// 详情补上线日期（搜索载荷没有日期字段），供界面按最新/最热排序。
const (
	hongguoProducerMaxPages    = 6
	hongguoProducerEnrichLimit = 40
)

func (engine *nativeEngine) nativeProducerDramas(ctx context.Context, producer string) (any, error) {
	producer = strings.TrimSpace(producer)
	if producer == "" {
		return nil, errors.New("出品方为空")
	}
	dramas, err := engine.downloader.hongguoProducerDramas(ctx, producer)
	if err != nil {
		return nil, err
	}
	items := make([]nativeDrama, 0, len(dramas))
	for _, drama := range dramas {
		items = append(items, nativeNormalize(drama))
	}
	return map[string]any{"items": items}, nil
}

func (engine *nativeEngine) nativeProducerWorks(ctx context.Context, drama nativeDrama) (any, error) {
	source, _, valid := splitProviderDramaID(drama.ID)
	if !valid || source != sourceHongguo {
		return nil, errors.New("仅红果剧集有出品方信息")
	}
	name := strings.TrimSpace(drama.Producer)
	if name == "" {
		name = engine.downloader.hongguoSearchProducer(ctx, drama.ID, drama.Title)
	}
	if name == "" {
		return map[string]any{"producer": "", "items": []nativeDrama{}}, nil
	}
	dramas, err := engine.downloader.hongguoProducerDramas(ctx, name)
	if err != nil {
		return nil, err
	}
	items := make([]nativeDrama, 0, len(dramas))
	for _, item := range dramas {
		items = append(items, nativeNormalize(item))
	}
	return map[string]any{"producer": name, "items": items}, nil
}

func (downloader *Downloader) hongguoProducerDramas(ctx context.Context, producer string) ([]Drama, error) {
	seen := map[string]bool{}
	dramas := []Drama{}
	for page := 1; page <= hongguoProducerMaxPages; page++ {
		items, hasMore, err := downloader.fetchHongguoProducerPage(ctx, producer, page)
		if err != nil {
			if page == 1 {
				return nil, err
			}
			break
		}
		for _, drama := range items {
			if !seen[drama.ID] {
				seen[drama.ID] = true
				dramas = append(dramas, drama)
			}
		}
		if !hasMore {
			break
		}
	}
	enrichCtx, enrichCancel := context.WithTimeout(ctx, 25*time.Second)
	downloader.enrichHongguoProducerDates(enrichCtx, dramas)
	enrichCancel()
	for i := range dramas {
		if dramas[i].Heat == "" {
			dramas[i].Heat = dramas[i].Views
		}
	}
	return dramas, nil
}

func (downloader *Downloader) fetchHongguoProducerPage(ctx context.Context, producer string, pageNum int) ([]Drama, bool, error) {
	client := downloader.hongguoClient()
	offset := strconv.Itoa((pageNum - 1) * hongguoSearchPageSize)
	query := url.Values{"query": {producer}, "offset": {offset}, "count": {strconv.Itoa(hongguoSearchPageSize)}, "tab_type": {hongguoSearchSeriesTab}}
	if pageNum > 1 {
		query.Set("passback", offset)
		client.mu.Lock()
		searchID := client.searchIDs[producer]
		client.mu.Unlock()
		if searchID != "" {
			query.Set("search_id", searchID)
		}
	}
	result, err := downloader.hongguoAppRequest(ctx, http.MethodGet, hongguoSearchTabPath, query, nil)
	if err != nil {
		return nil, false, err
	}
	var tab map[string]any
	for _, item := range anyList(result["search_tabs"]) {
		if candidate, _ := item.(map[string]any); mapString(candidate, "tab_type") == hongguoSearchSeriesTab {
			tab = candidate
		}
	}
	if tab == nil {
		return nil, false, errors.New("红果搜索未返回有效结果")
	}
	if searchID := mapString(tab, "search_id"); pageNum == 1 && searchID != "" {
		client.mu.Lock()
		if len(client.searchIDs) >= 64 {
			client.searchIDs = map[string]string{}
		}
		client.searchIDs[producer] = searchID
		client.mu.Unlock()
	}
	dramas := []Drama{}
	seen := map[string]bool{}
	for _, cell := range anyList(tab["data"]) {
		row, _ := cell.(map[string]any)
		for _, video := range anyList(row["video_data"]) {
			item, _ := video.(map[string]any)
			if strings.TrimSpace(mapString(item, "copyright")) != producer {
				continue
			}
			drama := hongguoDramaFromAny(map[string]any{"video_data": video}, "短剧")
			if drama.ID != "" && !seen[drama.ID] {
				seen[drama.ID] = true
				dramas = append(dramas, drama)
			}
		}
	}
	return dramas, tab["has_more"] == true, nil
}

func (downloader *Downloader) enrichHongguoProducerDates(ctx context.Context, dramas []Drama) {
	indexes := []int{}
	for i := range dramas {
		if dramas[i].OnlineDate == "" && dramas[i].SourceID != "" {
			indexes = append(indexes, i)
		}
	}
	if len(indexes) > hongguoProducerEnrichLimit {
		indexes = indexes[:hongguoProducerEnrichLimit]
	}
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	for _, idx := range indexes {
		idx := idx
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				return
			}
			itemCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
			defer cancel()
			body, err := downloader.fetchProviderText(itemCtx, hongguoBaseURL+"/detail?series_id="+url.QueryEscape(dramas[idx].SourceID), hongguoBaseURL+"/")
			if err != nil {
				return
			}
			page := routerLoaderMap(parseRouterData(body), "detail_page", "detail_")
			detail, _ := page["seriesDetail"].(map[string]any)
			if date := providerTimestampDate(mapString(detail, "first_visible_time")); date != "" {
				dramas[idx].OnlineDate = date
			}
		}()
	}
	wg.Wait()
}

// hongguoSearchProducer 按剧名走一次搜索、用剧 ID 精确命中，取该剧的
// 出品方。详情与首页推荐载荷都没有 copyright，只能这样补；搜索结果有
// 5 分钟缓存，重复打开不重复请求。查不到返回空，不影响详情主流程。
func (downloader *Downloader) hongguoSearchProducer(ctx context.Context, dramaID, title string) string {
	if strings.TrimSpace(title) == "" {
		return ""
	}
	lookupCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	entry, err := downloader.searchHongguoDramas(lookupCtx, title)
	if err != nil {
		return ""
	}
	for _, item := range entry.Dramas {
		if item.ID == dramaID {
			return item.Producer
		}
	}
	return ""
}
