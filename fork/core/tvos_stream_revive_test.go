package core

import (
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// 本仓库（tvOS 分支）自带补丁的测试，由 scripts/build_tvos.py --test-overlay 经 go test -overlay 运行。

func tvosReviveFixture(t *testing.T) (*nativeEngine, *nativeStreamServer, string) {
	t.Helper()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		io.WriteString(w, "binary-media")
	}))
	t.Cleanup(upstream.Close)
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	stream, err := newNativeStreamServer(engine.downloader)
	if err != nil {
		t.Fatal(err)
	}
	engine.stream = stream
	nativeState.Lock()
	previous := nativeState.engine
	nativeState.engine = engine
	nativeState.Unlock()
	t.Cleanup(func() {
		nativeState.Lock()
		nativeState.engine = previous
		nativeState.Unlock()
		engine.mu.Lock()
		current := engine.stream
		engine.mu.Unlock()
		if current != nil {
			current.server.Close()
		}
	})
	address, _ := stream.nativeOpen(providerMedia{URL: upstream.URL + "/video.mp4"})
	return engine, stream, address
}

func tvosFetch(address string) (string, error) {
	client := &http.Client{Transport: &http.Transport{DisableKeepAlives: true}}
	response, err := client.Get(address)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return string(body), err
}

func TestTVOSReviveStreamIsIdleBeforeAnyPlayback(t *testing.T) {
	nativeState.Lock()
	previous := nativeState.engine
	nativeState.engine = nil
	nativeState.Unlock()
	defer func() {
		nativeState.Lock()
		nativeState.engine = previous
		nativeState.Unlock()
	}()
	if got := ReviveNativeStream(); got != "idle" {
		t.Fatalf("no engine: got %q, want idle", got)
	}
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	nativeState.Lock()
	nativeState.engine = engine
	nativeState.Unlock()
	if got := ReviveNativeStream(); got != "idle" {
		t.Fatalf("no stream yet: got %q, want idle", got)
	}
}

// App 挂起时系统回收了监听的套接字：恢复后原来的播放地址照样能用（同一个端口、同一批会话）。
func TestTVOSReviveStreamReopensTheSamePort(t *testing.T) {
	_, stream, address := tvosReviveFixture(t)
	if body, err := tvosFetch(address); err != nil || body != "binary-media" {
		t.Fatalf("before: body %q err %v", body, err)
	}
	if got := ReviveNativeStream(); got != "alive" {
		t.Fatalf("listening: got %q, want alive", got)
	}
	stream.server.Close() // 模拟系统回收：没有东西在监听了
	if _, err := tvosFetch(address); err == nil {
		t.Fatal("expected the old address to be refused once the listener is gone")
	}
	if got := ReviveNativeStream(); got != "revived" {
		t.Fatalf("listener gone: got %q, want revived", got)
	}
	if body, err := tvosFetch(address); err != nil || body != "binary-media" {
		t.Fatalf("after revive: body %q err %v", body, err)
	}
	if got := ReviveNativeStream(); got != "alive" {
		t.Fatalf("after revive: got %q, want alive", got)
	}
}

// 原端口被别的程序占了：丢掉旧服务，下次起播时核心重新创建（新端口）。
func TestTVOSReviveStreamResetsWhenThePortIsTaken(t *testing.T) {
	engine, stream, address := tvosReviveFixture(t)
	// 先取一次，确保服务已经在接连接：Close 才会同步关掉监听，端口立刻空出来。
	if body, err := tvosFetch(address); err != nil || body != "binary-media" {
		t.Fatalf("before: body %q err %v", body, err)
	}
	stream.server.Close()
	squatter, err := net.Listen("tcp4", strings.TrimPrefix(stream.address, "http://"))
	if err != nil {
		t.Fatal("could not occupy the port: " + err.Error())
	}
	defer squatter.Close()
	go func() {
		for {
			connection, err := squatter.Accept()
			if err != nil {
				return
			}
			connection.Close()
		}
	}()
	// 端口上有别的程序在听：连得上，但不是我们的服务——这里只验证「重新监听失败」这一支，
	// 所以直接走内部步骤。
	if stream.relisten() {
		t.Fatal("relisten should fail while another listener holds the port")
	}
	engine.dropStream(stream)
	engine.mu.Lock()
	current := engine.stream
	engine.mu.Unlock()
	if current != nil {
		t.Fatal("the dead stream server should be dropped so the next playback creates a new one")
	}
	if len(stream.sessions) != 0 {
		t.Fatalf("sessions of the dropped server should be released, %d left", len(stream.sessions))
	}
}
