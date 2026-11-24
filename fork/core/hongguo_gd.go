package core

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

const hongguoGDRegisterURL = "https://log5-applog-lf.fqnovel.com/service/2/device_register/?tt_data=a&cronet_version=8d40f833_2026-03-03&ttnet_version=4.2.243.31-douyin&use_store_region_cookie=1"
const hongguoGDTabBase = "https://api5-normal-sinfonlineb.fqnovel.com/reading/bookapi/video_tab/multi_video_model/v1/"
const hongguoGDPlayerBaseB = "https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/player/v1"
const hongguoGDPlayerBaseA = "https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1"
const hongguoGDModelBaseA = "https://api5-normal-sinfonlinea.fqnovel.com/novel/player/video_model/v1/"
const hongguoGDModelBaseC = "https://api5-normal-sinfonlinec.fqnovel.com/novel/player/video_model/v1/"
const hongguoGDTabUA = "com.phoenix.read/73932 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)"
const hongguoGDPlayerUA = "com.phoenix.read/73932 (Linux; U; Android 12; zh_CN_#Hans; PGT-AN10; Build/V417IR;tt-ok/3.12.13.20)"
const hongguoGDRegisterUA = "com.phoenix.read/72232 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3)"

type hongguoGDIdentity struct {
	DeviceID string
	IID      string
	CDID     string
}

var hgGDState struct {
	sync.Mutex
	identity  *hongguoGDIdentity
	failUntil time.Time
	lastErr   error
}

func hongguoGDGzip(data []byte) ([]byte, error) {
	var buffer bytes.Buffer
	writer, err := gzip.NewWriterLevel(&buffer, gzip.DefaultCompression)
	if err != nil {
		return nil, err
	}
	if _, err := writer.Write(data); err != nil {
		return nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}

func hongguoGDResponseID(payload map[string]any, name string) string {
	value := payload[name+"_str"]
	if value == nil || value == "" {
		value = payload[name]
	}
	switch typed := value.(type) {
	case json.Number:
		if parsed, err := typed.Int64(); err == nil && parsed > 0 {
			return typed.String()
		}
	case string:
		typed = strings.TrimSpace(typed)
		if typed != "" && strings.Trim(typed, "0123456789") == "" && strings.Trim(typed, "0") != "" {
			return typed
		}
	}
	return ""
}

func (downloader *Downloader) hongguoGDRegister(ctx context.Context) (*hongguoGDIdentity, error) {
	now := time.Now().UnixMilli()
	cdid := uuidLike()
	openUDIDRaw := make([]byte, 8)
	if _, err := io.ReadFull(rand.Reader, openUDIDRaw); err != nil {
		return nil, err
	}
	header := map[string]any{
		"display_name": "红果免费短剧", "update_version_code": 73932, "manifest_version_code": 73932,
		"app_version_minor": "7.3.9.32", "aid": 8662, "channel": "update_64", "package": "com.phoenix.read",
		"app_version": "7.3.9.32", "version_code": 73932, "sdk_version": "3.7.0-rc.34-fanqie-xiaoshuo",
		"sdk_target_version": 29, "git_hash": "3a88f4e", "os": "Android", "os_version": "16", "os_api": 36,
		"device_model": "25053RT47C", "device_brand": "Redmi", "device_manufacturer": "Redmi",
		"cpu_abi": "arm64-v8a", "release_build": "b5e187f", "density_dpi": 520, "display_density": "mdpi",
		"resolution": "1280x2772", "language": "zh", "timezone": 8, "access": "wifi", "not_request_sender": 0,
		"carrier": "CHINA MOBILE", "mcc_mnc": "46000", "rom": "eng.root.20231116.160340",
		"rom_version": "W528JS release-keys", "cdid": cdid,
		"sig_hash": "56a962410c494bbaf0b58dba20cae56f", "openudid": hex.EncodeToString(openUDIDRaw),
		"clientudid": uuidLike(), "ipv6_list": []any{}, "region": "CN", "tz_name": "Asia/Shanghai",
		"tz_offset": 28800, "sim_region": "cn", "sim_serial_number": []any{}, "oaid_may_support": false,
		"req_id": uuidLike(), "device_platform": "android",
		"custom":                map[string]any{"account_region_src": "fallback", "account_region": "cn", "host_bit": 64, "dragon_device_type": "phone"},
		"pre_installed_channel": "", "apk_first_install_time": now, "is_system_app": 0, "sdk_flavor": "china", "guest_mode": 0,
	}
	envelope, err := json.Marshal(map[string]any{"magic_tag": "ss_app_log", "header": header, "_gen_time": now})
	if err != nil {
		return nil, err
	}
	compressed, err := hongguoGDGzip(envelope)
	if err != nil {
		return nil, err
	}
	salt, err := hex.DecodeString(hongguoPlayURLSalt)
	if err != nil {
		return nil, err
	}
	random := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, random); err != nil {
		return nil, err
	}
	inner := sha512.Sum512(random)
	derivedInput := make([]byte, 0, sha512.Size+len(salt))
	derivedInput = append(derivedInput, inner[:]...)
	derivedInput = append(derivedInput, salt...)
	derived := sha512.Sum512(derivedInput)
	block, err := aes.NewCipher(derived[:16])
	if err != nil {
		return nil, err
	}
	digest := sha512.Sum512(compressed)
	plaintext := make([]byte, 0, sha512.Size+len(compressed))
	plaintext = append(plaintext, digest[:]...)
	plaintext = append(plaintext, compressed...)
	pad := aes.BlockSize - len(plaintext)%aes.BlockSize
	for index := 0; index < pad; index++ {
		plaintext = append(plaintext, byte(pad))
	}
	ciphertext := make([]byte, len(plaintext))
	cipher.NewCBCEncrypter(block, derived[16:32]).CryptBlocks(ciphertext, plaintext)
	prefix, err := hex.DecodeString("746305100000")
	if err != nil {
		return nil, err
	}
	data := make([]byte, 0, len(prefix)+len(random)+len(ciphertext))
	data = append(data, prefix...)
	data = append(data, random...)
	data = append(data, ciphertext...)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, hongguoGDRegisterURL, bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	stub := md5.Sum(data)
	request.Header.Set("User-Agent", hongguoGDRegisterUA)
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/octet-stream;tt-data=a")
	request.Header.Set("log-encode-type", "gzip")
	request.Header.Set("x-ss-dp", "8662")
	request.Header.Set("x-ss-req-ticket", fmt.Sprintf("%d", now))
	request.Header.Set("x-vc-bdturing-sdk-version", "4.0.3.cn")
	request.Header.Set("lc", "101")
	request.Header.Set("sdk-version", "2")
	request.Header.Set("passport-sdk-version", "5051452")
	request.Header.Set("x-neptune", "-8|50:51:59:30:40:47:49:39")
	request.Header.Set("x-ss-stub", strings.ToUpper(hex.EncodeToString(stub[:])))
	response, err := downloader.doPreparedCatalogRequest(request, 20*time.Second, nil)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	content, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	if response.Header.Get("Content-Encoding") == "gzip" && len(content) > 0 {
		reader, gzErr := gzip.NewReader(bytes.NewReader(content))
		if gzErr == nil {
			if decoded, readErr := io.ReadAll(io.LimitReader(reader, 4<<20)); readErr == nil {
				content = decoded
			}
			reader.Close()
		}
	}
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("红果 GD 设备注册 HTTP %d", response.StatusCode)
	}
	var payload map[string]any
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&payload); err != nil {
		return nil, errors.New("红果 GD 设备注册返回格式异常")
	}
	if rawCode, ok := payload["code"].(json.Number); ok {
		if parsed, err := rawCode.Int64(); err != nil || parsed != 0 {
			return nil, errors.New("红果 GD 设备注册被拒绝")
		}
	}
	deviceID := hongguoGDResponseID(payload, "device_id")
	installID := hongguoGDResponseID(payload, "install_id")
	if deviceID == "" || installID == "" {
		return nil, errors.New("红果 GD 设备注册未返回设备标识")
	}
	return &hongguoGDIdentity{DeviceID: deviceID, IID: installID, CDID: cdid}, nil
}

func (downloader *Downloader) hongguoGDIdentity(ctx context.Context, force bool) (*hongguoGDIdentity, error) {
	hgGDState.Lock()
	if !force && hgGDState.identity != nil {
		identity := hgGDState.identity
		hgGDState.Unlock()
		return identity, nil
	}
	if time.Now().Before(hgGDState.failUntil) && hgGDState.lastErr != nil {
		err := hgGDState.lastErr
		hgGDState.Unlock()
		return nil, err
	}
	hgGDState.Unlock()
	identity, err := downloader.hongguoGDRegister(ctx)
	hgGDState.Lock()
	defer hgGDState.Unlock()
	if err != nil {
		hgGDState.failUntil = time.Now().Add(10 * time.Second)
		hgGDState.lastErr = err
		return nil, err
	}
	hgGDState.identity = identity
	hgGDState.lastErr = nil
	hgGDState.failUntil = time.Time{}
	return identity, nil
}

func hongguoGDSmallValues(identity *hongguoGDIdentity) map[string]string {
	return map[string]string{
		"aid": "8662", "app_name": "novelread", "version_code": "74332", "version_name": "7.4.3.32",
		"channel": "vivo_8662_64", "device_platform": "android", "device_type": "PGT-AN10", "os_version": "12",
		"update_version_code": "74332", "iid": identity.IID, "cdid": identity.CDID, "device_id": identity.DeviceID,
	}
}

func hongguoGDTabValues(identity *hongguoGDIdentity, videoID string) map[string]string {
	values := hongguoGDSmallValues(identity)
	for key, value := range map[string]string{
		"os": "android", "ssmix": "a", "manifest_version_code": "74332", "resolution": "1920*1080", "dpi": "280",
		"device_brand": "HONOR", "language": "zh", "os_api": "31", "ac": "wifi", "host_abi": "arm64-v8a",
		"dragon_device_type": "phone", "pv_player": "74332", "compliance_status": "0", "need_personal_recommend": "1",
		"player_so_load": "1", "is_android_pad_screen": "0", "rom_version": "V417IR+release-keys",
		"video_id": videoID, "video_id_type": "0", "device_level": "1",
		"need_all_video_definition": "1", "need_mp4_align": "0", "use_os_player": "0",
		"video_platform": "1024", "source": "0", "from_video_id": "",
	} {
		values[key] = value
	}
	return values
}

func hongguoGDParseMedia(content []byte, videoID string) (providerMedia, error) {
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
	if wrapped := mapValue(data, "1004"); wrapped != nil {
		data = wrapped
	}
	if wrapped := mapValue(data, "video_model_data"); wrapped != nil {
		data = wrapped
	}
	entry := mapValue(data, videoID)
	if entry == nil {
		entry = data
	}
	model, err := hongguoModelFromEntry(entry)
	if err != nil {
		return providerMedia{}, err
	}
	if len(model) == 0 {
		return providerMedia{}, errors.New("红果播放接口未返回所选分集")
	}
	return selectHongguoAppMedia(model)
}

type hongguoGDRoute struct {
	method string
	base   string
	values map[string]string
	body   []byte
	ua     string
}

func (downloader *Downloader) hongguoGDDo(ctx context.Context, route hongguoGDRoute) ([]byte, error) {
	signedURL, headers, err := signHongguoPlaybackV5(route.base, route.values, route.body, time.Now().UnixMilli(), nil)
	if err != nil {
		return nil, err
	}
	var reader io.Reader
	if route.body != nil {
		reader = bytes.NewReader(route.body)
	}
	request, err := http.NewRequestWithContext(ctx, route.method, signedURL, reader)
	if err != nil {
		return nil, err
	}
	for key, value := range headers {
		request.Header.Set(key, value)
	}
	request.Header.Set("User-Agent", route.ua)
	request.Header.Set("Accept", "application/json")
	if route.body != nil {
		request.Header.Set("Content-Encoding", "gzip")
	}
	response, err := downloader.doPreparedCatalogRequest(request, 15*time.Second, nil)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	content, err := io.ReadAll(io.LimitReader(response.Body, 16<<20))
	if err != nil {
		return nil, err
	}
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("红果 GD 取流 HTTP %d", response.StatusCode)
	}
	return content, nil
}

func (downloader *Downloader) hongguoGDRoutes(ctx context.Context, videoID string, identity *hongguoGDIdentity) (providerMedia, error) {
	batchPayload, err := json.Marshal(map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": 1, "disable_digg_stat": false, "disable_video_relate_book": false,
			"need_all_video_definition": true, "need_mp4_align": false, "use_os_player": false, "use_server_dns": false,
			"video_platform": 1024,
		},
		"mixed_video_id_map": map[string]any{"1004": []string{videoID}},
		"dr_scene":           "player",
	})
	if err != nil {
		return providerMedia{}, err
	}
	batchBody, err := hongguoGDGzip(batchPayload)
	if err != nil {
		return providerMedia{}, err
	}
	singlePayload, err := json.Marshal(map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": 3, "disable_digg_stat": false, "from_video_id": "",
			"need_all_video_definition": true, "need_mp4_align": false, "source": 9, "use_os_player": false,
			"use_server_dns": false, "video_platform": 3,
		},
		"content_type": 1004,
		"video_id":     videoID,
	})
	if err != nil {
		return providerMedia{}, err
	}
	singleBody, err := hongguoGDGzip(singlePayload)
	if err != nil {
		return providerMedia{}, err
	}
	small := hongguoGDSmallValues(identity)
	routes := []hongguoGDRoute{
		{method: http.MethodGet, base: hongguoGDTabBase, values: hongguoGDTabValues(identity, videoID), ua: hongguoGDTabUA},
		{method: http.MethodPost, base: hongguoGDPlayerBaseB, values: small, body: batchBody, ua: hongguoGDPlayerUA},
		{method: http.MethodPost, base: hongguoGDPlayerBaseA, values: small, body: batchBody, ua: hongguoGDPlayerUA},
		{method: http.MethodPost, base: hongguoGDModelBaseA, values: small, body: singleBody, ua: hongguoGDPlayerUA},
		{method: http.MethodPost, base: hongguoGDModelBaseC, values: small, body: singleBody, ua: hongguoGDPlayerUA},
	}
	var lastErr error = errHongguoEmptyBody
	for _, route := range routes {
		for attempt := 0; attempt < 2; attempt++ {
			content, err := downloader.hongguoGDDo(ctx, route)
			if err != nil {
				lastErr = err
				break
			}
			if len(content) == 0 {
				lastErr = errHongguoEmptyBody
				if attempt == 0 {
					select {
					case <-time.After(250 * time.Millisecond):
						continue
					case <-ctx.Done():
						return providerMedia{}, ctx.Err()
					}
				}
				break
			}
			media, parseErr := hongguoGDParseMedia(content, videoID)
			if parseErr == nil {
				return media, nil
			}
			lastErr = parseErr
			break
		}
	}
	return providerMedia{}, lastErr
}

func (downloader *Downloader) resolveHongguoPlaybackGD(ctx context.Context, videoID string) (providerMedia, error) {
	var lastErr error = errHongguoEmptyBody
	for round := 0; round < 2; round++ {
		identity, err := downloader.hongguoGDIdentity(ctx, round > 0)
		if err != nil {
			return providerMedia{}, err
		}
		media, err := downloader.hongguoGDRoutes(ctx, videoID, identity)
		if err == nil {
			return media, nil
		}
		lastErr = err
	}
	return providerMedia{}, lastErr
}
