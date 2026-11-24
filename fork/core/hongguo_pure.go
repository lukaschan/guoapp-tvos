package core

import (
	"bytes"
	"context"
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"sync"
	"time"
)

const (
	hongguoPureHost        = "api5-normal-sinfonlinea.fqnovel.com"
	hongguoPureVideoPath   = "/novel/player/video_model/v1/"
	hongguoPureVersionName = "7.3.9.32"
	hongguoPureVersionCode = "73932"
	hongguoPureUA          = "com.phoenix.read/73932 (Linux; U; Android 14; zh_CN; 23127PN0CC; Build/UKQ1.230804.001; Cronet/TTNetVersion:8d40f833 2026-03-03 QuicVersion:21ac1950 2025-11-18)"
	hongguoPureMaxAge      = 7 * time.Minute
)

type hongguoPureIdentity struct {
	DeviceID       string
	InstallID      string
	CDID           string
	OpenUDID       string
	RegisteredAtMS int64
}

func (id hongguoPureIdentity) usable() bool {
	return id.DeviceID != "" && id.InstallID != "" && id.CDID != "" && id.OpenUDID != "" &&
		time.Since(time.UnixMilli(id.RegisteredAtMS)) < hongguoPureMaxAge
}

var hgPureState = struct {
	sync.Mutex
	identity      *hongguoPureIdentity
	rejected      map[string]bool
	blockedUntil  time.Time
	registerAfter time.Time
	clockOffsetMS int64
	clockAfter    time.Time
}{rejected: map[string]bool{}}

func hongguoBasicSignHeaders(params string, body []byte) map[string]string {
	ts := time.Now().Unix()
	var seed [2]byte
	_, _ = rand.Read(seed[:])
	variant := uint16(seed[0])<<8 | uint16(seed[1])
	return map[string]string{
		"X-Khronos": strconv.FormatInt(ts, 10),
		"X-Gorgon":  hongguoClassicGorgon(params, body, ts, variant, 0x4481),
		"X-Argus":   hongguoClassicArgus(ts),
	}
}

func hongguoClassicArgus(ts int64) string {
	var buf [4]byte
	binary.LittleEndian.PutUint32(buf[:], uint32(ts))
	return base64.StdEncoding.EncodeToString(buf[:])
}

func hongguoClassicGorgon(params string, body []byte, ts int64, variant uint16, flags uint16) string {
	paramsDigest := md5.Sum([]byte(params))
	chunk := [4]byte{}
	if len(body) > 0 {
		bodyDigest := md5.Sum(body)
		copy(chunk[:], bodyDigest[:4])
	}
	concat := make([]byte, 0, 20)
	concat = append(concat, paramsDigest[:4]...)
	concat = append(concat, chunk[:]...)
	concat = append(concat, 0, 0, 0, 0, 0x00, 0x03, 0x0a, 0x04)
	var tsBuf [4]byte
	binary.BigEndian.PutUint32(tsBuf[:], uint32(ts))
	concat = append(concat, tsBuf[:]...)
	fh, fl := byte(flags>>8), byte(flags)
	key := []byte{0x4a, fh, 0x16, byte(variant), 0x47, 0x6c, fl, byte(variant >> 8)}
	ks := hongguoBrokenRC4(key, 20)
	for i := range concat {
		concat[i] ^= ks[i]
	}
	head := []byte{0x84, 0x04, byte(variant >> 8), byte(variant), fh, fl}
	return hex.EncodeToString(append(head, hongguoGorgonMix(concat)...))
}

func hongguoBrokenRC4(key []byte, n int) []byte {
	s := make([]byte, 256)
	for i := range s {
		s[i] = byte(i)
	}
	j := 0
	for i := 0; i < 256; i++ {
		j = (j + int(s[i]) + int(key[i&7])) & 0xff
		s[i] = s[j]
	}
	out := make([]byte, 0, n)
	i, jj := 0, 0
	for len(out) < n {
		i = (i + 1) & 0xff
		jj = (jj + int(s[i])) & 0xff
		v := s[jj]
		s[i] = v
		out = append(out, s[(int(s[i])+int(v))&0xff])
	}
	return out
}

func hongguoGorgonMix(seed []byte) []byte {
	buf := append([]byte(nil), seed...)
	for n := 0; n < 20 && n < len(buf); n++ {
		buf[n] = (buf[n]&0x0f)<<4 | (buf[n]>>4)&0x0f
		x := buf[n] ^ buf[(n+1)%20]
		var r byte
		for i := 0; i < 8; i++ {
			if x&(1<<uint(i)) != 0 {
				r |= 1 << uint(7-i)
			}
		}
		buf[n] = 0x14 ^ ^r
	}
	return buf
}

func (downloader *Downloader) registerHongguoPureDevice(ctx context.Context) (hongguoPureIdentity, error) {
	cdid, openudid := uuidLike(), randomHex(8)
	query := "aid=8662&app_name=novelread&version_code=73932&version_name=7.3.9.32&device_platform=android&os=android&ssmix=a" +
		"&language=zh&channel=xiaomi_8662_64&device_type=23127PN0CC&device_brand=Xiaomi&resolution=1200*2670&dpi=460" +
		"&host_abi=arm64-v8a&manifest_version_code=73932&update_version_code=73932&ac=wifi&app_type=normal&cpu_support64=true" +
		"&os_api=34&os_version=14&cdid=" + cdid + "&openudid=" + openudid
	header := map[string]any{
		"display_name": "红果短剧", "aid": 8662, "channel": "xiaomi_8662_64", "package": "com.phoenix.read",
		"app_version": "7.3.9.32", "version_code": 73932, "manifest_version_code": 73932, "update_version_code": 73932,
		"sdk_version": "3.9.5", "sdk_target_version": 34, "os": "Android", "os_version": "14", "os_api": 34,
		"device_model": "23127PN0CC", "device_brand": "Xiaomi", "device_manufacturer": "Xiaomi", "cpu_abi": "arm64-v8a",
		"release_build": "UKQ1.230804.001", "density_dpi": 460, "display_density": "xxhdpi", "resolution": "2670x1200",
		"language": "zh", "timezone": 8, "region": "CN", "tz_name": "Asia/Shanghai",
		"cdid": cdid, "openudid": openudid, "clientudid": uuidLike(), "google_aid": "", "req_id": uuidLike(),
	}
	body, err := json.Marshal(map[string]any{"magic_tag": "ss_app_log", "header": header, "_gen_time": time.Now().Unix()})
	if err != nil {
		return hongguoPureIdentity{}, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, hongguoDeviceRegisterURL+"?"+query, bytes.NewReader(body))
	if err != nil {
		return hongguoPureIdentity{}, err
	}
	for key, value := range hongguoBasicSignHeaders(query, body) {
		request.Header.Set(key, value)
	}
	request.Header.Set("User-Agent", hongguoPureUA)
	request.Header.Set("Content-Type", "application/json; charset=utf-8")
	request.Header.Set("sdk-version", "2")
	response, err := downloader.doPreparedCatalogRequest(request, 10*time.Second, nil)
	if err != nil {
		return hongguoPureIdentity{}, err
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, 64<<10))
	response.Body.Close()
	if err != nil {
		return hongguoPureIdentity{}, err
	}
	if response.StatusCode != http.StatusOK {
		return hongguoPureIdentity{}, hongguoRegisterRejection{fmt.Errorf("红果播放器设备注册 HTTP %d", response.StatusCode)}
	}
	var result map[string]any
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&result); err != nil {
		return hongguoPureIdentity{}, hongguoRegisterRejection{errors.New("红果播放器设备注册返回格式异常")}
	}
	deviceID := mapString(result, "device_id_str", "device_id")
	installID := mapString(result, "install_id_str", "install_id")
	if installID == "" || installID == "0" {
		installID = mapString(result, "iid")
	}
	if !hongguoNumericID.MatchString(deviceID) || !hongguoNumericID.MatchString(installID) || deviceID == "0" || installID == "0" {
		return hongguoPureIdentity{}, hongguoRegisterRejection{errors.New("红果播放器设备注册未返回设备号")}
	}
	return hongguoPureIdentity{DeviceID: deviceID, InstallID: installID, CDID: cdid, OpenUDID: openudid,
		RegisteredAtMS: time.Now().UnixMilli()}, nil
}

func (downloader *Downloader) ensureHongguoPureIdentity(ctx context.Context, failedID string) (hongguoPureIdentity, error) {
	hgPureState.Lock()
	defer hgPureState.Unlock()
	if failedID != "" {
		hgPureState.rejected[failedID] = true
		if hgPureState.identity != nil && hgPureState.identity.DeviceID == failedID {
			hgPureState.identity = nil
		}
	}
	if id := hgPureState.identity; id != nil && id.usable() && !hgPureState.rejected[id.DeviceID] && id.DeviceID != failedID {
		return *id, nil
	}
	if time.Now().Before(hgPureState.blockedUntil) {
		return hongguoPureIdentity{}, errors.New("红果播放器设备注册冷却中，请稍后重试")
	}
	if wait := time.Until(hgPureState.registerAfter); wait > 0 {
		select {
		case <-time.After(wait):
		case <-ctx.Done():
			return hongguoPureIdentity{}, ctx.Err()
		}
	}
	id, err := downloader.registerHongguoPureDevice(ctx)
	if err != nil {
		hgPureState.blockedUntil = time.Now().Add(30 * time.Second)
		return hongguoPureIdentity{}, err
	}
	hgPureState.identity = &id
	hgPureState.registerAfter = time.Now().Add(time.Second)
	return id, nil
}

func (downloader *Downloader) hongguoPureSigningMillis(ctx context.Context) int64 {
	hgPureState.Lock()
	now := time.Now()
	if now.Before(hgPureState.clockAfter) {
		offset := hgPureState.clockOffsetMS
		hgPureState.Unlock()
		return now.UnixMilli() + offset
	}
	hgPureState.clockAfter = now.Add(60 * time.Second)
	hgPureState.Unlock()
	start := time.Now()
	if request, err := http.NewRequestWithContext(ctx, http.MethodHead, "https://"+hongguoPureHost+hongguoPureVideoPath, nil); err == nil {
		request.Header.Set("User-Agent", hongguoPureUA)
		request.Header.Set("Cache-Control", "no-cache")
		if response, err := downloader.doPreparedCatalogRequest(request, 5*time.Second, nil); err == nil {
			received := time.Now()
			status, date, age := response.StatusCode, response.Header.Get("Date"), response.Header.Get("Age")
			response.Body.Close()
			if status >= 200 && status < 500 && received.Sub(start) <= 10*time.Second && (age == "" || age == "0") && date != "" {
				if server, err := http.ParseTime(date); err == nil {
					offset := server.UnixMilli() + 500 - (start.UnixMilli()+received.UnixMilli())/2
					hgPureState.Lock()
					hgPureState.clockOffsetMS = offset
					hgPureState.clockAfter = received.Add(300 * time.Second)
					hgPureState.Unlock()
				}
			}
		}
	}
	hgPureState.Lock()
	offset := hgPureState.clockOffsetMS
	hgPureState.Unlock()
	return time.Now().UnixMilli() + offset
}

func hongguoPurePairs(id hongguoPureIdentity) [][2]string {
	vc := hongguoPureVersionCode
	return [][2]string{
		{"iid", id.InstallID}, {"device_id", id.DeviceID}, {"ac", "wifi"}, {"channel", "xiaomi_8662_64"},
		{"aid", "8662"}, {"app_name", "novelread"}, {"cdid", id.CDID}, {"version_code", vc},
		{"version_name", hongguoPureVersionName}, {"device_platform", "android"}, {"os", "android"}, {"ssmix", "a"},
		{"device_type", "23127PN0CC"}, {"device_brand", "Xiaomi"}, {"language", "zh"}, {"os_api", "34"},
		{"os_version", "14"}, {"manifest_version_code", vc}, {"resolution", "1200*2670"}, {"dpi", "460"},
		{"update_version_code", vc}, {"host_abi", "arm64-v8a"}, {"dragon_device_type", "phone"}, {"pv_player", vc},
		{"compliance_status", "0"}, {"need_personal_recommend", "1"}, {"player_so_load", "1"},
		{"is_android_pad_screen", "0"}, {"openudid", id.OpenUDID},
	}
}

func hongguoPurePairValue(pairs [][2]string, key string) string {
	for _, pair := range pairs {
		if pair[0] == key {
			return pair[1]
		}
	}
	return ""
}

func hongguoPureCodeOK(payload map[string]any) error {
	values := []any{payload["code"]}
	if base := mapValue(payload, "BaseResp"); base != nil {
		values = append(values, base["StatusCode"])
	}
	for _, value := range values {
		if value == nil {
			continue
		}
		var text string
		switch typed := value.(type) {
		case string:
			text = typed
		case json.Number:
			text = typed.String()
		case float64:
			text = strconv.FormatInt(int64(typed), 10)
		default:
			text = fmt.Sprint(typed)
		}
		if text != "0" {
			return fmt.Errorf("红果播放接口 code=%s %s", text, mapString(payload, "message"))
		}
	}
	return nil
}

func mapValue(payload map[string]any, key string) map[string]any {
	if payload == nil {
		return nil
	}
	nested, _ := payload[key].(map[string]any)
	return nested
}

func (downloader *Downloader) hongguoPurePost(ctx context.Context, url string, body []byte, headers map[string]string, readingRequest string) ([]byte, int, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, 0, err
	}
	for key, value := range headers {
		if value != "" {
			request.Header.Set(key, value)
		}
	}
	request.Header.Set("User-Agent", hongguoPureUA)
	request.Header.Set("x-ss-dp", "8662")
	request.Header.Set("lc", "101")
	request.Header.Set("x-reading-request", readingRequest)
	response, err := downloader.doPreparedCatalogRequest(request, 20*time.Second, nil)
	if err != nil {
		return nil, 0, err
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, 16<<20))
	response.Body.Close()
	if err != nil {
		return nil, 0, err
	}
	return content, response.StatusCode, nil
}

func hongguoPureParseMedia(content []byte, entryKey string) (providerMedia, error) {
	if len(content) == 0 {
		return providerMedia{}, errHongguoEmptyBody
	}
	var payload map[string]any
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&payload); err != nil {
		return providerMedia{}, fmt.Errorf("%w（返回格式异常）", errHongguoEmptyBody)
	}
	if err := hongguoPureCodeOK(payload); err != nil {
		return providerMedia{}, err
	}
	data := mapValue(payload, "data")
	if data == nil {
		return providerMedia{}, errors.New("红果播放接口未返回数据")
	}
	entry := data
	if entryKey != "" {
		entry = mapValue(data, entryKey)
		if entry == nil {
			return providerMedia{}, errors.New("红果播放接口缺少请求的分集")
		}
	}
	model, err := hongguoModelFromEntry(entry)
	if err != nil {
		return providerMedia{}, err
	}
	return selectHongguoAppMedia(model)
}

func (downloader *Downloader) hongguoPureSingle(ctx context.Context, videoID string, level int, pairs [][2]string) (providerMedia, error) {
	deviceLevel := 3
	if level >= 4 {
		deviceLevel = 4
	}
	body, err := json.Marshal(map[string]any{
		"biz_param": map[string]any{"device_level": deviceLevel, "need_all_video_definition": true, "video_id_type": 0, "video_platform": 3},
		"video_id":  videoID,
	})
	if err != nil {
		return providerMedia{}, err
	}
	deviceID := hongguoPurePairValue(pairs, "device_id")
	var lastErr error = errHongguoEmptyBody
	for attempt := 0; attempt < 2; attempt++ {
		if attempt > 0 {
			select {
			case <-time.After(500 * time.Millisecond):
			case <-ctx.Done():
				return providerMedia{}, ctx.Err()
			}
		}
		nowMs := downloader.hongguoPureSigningMillis(ctx)
		query, headers, err := hgCurSign(pairs, nowMs, deviceID, hongguoPureVersionName, body, nil)
		if err != nil {
			return providerMedia{}, err
		}
		reading := headers["x-ss-req-ticket"] + "-" + strconv.FormatInt(time.Now().UnixNano()&0x7fffffff, 10)
		content, status, err := downloader.hongguoPurePost(ctx, "https://"+hongguoPureHost+hongguoPureVideoPath+"?"+query, body, headers, reading)
		if err != nil {
			lastErr = err
			continue
		}
		if status == http.StatusTooManyRequests || status >= 500 {
			lastErr = fmt.Errorf("红果 video_model HTTP %d", status)
			continue
		}
		if status != http.StatusOK {
			return providerMedia{}, fmt.Errorf("红果 video_model HTTP %d", status)
		}
		return hongguoPureParseMedia(content, "")
	}
	return providerMedia{}, lastErr
}

func (downloader *Downloader) hongguoPureBatch(ctx context.Context, videoID string, level int, pairs [][2]string, path string) (providerMedia, error) {
	body, err := json.Marshal(map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": level, "disable_digg_stat": false, "disable_video_relate_book": false,
			"need_all_video_definition": true, "need_mp4_align": false, "use_os_player": false, "use_server_dns": true,
			"use_server_dns_scene": "cold_start_stage", "video_platform": 1024,
		},
		"dr_scene":           "player",
		"mixed_video_id_map": map[string]any{"1004": []string{videoID}},
	})
	if err != nil {
		return providerMedia{}, err
	}
	deviceID := hongguoPurePairValue(pairs, "device_id")
	nowMs := downloader.hongguoPureSigningMillis(ctx)
	query, headers, err := hgCurSign(pairs, nowMs, deviceID, hongguoPureVersionName, body, nil)
	if err != nil {
		return providerMedia{}, err
	}
	reading := headers["x-ss-req-ticket"] + "-" + strconv.FormatInt(nowMs&0x7fffffff, 10)
	content, status, err := downloader.hongguoPurePost(ctx, "https://"+hongguoPureHost+path+"?"+query, body, headers, reading)
	if err != nil {
		return providerMedia{}, err
	}
	if status != http.StatusOK {
		return providerMedia{}, fmt.Errorf("红果 multi_video_model HTTP %d", status)
	}
	return hongguoPureParseMedia(content, videoID)
}

func (downloader *Downloader) hongguoPureLevels(ctx context.Context, videoID string, pairs [][2]string) (providerMedia, error) {
	for _, level := range []int{3, 4} {
		media, err := downloader.hongguoPureSingle(ctx, videoID, level, pairs)
		if errors.Is(err, errHongguoEmptyBody) {
			for _, path := range []string{"/novel/player/multi_video_model/v1", "/novel/player/multi_video_model/player/v1"} {
				media, err = downloader.hongguoPureBatch(ctx, videoID, level, pairs, path)
				if !errors.Is(err, errHongguoEmptyBody) {
					break
				}
			}
		}
		if err == nil {
			return media, nil
		}
		if errors.Is(err, errHongguoNoCompatibleMedia) && level == 3 {
			continue
		}
		return providerMedia{}, err
	}
	return providerMedia{}, errHongguoEmptyBody
}

func (downloader *Downloader) resolveHongguoPlaybackPure(ctx context.Context, videoID string) (providerMedia, error) {
	failedID := ""
	for attempt := 0; attempt < 3; attempt++ {
		identity, err := downloader.ensureHongguoPureIdentity(ctx, failedID)
		if err != nil {
			return providerMedia{}, err
		}
		media, err := downloader.hongguoPureLevels(ctx, videoID, hongguoPurePairs(identity))
		if err == nil {
			return media, nil
		}
		if !errors.Is(err, errHongguoEmptyBody) {
			return providerMedia{}, err
		}
		failedID = identity.DeviceID
		if attempt == 2 {
			hgPureState.Lock()
			hgPureState.blockedUntil = time.Now().Add(30 * time.Second)
			hgPureState.Unlock()
			return providerMedia{}, fmt.Errorf("红果取流被上游空包拒绝，已尝试 3 个播放器身份，请稍后重试：%w", errHongguoEmptyBody)
		}
	}
	return providerMedia{}, errHongguoEmptyBody
}
