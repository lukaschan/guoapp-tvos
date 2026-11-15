package core

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

func TestHuangguoAICategoriesExcludeOffline(t *testing.T) {
	for _, entry := range nativeAICategories {
		if entry.ID == "ai-huanlian" || entry.ID == "ai-mogai" {
			t.Fatalf("offline category %s is still listed", entry.ID)
		}
	}
	if len(nativeAICategories) == 0 {
		t.Fatal("no huangguoai categories remain")
	}
}

func TestParseHuangguoPublish(t *testing.T) {
	js := "var subdomains = ['thu', 'pku', 'fdu'];\n" +
		"var urls = ['ixgukkejj.cc/', 'bmikbxhi.cc/'];\n" +
		"var newestUrls = [];\n"
	hosts := parseHuangguoPublish(js)
	if len(hosts) != 6 {
		t.Fatalf("expected 6 host combinations, got %v", hosts)
	}
	seen := map[string]bool{}
	for _, host := range hosts {
		seen[host] = true
	}
	for _, want := range []string{"https://thu.ixgukkejj.cc", "https://thu.bmikbxhi.cc", "https://pku.ixgukkejj.cc", "https://fdu.bmikbxhi.cc"} {
		if !seen[want] {
			t.Fatalf("missing published host %s in %v", want, hosts)
		}
	}
	if hosts := parseHuangguoPublish("var urls = [];"); len(hosts) != 0 {
		t.Fatalf("empty publish data must yield no hosts, got %v", hosts)
	}
	if hosts := parseHuangguoPublish("var urls = ['not a host', 'ok.example.cc/'];"); len(hosts) != 1 || hosts[0] != "https://ok.example.cc" {
		t.Fatalf("invalid publish entries must be filtered, got %v", hosts)
	}
}

func TestHuangguoDiscoveredHostRecognition(t *testing.T) {
	huangguoDiscoverMu.Lock()
	saved, savedNext := huangguoDiscovered, huangguoDiscoverNext
	huangguoDiscovered = []string{"https://thu.ixgukkejj.cc"}
	huangguoDiscoverMu.Unlock()
	defer func() {
		huangguoDiscoverMu.Lock()
		huangguoDiscovered, huangguoDiscoverNext = saved, savedNext
		huangguoDiscoverMu.Unlock()
	}()
	if !isHuangguoAIMirrorHost("thu.ixgukkejj.cc") {
		t.Fatal("discovered host was not recognized as a huangguoai mirror")
	}
	if providerSourceForURL("https://zju.ixgukkejj.cc/api/edge/request") != sourceHuangguoAI {
		t.Fatal("host under a discovered root domain was not recognized as huangguoai")
	}
}

// 实测探针（默认跳过）：GUOAPP_HUANGGUO_LIVE=1 go test ./core/ -run TestHuangguoLiveProbe -v
// 走真实引擎路径验证分类列表、分类目录、详情与播放解析。
func TestHuangguoLiveProbe(t *testing.T) {
	if os.Getenv("GUOAPP_HUANGGUO_LIVE") != "1" {
		t.Skip("set GUOAPP_HUANGGUO_LIVE=1 to run the live huangguo probe")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	categories, err := engine.nativeCategories(ctx, sourceHuangguoAI, true)
	if err != nil {
		t.Fatalf("categories: %v", err)
	}
	for _, entry := range categories {
		if entry.ID == "ai-huanlian" || entry.ID == "ai-mogai" {
			t.Fatalf("offline category %s is still served", entry.ID)
		}
	}
	t.Logf("categories: %v", categories)

	all, err := engine.nativeCatalog(ctx, nativeInput{Source: sourceHuangguoAI, Page: 1})
	if err != nil {
		t.Fatalf("catalog(all): %v", err)
	}
	if len(all.Items) == 0 {
		t.Fatal("catalog(all) returned no items")
	}
	t.Logf("catalog(all): %d items, first: %s %s", len(all.Items), all.Items[0].ID, all.Items[0].Title)

	ai, err := engine.nativeCatalog(ctx, nativeInput{Source: sourceHuangguoAI, Page: 1, Category: "ai-duanju"})
	if err != nil {
		t.Fatalf("catalog(ai-duanju): %v", err)
	}
	if len(ai.Items) == 0 {
		t.Fatal("catalog(ai-duanju) returned no items")
	}
	t.Logf("catalog(ai-duanju): %d items", len(ai.Items))

	sourceID := all.Items[0].SourceID
	if sourceID == "" {
		_, sourceID, _ = splitProviderDramaID(all.Items[0].ID)
	}
	drama, chapters, err := engine.downloader.fetchHuangguoAIDetail(ctx, sourceID)
	if err != nil {
		t.Fatalf("detail(%s): %v", sourceID, err)
	}
	t.Logf("detail: %s %s, %d chapters", drama.ID, drama.DisplayTitle(), len(chapters))

	playURL, err := engine.downloader.fetchHuangguoAIPlayURL(ctx, sourceID, 1)
	if err != nil {
		t.Fatalf("play(%s): %v", sourceID, err)
	}
	if playURL == "" || !strings.Contains(playURL, ".m3u8") && !strings.Contains(playURL, ".mp4") {
		t.Fatalf("play(%s) returned an unusable URL: %q", sourceID, playURL)
	}
	t.Logf("play url: %s", playURL)
}
