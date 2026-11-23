package core

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

type hgFixtureWhole struct {
	ID     string `json:"id"`
	Inputs struct {
		RawQuery     string `json:"raw_query"`
		RecordDigest []byte `json:"record_digest"`
		FactorPB     []byte `json:"factor_pb"`
		Material     []byte `json:"material"`
		LicenseID    string `json:"license_id"`
		AID          string `json:"aid"`
		Seconds      uint64 `json:"seconds"`
		GorgonNonce  uint16 `json:"gorgon_nonce"`
		GorgonFlags  uint16 `json:"native_gorgon_flags"`
		HeliosRandom uint32 `json:"helios_random"`
		MedusaRand1  uint32 `json:"medusa_random1"`
		MedusaRand2  uint32 `json:"medusa_random2"`
		LocalAddr    uint64 `json:"local_buffer_address"`
		PrevState    uint32 `json:"previous_thread_state"`
	} `json:"inputs"`
	ExpectedHeaderSHA map[string]string `json:"expected_header_sha256"`
	ExpectedState     uint32            `json:"expected_thread_state"`
}

type hgFixtureTransform struct {
	Branch       int    `json:"branch"`
	Key          []byte `json:"key"`
	IV           []byte `json:"iv"`
	Plain        []byte `json:"plain"`
	ExpectedSHA  string `json:"expected_sha256"`
}

func TestHGCurrentComputeFixtures(t *testing.T) {
	raw, err := os.ReadFile("/home/hatch/workspace/iduanju/STVTests/Fixtures/hongguo/current_crypto.json")
	if err != nil {
		t.Skip("fixtures unavailable")
	}
	var doc struct {
		Whole      []hgFixtureWhole     `json:"whole"`
		Transforms []hgFixtureTransform `json:"transforms"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	sha := func(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
	for _, v := range doc.Whole {
		x := v.Inputs
		headers, state, err := hgCurCompute(x.RawQuery, x.RecordDigest, x.FactorPB, x.Material,
			x.LicenseID, x.AID, x.Seconds, x.GorgonNonce, x.GorgonFlags, x.HeliosRandom,
			x.MedusaRand1, x.MedusaRand2, x.LocalAddr, x.PrevState)
		if err != nil {
			t.Fatalf("%s: %v", v.ID, err)
		}
		if state != v.ExpectedState {
			t.Errorf("%s: state %d want %d", v.ID, state, v.ExpectedState)
		}
		for name, want := range v.ExpectedHeaderSHA {
			got, ok := headers[name]
			if !ok {
				t.Errorf("%s: missing header %s", v.ID, name)
				continue
			}
			if sha([]byte(got)) != want {
				t.Errorf("%s: header %s sha mismatch", v.ID, name)
			}
		}
	}
	for _, v := range doc.Transforms {
		out, err := hgCurTransform(v.Plain, v.Key, v.IV, v.Branch)
		if err != nil {
			t.Fatalf("transform: %v", err)
		}
		if sha(out) != v.ExpectedSHA {
			t.Errorf("transform branch %d sha mismatch", v.Branch)
		}
	}
}

func TestHGCurrentFactorFixtures(t *testing.T) {
	raw, err := os.ReadFile("/home/hatch/workspace/iduanju/STVTests/Fixtures/hongguo/current_factor.json")
	if err != nil {
		t.Skip("fixtures unavailable")
	}
	var cases []struct {
		ToySeed   int    `json:"toy_seed"`
		InputSeed int    `json:"public_input_seed"`
		Seconds   uint32 `json:"public_seconds"`
		SHA       string `json:"output_sha256"`
	}
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	for i, c := range cases {
		input := make([]byte, 52)
		for j := range input {
			input[j] = byte(j*37 + c.InputSeed)
		}
		out, err := hgCurFactor(input, c.Seconds, c.ToySeed)
		if err != nil {
			t.Fatalf("case %d: %v", i, err)
		}
		h := sha256.Sum256(out)
		if hex.EncodeToString(h[:]) != c.SHA {
			t.Errorf("case %d (selector %d seed %d sec %d) sha mismatch", i, c.ToySeed, c.InputSeed, c.Seconds)
		}
	}
}
