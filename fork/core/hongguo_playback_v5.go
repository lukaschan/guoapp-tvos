package core

import (
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"math"
	"math/bits"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
)

func v5Le32(value uint32) []byte {
	return []byte{byte(value), byte(value >> 8), byte(value >> 16), byte(value >> 24)}
}

// v5rotl32 mirrors the JS rotl32: the shift is masked with & 31 first,
// so negative shifts wrap the same way.
func v5rotl32(value uint32, shift int32) uint32 {
	shift &= 31
	if shift == 0 {
		return value
	}
	return bits.RotateLeft32(value, int(shift))
}

func v5IV(queryHash, bodyMd5 []byte, ts int32) int32 {
	value := int32(0x20230928)
	for _, data := range [][]byte{queryHash, bodyMd5, v5Le32(uint32(ts))} {
		for index, b := range data {
			if index&1 == 0 {
				value = int32(uint32(value)>>4) ^ value ^ (value << 6) ^ int32(b)
			} else {
				value = ^(int32(uint32(value)>>7) ^ value ^ (int32(b) | (value << 12)))
			}
		}
	}
	return value
}

var v5HashTable = [64]uint32{
	0xebb64faf, 0x07aadcc2, 0xcf3187bf, 0xe01138ff, 0x6d0bfcff, 0x5a30a3be, 0xb41ad638, 0x34180eb8,
	0xf233eb6f, 0xb1a584cc, 0xccc30dc7, 0x47d1db51, 0xd55653de, 0x70a84fa1, 0x57473c12, 0xf76f0288,
	0x2c077f0a, 0xda0dcad0, 0xfbb86f6c, 0xfdc4cf00, 0x688a020d, 0xe676c6a6, 0x8cd6338b, 0x1a3c8d0e,
	0xcce8b06b, 0x6ad0ed0b, 0xa0522717, 0xdc71ac83, 0x2285db71, 0xd5b4dda6, 0x736f8650, 0x6560306c,
	0x617ce2a6, 0xe423417e, 0x0a40e143, 0x544e4032, 0x88dffb2a, 0x716c1ae0, 0x4c467a88, 0x05b23bb3,
	0xe1d0b866, 0xbaa3dcb8, 0xae3374d3, 0xc3381a50, 0x1702f75b, 0xfe6da368, 0xf0b4cf48, 0x4e0ffbb8,
	0x72aad10d, 0x26c53a3d, 0xf2bce0f6, 0xb4557581, 0x4a257fdd, 0x8c3182a2, 0xab0b3b86, 0x3d5dfb14,
	0x4f103634, 0xd37b52d7, 0x444eff16, 0xeb0a33d1, 0x6ca86f6e, 0x00284ba7, 0x08387cfa, 0x5fb37586,
}

func v5Hash(queryHash, bodyMd5 []byte, ts int32) ([]byte, error) {
	if len(queryHash) != 32 || len(bodyMd5) != 16 {
		return nil, errors.New("V5 hash requires a 32-byte query hash and a 16-byte body hash")
	}
	if v5IV(queryHash, bodyMd5, ts)&15 != 12 {
		return nil, errors.New("unsupported V5 hash branch")
	}
	var ivBits uint32 = 0x9d4a97c2
	iv := int32(ivBits)
	count := iv + ts
	table := make([]uint32, 64)
	for index, value := range v5HashTable {
		table[index] = v5rotl32(value, -((count+1)&255))
	}
	shift := uint((count + 2) & 7)
	padding := make([]byte, 4)
	for index, value := range []uint32{0xfa, 0x45, 0x61, 0xd7} {
		padding[index] = byte(((value | (value << 8)) >> shift) & 255)
	}
	data := make([]byte, 0, 64)
	data = append(data, queryHash...)
	data = append(data, bodyMd5...)
	data = append(data, v5Le32(uint32(ts))...)
	data = append(data, padding...)
	data = append(data, 0, 0, 0, 0, 0, 0, 1, 0xa0)
	words := make([]uint32, 0, 128)
	for index := 0; index < len(data); index += 4 {
		words = append(words, uint32(data[index])<<24|uint32(data[index+1])<<16|uint32(data[index+2])<<8|uint32(data[index+3]))
	}
	for index := 0; index < 112; index++ {
		x := words[index+1]
		y := words[index+14]
		words = append(words, words[index]+words[index+9]+
			(bits.RotateLeft32(x, 14) ^ bits.RotateLeft32(x, 25) ^ (x >> 3))+
			(bits.RotateLeft32(y, 13) ^ bits.RotateLeft32(y, 15) ^ (y >> 10)))
	}
	initialValues := [8]uint32{0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f, 984304912, 3005047866, 2874125293, 2152413264}
	var initial [8]uint32
	for index, value := range initialValues {
		initial[index] = v5rotl32(value, -count)
	}
	state := initial
	for index := 0; index < 96; index++ {
		base := iv + int32(index)
		choose := ((state[4] ^ state[0]) & state[1]) ^ state[4]
		sigma1 := bits.RotateLeft32(state[1], 26) ^ bits.RotateLeft32(state[1], 21) ^ bits.RotateLeft32(state[1], 7)
		mixed := words[base&127] + choose + sigma1 + table[base&63] + state[6]
		sigma0 := bits.RotateLeft32(state[3], 30) ^ bits.RotateLeft32(state[3], 19) ^ bits.RotateLeft32(state[3], 10)
		majority := (state[3] & state[5]) | ((state[3] | state[5]) & state[2])
		old := state[7]
		copy(state[1:], state[:7])
		state[0] = old
		state[7] = sigma0 + majority + mixed
		state[0] = old + mixed
	}
	digest := make([]byte, 32)
	for index := 0; index < 8; index++ {
		value := state[index] + initial[index]
		digest[index*4] = byte(value >> 24)
		digest[index*4+1] = byte(value >> 16)
		digest[index*4+2] = byte(value >> 8)
		digest[index*4+3] = byte(value)
	}
	folded := make([]byte, 16)
	for index := 0; index < 16; index++ {
		folded[index] = digest[index] ^ digest[index+16]
	}
	check := int32(0x20220420)
	for index := 0; index < 12; index++ {
		even := index&1 == 0
		var temp int32
		if even {
			temp = int32(uint32(check)>>3) ^ check
			check = (int32(folded[index]) ^ (check << 7)) ^ temp
		} else {
			temp = int32(uint32(check)>>5) ^ check
			check = (^(int32(folded[index]) | (check << 11))) ^ temp
		}
	}
	out := make([]byte, 0, 20)
	out = append(out, folded...)
	out = append(out, v5Le32(uint32(((check|4)^0x1000000)|0x20))...)
	return out, nil
}

var v5Magic = []byte{0x2d, 0x4b, 0x4f, 0xca, 0x49, 0x75, 0x0d, 0x43, 0x3f, 0xb5, 0xae, 0x2c, 0x22, 0x6d, 0xcc, 0x56}

var v5SignKey = []byte{
	0xb2, 0x3c, 0x2a, 0x47, 0x0a, 0x20, 0xd1, 0x05, 0xdc, 0x3f, 0x8c, 0x44, 0x38, 0xf8, 0x27, 0x2e,
	0xd4, 0x6d, 0x6c, 0x89, 0xff, 0xdc, 0xde, 0xdd, 0x51, 0x08, 0x69, 0x8d, 0x26, 0xe9, 0x48, 0x9d,
}

const v5SboxHex = "53290fe9e51f316f90f74a7e034d367784ab49237cd0135cdc632c322fd3be0e2624a417ecd9151a7ff64f60730a87f9445ec6ada2f865d22b696c4188f24c0d" +
	"f37b75510b939f6bc2fe6883e68bc8c722181ba0bdb08c9871b50c9a16b46eea8eed20ba4b8a14e0fcf1468dbbef05a93e5a9d7dcf06898635c1fd99f5de287a" +
	"80c594daaab19b6279fbd75070cb52eb2555c456e39e7839853874e2f0013ac0b64742d8ca10e4b79c955de8b843ce4ed464a6a72ed508091c92e7b3eedd1e1d" +
	"d12afac321618fa3d65f9167c982f43d66a53c6a1997585b346dbf9672ff37cdbc073b2dae11453304df00815476b2a13fccdb30b957a8acafe1274002485912" +
	"38922563e36406d37a24100b7902a028044e218453c2a399199c9d13dc40c55ba67e502273850ebdc1a2e2188b8f2d9e3cb909b8c46a2a9f4a6dd93007eafa65" +
	"b7b3a881aa908cc74f0ad76bbbb58617c37012ca05a469fd44e62eecf1e4272ce860c0ae5eadf99b20d8f0234174006f3f110d7657d01645d4eff8f71471cbfe" +
	"1cb2f52648727bf3c9de55153e031b4d61757db63dbf7782eeafe9018a8891362fb14759ac32bab03b349aeb5a377c5156be4c8dfbe13a684bda39cf836697c8" +
	"94545fe0f2491acea9fc6252f4ff1e0fe72bd2df6e67a7f635e5bcc6d1a5dd951d89960887a18eb40c785cdb1f80ed42299333ab98cdd67f316cd54346585dcc" +
	"d759fb722789b08807cc0fda293f7e5e1819bb0353517020b31d3d00374952bea2c421e862040a9ec892a05b266b7a0d0cc316f483b81af39715657ffe32ad8d" +
	"e0c13077646035236ee5363e5f900e9a7cf850a81cd9960b6df73317226f99eaa6fff15cec34acb98246639b918ab2851466a7cdfc4ad1b52c2ae95a58d3734e" +
	"47ddd5b7560193f644ef9c408b7dee39b4d6aabf4de761e3252d4c7ba3843187745d55e6a5db05d42b45caed43c0c5d0b64bfa9d94a4a9d8f2f0e1a108dcfd28" +
	"8fd2bc1fc7bd675412138169cb09249875ba3b68cfb11180afae104fc9789571c6dfce02413886796ae21e3c488cc21b9f423a066c2eabf98e2fdeeb5776e4f5" +
	"d09a515ba58cbbab3e37b09fd4f6d9244df80512e84cd7956be301cf64f1429d58577cc241f3a2c655144f81aaf95a4e108da894b38970561ae9002619fbbac9" +
	"1fa922ed202bfc62cb08e0de2a7f3631435f8b47c8a3c563b4db4071ce74c46da6fa696a9e282d1e825d663b93bfd56c48dce1884bb10fccea063929f746443f" +
	"d830a4232e53da21a1f2d1bdfebc3a02c10a1b8ad31d04fd616590d272ac737e98eb33af60528716bee78ec0ee8699031177277d9cff32542c67caf5f4459168" +
	"1335ae0e178f3409a7803db83892dde5b9b7f0c750e24aef077badd678a09b850b84ec1597e4963cb5e675df1c0d6fb618496ecd76c35c798325590c2fb27a5e"

var v5Sbox = func() []byte {
	decoded, err := hex.DecodeString(v5SboxHex)
	if err != nil || len(decoded) != 1024 {
		panic("invalid V5 sbox")
	}
	return decoded
}()

func v5Carrier(keyBytes, ivBytes, sourceBytes []byte, ts int32) ([]byte, error) {
	if len(keyBytes) != 16 || len(ivBytes) != 16 || len(sourceBytes) < 248 {
		return nil, errors.New("V5 carrier requires 16-byte key/IV and at least 248 source bytes")
	}
	variant := ts & 3
	box := v5Sbox[variant*256 : (variant+1)*256]
	con := [][4]int{{2, 0, 3, 1}, {1, 3, 2, 0}, {3, 2, 1, 0}, {2, 3, 1, 0}}[variant]
	order := [][16]int{
		{0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11},
		{0, 9, 14, 11, 4, 13, 2, 3, 8, 1, 6, 15, 12, 5, 10, 7},
		{0, 9, 14, 3, 4, 13, 2, 15, 8, 1, 6, 11, 12, 5, 10, 7},
		{0, 9, 14, 15, 4, 13, 2, 3, 8, 1, 6, 11, 12, 5, 10, 7},
	}[variant]
	initial := []uint32{0xbbb5de72, 0xd4638d5b, 0x92a5f73b, 0x89f8a1c9}[variant]
	initialBytes := v5Le32(initial)
	expanded := make([]byte, 48)
	for index := 0; index < 16; index++ {
		expanded[index] = initialBytes[index&3] ^ keyBytes[index]
	}
	rounds := 8
	for index := 4; index < 12; index++ {
		at := 4 * (index - 1)
		a, b, c, d := expanded[at], expanded[at+1], expanded[at+2], expanded[at+3]
		if index&3 == 0 {
			next := byte(((initial >> (rounds & 24)) ^ uint32(box[b])) & 255)
			b = box[c]
			c = box[d]
			d = box[a]
			a = next
		}
		rounds += 2
		expanded[at+4] = a ^ expanded[at-12]
		expanded[at+5] = b ^ expanded[at-11]
		expanded[at+6] = c ^ expanded[at-10]
		expanded[at+7] = d ^ expanded[at-9]
	}
	xt := func(value byte) byte {
		return byte((uint32(value) << 1) ^ map[bool]uint32{true: 0x1b, false: 0}[value&128 != 0]) & 255
	}
	block := func(value []byte) []byte {
		rows := make([][]byte, 4)
		for index := 0; index < 4; index++ {
			rows[index] = append([]byte(nil), value[index*4:index*4+4]...)
		}
		addCon := func(offset int) {
			for i := 0; i < 4; i++ {
				for j := 0; j < 4; j++ {
					rows[i][j] ^= expanded[(offset+i)*4+con[j]]
				}
			}
		}
		addCon(0)
		for round := 1; round <= 2; round++ {
			for i := 0; i < 4; i++ {
				for j := 0; j < 4; j++ {
					rows[i][j] = box[rows[i][j]]
				}
			}
			before := rows
			rows = [][]byte{before[con[0]], before[con[1]], before[con[2]], before[con[3]]}
			flat := make([]byte, 0, 16)
			for _, row := range rows {
				flat = append(flat, row...)
			}
			for index := 0; index < 16; index++ {
				rows[index/4][index%4] = flat[order[index]]
			}
			if round == 1 {
				for i := 0; i < 4; i++ {
					row := rows[i]
					rows[i] = []byte{row[con[0]], row[con[1]], row[con[2]], row[con[3]]}
				}
				for index := 0; index < 4; index++ {
					mixed := rows[0][index] ^ rows[1][index] ^ rows[2][index] ^ rows[3][index]
					first := rows[0][index]
					rows[0][index] ^= mixed ^ xt(rows[0][index]^rows[1][index])
					rows[1][index] ^= mixed ^ xt(rows[1][index]^rows[2][index])
					rows[2][index] ^= mixed ^ xt(rows[2][index]^rows[3][index])
					rows[3][index] ^= mixed ^ xt(rows[3][index]^first)
				}
			}
			addCon(round * 4)
		}
		for i := 0; i < 4; i++ {
			for j := 0; j < 4; j++ {
				rows[i][j] ^= expanded[(4+i)*4+j]
			}
		}
		out := make([]byte, 0, 16)
		for _, row := range rows {
			out = append(out, row...)
		}
		return out
	}
	wire := [8]int{6, 5, 3, 4, 2, 7, 1, 0}
	compact := [8]int{1, 7, 3, 6, 2, 0, 4, 5}
	plaintext := make([]byte, 32)
	for i := 0; i < 31; i++ {
		for j := 0; j < 8; j++ {
			plaintext[i] |= ((sourceBytes[i*8+j] >> wire[j]) & 1) << compact[j]
		}
	}
	plaintext[31] = 1
	input := make([]byte, 16)
	for index := 0; index < 16; index++ {
		input[index] = plaintext[index] ^ ivBytes[index]
	}
	first := block(input)
	for index := 0; index < 16; index++ {
		input[index] = plaintext[index+16] ^ first[index]
	}
	key := append(append([]byte(nil), first...), block(input)...)
	out := make([]byte, 0, len(sourceBytes)+1)
	out = append(out, key[31])
	out = append(out, sourceBytes...)
	for i := 0; i < 31; i++ {
		for j := 0; j < 8; j++ {
			at := 1 + i*8 + j
			out[at] = (out[at] &^ (1 << wire[j])) | (((key[i] >> compact[j]) & 1) << wire[j])
		}
	}
	return out, nil
}

func v5AppendUvarint(out []byte, value uint64) []byte {
	for value >= 0x80 {
		out = append(out, byte(value&0x7f)|0x80)
		value >>= 7
	}
	return append(out, byte(value))
}

type v5Field struct {
	tag     uint64
	num     int64
	fnum    float32
	bytes   []byte
	isNum   bool
	isFloat bool
}

func v5Num(tag uint64, value int64) v5Field    { return v5Field{tag: tag, num: value, isNum: true} }
func v5Bytes(tag uint64, value []byte) v5Field { return v5Field{tag: tag, bytes: value} }
func v5Str(tag uint64, value string) v5Field   { return v5Field{tag: tag, bytes: []byte(value)} }
func v5Float(tag uint64, value float32) v5Field {
	return v5Field{tag: tag, fnum: value, isFloat: true}
}

func v5Proto(fields []v5Field) []byte {
	out := []byte{}
	for _, field := range fields {
		if field.isNum {
			zigzag := uint64(field.num<<1) ^ uint64(field.num>>63)
			out = v5AppendUvarint(out, field.tag*8)
			out = v5AppendUvarint(out, zigzag)
		} else if field.isFloat {
			out = v5AppendUvarint(out, field.tag*8+5)
			out = append(out, v5Le32(math.Float32bits(field.fnum))...)
		} else if len(field.bytes) != 0 {
			out = v5AppendUvarint(out, field.tag*8+2)
			out = v5AppendUvarint(out, uint64(len(field.bytes)))
			out = append(out, field.bytes...)
		}
	}
	return out
}

func v5rotl8(value byte, shift uint) byte {
	return (value << shift) | (value >> (8 - shift))
}

func v5Xmxor(data, key []byte) []byte {
	encoded := make([]byte, len(data))
	for index := range data {
		at := (index * 4) & 28
		d0 := int(key[at])
		d1 := int(key[at+1])
		mixed := int(v5rotl8(data[index], 4)) + d0
		mixed = (^mixed) ^ d1
		mixed = int(v5rotl8(byte(mixed), 3))
		mixed = (mixed + d1) & 255
		mixed ^= d0
		encoded[len(data)-index-1] = byte(^mixed)
	}
	lastIndex := len(encoded) - 1
	last := int(encoded[lastIndex] ^ encoded[lastIndex-1])
	first := int(encoded[0])
	encoded[0] = byte(((^last) + first) & 255)
	encoded[1] = byte(((int(encoded[0]) ^ int(encoded[lastIndex]) ^ 254) + int(encoded[1])) & 255)
	encoded[2] = byte((int(encoded[2]) + ((last - first) ^ int(v5rotl8(encoded[1], 3)) ^ 2)) & 255)
	for index := 0; index < len(encoded)-4; index++ {
		mixed := int(v5rotl8(encoded[index+2], 3)) ^ int(encoded[index+1]) ^ (index + 3)
		encoded[index+3] = byte(((^mixed) + int(encoded[index+3])) & 255)
	}
	encoded[lastIndex] ^= encoded[lastIndex-1]
	sum := 0
	for index := 1; index < len(encoded); index++ {
		sum += int(encoded[index])
	}
	encoded[0] = byte(((int(encoded[0]) ^ int(encoded[1])) + sum) & 255)
	return encoded
}

func v5ReadU64(data []byte, offset int) uint64 {
	low := uint64(uint32(data[offset]) | uint32(data[offset+1])<<8 | uint32(data[offset+2])<<16 | uint32(data[offset+3])<<24)
	high := uint64(uint32(data[offset+4]) | uint32(data[offset+5])<<8 | uint32(data[offset+6])<<16 | uint32(data[offset+7])<<24)
	return low | (high << 32)
}

func v5WriteU64(data []byte, offset int, value uint64) {
	low := uint32(value)
	high := uint32(value >> 32)
	for index := 0; index < 4; index++ {
		data[offset+index] = byte(low >> (8 * index))
		data[offset+4+index] = byte(high >> (8 * index))
	}
}

func v5Pad16(data []byte) []byte {
	padding := 16 - (len(data) % 16)
	out := make([]byte, len(data)+padding)
	copy(out, data)
	for index := len(data); index < len(out); index++ {
		out[index] = byte(padding)
	}
	return out
}

func v5Helios(ts int64, random io.Reader) (string, error) {
	prefix := make([]byte, 4)
	if _, err := io.ReadFull(random, prefix); err != nil {
		return "", err
	}
	digest := md5.Sum(append(append([]byte(nil), prefix...), []byte("8662")...))
	ascii := []byte(hex.EncodeToString(digest[:]))
	left := v5ReadU64(ascii, 0)
	right := v5ReadU64(ascii, 8)
	queue := []uint64{v5ReadU64(ascii, 16), v5ReadU64(ascii, 24)}
	keys := make([]uint64, 0, 34)
	for index := 0; index < 34; index++ {
		keys = append(keys, left)
		mixed := (bits.RotateLeft64(right, -8) + left) ^ uint64(index)
		queue = append(queue, mixed)
		left = mixed ^ bits.RotateLeft64(left, 3)
		right = queue[0]
		queue = queue[1:]
	}
	data := v5Pad16([]byte(strconv.FormatInt(ts, 10) + "-646637794-8662"))
	for offset := 0; offset < len(data); offset += 16 {
		a := v5ReadU64(data, offset)
		b := v5ReadU64(data, offset+8)
		for _, key := range keys {
			b = key ^ (a + bits.RotateLeft64(b, -8))
			a = b ^ bits.RotateLeft64(a, 3)
		}
		v5WriteU64(data, offset, a)
		v5WriteU64(data, offset+8, b)
	}
	return base64.StdEncoding.EncodeToString(append(prefix, data...)), nil
}

type v5ProcessState struct {
	nonce   string
	started int64
}

var (
	v5ProcessMu sync.Mutex
	v5Process   *v5ProcessState
)

func v5Medusa(queryHash, f13 []byte, ts int32, who map[string]string, nowMs int64, random io.Reader) (string, error) {
	v5ProcessMu.Lock()
	if v5Process == nil {
		raw := make([]byte, 18)
		if _, err := io.ReadFull(random, raw); err != nil {
			v5ProcessMu.Unlock()
			return "", err
		}
		nonce := base64.StdEncoding.EncodeToString(raw)
		nonce = strings.ReplaceAll(nonce, "+", "-")
		nonce = strings.ReplaceAll(nonce, "/", "_")
		nonce = strings.TrimRight(nonce, "=")
		v5Process = &v5ProcessState{nonce: nonce, started: nowMs}
	}
	process := v5Process
	v5ProcessMu.Unlock()

	flags := []byte{0x44, 0x80, 0, 0, 0, 0, 0, 0}
	secToken := "A" + process.nonce
	if len(secToken) > 25 {
		secToken = secToken[:25]
	}
	brand := who["device_brand"]
	if brand == "" {
		brand = "HONOR"
	}
	deviceType := who["device_type"]
	deviceInfo := v5Proto([]v5Field{
		v5Num(1, 1), v5Num(2, 2), v5Str(3, "8662"), v5Str(4, who["device_id"]), v5Str(5, secToken),
		v5Str(6, "!noperm!"), v5Num(7, -888888), v5Num(8, -888888), v5Num(9, 3), v5Num(10, -888888),
		v5Str(11, "!notset!"), v5Str(12, "Asia/Shanghai,8"), v5Str(13, "zh_CN"), v5Num(14, 4),
		v5Float(16, 0), v5Float(17, 0), v5Float(18, 0), v5Float(19, 0), v5Float(20, 0), v5Float(21, 0),
		v5Str(22, who["os_version"]), v5Num(23, 41), v5Num(24, 36),
		v5Num(25, process.started), v5Num(26, process.started), v5Num(27, process.started), v5Num(28, nowMs),
		v5Num(29, -1),
		v5Str(30, deviceType), v5Str(31, brand), v5Str(32, deviceType), v5Str(33, deviceType),
		v5Str(34, brand), v5Str(35, brand), v5Str(36, brand), v5Num(38, 31),
	})
	envRand := make([]byte, 4)
	if _, err := io.ReadFull(random, envRand); err != nil {
		return "", err
	}
	envLaunch := 100 + int64(float64(uint32(envRand[0])|uint32(envRand[1])<<8)/65536.0*21)
	envPid := 10001 + int64(float64(uint32(envRand[2])|uint32(envRand[3])<<8)/65536.0*2000)
	envSub13 := v5Proto([]v5Field{v5Num(1, int64(ts)), v5Num(2, -2), v5Num(4, 200)})
	env := v5Proto([]v5Field{
		v5Num(1, envLaunch), v5Num(2, 247235599), v5Num(3, 247235596), v5Num(5, 7),
		v5Str(6, "v04.10.03.04-bugfix"), v5Num(7, envPid), v5Str(8, who["channel"]), v5Bytes(12, deviceInfo),
		v5Bytes(13, envSub13), v5Str(14, who["version_name"]),
	})
	field3 := make([]byte, 4)
	if _, err := io.ReadFull(random, field3); err != nil {
		return "", err
	}
	field3Value := uint32(field3[0]) | uint32(field3[1])<<8 | uint32(field3[2])<<16 | uint32(field3[3])<<24
	message := v5Proto([]v5Field{
		v5Bytes(1, v5Magic), v5Num(2, 5), v5Num(3, int64(field3Value)), v5Str(4, "8662"),
		v5Str(5, who["device_id"]), v5Str(6, "646637794"), v5Str(7, who["version_name"]), v5Str(8, "v04.10.03-ml-android"),
		v5Num(9, 0x040a0300), v5Bytes(10, flags), v5Num(12, int64(ts)), v5Bytes(13, f13), v5Bytes(14, queryHash[:6]),
		v5Bytes(15, v5Proto([]v5Field{v5Num(1, 305), v5Num(2, 4), v5Num(3, 694367), v5Num(5, 1621072674)})),
		v5Str(16, secToken), v5Num(17, int64(ts)), v5Str(20, "none"),
		v5Num(21, 312), v5Bytes(23, env),
		v5Str(24, `{"cmr":16777216,"cmr2":16777216,"un_h":11,"vpn":0,"kd":0,"dyn":"","do":1,"tk":true}`),
	})
	nonceBytes := make([]byte, 4)
	if _, err := io.ReadFull(random, nonceBytes); err != nil {
		return "", err
	}
	nonce := uint32(nonceBytes[0]) | uint32(nonceBytes[1])<<8 | uint32(nonceBytes[2])<<16 | uint32(nonceBytes[3])<<24
	hashInput := append(append(append([]byte(nil), v5SignKey...), v5Le32(nonce)...), v5SignKey...)
	hashArray := hongguoSM3(hashInput)
	hash := hashArray[:]
	high := (nonce >> 16) & 255
	seed := v5Le32(^(((high << 11) | (nonce >> 24)) ^ (high >> 5) ^ high))
	transformed := append(append([]byte(nil), flags...), v5Xmxor(message, hash)...)
	for left, right := 0, len(transformed)-1; left < right; left, right = left+1, right-1 {
		transformed[left], transformed[right] = transformed[right], transformed[left]
	}
	for index := range transformed {
		transformed[index] ^= seed[(^index)&3]
	}
	check := uint32(0x18000001) | ((uint32(queryHash[0]) & 63) << 14) | ((uint32(f13[0]) & 63) << 8)
	packedRandom := make([]byte, 4)
	if _, err := io.ReadFull(random, packedRandom); err != nil {
		return "", err
	}
	packed := []byte{0xca}
	packed = append(packed, packedRandom...)
	packed = append(packed, v5Le32(check)...)
	packed = append(packed, transformed...)
	packed = append(packed, byte(nonce>>16), byte(nonce>>24))
	keyHash := md5.Sum(v5SignKey[:16])
	ivHash := md5.Sum(v5SignKey[16:32])
	encrypted, err := v5Carrier(keyHash[:], ivHash[:], packed, ts)
	if err != nil {
		return "", err
	}
	prefix := append(v5Le32(5), v5Magic...)
	stamp := v5Le32(uint32(ts))
	for index := range prefix {
		prefix[index] ^= stamp[index&3]
	}
	out := append(prefix, byte(nonce), byte(nonce>>8), 0, 1)
	out = append(out, encrypted...)
	return base64.StdEncoding.EncodeToString(out), nil
}

func v5EncodeQuery(params map[string]string) string {
	keys := make([]string, 0, len(params))
	for key := range params {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		parts = append(parts, url.QueryEscape(key)+"="+url.QueryEscape(params[key]))
	}
	return strings.Join(parts, "&")
}

func v5QueryValue(query, name string) string {
	for _, part := range strings.Split(query, "&") {
		if part == "" {
			continue
		}
		key, value, _ := strings.Cut(part, "=")
		decodedKey, err := url.QueryUnescape(strings.ReplaceAll(key, "+", " "))
		if err != nil || decodedKey != name {
			continue
		}
		decoded, err := url.QueryUnescape(strings.ReplaceAll(value, "+", " "))
		if err != nil {
			return ""
		}
		return decoded
	}
	return ""
}

// signHongguoPlaybackV5 signs a playback request the V5 way and returns the
// full URL plus the headers to set. Randomness is injectable for tests.
func signHongguoPlaybackV5(base string, values map[string]string, body []byte, nowMs int64, random io.Reader) (string, map[string]string, error) {
	if random == nil {
		random = rand.Reader
	}
	ts := int32(nowMs / 1000)
	var bodyMd5 []byte
	if body != nil {
		sum := md5.Sum(body)
		bodyMd5 = sum[:]
	} else {
		bodyMd5 = make([]byte, 16)
	}
	params := make(map[string]string, len(values)+1)
	for key, value := range values {
		params[key] = value
	}
	var query string
	var queryHash []byte
	found := false
	for offset := int64(0); offset < 1024; offset++ {
		params["_rticket"] = strconv.FormatInt(nowMs+offset, 10)
		query = v5EncodeQuery(params)
		queryHashArray := hongguoSM3([]byte(query))
		queryHash = queryHashArray[:]
		if v5IV(queryHash, bodyMd5, ts)&15 == 12 {
			found = true
			break
		}
	}
	if !found {
		return "", nil, fmt.Errorf("无法在 1024 次 ticket 尝试内生成 V5 播放签名")
	}
	who := map[string]string{}
	for _, name := range []string{"device_id", "version_name", "os_version", "device_type", "channel"} {
		who[name] = v5QueryValue(query, name)
		if who[name] == "" {
			return "", nil, fmt.Errorf("播放签名缺少设备字段：%s", name)
		}
	}
	who["device_brand"] = v5QueryValue(query, "device_brand")
	if who["device_brand"] == "" {
		who["device_brand"] = "HONOR"
	}
	f13, err := v5Hash(queryHash, bodyMd5, ts)
	if err != nil {
		return "", nil, err
	}
	helios, err := v5Helios(int64(ts), random)
	if err != nil {
		return "", nil, err
	}
	medusa, err := v5Medusa(queryHash, f13, ts, who, nowMs, random)
	if err != nil {
		return "", nil, err
	}
	headers := map[string]string{
		"X-Khronos": strconv.FormatInt(int64(ts), 10),
		"X-Helios":  helios,
		"X-Medusa":  medusa,
	}
	if body != nil {
		headers["X-SS-STUB"] = strings.ToUpper(hex.EncodeToString(bodyMd5))
		headers["Content-Type"] = "application/json; charset=utf-8"
	}
	return base + "?" + query, headers, nil
}
