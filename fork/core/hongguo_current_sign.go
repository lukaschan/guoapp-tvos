package core

import (
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

const hgCurrentProfileB64 = "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"

var (
	hgCurMaterial  []byte
	hgCurHeader    []byte
	hgCurBoxes     [4][]byte
	hgCurInitial   [4][]byte
	hgCurChecksum  [256]uint64
	hgCurFactorIV  [8]uint32
	hgCurFactorTab [64]uint32
	hgCurPadding   []byte
)

func init() {
	profile, err := base64.StdEncoding.DecodeString(hgCurrentProfileB64)
	if err != nil || len(profile) != 3428 {
		panic("hongguo current profile invalid")
	}
	hgCurMaterial = profile[0:32]
	hgCurHeader = profile[32:48]
	for i := 0; i < 4; i++ {
		hgCurBoxes[i] = profile[48+i*256 : 48+(i+1)*256]
		hgCurInitial[i] = profile[1072+i*4 : 1076+i*4]
	}
	for i := 0; i < 256; i++ {
		hgCurChecksum[i] = binary.LittleEndian.Uint64(profile[1088+i*8:])
	}
	for i := 0; i < 8; i++ {
		hgCurFactorIV[i] = binary.LittleEndian.Uint32(profile[3136+i*4:])
	}
	for i := 0; i < 64; i++ {
		hgCurFactorTab[i] = binary.LittleEndian.Uint32(profile[3168+i*4:])
	}
	hgCurPadding = profile[3424:3428]
}

func hgCurSM3(data []byte) []byte {
	h := hongguoSM3(data)
	return h[:]
}

func hgCurRR(x uint32, n int) uint32 {
	n &= 31
	return x>>uint(n) | x<<uint((32-n)&31)
}

func hgCurR64(x uint64, n int) uint64 {
	n &= 63
	return x>>uint(n) | x<<uint((64-n)&63)
}

func hgCurLE32(v uint32) []byte {
	var b [4]byte
	binary.LittleEndian.PutUint32(b[:], v)
	return b[:]
}

func hgCurBE32(v uint32) []byte {
	var b [4]byte
	binary.BigEndian.PutUint32(b[:], v)
	return b[:]
}

func hgCurGetIV(iv uint32, data []byte) uint32 {
	v := iv
	for i, b := range data {
		if i&1 == 0 {
			v = (v >> 4) ^ v ^ (v << 6) ^ uint32(b)
			continue
		}
		v = ^((v >> 7) ^ v ^ (uint32(b) | (v << 12)))
	}
	return v
}

func hgCurVarint(v uint64) []byte {
	var out []byte
	for v > 127 {
		out = append(out, byte(v&127)|128)
		v >>= 7
	}
	return append(out, byte(v))
}

func hgCurPKey(tag uint32, wire byte) []byte {
	return hgCurVarint(uint64(tag)<<3 | uint64(wire))
}

func hgCurPBytes(tag uint32, b []byte) []byte {
	if len(b) == 0 {
		return nil
	}
	out := hgCurPKey(tag, 2)
	out = append(out, hgCurVarint(uint64(len(b)))...)
	return append(out, b...)
}

func hgCurPStr(tag uint32, s string) []byte { return hgCurPBytes(tag, []byte(s)) }

func hgCurPSInt(tag uint32, v int64) []byte {
	out := hgCurPKey(tag, 0)
	return append(out, hgCurVarint(uint64((v<<1)^(v>>63)))...)
}

func hgCurEncQueryPart(s string) string {
	var sb strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' ||
			strings.IndexByte("-_.!~*'()", c) >= 0 {
			sb.WriteByte(c)
		} else {
			fmt.Fprintf(&sb, "%%%02X", c)
		}
	}
	return sb.String()
}

func hgCurEncodeQuery(pairs [][2]string) string {
	parts := make([]string, len(pairs))
	for i, p := range pairs {
		parts[i] = hgCurEncQueryPart(p[0]) + "=" + hgCurEncQueryPart(p[1])
	}
	return strings.Join(parts, "&")
}

var errHGCurrentBad = errors.New("hongguo current signer: invalid input")

func hgCurFactor(input []byte, seconds uint32, selector int) ([]byte, error) {
	if len(input) != 52 {
		return nil, errHGCurrentBad
	}
	var cfgA, rounds int
	switch selector {
	case 0:
		cfgA, rounds = 15, 100
	case 3:
		cfgA, rounds = 13, 96
	case 6:
		cfgA, rounds = 62, 94
	case 9:
		cfgA, rounds = 79, 97
	case 12:
		cfgA, rounds = 66, 96
	case 15:
		cfgA, rounds = 127, 99
	default:
		return nil, errHGCurrentBad
	}
	rotation := seconds + uint32(cfgA) - 15 + 0xee47628f
	var iniArr [8]uint32
	var tabArr [64]uint32
	for i := 0; i < 8; i++ {
		iniArr[i] = hgCurRR(hgCurFactorIV[i], int(rotation&31))
	}
	for i := 0; i < 64; i++ {
		tabArr[i] = hgCurRR(hgCurFactorTab[i], int((rotation+1)&31))
	}
	block := make([]byte, 64)
	copy(block, input)
	shift := int((rotation + 2) & 7)
	for i := 0; i < 4; i++ {
		x := uint32(hgCurPadding[i])
		block[52+i] = byte(x>>uint(shift) | x<<uint((8-shift)&7))
	}
	block[62] = 1
	block[63] = 0xa0
	var w [128]uint32
	for i := 0; i < 16; i++ {
		w[i] = binary.BigEndian.Uint32(block[i*4:])
	}
	for i := 16; i < 128; i++ {
		x, y := w[i-15], w[i-2]
		w[i] = w[i-16] + (hgCurRR(x, 7) ^ hgCurRR(x, 18) ^ (x >> 3)) + w[i-7] + (hgCurRR(y, 17) ^ hgCurRR(y, 19) ^ (y >> 10))
	}
	sig := func(x uint32) uint32 { return hgCurRR(x, 6) ^ hgCurRR(x, 11) ^ hgCurRR(x, 25) }
	upper := func(x uint32) uint32 { return hgCurRR(x, 2) ^ hgCurRR(x, 13) ^ hgCurRR(x, 22) }
	v := iniArr
	for round := 0; round < rounds; round++ {
		a, b, c, d, e, f, g, h := v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]
		idx := cfgA + round
		kw := tabArr[idx&63] + w[idx&127]
		switch selector {
		case 0:
			t := kw + (c ^ (e & (f ^ c))) + sig(e) + g
			v = [8]uint32{t + h, a, b, c, d, e, f, ((a & b) | ((b | a) & d)) + upper(a) + t}
		case 3:
			t := kw + (h ^ (a & (c ^ h))) + sig(a) + b
			v = [8]uint32{h, a, ((f & d) | ((d | f) & g)) + upper(f) + t, c, d, t + e, f, g}
		case 6:
			t := kw + (a ^ (d & (b ^ a))) + sig(d) + c
			v = [8]uint32{h, a, b, ((h & g) | ((g | h) & f)) + upper(h) + t, d, t + e, f, g}
		case 9:
			t := kw + (b ^ (c & (f ^ b))) + sig(c) + d
			v = [8]uint32{h, t + a, b, c, ((g & h) | ((h | g) & e)) + upper(g) + t, e, f, g}
		case 12:
			t := kw + (e ^ (b & (a ^ e))) + sig(b) + g
			v = [8]uint32{t + h, a, b, c, d, e, f, ((d & f) | ((f | d) & c)) + upper(d) + t}
		default:
			t := kw + (a ^ (b & (d ^ a))) + sig(b) + f
			v = [8]uint32{h, a, b, c, d, t + e, ((g & c) | ((c | g) & h)) + upper(g) + t, g}
		}
	}
	digest := make([]byte, 0, 32)
	for i := 0; i < 8; i++ {
		digest = append(digest, hgCurBE32(iniArr[i]+v[i])...)
	}
	out := make([]byte, 20)
	for i := 0; i < 16; i++ {
		out[i] = digest[i] ^ digest[i+16]
	}
	var state uint32 = 0x20220420
	for i := 0; i < 8; i++ {
		x := uint32(out[i])
		if i%2 == 1 {
			state = ^(state ^ ((state << 11) | x) ^ (state >> 5))
		} else {
			state = state ^ (state << 7) ^ x ^ (state >> 3)
		}
	}
	copy(out[16:20], hgCurLE32((state&^0x24)^0x01000000))
	return out, nil
}

func hgCurGorgon(query string, digest []byte, t uint64, nonce uint16, flags uint16) string {
	key := []int{0x4a, int(flags & 255), 0x16, int(nonce >> 8), 0x47, 0x6c, int(flags >> 8), int(nonce & 255)}
	table := make([]int, 256)
	for i := range table {
		table[i] = i
	}
	j := 0
	for i := 0; i < 256; i++ {
		j = (j + table[i] + key[i%8]) & 255
		table[i] = table[j]
	}
	qh := md5.Sum([]byte(query))
	seed := make([]byte, 0, 20)
	seed = append(seed, qh[:4]...)
	seed = append(seed, digest[:4]...)
	seed = append(seed, 0, 0, 0, 0, 0, 9, 9, 4)
	seed = append(seed, hgCurBE32(uint32(t))...)
	out := make([]byte, 20)
	j = 0
	for n := 0; n < 20; n++ {
		i := n + 1
		j += table[i&255]
		y := table[j&255]
		table[i&255] = y
		out[n] = seed[n] ^ byte(table[(y+y)&255])
	}
	for i := 0; i < 20; i++ {
		x := out[i]
		swapped := (x >> 4) | (x << 4)
		vv := out[(i+1)%20] ^ swapped
		var rev byte
		for b := 0; b < 8; b++ {
			rev |= ((vv >> uint(b)) & 1) << uint(7-b)
		}
		out[i] = ^(rev ^ 20)
	}
	head := []byte{0x84, 4, byte(nonce), byte(nonce >> 8), byte(flags), byte(flags >> 8)}
	return hex.EncodeToString(append(head, out...))
}

func hgCurHelios(t uint64, license, aid string, random uint32) string {
	md := md5.Sum(append(hgCurLE32(random), []byte(aid)...))
	key := []byte(hex.EncodeToString(md[:]))
	rd := func(off int) uint64 { return binary.LittleEndian.Uint64(key[off:]) }
	var keys [35]uint64
	keys[0] = rd(0)
	a := keys[0]
	b := rd(8)
	queue := []uint64{rd(16), rd(24)}
	for i := 0; i < 34; i++ {
		x := (hgCurR64(b, 8) + a) ^ uint64(i)
		queue = append(queue, x)
		x ^= hgCurR64(a, 61)
		keys[i+1] = x
		a = x
		b = queue[0]
		queue = queue[1:]
	}
	raw := []byte(fmt.Sprintf("%d-%s-%s", t, license, aid))
	n := 16 - len(raw)%16
	plain := append(append([]byte{}, raw...), make([]byte, n)...)
	for i := len(raw); i < len(plain); i++ {
		plain[i] = byte(n)
	}
	out := append([]byte{}, hgCurLE32(random)...)
	for at := 0; at < len(plain); at += 16 {
		l := binary.LittleEndian.Uint64(plain[at:])
		r := binary.LittleEndian.Uint64(plain[at+8:])
		for i := 0; i < 34; i++ {
			nr := keys[i] ^ (l + hgCurR64(r, 8))
			l = nr ^ hgCurR64(l, 61)
			r = nr
		}
		var lb, rb [8]byte
		binary.LittleEndian.PutUint64(lb[:], l)
		binary.LittleEndian.PutUint64(rb[:], r)
		out = append(out, lb[:]...)
		out = append(out, rb[:]...)
	}
	return base64.StdEncoding.EncodeToString(out)
}

func hgCurKS(pb, mat, t4 []byte) []byte {
	boxIn := append(append(append([]byte{}, mat...), t4...), mat...)
	box := hgCurSM3(boxIn)
	n := len(pb)
	b := make([]byte, n)
	for i := 0; i < n; i++ {
		a := uint32(box[4*i%32])
		c := uint32(box[(4*i+1)%32])
		x := uint32(pb[i])
		w := ^(((x >> 4) | (x << 4)) + a ^ c)
		rot := ((w << 3) & 0xfffffff8) | ((w >> 5) & 7)
		b[n-1-i] = byte(^(a ^ (rot + c)))
	}
	last, prev := b[n-1], b[n-2]
	b[0] += ^(last ^ prev)
	b[1] = (b[0] ^ last ^ 254) + b[1]
	for j := 2; j < n-1; j++ {
		v := uint32(b[j-1])
		rot := ((v >> 5) & 7) | (v << 3)
		b[j] += byte(^(uint32(b[j-2]) ^ rot ^ uint32(j)))
	}
	b[n-1] ^= b[n-2]
	var sum byte
	for _, x := range b[1:] {
		sum += x
	}
	b[0] = (b[0] ^ b[1]) + sum
	reg := ^(((uint32(t4[2]) << 11) | uint32(t4[3])) ^ uint32(t4[2]) ^ (uint32(t4[2]) >> 5))
	mask := hgCurBE32(reg)
	stream := append(make([]byte, 8), b...)
	out := make([]byte, len(stream))
	for i := range stream {
		out[i] = mask[i%4] ^ stream[len(stream)-1-i]
	}
	return out
}

var hgCurCon = [4][4]int{{2, 0, 3, 1}, {1, 3, 2, 0}, {3, 2, 1, 0}, {2, 3, 1, 0}}
var hgCurOrder = [4][16]int{
	{0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11},
	{0, 9, 14, 11, 4, 13, 2, 3, 8, 1, 6, 15, 12, 5, 10, 7},
	{0, 9, 14, 3, 4, 13, 2, 15, 8, 1, 6, 11, 12, 5, 10, 7},
	{0, 9, 14, 15, 4, 13, 2, 3, 8, 1, 6, 11, 12, 5, 10, 7},
}

func hgCurTransform(plain, key, iv []byte, branch int) ([]byte, error) {
	if len(key) != 16 || len(iv) != 16 || branch < 0 || branch > 3 {
		return nil, errHGCurrentBad
	}
	box := hgCurBoxes[branch]
	ini := binary.LittleEndian.Uint32(hgCurInitial[branch])
	var expanded [48]byte
	for i := 0; i < 16; i++ {
		expanded[i] = key[i] ^ hgCurInitial[branch][i%4]
	}
	rounds := 8
	for i := 4; i < 12; i++ {
		at := 4 * (i - 1)
		a, b, c, d := expanded[at], expanded[at+1], expanded[at+2], expanded[at+3]
		if i&3 == 0 {
			old := a
			a = byte((ini >> uint(rounds&24)) ^ uint32(box[b]))
			b = box[c]
			c = box[d]
			d = box[old]
		}
		rounds += 2
		for j, v := range []byte{a, b, c, d} {
			expanded[at+4+j] = v ^ expanded[at-12+j]
		}
	}
	pad := 16 - len(plain)%16
	source := append(append([]byte{}, plain...), make([]byte, pad)...)
	for i := len(plain); i < len(source); i++ {
		source[i] = byte(pad)
	}
	co := hgCurCon[branch]
	previous := append([]byte{}, iv...)
	var out []byte
	for at := 0; at < len(source); at += 16 {
		var state [16]byte
		for i := 0; i < 16; i++ {
			state[i] = source[at+i] ^ previous[i] ^ expanded[4*(i/4)+co[i%4]]
		}
		for round := 1; round <= 2; round++ {
			old := state
			for i := 0; i < 16; i++ {
				state[i] = box[old[co[i/4]*4+i%4]]
			}
			old = state
			for i := 0; i < 16; i++ {
				state[i] = old[hgCurOrder[branch][i]]
			}
			if round == 1 {
				old = state
				for i := 0; i < 16; i++ {
					state[i] = old[4*(i/4)+co[i%4]]
				}
				for j := 0; j < 4; j++ {
					total := state[j] ^ state[4+j] ^ state[8+j] ^ state[12+j]
					first := state[j]
					for i := 0; i < 4; i++ {
						var next byte
						if i < 3 {
							next = state[(i+1)*4+j]
						} else {
							next = first
						}
						x := state[i*4+j] ^ next
						var xt byte
						if x&128 != 0 {
							xt = (x << 1) ^ 0x1b
						} else {
							xt = x << 1
						}
						state[i*4+j] ^= total ^ xt
					}
				}
			}
			for i := 0; i < 16; i++ {
				state[i] ^= expanded[16*round+4*(i/4)+co[i%4]]
			}
		}
		for i := 0; i < 16; i++ {
			previous[i] = state[i] ^ expanded[16+i]
		}
		out = append(out, previous...)
	}
	return out, nil
}

func hgCurMid(pb []byte) (uint16, error) {
	at := 0
	first := [2]int{-1, -1}
	read := func() (uint64, error) {
		var v uint64
		for i := 0; i < 10; i++ {
			if at >= len(pb) {
				return 0, errHGCurrentBad
			}
			b := pb[at]
			at++
			if i == 9 && b > 1 {
				return 0, errHGCurrentBad
			}
			v |= uint64(b&127) << uint(7*i)
			if b&128 == 0 {
				return v, nil
			}
		}
		return 0, errHGCurrentBad
	}
	for at < len(pb) {
		tag, err := read()
		if err != nil {
			return 0, err
		}
		if tag>>3 == 0 {
			return 0, errHGCurrentBad
		}
		switch tag & 7 {
		case 0:
			if _, err := read(); err != nil {
				return 0, err
			}
		case 1:
			at += 8
		case 5:
			at += 4
		case 2:
			n64, err := read()
			if err != nil || n64 > uint64(len(pb)-at) {
				return 0, errHGCurrentBad
			}
			n, field := int(n64), int(tag>>3)
			if field >= 13 && field <= 14 && n > 0 {
				first[field-13] = int(pb[at])
			}
			at += n
		default:
			return 0, errHGCurrentBad
		}
		if at > len(pb) {
			return 0, errHGCurrentBad
		}
	}
	if first[0] < 0 || first[1] < 0 {
		return 0, errHGCurrentBad
	}
	return uint16(first[0]&63) | uint16(first[1]&63)<<6, nil
}

func hgCurMedusa(pb, mat []byte, t uint64, r1, r2 uint32) (string, error) {
	m, err := hgCurMid(pb)
	if err != nil {
		return "", err
	}
	t4 := hgCurLE32(r1)
	var prefix uint32
	for i, xb := range mat {
		x := uint32(xb)
		if i%2 == 0 {
			prefix = prefix ^ (prefix << 7) ^ x ^ (prefix >> 3)
		} else {
			prefix = prefix ^ (^((prefix << 11) ^ x ^ (prefix >> 5)))
		}
	}
	pre := []byte{byte(prefix)}
	pre = append(pre, hgCurLE32(r2)...)
	pre = append(pre, 1, byte(m), byte(m>>8), 0x18)
	pre = append(pre, hgCurKS(pb, mat, t4)...)
	pre = append(pre, t4[2:4]...)
	if len(pre) < 248 {
		return "", errHGCurrentBad
	}
	lane := [8]int{6, 5, 3, 4, 2, 7, 1, 0}
	bits := [8]int{1, 7, 3, 6, 2, 0, 4, 5}
	var plain [31]byte
	for i := 0; i < 248; i++ {
		plain[i/8] |= ((pre[i] >> uint(lane[i%8])) & 1) << uint(bits[i%8])
	}
	k1 := md5.Sum(mat[0:16])
	k2 := md5.Sum(mat[16:32])
	channel, err := hgCurTransform(plain[:], k1[:], k2[:], int(t&3))
	if err != nil {
		return "", err
	}
	body := append([]byte{}, pre...)
	for i := 0; i < 248; i++ {
		body[i] = (body[i] &^ (1 << uint(lane[i%8]))) | (((channel[i/8] >> uint(bits[i%8])) & 1) << uint(lane[i%8]))
	}
	hdr := append(hgCurLE32(5), hgCurHeader...)
	mask := hgCurLE32(uint32(t))
	for i := range hdr {
		hdr[i] ^= mask[i%4]
	}
	out := append([]byte{}, hdr...)
	out = append(out, t4[:2]...)
	out = append(out, 0, 1, channel[31])
	out = append(out, body...)
	return base64.StdEncoding.EncodeToString(out), nil
}

func hgCurCompute(query string, digest, pb, material []byte, license, aid string,
	seconds uint64, nonce uint16, flags uint16, heliosRandom, random1, random2 uint32,
	local uint64, previous uint32) (map[string]string, uint32, error) {
	if len(material) != 32 || len(digest) != 16 || len(pb) < 2 || len(pb) > 32768 {
		return nil, 0, errHGCurrentBad
	}
	var crc uint64
	for i := 0; i < len(license); i++ {
		crc = hgCurChecksum[byte(crc)^license[i]] ^ (crc >> 8)
	}
	state := uint32(hgCurR64(crc^seconds^local, 60)) ^ previous
	medusa, err := hgCurMedusa(pb, material, seconds, random1, random2)
	if err != nil {
		return nil, 0, err
	}
	headers := map[string]string{
		"x-khronos": fmt.Sprintf("%d", seconds),
		"x-argus":   base64.StdEncoding.EncodeToString(hgCurLE32(uint32(seconds))),
		"x-ladon":   base64.StdEncoding.EncodeToString(hgCurBE32(state)),
		"x-gorgon":  hgCurGorgon(query, digest, seconds, nonce, flags),
		"x-helios":  hgCurHelios(seconds, license, aid, heliosRandom),
		"x-medusa":  medusa,
	}
	return headers, state, nil
}

func hgCurProtobuf(t uint32, deviceID, version string, nonce uint32, factor, hash []byte) []byte {
	var pb []byte
	pb = append(pb, hgCurPBytes(1, hgCurHeader)...)
	pb = append(pb, hgCurPSInt(2, 5)...)
	pb = append(pb, hgCurPSInt(3, int64(nonce))...)
	pb = append(pb, hgCurPStr(4, "8662")...)
	pb = append(pb, hgCurPStr(5, deviceID)...)
	pb = append(pb, hgCurPStr(6, "646637794")...)
	pb = append(pb, hgCurPStr(7, version)...)
	pb = append(pb, hgCurPStr(8, "v04.10.03-ml-android")...)
	pb = append(pb, hgCurPSInt(9, 135529984/2)...)
	pb = append(pb, hgCurPBytes(10, make([]byte, 8))...)
	pb = append(pb, hgCurPSInt(12, int64(t))...)
	pb = append(pb, hgCurPBytes(13, factor)...)
	pb = append(pb, hgCurPBytes(14, hash)...)
	var counters []byte
	counters = append(counters, hgCurPSInt(1, 1)...)
	counters = append(counters, hgCurPSInt(2, 1)...)
	counters = append(counters, hgCurPSInt(3, 1)...)
	pb = append(pb, hgCurPBytes(15, counters)...)
	pb = append(pb, hgCurPSInt(17, int64(t))...)
	pb = append(pb, hgCurPStr(20, "none")...)
	pb = append(pb, hgCurPSInt(21, 377)...)
	var env []byte
	env = append(env, hgCurPSInt(1, 100)...)
	env = append(env, hgCurPSInt(5, 7)...)
	env = append(env, hgCurPStr(6, "v04.10.03.04-bugfix")...)
	env = append(env, hgCurPSInt(7, 10001)...)
	env = append(env, hgCurPStr(14, version)...)
	pb = append(pb, hgCurPBytes(23, env)...)
	pb = append(pb, hgCurPStr(24, `{"cmr":16777216,"cmr2":16777216,"vpn":0,"kd":0,"dyn":"","do":0,"tk":false}`)...)
	pb = append(pb, hgCurPStr(25, "AAAAAAAAAAAAAAAAAAAAAAAAA")...)
	return pb
}

func hgCurSign(pairs [][2]string, nowMillis int64, deviceID, versionName string, body, entropy []byte) (string, map[string]string, error) {
	ent := entropy
	if ent == nil {
		ent = make([]byte, 24)
		if _, err := rand.Read(ent); err != nil {
			return "", nil, err
		}
	}
	if nowMillis < 1000 || deviceID == "" || len(deviceID) > 64 || versionName == "" || len(versionName) > 32 || len(ent) != 24 {
		return "", nil, errHGCurrentBad
	}
	var base [][2]string
	for _, p := range pairs {
		if p[0] != "ts" && p[0] != "_rticket" {
			base = append(base, p)
		}
	}
	digest := md5.Sum(body)
	le := func(off int) uint32 { return binary.LittleEndian.Uint32(ent[off:]) }
	for offset := int64(0); offset < 128; offset++ {
		ticket := nowMillis + offset
		t := uint32(ticket / 1000)
		q := append(append([][2]string{}, base...), [2]string{"ts", fmt.Sprintf("%d", t)}, [2]string{"_rticket", fmt.Sprintf("%d", ticket)})
		query := hgCurEncodeQuery(q)
		if len(query) > 32768 {
			return "", nil, errHGCurrentBad
		}
		hash := hgCurSM3([]byte(query))
		input := append(append(append([]byte{}, hash...), digest[:]...), hgCurLE32(t)...)
		selector := int(hgCurGetIV(0x20230928, input) & 15)
		if selector%3 != 0 {
			continue
		}
		f, err := hgCurFactor(input, t, selector)
		if err != nil {
			return "", nil, err
		}
		pb := hgCurProtobuf(t, deviceID, versionName, le(0), f, hash[:6])
		headers, _, err := hgCurCompute(query, digest[:], pb, hgCurMaterial, "646637794", "8662",
			uint64(t), uint16(ent[0])|uint16(ent[1])<<8, 0x101, le(4), le(8), le(12), 0x10000000, le(16))
		if err != nil {
			return "", nil, err
		}
		headers["Accept"] = "application/json; charset=utf-8,application/x-protobuf"
		headers["Content-Type"] = "application/json; charset=utf-8"
		headers["x-xs-from-web"] = "0"
		headers["sdk-version"] = "2"
		headers["x-ss-req-ticket"] = fmt.Sprintf("%d", ticket)
		headers["x-ss-stub"] = hex.EncodeToString(digest[:])
		return query, headers, nil
	}
	return "", nil, errors.New("hongguo current signer: selector search failed")
}
