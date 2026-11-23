package core

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

type hongguoLaneFixture struct {
	registered int
	tabs       []hongguoLaneRequest
}

type hongguoLaneRequest struct {
	platform string
	deviceID string
}

func (fixture *hongguoLaneFixture) downloader(t *testing.T, tab func(request *http.Request) (int, string)) *Downloader {
	t.Helper()
	return sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if request.URL.Path == "/service/2/device_register/" {
			fixture.registered++
			id := strconv.Itoa(9000 + fixture.registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		if request.URL.Path == "/reading/bookapi/video_tab/multi_video_model/v1/" {
			fixture.tabs = append(fixture.tabs, hongguoLaneRequest{
				platform: request.URL.Query().Get("device_platform"),
				deviceID: request.URL.Query().Get("device_id"),
			})
			status, body := tab(request)
			return sourceFixtureResponse(request, status, body), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
	})
}

func hongguoTabBody(videoID, model string) string {
	return `{"code":0,"data":{"video_model_data":{"` + videoID + `":{"video_model":` + model + `}}}}`
}

const hongguoLaneH264Model = `{"video_duration":58.167,"video_list":[{"main_url":"https://media.example.invalid/main.mp4","video_meta":{"codec_type":"h264","definition":"720p"}}]}`

func TestHongguoPlaybackFlatPCModel(t *testing.T) {
	const spade = "lbwbxmKBGftitzL5Y7EtzVaKGsVRvC3zZ48b80uNN99klCyJiQ=="
	model := `{"video_duration":58.167,"key_seed":"unused","video_list":[` +
		`{"main_url":"https://media.example.invalid/360.mp4","definition":"360p","codec_type":"bytevc1","vwidth":360,"vheight":640,"encrypt":true,"encryption_method":"cenc-aes-ctr","kid":"kid-360","spade_a":"` + spade + `"},` +
		`{"main_url":"https://media.example.invalid/720.mp4","definition":"720p","codec_type":"bytevc1","vwidth":720,"vheight":1280,"encrypt":true,"encryption_method":"cenc-aes-ctr","kid":"kid-720","spade_a":"` + spade + `"}]}`
	fixture := &hongguoLaneFixture{}
	d := fixture.downloader(t, func(request *http.Request) (int, string) {
		return http.StatusOK, hongguoTabBody("800001", model)
	})
	media, err := d.fetchHongguoTabMedia(context.Background(), "800001", false, "pc")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.invalid/720.mp4" || media.Quality != 720 {
		t.Fatalf("unexpected flat pc media: %+v", media)
	}
	if media.Duration != 58167*time.Millisecond {
		t.Fatalf("unexpected duration: %v", media.Duration)
	}
	if len(media.CENCKey) != 16 {
		t.Fatalf("expected a 16 byte content key, got %d", len(media.CENCKey))
	}
	if len(media.Variants) != 2 {
		t.Fatalf("expected 2 variants, got %d", len(media.Variants))
	}
	if len(fixture.tabs) != 1 || fixture.tabs[0].platform != "pc" {
		t.Fatalf("unexpected tab requests: %+v", fixture.tabs)
	}
}

func TestHongguoPlaybackEmptyResponseRetriesOnPCLane(t *testing.T) {
	fixture := &hongguoLaneFixture{}
	d := fixture.downloader(t, func(request *http.Request) (int, string) {
		if request.URL.Query().Get("device_platform") != "pc" {
			return http.StatusOK, ""
		}
		return http.StatusOK, hongguoTabBody("800001", hongguoLaneH264Model)
	})
	media, err := d.resolveHongguoAppMedia(context.Background(), "800001")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.invalid/main.mp4" {
		t.Fatalf("unexpected media: %+v", media)
	}
	foundPC := false
	for _, tab := range fixture.tabs {
		foundPC = foundPC || tab.platform == "pc"
	}
	if !foundPC {
		t.Fatalf("pc lane was never tried: %+v", fixture.tabs)
	}
}

func TestHongguoPlaybackEmptyResponsesRotateDevice(t *testing.T) {
	fixture := &hongguoLaneFixture{}
	var original string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if request.URL.Path == "/service/2/device_register/" {
			fixture.registered++
			id := strconv.Itoa(9000 + fixture.registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		if request.URL.Path == "/reading/bookapi/video_tab/multi_video_model/v1/" {
			if request.URL.Query().Get("device_id") == original {
				return sourceFixtureResponse(request, http.StatusOK, ""), nil
			}
			return sourceFixtureResponse(request, http.StatusOK, hongguoTabBody("800001", hongguoLaneH264Model)), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
	})
	original = d.hongguoClient().state.DeviceID
	media, err := d.resolveHongguoAppMedia(context.Background(), "800001")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.invalid/main.mp4" {
		t.Fatalf("unexpected media: %+v", media)
	}
	if fixture.registered == 0 {
		t.Fatal("device was never rotated")
	}
}

func TestHongguoPlaybackAllEmptyReportsBlocked(t *testing.T) {
	fixture := &hongguoLaneFixture{}
	d := fixture.downloader(t, func(request *http.Request) (int, string) {
		return http.StatusOK, ""
	})
	_, err := d.resolveHongguoAppMedia(context.Background(), "800001")
	if err == nil {
		t.Fatal("expected an error")
	}
	if !errors.Is(err, errHongguoEmptyBody) || !strings.Contains(err.Error(), "风控未放行") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestHongguoPlaybackIncompatibleRetriesOnPCLane(t *testing.T) {
	vvcModel := `{"video_duration":58.167,"video_list":[{"main_url":"https://media.example.invalid/vvc.mp4","video_meta":{"codec_type":"bytevc2","definition":"720p"},"gear_des_key":"1:encrypt|2:bytevc2|4:720p"}]}`
	pcModel := `{"video_duration":58.167,"video_list":[{"main_url":"https://media.example.invalid/pc720.mp4","definition":"720p","codec_type":"bytevc1","vwidth":720,"vheight":1280}]}`
	fixture := &hongguoLaneFixture{}
	d := fixture.downloader(t, func(request *http.Request) (int, string) {
		if request.URL.Query().Get("device_platform") != "pc" {
			return http.StatusOK, hongguoTabBody("800001", vvcModel)
		}
		return http.StatusOK, hongguoTabBody("800001", pcModel)
	})
	media, err := d.resolveHongguoAppMedia(context.Background(), "800001")
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example.invalid/pc720.mp4" || media.Quality != 720 {
		t.Fatalf("unexpected media: %+v", media)
	}
	if len(fixture.tabs) < 2 || fixture.tabs[0].platform != "android" {
		t.Fatalf("unexpected lane order: %+v", fixture.tabs)
	}
	last := fixture.tabs[len(fixture.tabs)-1]
	if last.platform != "pc" || last.deviceID != fixture.tabs[0].deviceID {
		t.Fatalf("pc lane did not reuse the device: %+v", fixture.tabs)
	}
}
