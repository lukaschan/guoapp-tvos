package core

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const hongguoFallbackTestSeed = "c3ludGhldGljLXBsYXktdXJsLXNlZWQtdmFsdWU="
const hongguoFallbackTest720 = "qAABALUkO1MRVTUg+MSemgpTZZVSP0rNJcYa/ZvyhQOF0DBlH0Za09GLLLO537j51jx0jg=="
const hongguoFallbackTest1080 = "qAABALUkO1MRVTUg+MSemgpTZZVSP0rNJcYa/ZvyhQOF0DBlVrDho7odtelXm+CoS2sCoQ=="
const hongguoFallbackTest1080Backup = "qAABALUkO1MRVTUg+MSemgpTZZVSP0rNJcYa/ZvyhQOF0DBlMR7OSE8Ahs3ifaiQ7uu8GQB2o032GZIGe86ItzNWq/A="

func TestDecodeHongguoPlayURL(t *testing.T) {
	address, err := decodeHongguoPlayURL(hongguoFallbackTest720, hongguoFallbackTestSeed)
	if err != nil || address != "https://media.example.invalid/h265-720.mp4" {
		t.Fatalf("sealed 720: %q, %v", address, err)
	}
	address, err = decodeHongguoPlayURL(hongguoFallbackTest1080, hongguoFallbackTestSeed)
	if err != nil || address != "https://media.example.invalid/h265-1080.mp4" {
		t.Fatalf("sealed 1080: %q, %v", address, err)
	}
	address, err = decodeHongguoPlayURL("https://media.example.invalid/plain.mp4", hongguoFallbackTestSeed)
	if err != nil || address != "https://media.example.invalid/plain.mp4" {
		t.Fatalf("plain passthrough: %q, %v", address, err)
	}
	unknown := append([]byte{0xa8, 0x00, 0x02, 0x00}, make([]byte, 32)...)
	for i := 4; i < len(unknown); i++ {
		unknown[i] = 7
	}
	_, err = decodeHongguoPlayURL(base64.StdEncoding.EncodeToString(unknown), hongguoFallbackTestSeed)
	var versionErr *hongguoPlayURLVersionError
	if !errors.As(err, &versionErr) || versionErr.version != 2 || !strings.Contains(err.Error(), "编码版本 2") {
		t.Fatalf("unknown version: %v", err)
	}
	address, err = decodeHongguoPlayURL("", hongguoFallbackTestSeed)
	if err != nil || address != "" {
		t.Fatalf("empty: %q, %v", address, err)
	}
}

func TestHongguoFallbackDecodesSealedH265(t *testing.T) {
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.URL.Path == "/reading/bookapi/video_tab/multi_video_model/v1/":
			_, _ = fmt.Fprintf(w, `{"code":0,"data":{"video_model_data":{"800003":{"video_model":{"video_duration":80.5,"fallback_api":{"fallback_api":%q},"video_list":[{"main_url":"https://media.example.invalid/vvc.mp4","video_meta":{"codec_type":"bytevc2","definition":"1080p"}}]}}}}}`, server.URL+"/video/fplay/1/synthetic?aid=8662&codec_type=4&stream_type=encrypt")
		case r.URL.Path == "/video/fplay/1/synthetic":
			query := r.URL.Query()
			if query.Get("codec_type") != "1" || query.Get("stream_type") != "encrypt" {
				t.Errorf("fallback query not rewritten: %s", r.URL.RawQuery)
			}
			_, _ = fmt.Fprintf(w, `{"video_info":{"data":{"video_duration":80.5,"key_seed":%q,"video_list":{"video_1":{"definition":"720p","codec_type":"h265","vwidth":720,"vheight":1280,"main_url":%q},"video_2":{"definition":"1080p","codec_type":"h265","vwidth":1080,"vheight":1920,"main_url":%q,"backup_url_1":%q}}}}}`, hongguoFallbackTestSeed, hongguoFallbackTest720, hongguoFallbackTest1080, hongguoFallbackTest1080Backup)
		default:
			t.Errorf("unexpected request: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	d := newHongguoRequestTestDownloader(server)
	d.hongguoClient().baseURL = server.URL
	d.hongguoClient().playbackBaseURL = server.URL
	media, err := d.resolveHongguoAppMedia(context.Background(), "800003")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.invalid/h265-1080.mp4" || media.Quality != 1080 {
		t.Fatalf("unexpected fallback media: %+v", media)
	}
	if media.Duration != 80500*time.Millisecond {
		t.Fatalf("unexpected duration: %v", media.Duration)
	}
	if len(media.Variants) != 3 {
		t.Fatalf("expected 3 variants, got %d", len(media.Variants))
	}
}
