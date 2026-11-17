package core

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const hongguoPlaybackBaseURL = "https://api5-normal-sinfonlinea.fqnovel.com"
const hongguoPlaybackPath = "/novel/player/multi_video_model/player/v1"
const hongguoPlaybackUserAgent = "com.phoenix.read/73932 (Linux; U; Android 12; zh_CN_#Hans; PGT-AN10; Build/V417IR;tt-ok/3.12.13.20)"

var errHongguoNoCompatibleMedia = errors.New("红果 App 未返回兼容的媒体")

func hongguoPlaybackQuery(deviceID, installID string) map[string]string {
	return map[string]string{
		"aid": "8662", "app_name": "novelread", "version_code": "74332", "version_name": "7.4.3.32",
		"channel": "vivo_8662_64", "device_platform": "android", "device_type": "PGT-AN10", "os_version": "12",
		"update_version_code": "74332", "iid": installID, "cdid": uuidLike(), "device_id": deviceID,
	}
}

// hongguoPlaybackRequest performs one V5-signed playback model request,
// rotating the device identity on empty responses like the reference client.
func (downloader *Downloader) hongguoPlaybackRequest(ctx context.Context, helper bool, payload any) (map[string]any, error) {
	client := downloader.hongguoClient()
	base := client.playbackBaseURL
	if base == "" {
		base = hongguoPlaybackBaseURL
	}
	registerErr := downloader.ensureHongguoDevice(ctx, helper, "")
	deviceID, installID, _ := client.device(helper)
	if helper {
		if deviceID == "" {
			return nil, errors.New("红果辅助设备不可用")
		}
		ctx = context.WithValue(ctx, requestLaneKey{}, "hongguo-helper")
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	values := hongguoPlaybackQuery(deviceID, installID)
	attempts := downloader.cfg.Retries
	if attempts < 1 {
		attempts = 1
	}
	if attempts > 3 {
		attempts = 3
	}
	var lastErr error
	rotations := 0
	for attempt := 0; attempt < attempts; attempt++ {
		if attempt > 0 {
			select {
			case <-time.After(time.Duration(attempt) * time.Second):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		request, err := http.NewRequestWithContext(ctx, http.MethodPost, base+hongguoPlaybackPath, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		request.Header.Set("User-Agent", hongguoPlaybackUserAgent)
		request.Header.Set("Accept", "application/json")
		response, err := downloader.doPreparedCatalogRequest(request, 20*time.Second, func(prepared *http.Request) {
			signedURL, headers, signErr := signHongguoPlaybackV5(base+hongguoPlaybackPath, values, body, time.Now().UnixMilli(), nil)
			if signErr != nil {
				return
			}
			if parsed, parseErr := url.Parse(signedURL); parseErr == nil {
				prepared.URL = parsed
			}
			for key, value := range headers {
				prepared.Header.Set(key, value)
			}
		})
		if err != nil {
			lastErr = err
			var backoff *requestBackoff
			if errors.As(err, &backoff) || ctx.Err() != nil {
				return nil, err
			}
			continue
		}
		content, readErr := io.ReadAll(io.LimitReader(response.Body, providerMaxBodyBytes+1))
		response.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}
		if response.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("红果 App 接口 HTTP %d", response.StatusCode)
			if response.StatusCode >= 400 && response.StatusCode < 500 {
				return nil, lastErr
			}
			continue
		}
		if len(content) == 0 {
			lastErr = errors.New("红果 App 接口未返回有效数据")
			if rotations < hongguoDeviceRotations {
				if registerErr = downloader.ensureHongguoDevice(ctx, helper, deviceID); registerErr == nil {
					rotations++
					deviceID, installID, _ = client.device(helper)
					values["device_id"] = deviceID
					values["iid"] = installID
					attempt--
				}
			}
			if registerErr != nil {
				lastErr = fmt.Errorf("红果 App 接口未返回有效数据（设备注册失败：%v）", registerErr)
			}
			continue
		}
		if len(content) > providerMaxBodyBytes {
			return nil, errors.New("红果 App 接口未返回有效数据")
		}
		var result map[string]any
		decoder := json.NewDecoder(bytes.NewReader(content))
		decoder.UseNumber()
		if err := decoder.Decode(&result); err != nil || result == nil {
			return nil, errors.New("红果 App 接口返回格式异常")
		}
		code := firstNonEmpty(mapString(result, "code", "Code", "status_code"), mapString(nestedMap(result, "BaseResp"), "StatusCode"))
		if code != "" && code != "0" {
			return nil, fmt.Errorf("红果 App 接口暂不可用（%s）", truncate(code, 20))
		}
		return result, nil
	}
	return nil, lastErr
}

func (downloader *Downloader) fetchHongguoPlaybackMedia(ctx context.Context, videoID string, helper bool) (providerMedia, error) {
	payload := map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": 1, "disable_digg_stat": false, "disable_video_relate_book": false,
			"need_all_video_definition": true, "need_mp4_align": false, "use_os_player": false, "use_server_dns": false,
			"video_platform": 1024,
		},
		"mixed_video_id_map": map[string]any{"1004": []string{videoID}},
		"dr_scene":           "player",
	}
	result, err := downloader.hongguoPlaybackRequest(ctx, helper, payload)
	if err != nil {
		return providerMedia{}, err
	}
	entries := nestedMap(result, "data")
	entry := entries
	if grouped, ok := entries["1004"].(map[string]any); ok {
		entry = grouped
	}
	data, _ := entry[videoID].(map[string]any)
	if len(data) == 0 {
		return providerMedia{}, errors.New("红果 App 未返回所请求的分集播放信息")
	}
	model, _ := data["video_model"].(map[string]any)
	if encoded, ok := data["video_model"].(string); ok && encoded != "" {
		if decoded, err := decodeHongguoBase64(encoded); err == nil && len(decoded) > 0 {
			encoded = string(decoded)
		}
		decoder := json.NewDecoder(strings.NewReader(encoded))
		decoder.UseNumber()
		parsed := map[string]any{}
		if err := decoder.Decode(&parsed); err != nil {
			return providerMedia{}, errors.New("红果 App 播放信息格式异常")
		}
		model = parsed
	}
	if len(model) == 0 {
		if rows := anyList(data["video_list"]); len(rows) > 0 {
			model = map[string]any{
				"video_list":     data["video_list"],
				"video_duration": data["video_duration"],
				"duration":       data["duration"],
			}
		}
	}
	media, err := selectHongguoAppMedia(model)
	if err != nil {
		if strings.Contains(err.Error(), "未返回兼容的媒体") {
			return providerMedia{}, errHongguoNoCompatibleMedia
		}
		return providerMedia{}, err
	}
	return media, nil
}

// resolveHongguoPlaybackV5 mirrors the reference client's lane flow: primary
// device, then the helper device, then a rotated helper device — the fallbacks
// only engage when the returned model has no compatible media.
func (downloader *Downloader) resolveHongguoPlaybackV5(ctx context.Context, videoID string) (providerMedia, error) {
	if !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果视频 ID 无效")
	}
	media, err := downloader.fetchHongguoPlaybackMedia(ctx, videoID, false)
	if !errors.Is(err, errHongguoNoCompatibleMedia) {
		return media, err
	}
	media, err = downloader.fetchHongguoPlaybackMedia(ctx, videoID, true)
	if !errors.Is(err, errHongguoNoCompatibleMedia) {
		return media, err
	}
	client := downloader.hongguoClient()
	helperID, _, _ := client.device(true)
	if rotateErr := downloader.ensureHongguoDevice(ctx, true, helperID); rotateErr != nil {
		return providerMedia{}, fmt.Errorf("%v；更换辅助设备也没有成功：%v", err, rotateErr)
	}
	return downloader.fetchHongguoPlaybackMedia(ctx, videoID, true)
}
