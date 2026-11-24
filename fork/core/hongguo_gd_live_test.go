package core

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"
)

// Live probe for the GD (GuoDuo) lane only: HONGGUO_LIVE=1 go test ./core/ -run TestHongguoGDLive -v
func TestHongguoGDLive(t *testing.T) {
	if os.Getenv("HONGGUO_LIVE") != "1" {
		t.Skip("set HONGGUO_LIVE=1 to run")
	}
	d := &Downloader{
		cfg:     Config{dataDir: t.TempDir(), Retries: 2},
		client:  &http.Client{Timeout: 45 * time.Second},
		limiter: newRequestLimiter(3, 250*time.Millisecond),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 240*time.Second)
	defer cancel()
	identity, err := d.hongguoGDIdentity(ctx, true)
	if err != nil {
		t.Fatalf("GD registration failed: %v", err)
	}
	t.Logf("registered device_id=%s iid=%s", identity.DeviceID, identity.IID)
	media, err := d.resolveHongguoPlaybackGD(ctx, "7690411695105133592")
	if err != nil {
		t.Fatalf("GD resolve failed: %v", err)
	}
	t.Logf("URL: %s", media.URL)
	t.Logf("quality=%d duration=%v variants=%d cenc=%v", media.Quality, media.Duration, len(media.Variants), media.CENCKey != nil)
	if media.URL == "" {
		t.Fatal("empty media URL")
	}
}
