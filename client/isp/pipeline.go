package isp

import (
	"bytes"
	"image"
	"image/jpeg"
	"math"
	"runtime"
	"sync"
)

type Config struct {
	Enabled        bool    `json:"enabled"`
	TemporalNR     float64 `json:"temporal_nr"`     // 0.0 (off) .. 0.75 (strong static NR)
	MotionThresh   int     `json:"motion_thresh"`   // 8 .. 40 (luma diff threshold for motion rejection)
	ChromaDenoise  bool    `json:"chroma_denoise"`  // 3x3 edge-preserving chroma smoothing
	AutoLevels     bool    `json:"auto_levels"`     // Auto black-point + contrast stretch
	AutoWB         bool    `json:"auto_wb"`         // Subtle gray-world white balance correction
	Sharpen        float64 `json:"sharpen"`         // 0.0 .. 1.0 (AMD FidelityFX CAS strength)
	Saturation     float64 `json:"saturation"`      // 0.5 .. 1.6 (1.0 = neutral)
	Gamma          float64 `json:"gamma"`           // 0.7 .. 1.4 (1.0 = neutral)
	SplitCompare   int     `json:"split_compare"`   // 0 = off, 1..99 = % divider (raw left, ISP right)
	OutJPEGQuality int     `json:"out_jpeg_quality"`
}

func DefaultConfig() Config {
	return Config{
		Enabled:        true,
		TemporalNR:     0.45,
		MotionThresh:   16,
		ChromaDenoise:  true,
		AutoLevels:     true,
		AutoWB:         true,
		Sharpen:        0.55,
		Saturation:     1.12,
		Gamma:          0.95,
		SplitCompare:   0,
		OutJPEGQuality: 90,
	}
}

type Pipeline struct {
	mu       sync.Mutex
	cfg      Config
	prevW    int
	prevH    int
	prevRGB  []uint8 // Accumulated temporal reference (3 bytes/px)
	workRGB  []uint8 // Current decoded RGB buffer
	stageRGB []uint8 // Intermediate buffer for CAS

	// Temporally smoothed auto-levels & WB gains to avoid flicker
	emaBlack  float64
	emaWhite  float64
	emaGainR  float64
	emaGainG  float64
	emaGainB  float64
	emaInited bool
}

func NewPipeline() *Pipeline {
	return &Pipeline{
		cfg:      DefaultConfig(),
		emaBlack: 0,
		emaWhite: 255,
		emaGainR: 1,
		emaGainG: 1,
		emaGainB: 1,
	}
}

func (p *Pipeline) SetConfig(c Config) {
	p.mu.Lock()
	p.cfg = c
	p.mu.Unlock()
}

func (p *Pipeline) GetConfig() Config {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.cfg
}

func (p *Pipeline) ResetTemporal() {
	p.mu.Lock()
	p.prevW = 0
	p.prevH = 0
	p.emaInited = false
	p.mu.Unlock()
}

// ProcessJPEG decodes raw JPEG, runs the parallelized ISP pipeline, and returns both
// processed RGBA image and re-encoded JPEG (or raw passthrough if disabled).
func (p *Pipeline) ProcessJPEG(rawJPEG []byte) (*image.RGBA, []byte, error) {
	p.mu.Lock()
	cfg := p.cfg
	p.mu.Unlock()

	if !cfg.Enabled {
		return nil, rawJPEG, nil
	}

	img, err := jpeg.Decode(bytes.NewReader(rawJPEG))
	if err != nil {
		return nil, rawJPEG, err
	}

	outImg := p.ProcessImage(img, cfg)

	q := cfg.OutJPEGQuality
	if q < 60 || q > 98 {
		q = 90
	}
	var buf bytes.Buffer
	buf.Grow(len(rawJPEG) + len(rawJPEG)/2)
	if err := jpeg.Encode(&buf, outImg, &jpeg.Options{Quality: q}); err != nil {
		return outImg, rawJPEG, err
	}
	return outImg, buf.Bytes(), nil
}

func (p *Pipeline) ProcessImage(src image.Image, cfg Config) *image.RGBA {
	p.mu.Lock()
	defer p.mu.Unlock()

	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	n3 := w * h * 3

	if len(p.workRGB) != n3 {
		p.workRGB = make([]uint8, n3)
		p.stageRGB = make([]uint8, n3)
		p.prevRGB = make([]uint8, n3)
		p.prevW = 0
		p.prevH = 0
	}

	// Step 1: Fast decode to packed RGB (with optional 3x3 chroma denoise on YCbCr!)
	p.extractRGB(src, w, h, cfg.ChromaDenoise)

	// Keep raw copy only if split comparison is requested
	var rawCopy []uint8
	if cfg.SplitCompare > 0 && cfg.SplitCompare < 100 {
		rawCopy = make([]uint8, n3)
		copy(rawCopy, p.workRGB)
	}

	// Step 2: Motion-Adaptive Temporal Noise Reduction
	if cfg.TemporalNR > 0.01 && p.prevW == w && p.prevH == h {
		p.applyTemporalNR(w, h, cfg.TemporalNR, cfg.MotionThresh)
	} else {
		copy(p.prevRGB, p.workRGB)
		p.prevW = w
		p.prevH = h
	}

	// Step 3: Auto Black-Level / Contrast + Gray-World WB + Gamma + Saturation (combined LUT/pass)
	if cfg.AutoLevels || cfg.AutoWB || math.Abs(cfg.Gamma-1.0) > 0.01 || math.Abs(cfg.Saturation-1.0) > 0.01 {
		p.applyToneAndColor(w, h, cfg)
	}

	// Step 4: AMD FidelityFX CAS (Contrast-Adaptive Sharpening)
	finalRGB := p.workRGB
	if cfg.Sharpen > 0.01 {
		p.applyCAS(w, h, cfg.Sharpen)
		finalRGB = p.stageRGB
	}

	// Pack to *image.RGBA (with optional raw/enhanced split line)
	out := image.NewRGBA(image.Rect(0, 0, w, h))
	splitX := -1
	if len(rawCopy) == n3 {
		splitX = (w * cfg.SplitCompare) / 100
	}

	parallelRows(h, func(y0, y1 int) {
		for y := y0; y < y1; y++ {
			srcOff := y * w * 3
			dstOff := y * out.Stride
			for x := 0; x < w; x++ {
				if splitX >= 0 && x < splitX {
					out.Pix[dstOff] = rawCopy[srcOff]
					out.Pix[dstOff+1] = rawCopy[srcOff+1]
					out.Pix[dstOff+2] = rawCopy[srcOff+2]
					out.Pix[dstOff+3] = 255
				} else if splitX >= 0 && (x == splitX || x == splitX+1) {
					out.Pix[dstOff] = 59
					out.Pix[dstOff+1] = 130
					out.Pix[dstOff+2] = 246
					out.Pix[dstOff+3] = 255
				} else {
					out.Pix[dstOff] = finalRGB[srcOff]
					out.Pix[dstOff+1] = finalRGB[srcOff+1]
					out.Pix[dstOff+2] = finalRGB[srcOff+2]
					out.Pix[dstOff+3] = 255
				}
				srcOff += 3
				dstOff += 4
			}
		}
	})

	return out
}

func (p *Pipeline) extractRGB(src image.Image, w, h int, chromaDenoise bool) {
	ycbcr, isYCbCr := src.(*image.YCbCr)
	if !isYCbCr {
		b := src.Bounds()
		parallelRows(h, func(y0, y1 int) {
			for y := y0; y < y1; y++ {
				off := y * w * 3
				for x := 0; x < w; x++ {
					r, g, bl, _ := src.At(b.Min.X+x, b.Min.Y+y).RGBA()
					p.workRGB[off] = uint8(r >> 8)
					p.workRGB[off+1] = uint8(g >> 8)
					p.workRGB[off+2] = uint8(bl >> 8)
					off += 3
				}
			}
		})
		return
	}

	// Fast parallel YCbCr -> RGB with optional 3x3 chroma plane denoising!
	// OV3660 JPEGs are 4:2:0 or 4:2:2 YCbCr. Smoothing Cb/Cr directly kills color speckle
	// without touching high-frequency Y luminance detail!
	var cbSmooth, crSmooth []uint8
	cw, ch := len(ycbcr.Cb), 0
	if chromaDenoise && ycbcr.CStride > 0 && len(ycbcr.Cb) > 0 {
		ch = len(ycbcr.Cb) / ycbcr.CStride
		cw = ycbcr.CStride
		cbSmooth = make([]uint8, len(ycbcr.Cb))
		crSmooth = make([]uint8, len(ycbcr.Cr))
		copy(cbSmooth, ycbcr.Cb)
		copy(crSmooth, ycbcr.Cr)
		if ch > 2 && cw > 2 {
			parallelRows(ch-2, func(r0, r1 int) {
				for cy := r0 + 1; cy < r1+1; cy++ {
					row := cy * cw
					for cx := 1; cx < cw-1; cx++ {
						idx := row + cx
						// 3x3 edge-aware weighted chroma average (threshold prevents color bleed across sharp edges)
						c0 := int(ycbcr.Cb[idx])
						r0v := int(ycbcr.Cr[idx])
						sumC, sumR, wSum := c0*4, r0v*4, 4
						nbrs := [8]int{idx - cw - 1, idx - cw, idx - cw + 1, idx - 1, idx + 1, idx + cw - 1, idx + cw, idx + cw + 1}
						for _, ni := range nbrs {
							nc := int(ycbcr.Cb[ni])
							nr := int(ycbcr.Cr[ni])
							dc := nc - c0
							if dc < 0 {
								dc = -dc
							}
							dr := nr - r0v
							if dr < 0 {
								dr = -dr
							}
							if dc < 18 && dr < 18 {
								sumC += nc
								sumR += nr
								wSum++
							}
						}
						cbSmooth[idx] = uint8(sumC / wSum)
						crSmooth[idx] = uint8(sumR / wSum)
					}
				}
			})
		}
	} else {
		cbSmooth = ycbcr.Cb
		crSmooth = ycbcr.Cr
	}

	b := ycbcr.Bounds()
	parallelRows(h, func(y0, y1 int) {
		for y := y0; y < y1; y++ {
			sy := b.Min.Y + y
			yiBase := ycbcr.YOffset(b.Min.X, sy)
			off := y * w * 3
			for x := 0; x < w; x++ {
				sx := b.Min.X + x
				yy := int32(ycbcr.Y[yiBase+x])
				ci := ycbcr.COffset(sx, sy)
				cb := int32(cbSmooth[ci]) - 128
				cr := int32(crSmooth[ci]) - 128

				// BT.601 fixed-point YCbCr -> RGB
				r := yy + ((91881 * cr) >> 16)
				g := yy - ((22554*cb + 46802*cr) >> 16)
				bl := yy + ((116130 * cb) >> 16)

				p.workRGB[off] = clampU8(r)
				p.workRGB[off+1] = clampU8(g)
				p.workRGB[off+2] = clampU8(bl)
				off += 3
			}
		}
	})
}

func (p *Pipeline) applyTemporalNR(w, h int, strength float64, thresh int) {
	// Blend weight for previous frame in static pixels: keep = strength (0..0.75)
	keepQ := int(strength * 256.0)
	if keepQ > 205 {
		keepQ = 205
	}
	curQ := 256 - keepQ
	tLow := thresh
	tHigh := thresh * 2

	parallelRows(h, func(y0, y1 int) {
		for y := y0; y < y1; y++ {
			off := y * w * 3
			end := off + w*3
			for i := off; i < end; i += 3 {
				cr, cg, cb := int(p.workRGB[i]), int(p.workRGB[i+1]), int(p.workRGB[i+2])
				pr, pg, pb := int(p.prevRGB[i]), int(p.prevRGB[i+1]), int(p.prevRGB[i+2])

				dr := cr - pr
				if dr < 0 {
					dr = -dr
				}
				dg := cg - pg
				if dg < 0 {
					dg = -dg
				}
				db := cb - pb
				if db < 0 {
					db = -db
				}
				// Max channel diff avoids color ghosting
				d := dg
				if dr > d {
					d = dr
				}
				if db > d {
					d = db
				}

				if d <= tLow {
					// Static region: strong temporal noise reduction
					nr := uint8((cr*curQ + pr*keepQ + 128) >> 8)
					ng := uint8((cg*curQ + pg*keepQ + 128) >> 8)
					nb := uint8((cb*curQ + pb*keepQ + 128) >> 8)
					p.workRGB[i] = nr
					p.workRGB[i+1] = ng
					p.workRGB[i+2] = nb
					p.prevRGB[i] = nr
					p.prevRGB[i+1] = ng
					p.prevRGB[i+2] = nb
				} else if d < tHigh {
					// Soft ramp transition
					wKeep := keepQ * (tHigh - d) / (tHigh - tLow)
					wCur := 256 - wKeep
					nr := uint8((cr*wCur + pr*wKeep + 128) >> 8)
					ng := uint8((cg*wCur + pg*wKeep + 128) >> 8)
					nb := uint8((cb*wCur + pb*wKeep + 128) >> 8)
					p.workRGB[i] = nr
					p.workRGB[i+1] = ng
					p.workRGB[i+2] = nb
					p.prevRGB[i] = nr
					p.prevRGB[i+1] = ng
					p.prevRGB[i+2] = nb
				} else {
					// Real motion: zero ghosting
					p.prevRGB[i] = uint8(cr)
					p.prevRGB[i+1] = uint8(cg)
					p.prevRGB[i+2] = uint8(cb)
				}
			}
		}
	})
}

func (p *Pipeline) applyToneAndColor(w, h int, cfg Config) {
	// Subsampled stats pass (every 4th pixel in X & Y -> ~6% cost)
	var hist [256]uint32
	var sumR, sumG, sumB, count float64
	var hiR, hiG, hiB, hiCount float64 // Top bright pixels for white-patch WB!
	for y := 0; y < h; y += 4 {
		row := y * w * 3
		for x := 0; x < w; x += 4 {
			i := row + x*3
			r, g, b := float64(p.workRGB[i]), float64(p.workRGB[i+1]), float64(p.workRGB[i+2])
			yVal := uint8(0.299*r + 0.587*g + 0.114*b)
			hist[yVal]++
			sumR += r
			sumG += g
			sumB += b
			count++
			if yVal >= 130 {
				hiR += r
				hiG += g
				hiB += b
				hiCount++
			}
		}
	}

	targetBlack := 0.0
	targetWhite := 255.0
	if cfg.AutoLevels && count > 100 {
		lowCut := uint32(count * 0.015)
		highCut := uint32(count * 0.992)
		var acc uint32
		for v := 0; v < 256; v++ {
			acc += hist[v]
			if acc >= lowCut {
				targetBlack = float64(v)
				break
			}
		}
		acc = 0
		for v := 0; v < 256; v++ {
			acc += hist[v]
			if acc >= highCut {
				targetWhite = float64(v)
				break
			}
		}
		if targetBlack > 42 {
			targetBlack = 42
		}
		targetBlack *= 0.80
		// Allow stretching underexposed bright highlights up to pure white (min white anchor 135)
		if targetWhite < 135 {
			targetWhite = 135
		}
		if targetWhite-targetBlack < 85 {
			targetBlack = 0
			targetWhite = 255
		}
	}

	gR, gG, gB := 1.0, 1.0, 1.0
	if cfg.AutoWB && count > 100 {
		// Hybrid White-Patch (70%) + Gray-World (30%) kills OV3660 green-cyan cast cleanly!
		var refR, refG, refB float64
		if hiCount > count*0.04 {
			refR = 0.70*(hiR/hiCount) + 0.30*(sumR/count)
			refG = 0.70*(hiG/hiCount) + 0.30*(sumG/count)
			refB = 0.70*(hiB/hiCount) + 0.30*(sumB/count)
		} else {
			refR, refG, refB = sumR/count, sumG/count, sumB/count
		}
		avg := (refR + refG + refB) / 3.0
		if avg > 15 && refR > 10 && refG > 10 && refB > 10 {
			gR = 1.0 + 0.70*((avg/refR)-1.0)
			gG = 1.0 + 0.70*((avg/refG)-1.0)
			gB = 1.0 + 0.70*((avg/refB)-1.0)
			gR = clampF(gR, 0.82, 1.24)
			gG = clampF(gG, 0.84, 1.16)
			gB = clampF(gB, 0.82, 1.24)
		}
	}

	if !p.emaInited {
		p.emaBlack, p.emaWhite = targetBlack, targetWhite
		p.emaGainR, p.emaGainG, p.emaGainB = gR, gG, gB
		p.emaInited = true
	} else {
		const a = 0.12
		p.emaBlack = p.emaBlack*(1-a) + targetBlack*a
		p.emaWhite = p.emaWhite*(1-a) + targetWhite*a
		p.emaGainR = p.emaGainR*(1-a) + gR*a
		p.emaGainG = p.emaGainG*(1-a) + gG*a
		p.emaGainB = p.emaGainB*(1-a) + gB*a
	}

	// Precompute 256-entry per-channel tone + WB + gamma LUTs (ultra fast!)
	var lutR, lutG, lutB [256]uint8
	scale := 255.0 / math.Max(1.0, p.emaWhite-p.emaBlack)
	gamma := cfg.Gamma
	if gamma < 0.5 || gamma > 2.0 {
		gamma = 1.0
	}
	for v := 0; v < 256; v++ {
		norm := clampF((float64(v)-p.emaBlack)*scale/255.0, 0.0, 1.0)
		// Subtle filmic S-curve + gamma
		norm = math.Pow(norm, gamma)
		lutR[v] = clampU8(int32(norm*p.emaGainR*255.0 + 0.5))
		lutG[v] = clampU8(int32(norm*p.emaGainG*255.0 + 0.5))
		lutB[v] = clampU8(int32(norm*p.emaGainB*255.0 + 0.5))
	}

	sat := cfg.Saturation
	doSat := math.Abs(sat-1.0) > 0.01
	satQ := int32(sat * 256.0)

	parallelRows(h, func(y0, y1 int) {
		for y := y0; y < y1; y++ {
			off := y * w * 3
			end := off + w*3
			if !doSat {
				for i := off; i < end; i += 3 {
					p.workRGB[i] = lutR[p.workRGB[i]]
					p.workRGB[i+1] = lutG[p.workRGB[i+1]]
					p.workRGB[i+2] = lutB[p.workRGB[i+2]]
				}
			} else {
				for i := off; i < end; i += 3 {
					r := int32(lutR[p.workRGB[i]])
					g := int32(lutG[p.workRGB[i+1]])
					b := int32(lutB[p.workRGB[i+2]])
					luma := (r*77 + g*150 + b*29) >> 8
					p.workRGB[i] = clampU8(luma + (((r - luma) * satQ) >> 8))
					p.workRGB[i+1] = clampU8(luma + (((g - luma) * satQ) >> 8))
					p.workRGB[i+2] = clampU8(luma + (((b - luma) * satQ) >> 8))
				}
			}
		}
	})
}

// applyCAS implements AMD FidelityFX Contrast-Adaptive Sharpening on RGB buffer.
func (p *Pipeline) applyCAS(w, h int, strength float64) {
	copy(p.stageRGB, p.workRGB)
	if w < 3 || h < 3 {
		return
	}
	// Peak negative lobe weight: -0.125 (subtle) to -0.20 (crisp)
	peak := -0.125 - 0.075*clampF(strength, 0.0, 1.0)
	stride := w * 3

	parallelRows(h-2, func(r0, r1 int) {
		for y := r0 + 1; y < r1+1; y++ {
			row := y * stride
			for x := 1; x < w-1; x++ {
				c := row + x*3
				n := c - stride
				s := c + stride
				we := c - 3
				ea := c + 3

				// Compute local luma contrast on green channel (fastest proxy)
				gC := float64(p.workRGB[c+1])
				gN := float64(p.workRGB[n+1])
				gS := float64(p.workRGB[s+1])
				gW := float64(p.workRGB[we+1])
				gE := float64(p.workRGB[ea+1])

				mn := math.Min(gC, math.Min(math.Min(gN, gS), math.Min(gW, gE)))
				mx := math.Max(gC, math.Max(math.Max(gN, gS), math.Max(gW, gE)))

				// Suppress sharpening in very flat noisy patches!
				if mx-mn < 6.0 {
					continue
				}

				// Adaptive weight: higher in medium contrast, dampened near clipping
				amp := math.Sqrt(clampF(math.Min(mn, 255.0-mx)/math.Max(mx, 1.0), 0.0, 1.0))
				weight := amp * peak
				invW := 1.0 / (1.0 + 4.0*weight)

				for ch := 0; ch < 3; ch++ {
					val := (float64(p.workRGB[c+ch]) +
						weight*(float64(p.workRGB[n+ch])+float64(p.workRGB[s+ch])+
							float64(p.workRGB[we+ch])+float64(p.workRGB[ea+ch]))) * invW
					p.stageRGB[c+ch] = clampU8(int32(val + 0.5))
				}
			}
		}
	})
}

func parallelRows(rows int, fn func(y0, y1 int)) {
	n := runtime.NumCPU()
	if n > rows {
		n = rows
	}
	if n <= 1 {
		fn(0, rows)
		return
	}
	var wg sync.WaitGroup
	wg.Add(n)
	chunk := (rows + n - 1) / n
	for i := 0; i < n; i++ {
		y0 := i * chunk
		y1 := y0 + chunk
		if y1 > rows {
			y1 = rows
		}
		if y0 >= y1 {
			wg.Done()
			continue
		}
		go func(a, b int) {
			defer wg.Done()
			fn(a, b)
		}(y0, y1)
	}
	wg.Wait()
}

func clampU8(v int32) uint8 {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return uint8(v)
}

func clampF(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
