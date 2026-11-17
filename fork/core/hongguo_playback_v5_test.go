package core

import (
	"strings"
	"testing"
)

// counterReader mirrors the oracle's deterministic randomBytes stream:
// the i-th byte produced in the process is i & 255.
type counterReader struct{ next int }

func (reader *counterReader) Read(p []byte) (int, error) {
	for index := range p {
		p[index] = byte(reader.next & 255)
		reader.next++
	}
	return len(p), nil
}

func TestSignHongguoPlaybackV5MatchesOracle(t *testing.T) {
	// Reset the process-lifetime Medusa state so the oracle's stream aligns.
	v5ProcessMu.Lock()
	v5Process = nil
	v5ProcessMu.Unlock()

	values := map[string]string{
		"aid": "8662", "app_name": "novelread", "version_code": "74332", "version_name": "7.4.3.32",
		"channel": "vivo_8662_64", "device_platform": "android", "device_type": "PGT-AN10", "os_version": "12",
		"update_version_code": "74332", "iid": "1234567890123456789",
		"cdid": "00000000-1111-2222-3333-444444444444", "device_id": "9876543210987654321",
	}
	url, headers, err := signHongguoPlaybackV5(
		"https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1",
		values, []byte(`{"biz_param":{"device_level":1}}`), 1763430000000, &counterReader{})
	if err != nil {
		t.Fatal(err)
	}
	wantURL := "https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1?_rticket=1763430000015&aid=8662&app_name=novelread&cdid=00000000-1111-2222-3333-444444444444&channel=vivo_8662_64&device_id=9876543210987654321&device_platform=android&device_type=PGT-AN10&iid=1234567890123456789&os_version=12&update_version_code=74332&version_code=74332&version_name=7.4.3.32"
	if url != wantURL {
		t.Errorf("url mismatch:\n got %s\nwant %s", url, wantURL)
	}
	wantHeaders := map[string]string{
		"X-Khronos":   "1763430000",
		"X-Helios":    "AAECA23pdG4AQ9XYLV5T+J3KK1Wl71BYsp3J36XftUuWs5HI",
		"X-SS-STUB":   "6CDB284A57ECD97E8F32E8C1253BDB09",
		"Content-Type": "application/json; charset=utf-8",
	}
	for key, want := range wantHeaders {
		if headers[key] != want {
			t.Errorf("header %s mismatch:\n got %s\nwant %s", key, headers[key], want)
		}
	}
	wantMedusa := "dc4baV2FVKM5uxYqT3u1RVKj1z8aGwABOco+FyAlgboIWOHmlZXixNcyut3jjCfls/kNZ5vDsNAwyMMBQAVCjBis7et1fk9xmxlTOK6xjDZaJ+cj640hAPipdvBNfNIM3awI1fc96oIHhBAraXZA56HtZ4DYmcTiv8RbSviJPItEU5J8D/vPWG49G8TXDUo4oA5Y0xuxfjYCRJMcs4TQRnBLmDIfzhaq9e76S5m5sp7+TW2nl2TnZxriJw3kkTpdG4z2FAt+HvlA8F8NlVVo/2xkDHjiVRfFgYeG0NfBNHTFzh3gmknOTSNK/BdhtYBbhTd7dC07lv3whaSPLbESrk4EApa9RXUsyQWbpMOD1GUtYdBTrLYt9iaJatpRrxZGpSfsyey8o26oaJLcaPTq7/xg3mU88Plo+xPCSEv6y2+YeaQ//N4SVh+3UGx197MJFSE/jEWEm8K1Xu/tI2s9u/ard0Q4hVeepq+a7fTqWLulD/65yT8gNs1OMqARMfNLhp4xI6Ozx2eTUXm66mu56dnzkERXpr+Dpx6gnfEcr4KYcvmefo6unkkiNo/Lr2wd0SX6J8LiMUZC+w/eH8qLFRaewlKKXNYSbLpR4aYyxX823vG5MW6kuzph6d1teEAZkIHFEGYH6yAC/v//H/7//x8cHQ=="
	if headers["X-Medusa"] != wantMedusa {
		t.Errorf("X-Medusa mismatch:\n got %s\nwant %s", headers["X-Medusa"], wantMedusa)
	}
	if !strings.HasPrefix(headers["X-Medusa"], "dc4baV2FVKM5") {
		t.Errorf("X-Medusa prefix drifted: %s", headers["X-Medusa"][:16])
	}
}

func TestSignHongguoPlaybackV5MatchesOracleNoBody(t *testing.T) {
	v5ProcessMu.Lock()
	v5Process = nil
	v5ProcessMu.Unlock()

	values := map[string]string{
		"aid": "8662", "app_name": "novelread", "version_code": "74332", "version_name": "7.4.3.32",
		"channel": "vivo_8662_64", "device_platform": "android", "device_type": "PGT-AN10", "os_version": "12",
		"update_version_code": "74332", "iid": "555000111222333444",
		"cdid": "abcdef01-2345-6789-abcd-ef0123456789", "device_id": "111222333444555666",
	}
	url, headers, err := signHongguoPlaybackV5(
		"https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1",
		values, nil, 1763501234567, &counterReader{})
	if err != nil {
		t.Fatal(err)
	}
	oracle := oracleCase2
	if url != oracle.url {
		t.Errorf("url mismatch:\n got %s\nwant %s", url, oracle.url)
	}
	for key, want := range oracle.headers {
		if headers[key] != want {
			t.Errorf("header %s mismatch:\n got %s\nwant %s", key, headers[key], want)
		}
	}
	if len(headers) != len(oracle.headers) {
		t.Errorf("header count mismatch: got %v", headers)
	}
}

var oracleCase2 = struct {
	url     string
	headers map[string]string
}{
	url: "https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1?_rticket=1763501234568&aid=8662&app_name=novelread&cdid=abcdef01-2345-6789-abcd-ef0123456789&channel=vivo_8662_64&device_id=111222333444555666&device_platform=android&device_type=PGT-AN10&iid=555000111222333444&os_version=12&update_version_code=74332&version_code=74332&version_name=7.4.3.32",
	headers: map[string]string{
		"X-Khronos": "1763501234",
		"X-Helios": "AAECA+AarbFTv9IzwAot4wKQ30ql71BYsp3J36XftUuWs5HI",
		"X-Medusa": "t+QcaZ+vU6P7kREqjVGyRZCJ0D8aGwABIco+HzAhAQkKWJ2SjAfLHfN629TO6HfD4BE3xbpi2PR7UAz0lBYA7VPftRQAAu1UNDUxrqblsefxiymzLwi9Wx3efnssQJLGyL0gk7BINH40b/UJrNBRvFRljyMWJT4wsRJhhRzrwAtBuliJ1CzQ2amlBN4yMrKsfjprfimOseQU5cGW3ET5oCtI9xPzcgBVDSSmIiq/z6O2KZwmQEBCQQQtnqonxUb1dRWT+/DoYGlqg9iqCD6YN279+JAZ5erOKM5TMVNC/675WbPsn8J7YrWyxArCIHbV4NRrVxa73cuNX3/6HBDxWP1+Utw9e0oRq0m0NwKrZ6DwzPGo32Fp7qcRJccCUrvLavAsvxsGLiC9PtF90fvPR9wKBaJ5sPcnLpnCzXnjmveMVTQO7AM9SA82bRuogd2FOMr7EGXnjnB8gFZTFwn93M6SkgkxOYsZGixGGrXqSrHMuDlds3gIljCIWBEVHHNGYcXxuoiiG5JVWFQDKTGu6s5EGq5kF6s4eE7EDifaK39M1QT3WqI3WOgPDmnSog1m6ruhQAgL9GhXIDWzPZfaUAFOHEKBQGB40ooxNT2hlQvUFtSeC5Qnhlx9buwu8P7xsuorUScocf8f/v//H/7/HB0=",
	},
}
