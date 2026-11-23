package core

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const hongguoPlaybackBaseURL = "https://api5-normal-sinfonlinea.fqnovel.com"
const hongguoPlaybackPath = "/novel/player/multi_video_model/player/v1"
const hongguoVideoTabPath = "/reading/bookapi/video_tab/multi_video_model/v1/"
const hongguoPlaybackUserAgent = "com.phoenix.read/" + hongguoAppVersionCode + " (Linux; U; Android 12; zh_CN_#Hans; PGT-AN10; Build/V417IR;tt-ok/3.12.13.20)"
const hongguoPlayURLSalt = "4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58"

var errHongguoNoCompatibleMedia = errors.New("红果 App 未返回兼容的媒体")
var errHongguoEmptyBody = errors.New("红果 App 接口对本次设备签名返回空响应，风控未放行")

const hongguoMainDeviceRotateCooldown = 2 * time.Minute

var hongguoMainDeviceRotation struct {
	sync.Mutex
	at time.Time
}

func takeHongguoMainDeviceRotation() bool {
	hongguoMainDeviceRotation.Lock()
	defer hongguoMainDeviceRotation.Unlock()
	if time.Since(hongguoMainDeviceRotation.at) < hongguoMainDeviceRotateCooldown {
		return false
	}
	hongguoMainDeviceRotation.at = time.Now()
	return true
}

var hongguoPlayURLPattern = regexp.MustCompile(`^https?://\S+$`)
var hongguoFallbackCodecTypes = []string{"1", "3"}

type hongguoPlayURLVersionError struct{ version int }

func (e *hongguoPlayURLVersionError) Error() string {
	return fmt.Sprintf("红果备用线路编码版本 %d 暂不支持", e.version)
}

func hongguoPlaybackQuery(deviceID, installID string) map[string]string {
	return map[string]string{
		"aid": "8662", "app_name": "novelread", "version_code": hongguoAppVersionCode, "version_name": hongguoAppVersionName,
		"channel": "vivo_8662_64", "device_platform": "android", "device_type": "PGT-AN10", "os_version": "12",
		"update_version_code": hongguoAppVersionCode, "iid": installID, "cdid": uuidLike(), "device_id": deviceID,
	}
}

func hongguoVideoTabQuery(deviceID, installID, videoID string) map[string]string {
	values := map[string]string{}
	for key, list := range hongguoAppQuery(deviceID, installID) {
		if len(list) > 0 {
			values[key] = list[0]
		}
	}
	values["video_id"] = videoID
	values["video_id_type"] = "0"
	values["device_level"] = "1"
	values["need_all_video_definition"] = "1"
	values["need_mp4_align"] = "0"
	values["use_os_player"] = "0"
	values["video_platform"] = "1024"
	values["source"] = "0"
	values["from_video_id"] = ""
	return values
}

// hongguoV5Request performs one V5-signed request (the video_tab GET or the
// player POST), rotating the device identity on empty responses like the
// reference client.
func (downloader *Downloader) hongguoV5Request(ctx context.Context, helper bool, base, path string, buildValues func(deviceID, installID string) map[string]string, body []byte) (map[string]any, error) {
	client := downloader.hongguoClient()
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
	values := buildValues(deviceID, installID)
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
		method := http.MethodPost
		var reader io.Reader
		if body == nil {
			method = http.MethodGet
		} else {
			reader = bytes.NewReader(body)
		}
		request, err := http.NewRequestWithContext(ctx, method, base+path, reader)
		if err != nil {
			return nil, err
		}
		request.Header.Set("User-Agent", hongguoPlaybackUserAgent)
		request.Header.Set("Accept", "application/json")
		response, err := downloader.doPreparedCatalogRequest(request, 20*time.Second, func(prepared *http.Request) {
			signedURL, headers, signErr := signHongguoPlaybackV5(base+path, values, body, time.Now().UnixMilli(), nil)
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
			lastErr = errHongguoEmptyBody
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
				lastErr = fmt.Errorf("%w（设备注册失败：%v）", errHongguoEmptyBody, registerErr)
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
			return nil, fmt.Errorf("%w（返回格式异常）", errHongguoEmptyBody)
		}
		code := firstNonEmpty(mapString(result, "code", "Code", "status_code"), mapString(nestedMap(result, "BaseResp"), "StatusCode"))
		if code != "" && code != "0" {
			return nil, fmt.Errorf("红果 App 接口暂不可用（%s）", truncate(code, 20))
		}
		return result, nil
	}
	return nil, lastErr
}

func hongguoModelFromEntry(data map[string]any) (map[string]any, error) {
	model, _ := data["video_model"].(map[string]any)
	if encoded, ok := data["video_model"].(string); ok && encoded != "" {
		encoded = strings.TrimSpace(encoded)
		if !strings.HasPrefix(encoded, "{") && !strings.HasPrefix(encoded, "[") {
			if decoded, err := decodeHongguoBase64(encoded); err == nil && len(decoded) > 0 {
				encoded = string(decoded)
			}
		}
		decoder := json.NewDecoder(strings.NewReader(encoded))
		decoder.UseNumber()
		parsed := map[string]any{}
		if err := decoder.Decode(&parsed); err != nil {
			return nil, errors.New("红果 App 播放信息格式异常")
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
	return model, nil
}

// hongguoMediaFromModel selects playable media from a playback model; when the
// model only carries codecs the player cannot use, it follows the model's
// fallback endpoint for a compatible codec like the reference client.
func (downloader *Downloader) hongguoMediaFromModel(ctx context.Context, model map[string]any) (providerMedia, error) {
	media, err := selectHongguoAppMedia(model)
	if err == nil {
		return media, nil
	}
	if !strings.Contains(err.Error(), "未返回兼容的媒体") {
		return providerMedia{}, err
	}
	return downloader.hongguoFallbackMedia(ctx, model)
}

func (downloader *Downloader) fetchHongguoTabMedia(ctx context.Context, videoID string, helper bool, platform string) (providerMedia, error) {
	client := downloader.hongguoClient()
	result, err := downloader.hongguoV5Request(ctx, helper, client.baseURL, hongguoVideoTabPath, func(deviceID, installID string) map[string]string {
		values := hongguoVideoTabQuery(deviceID, installID, videoID)
		if platform != "" {
			values["device_platform"] = platform
		}
		return values
	}, nil)
	if err != nil {
		return providerMedia{}, err
	}
	data, _ := nestedMap(result, "data", "video_model_data")[videoID].(map[string]any)
	if len(data) == 0 {
		return providerMedia{}, errors.New("红果 App 未返回所请求的分集播放信息")
	}
	model, err := hongguoModelFromEntry(data)
	if err != nil {
		return providerMedia{}, err
	}
	return downloader.hongguoMediaFromModel(ctx, model)
}

func (downloader *Downloader) fetchHongguoPlayerMedia(ctx context.Context, videoID string, helper bool, platform string) (providerMedia, error) {
	payload := map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": 1, "disable_digg_stat": false, "disable_video_relate_book": false,
			"need_all_video_definition": true, "need_mp4_align": false, "use_os_player": false, "use_server_dns": false,
			"video_platform": 1024,
		},
		"mixed_video_id_map": map[string]any{"1004": []string{videoID}},
		"dr_scene":           "player",
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return providerMedia{}, err
	}
	client := downloader.hongguoClient()
	result, err := downloader.hongguoV5Request(ctx, helper, client.playbackBaseURL, hongguoPlaybackPath, func(deviceID, installID string) map[string]string {
		values := hongguoPlaybackQuery(deviceID, installID)
		if platform != "" {
			values["device_platform"] = platform
		}
		return values
	}, body)
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
	model, err := hongguoModelFromEntry(data)
	if err != nil {
		return providerMedia{}, err
	}
	return downloader.hongguoMediaFromModel(ctx, model)
}

// fetchHongguoPlaybackMedia mirrors the reference client: the video_tab
// interface is primary and the player interface is the fallback; a model with
// no compatible media, or an empty response, is reported immediately so the
// caller can switch platform or device lanes.
func (downloader *Downloader) fetchHongguoPlaybackMedia(ctx context.Context, videoID string, helper bool, platform string) (providerMedia, error) {
	media, tabErr := downloader.fetchHongguoTabMedia(ctx, videoID, helper, platform)
	if tabErr == nil {
		return media, nil
	}
	if errors.Is(tabErr, errHongguoNoCompatibleMedia) || errors.Is(tabErr, errHongguoEmptyBody) {
		return providerMedia{}, tabErr
	}
	media, err := downloader.fetchHongguoPlayerMedia(ctx, videoID, helper, platform)
	if err == nil {
		return media, nil
	}
	if errors.Is(err, errHongguoNoCompatibleMedia) || errors.Is(err, errHongguoEmptyBody) {
		return providerMedia{}, err
	}
	return providerMedia{}, fmt.Errorf("%v；播放器接口：%v", tabErr, err)
}

func (downloader *Downloader) hongguoFallbackMedia(ctx context.Context, model map[string]any) (providerMedia, error) {
	endpoint := mapString(nestedMap(model, "fallback_api"), "fallback_api")
	if endpoint == "" {
		return providerMedia{}, errHongguoNoCompatibleMedia
	}
	var lastErr error
	for _, codecType := range hongguoFallbackCodecTypes {
		data, err := downloader.fetchHongguoFallbackPlay(ctx, endpoint, codecType)
		if err == nil {
			var variants []any
			variants, err = hongguoFallbackVariants(data)
			if err == nil {
				var media providerMedia
				media, err = selectHongguoAppMedia(map[string]any{"video_list": variants, "video_duration": mapString(data, "video_duration")})
				if err == nil {
					return media, nil
				}
				if strings.Contains(err.Error(), "未返回兼容的媒体") {
					err = errHongguoNoCompatibleMedia
				}
			}
		}
		if errors.Is(err, errHongguoNoCompatibleMedia) {
			lastErr = err
			continue
		}
		return providerMedia{}, fmt.Errorf("%v；备用线路：%v", errHongguoNoCompatibleMedia, err)
	}
	return providerMedia{}, fmt.Errorf("%w；备用线路：%v", errHongguoNoCompatibleMedia, lastErr)
}

func (downloader *Downloader) fetchHongguoFallbackPlay(ctx context.Context, endpoint, codecType string) (map[string]any, error) {
	parsed, err := url.Parse(endpoint)
	if err != nil {
		return nil, fmt.Errorf("红果备用线路请求失败：%v", err)
	}
	query := parsed.Query()
	query.Set("codec_type", codecType)
	parsed.RawQuery = query.Encode()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, parsed.String(), nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", hongguoPlaybackUserAgent)
	request.Header.Set("Accept", "application/json")
	response, err := downloader.doCatalogRequestWithTimeout(request, 20*time.Second)
	if err != nil {
		return nil, fmt.Errorf("红果备用线路请求失败：%v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("红果备用线路 HTTP %d", response.StatusCode)
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, providerMaxBodyBytes+1))
	if err != nil {
		return nil, err
	}
	var result map[string]any
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&result); err != nil || result == nil {
		return nil, errors.New("红果备用线路未返回有效数据")
	}
	data := nestedMap(result, "video_info", "data")
	if len(data) == 0 {
		return nil, errors.New("红果备用线路未返回有效数据")
	}
	return data, nil
}

func hongguoFallbackVariants(data map[string]any) ([]any, error) {
	seed := mapString(data, "key_seed")
	entries := anyList(data["video_list"])
	if rows, ok := data["video_list"].(map[string]any); ok && len(entries) == 0 {
		keys := make([]string, 0, len(rows))
		for key := range rows {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			entries = append(entries, rows[key])
		}
	}
	var variants []any
	var versionErr error
	decoded := 0
	for _, row := range entries {
		entry, _ := row.(map[string]any)
		if entry == nil {
			continue
		}
		variant := map[string]any{
			"gear_des_key": mapString(entry, "gear_des_key"),
			"video_meta": map[string]any{
				"codec_type": mapString(entry, "codec_type"),
				"definition": mapString(entry, "definition"),
				"vwidth":     mapString(entry, "vwidth"),
				"vheight":    mapString(entry, "vheight"),
			},
		}
		for _, key := range []string{"main_url", "backup_url_1", "backup_url_2"} {
			address, err := decodeHongguoPlayURL(mapString(entry, key), seed)
			if err != nil {
				var versionError *hongguoPlayURLVersionError
				if errors.As(err, &versionError) {
					versionErr = err
					continue
				}
				return nil, err
			}
			if address != "" {
				variant[key] = address
				decoded++
			}
		}
		spade := mapString(entry, "spade_a")
		method := mapString(entry, "encryption_method")
		if spade != "" || method != "" || entry["encrypt"] == true {
			variant["encrypt_info"] = map[string]any{"spade_a": spade, "encryption_method": method, "encrypt": entry["encrypt"] == true}
		}
		variants = append(variants, variant)
	}
	if versionErr != nil && decoded == 0 {
		return nil, versionErr
	}
	return variants, nil
}

// decodeHongguoPlayURL unwraps a fallback play address sealed by the server;
// plain addresses and values that do not carry the seal pass through as-is.
func decodeHongguoPlayURL(encoded, seed string) (string, error) {
	if encoded == "" || seed == "" {
		return encoded, nil
	}
	seedBytes, seedErr := decodeHongguoBase64(seed)
	raw, rawErr := decodeHongguoBase64(encoded)
	if seedErr != nil || rawErr != nil {
		return encoded, nil
	}
	if len(raw) < 20 || raw[0] != 0xa8 || raw[1] != 0x00 || (len(raw)-4)%16 != 0 {
		return encoded, nil
	}
	if address := decryptHongguoPlayURL(raw, seedBytes); address != "" {
		return address, nil
	}
	return "", &hongguoPlayURLVersionError{version: int(raw[2]) | int(raw[3])<<8}
}

func decryptHongguoPlayURL(raw, seed []byte) string {
	salt, err := hex.DecodeString(hongguoPlayURLSalt)
	if err != nil {
		return ""
	}
	seedHash := sha512.Sum512(seed)
	digestInput := make([]byte, 0, sha512.Size+len(salt))
	digestInput = append(digestInput, seedHash[:]...)
	digestInput = append(digestInput, salt...)
	digest := sha512.Sum512(digestInput)
	block, err := aes.NewCipher(digest[:16])
	if err != nil {
		return ""
	}
	ciphertext := raw[4:]
	plain := make([]byte, len(ciphertext))
	cipher.NewCBCDecrypter(block, digest[16:32]).CryptBlocks(plain, ciphertext)
	if len(plain) == 0 {
		return ""
	}
	pad := int(plain[len(plain)-1])
	if pad < 1 || pad > aes.BlockSize || pad > len(plain) {
		return ""
	}
	for _, value := range plain[len(plain)-pad:] {
		if int(value) != pad {
			return ""
		}
	}
	address := string(plain[:len(plain)-pad])
	if !hongguoPlayURLPattern.MatchString(address) {
		return ""
	}
	return address
}

func hongguoAppMediaError(skipped []error) error {
	unsupported, blocked := false, false
	for _, err := range skipped {
		unsupported = unsupported || errors.Is(err, errHongguoNoCompatibleMedia)
		blocked = blocked || errors.Is(err, errHongguoEmptyBody)
	}
	switch {
	case unsupported && blocked:
		return fmt.Errorf("红果 App 两条取流车道都没成功：既有只给不兼容编码的分集，接口也在拦截本次设备：%w；%w", errHongguoNoCompatibleMedia, errHongguoEmptyBody)
	case unsupported:
		return errHongguoNoCompatibleMedia
	default:
		return fmt.Errorf("红果 App 接口对本次设备签名返回空响应，风控未放行，换设备重试也没通过：%w", errHongguoEmptyBody)
	}
}

// resolveHongguoPlaybackV5 mirrors the reference client's lane flow: the
// platform hands out different codecs per device_platform and may answer one
// identity with empty responses while serving another, so each device is
// tried with the default platform and then the pc platform; empty responses
// additionally rotate the helper device, and finally the primary device (at
// most once per cooldown, to stay clear of registration rate limits).
func (downloader *Downloader) resolveHongguoPlaybackV5(ctx context.Context, videoID string) (providerMedia, error) {
	if !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果视频 ID 无效")
	}
	if media, err := downloader.resolveHongguoPlaybackPure(ctx, videoID); err == nil {
		return media, nil
	}
	var skipped []error
	run := func(helper bool) (providerMedia, bool, error) {
		for _, platform := range []string{"", "pc"} {
			media, err := downloader.fetchHongguoPlaybackMedia(ctx, videoID, helper, platform)
			if err == nil {
				return media, true, nil
			}
			if !errors.Is(err, errHongguoNoCompatibleMedia) && !errors.Is(err, errHongguoEmptyBody) {
				return providerMedia{}, false, err
			}
			skipped = append(skipped, err)
		}
		return providerMedia{}, false, nil
	}
	media, ok, err := run(false)
	if err != nil {
		return providerMedia{}, err
	}
	if ok {
		return media, nil
	}
	blocked := false
	for _, err := range skipped {
		blocked = blocked || errors.Is(err, errHongguoEmptyBody)
	}
	if !blocked {
		return providerMedia{}, hongguoAppMediaError(skipped)
	}
	client := downloader.hongguoClient()
	helperID, _, _ := client.device(true)
	if rotateErr := downloader.ensureHongguoDevice(ctx, true, helperID); rotateErr != nil {
		skipped = append(skipped, rotateErr)
	} else if media, ok, err := run(true); err != nil {
		skipped = append(skipped, err)
	} else if ok {
		return media, nil
	}
	mainID, _, _ := client.device(false)
	if mainID != "" && takeHongguoMainDeviceRotation() {
		if rotateErr := downloader.ensureHongguoDevice(ctx, false, mainID); rotateErr != nil {
			skipped = append(skipped, rotateErr)
		} else if media, ok, err := run(false); err != nil {
			skipped = append(skipped, err)
		} else if ok {
			return media, nil
		}
	}
	return providerMedia{}, hongguoAppMediaError(skipped)
}
