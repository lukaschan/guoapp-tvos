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
	wantMedusa := "dc4baV2FVKM5uxYqT3u1RVKj1z8eHwABvMoCIzQhgboJGJbAkNtOsPoYBaX2bggWWPyvYUbZvT4JEFRltaQMY1uy8ZMNI+RFW4TNBS6c3MPfTxFOOcKA7JY7SshDTlMZ8EY6UYrOFQS+Xp5GK1EpMQ4Nr5DnUEtZjJgeCdq8uxqvs53nkwDQ09Y0IbmI1rc4rlPUyrjgli41zIOyPRIOgOwvhUQO9iV2WmzDNp6oCX5N+9mDSgKqpT+Urx4aAdNXBPfJuervx2IhchClv0+flLYD8ymlBsryqw7ZP1ppSXC8qbznNQn5oq7Qv6pW3exHPsUvy60f9mV1A7aiHW3oV9F9lTKcQcKOX2rc6gDiBk00gZUkKfsICGu+Iu4sM7cB0jDTuaKlN2DOGHaX2ge0YSMq1iEpk6HddGkkqrGbeRSd5ztE956cn9q+PlR9Gx89cXz6DDiOmvCbBZ2dgLsX1jSLl0ZZSWqk+bKMfxZc/IEF8kjcu9xli1iBSKwqMt6HCf9gOzSpQu/Q9jtT7iB/2pB5b3WrgxewTcj2X3WLteY1cZLo/0zo8pdcoKS3lpYpZi8OObLTsfhPfOUjgZZ5Rmr/BJ7qmiOYTtcp8MvJYNonNA8b3wYPneJyLFxcGotQzfcfQJkIVsS++GSU8jcsPm+Emm8feSvM8epvrqYRYHWSMVBqGXKGxdIIGUMGedjftO2qz9W0Xnz9kNwk70gwvh5bNVzbTSnchFLC4NCQRhi5n4/FdKImIZiFuB7dSos8vM70mXLpaLLSZqvHif8iiVK+jG8kXAlGnxX7Ms62v2FYvAhBS2npbitGliUgNY9xWLx4stRw2oxft5Xc8QsILBsLGvSu7/Fb0erSwM8gXaO8jf3qTq2xcoZlB9raXjes7gQXJhJTG7d2cncD/////v//f7ogIQ=="
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
		"X-Medusa": "t+QcaZ+vU6P7kREqjVGyRZCJ0D8eHwABQooCKzQlgQkLGHQipwIrtGDGHk1WOfAA5qP7+zguQpZEnFTaZjFDjuw0dTo6Zw3vvBVlkgTidg6HmGqtcb6MjoVxrcMPN2PF4BNCiZFx5hk4RJb0Wdq6F/zWM3LL2pq/Oqc6WDAfxT2j/61bHdTlzPkpqQF6RyctgTHHgPISTj3icF1RnZpYvWEjLpalMaLSbaGA2tSidTtNaih1sb+mykr5zzsRIqPhnYHCzD6c8+HD+C1d5eGlNE9cBUFAPcuU9bntKD727PGpH7rLZD/RfNixH1yc9ojMbStSrX7c7B/gpPleOEUBFOFgCqmf5kGd18AiRL7snH4piyKez76NRe6vMmbnCCwEnMgNBCRHJtLH6F8Nx9GmmOP6fnxy76qV0m+u+Y9vtoSltD+oaAs9BS/o2cKTBVuDS24irpe2+Nd9VYsB5Ux4ZH3dfMiZfySCvbirUAHgGYB5+wGAHx99IcNVBGBUyztHZUafd1nzwaPAD2ne68J3UaXRAZA3Z5EGYwaf25O+X2naAEYLjV17v00aooml3dhT9R6SzJdrlnaSFnnqxLnKPhzp5KKaG/38zXpBFtrUAETdB44uD7u4s94M/LWAPvQfywDzISefVqGIkLJTjUBqmSG9xKtQ3tt+g1vCZyFP+N17NcH/FLqgpvjZKByz0Yc37cK3xP2SBbK/gu33OV4+hUpEM98UTVhy5C7D3GhXzCQiVrrHxQtFrPcId9fjEv/Zb9yIPGbenmMVgf5oNRxy+bxfrt2BO828NcvhJvhFbhgZhxkX5uptx8q4pxZNyCW9j+6soZanJ6oXG+4I5doN/u0owZNpHa16oGsm5/w7yU8cw9J21fZE4IfpHYwky2aSBVxVKUXJKatu9f/+/////n+7ICE=",
	},
}
