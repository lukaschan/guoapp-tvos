package core

import (
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// 出自 PitayaDrama（Austin-SALVATORE）的挂起恢复补丁，2026-11-15 合入本仓：
// scripts/apply_fork_overlay.py 构建时把本文件拷进 native/core，upstream/ 子模块本身不改。
//
// 问题：tvOS 在 App 挂起时（切到后台几分钟、电视休眠）会回收监听中的套接字。核心的本机播放服务
// （newNativeStreamServer，127.0.0.1 随机端口）只创建一次，被回收后所有播放地址都连不上
// （connection refused），任何一集都「播放失败」，只能彻底关掉 App 重开。
//
// ReviveNativeStream 由 App 在回到前台时调用（经 bridge 的 DuanjuReviveStream）：
//   - "idle"：核心还没就绪，或者还没起过播（没有本机播放服务）；
//   - "alive"：还在监听，什么都不做；
//   - "revived"：监听没了，已在原端口重新监听——播放地址和会话都不变，正在播的可以接着播；
//   - "reset"：原端口拿不回来，旧服务已丢弃，下次起播时核心会重新创建（新端口，旧地址作废）。

var nativeStreamReviveMu sync.Mutex

func ReviveNativeStream() string {
	nativeStreamReviveMu.Lock()
	defer nativeStreamReviveMu.Unlock()
	nativeState.Lock()
	engine := nativeState.engine
	nativeState.Unlock()
	if engine == nil {
		return "idle"
	}
	engine.mu.Lock()
	stream := engine.stream
	engine.mu.Unlock()
	if stream == nil {
		return "idle"
	}
	if stream.listening() {
		return "alive"
	}
	if stream.relisten() {
		return "revived"
	}
	engine.dropStream(stream)
	return "reset"
}

func (stream *nativeStreamServer) host() string {
	return strings.TrimPrefix(stream.address, "http://")
}

// 问一下自己的健康端点：TCP 能连上只证明端口上有东西在听，回了 204 才证明是
// 本机播放服务本身在正常服务——端口被别的服务占了、HTTP 层卡死都算监听没了。
// 探活不走代理、不复用连接、1 秒超时；健康端点不依赖任何会话与片源。
// （据 GitHub issue #2 的建议由 TCP 拨号升级而来，guoapp2 同步同改。）
func (stream *nativeStreamServer) listening() bool {
	client := &http.Client{
		Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true},
		Timeout:   time.Second,
	}
	request, err := http.NewRequest(http.MethodHead, stream.address+"/__guoapp_health", nil)
	if err != nil {
		return false
	}
	response, err := client.Do(request)
	if err != nil {
		return false
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, response.Body)
	return response.StatusCode == http.StatusNoContent
}

// 关掉旧的（已失效的）HTTP 服务，在原地址重新监听，处理函数和会话沿用。
func (stream *nativeStreamServer) relisten() bool {
	stream.mu.Lock()
	defer stream.mu.Unlock()
	old := stream.server
	_ = old.Close()
	listener, err := net.Listen("tcp4", stream.host())
	if err != nil {
		return false
	}
	server := &http.Server{
		Handler:           old.Handler,
		ReadHeaderTimeout: old.ReadHeaderTimeout,
		IdleTimeout:       old.IdleTimeout,
		MaxHeaderBytes:    old.MaxHeaderBytes,
	}
	stream.server = server
	go func() { _ = server.Serve(listener) }()
	return true
}

// 丢掉恢复不了的本机播放服务：释放它的会话，下次起播时 nativeOpenPlayback 会重新创建。
func (engine *nativeEngine) dropStream(stream *nativeStreamServer) {
	engine.mu.Lock()
	if engine.stream == stream {
		engine.stream = nil
	}
	engine.mu.Unlock()
	stream.mu.Lock()
	defer stream.mu.Unlock()
	_ = stream.server.Close()
	for token, session := range stream.sessions {
		stream.nativeCancel(session, "release")
		delete(stream.sessions, token)
	}
}
