package core

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"
)

// Live probe for the pure (current-dialect) lane only: HONGGUO_LIVE=1 go test ./core/ -run TestHongguoPureLive -v
func TestHongguoPureLive(t *testing.T) {
	if os.Getenv("HONGGUO_LIVE") != "1" {
		t.Skip("set HONGGUO_LIVE=1 to run")
	}
	d := &Downloader{
		cfg:     Config{dataDir: t.TempDir(), Retries: 2},
		client:  &http.Client{Timeout: 45 * time.Second},
		limiter: newRequestLimiter(3, 250*time.Millisecond),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
	defer cancel()
	media, err := d.resolveHongguoPlaybackPure(ctx, "7690411695105133592")
	if err != nil {
		t.Fatalf("pure resolve failed: %v", err)
	}
	t.Logf("URL: %s", media.URL)
	t.Logf("quality=%d duration=%v variants=%d cenc=%v", media.Quality, media.Duration, len(media.Variants), media.CENCKey != nil)
	if media.URL == "" {
		t.Fatal("empty media URL")
	}
}
