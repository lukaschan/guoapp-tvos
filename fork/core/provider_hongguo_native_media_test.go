package core

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newHongguoRequestTestDownloader(server *httptest.Server) *Downloader {
	return &Downloader{
		cfg:           Config{Retries: 1},
		client:        server.Client(),
		limiter:       newRequestLimiter(1, 0),
		providerHosts: map[string]string{},
	}
}

func TestHongguoPlaybackUsesV5SignedMultiVideoModel(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/novel/player/multi_video_model/player/v1" {
			t.Errorf("unexpected playback request: %s %s", r.Method, r.URL.Path)
		}
		for _, name := range []string{"X-Khronos", "X-Helios", "X-Medusa", "X-SS-STUB"} {
			if value := r.Header.Get(name); value == "" {
				t.Errorf("playback request is missing V5 header %s", name)
			}
		}
		for _, name := range []string{"X-Gorgon", "X-Argus", "X-Ladon"} {
			if value := r.Header.Get(name); value != "" {
				t.Errorf("playback request unexpectedly includes legacy header %s", name)
			}
		}
		if ua := r.Header.Get("User-Agent"); !strings.HasPrefix(ua, "com.phoenix.read/73932") {
			t.Errorf("unexpected playback user agent: %s", ua)
		}
		query := r.URL.Query()
		if query.Get("device_id") == "" || query.Get("iid") == "" || query.Get("version_code") != "74332" {
			t.Errorf("playback query lost its device identity: %s", r.URL.RawQuery)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		biz, _ := payload["biz_param"].(map[string]any)
		if biz["device_level"] != float64(1) || biz["video_platform"] != float64(1024) {
			t.Errorf("unexpected biz_param: %v", payload["biz_param"])
		}
		ids, _ := payload["mixed_video_id_map"].(map[string]any)
		if got, _ := ids["1004"].([]any); len(got) != 1 || got[0] != "800001" {
			t.Errorf("wrong mixed_video_id_map: %v", payload["mixed_video_id_map"])
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"code":0,"data":{"1004":{"800001":{"video_model":{"video_list":[{"main_url":"https://media.example.test/episode.mp4","video_meta":{"codec_type":"h264","definition":"1080p"}}]}}}}}`))
	}))
	defer server.Close()

	d := newHongguoRequestTestDownloader(server)
	d.hongguoClient().playbackBaseURL = server.URL
	media, err := d.resolveHongguoAppMedia(context.Background(), "800001")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.test/episode.mp4" || media.Quality != 1080 {
		t.Fatalf("unexpected resolved playback: %+v", media)
	}
}

func TestHongguoOtherAppRequestsRemainSigned(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/novel/player/video_detail/v1/" {
			t.Errorf("unexpected detail request path: %s", r.URL.Path)
		}
		for _, name := range []string{"X-Gorgon", "X-Khronos", "X-SS-STUB", "X-SS-Req-Ticket"} {
			if value := r.Header.Get(name); value == "" {
				t.Errorf("detail request is missing %s", name)
			}
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"code":0}`))
	}))
	defer server.Close()

	d := newHongguoRequestTestDownloader(server)
	d.hongguoClient().baseURL = server.URL
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]string{"series_id": "700001"}); err != nil {
		t.Fatal(err)
	}
}

func TestHongguoPlaybackFallsBackToDirectVideoList(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"code":0,"data":{"1004":{"800002":{"video_list":[{"main_url":"https://media.example.test/plain.mp4","video_meta":{"codec_type":"h264","definition":"720p"}}],"video_duration":"95"}}}}`))
	}))
	defer server.Close()

	d := newHongguoRequestTestDownloader(server)
	d.hongguoClient().playbackBaseURL = server.URL
	media, err := d.resolveHongguoAppMedia(context.Background(), "800002")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.test/plain.mp4" || media.Quality != 720 {
		t.Fatalf("unexpected resolved playback: %+v", media)
	}
}
