package bench

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/Aayush9029/xiao-camera-stream/client/isp"
	"github.com/Aayush9029/xiao-camera-stream/client/stream"
)

type QualityMetrics struct {
	Width         int     `json:"width"`
	Height        int     `json:"height"`
	SharpnessLap  float64 `json:"sharpness_laplacian"` // Laplacian variance (higher = sharper)
	EdgeTenengrad float64 `json:"edge_tenengrad"`      // Sobel gradient energy (higher = crisper)
	NoiseFloor    float64 `json:"noise_floor"`         // Smooth-region local std (lower = cleaner)
	SNR_dB        float64 `json:"snr_db"`              // Signal-to-noise estimate (higher = better)
	DynamicRange  float64 `json:"dynamic_range"`       // p99 - p1 luma spread (0..255)
	RMSContrast   float64 `json:"rms_contrast"`        // Luma standard deviation
	MeanLuma      float64 `json:"mean_luma"`
	ColorCast     float64 `json:"color_cast"` // Channel imbalance metric
}

type ModeBenchResult struct {
	Mode            string         `json:"mode"`
	DurationSec     float64        `json:"duration_sec"`
	Frames          int            `json:"frames"`
	RxFPS           float64        `json:"rx_fps"`
	CaptureFPS      float64        `json:"capture_fps"`
	Mbps            float64        `json:"mbps"`
	AvgFrameKB      float64        `json:"avg_frame_kb"`
	P50IntervalMs   float64        `json:"p50_interval_ms"`
	P95IntervalMs   float64        `json:"p95_interval_ms"`
	P99IntervalMs   float64        `json:"p99_interval_ms"`
	JitterMs        float64        `json:"jitter_ms"`
	SeqGaps         uint64         `json:"seq_gaps"`
	ISPTimeMs       float64        `json:"isp_time_ms"`
	TempC           float64        `json:"temp_c"`
	RSSI            int            `json:"rssi"`
	Width           int            `json:"width"`
	Height          int            `json:"height"`
	QualityParam    int            `json:"quality_param"`
	LatencyMedianMs float64        `json:"latency_median_ms,omitempty"`
	LatencyMinMs    float64        `json:"latency_min_ms,omitempty"`
	LatencyMaxMs    float64        `json:"latency_max_ms,omitempty"`
	UdpNacks        uint64         `json:"udp_nacks_sent"`
	UdpIncomplete   uint64         `json:"udp_incomplete"`
	RawQuality      QualityMetrics `json:"raw_quality"`
	ISPQuality      QualityMetrics `json:"isp_quality"`
	RawSamplePath   string         `json:"raw_sample_path,omitempty"`
	ISPSamplePath   string         `json:"isp_sample_path,omitempty"`
	SplitPath       string         `json:"split_sample_path,omitempty"`
}

func AnalyzeImage(img image.Image) QualityMetrics {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w < 16 || h < 16 {
		return QualityMetrics{Width: w, Height: h}
	}

	luma := make([]float64, w*h)
	var hist [256]int
	var sumY, sumR, sumG, sumB float64

	for y := 0; y < h; y++ {
		row := y * w
		for x := 0; x < w; x++ {
			r, g, bl, _ := img.At(b.Min.X+x, b.Min.Y+y).RGBA()
			rf, gf, bf := float64(r>>8), float64(g>>8), float64(bl>>8)
			yv := 0.299*rf + 0.587*gf + 0.114*bf
			luma[row+x] = yv
			yi := int(yv + 0.5)
			if yi < 0 {
				yi = 0
			} else if yi > 255 {
				yi = 255
			}
			hist[yi]++
			sumY += yv
			sumR += rf
			sumG += gf
			sumB += bf
		}
	}

	n := float64(w * h)
	meanY := sumY / n

	var varY float64
	for _, yv := range luma {
		d := yv - meanY
		varY += d * d
	}
	rmsContrast := math.Sqrt(varY / n)

	// p1 and p99 dynamic range
	p1Cut := int(n * 0.01)
	p99Cut := int(n * 0.99)
	p1, p99, acc := 0, 255, 0
	for i := 0; i < 256; i++ {
		acc += hist[i]
		if acc >= p1Cut {
			p1 = i
			break
		}
	}
	acc = 0
	for i := 0; i < 256; i++ {
		acc += hist[i]
		if acc >= p99Cut {
			p99 = i
			break
		}
	}

	// Laplacian variance & Tenengrad Sobel energy (normalized per pixel)
	var lapSum, lapSqSum, sobelSum float64
	var lapN float64
	// Also estimate noise floor from 8x8 blocks with lowest variance (smooth patches)
	var blockStds []float64

	for y := 1; y < h-1; y++ {
		row := y * w
		for x := 1; x < w-1; x++ {
			i := row + x
			c := luma[i]
			lap := luma[i-w] + luma[i+w] + luma[i-1] + luma[i+1] - 4.0*c
			lapSum += lap
			lapSqSum += lap * lap

			gx := -luma[i-w-1] + luma[i-w+1] - 2*luma[i-1] + 2*luma[i+1] - luma[i+w-1] + luma[i+w+1]
			gy := -luma[i-w-1] - 2*luma[i-w] - luma[i-w+1] + luma[i+w-1] + 2*luma[i+w] + luma[i+w+1]
			sobelSum += math.Sqrt(gx*gx + gy*gy)
			lapN++
		}
	}

	lapMean := lapSum / lapN
	lapVar := (lapSqSum / lapN) - lapMean*lapMean

	// 8x8 block noise floor: take the 15th percentile of block standard deviations
	for by := 0; by <= h-8; by += 8 {
		for bx := 0; bx <= w-8; bx += 8 {
			var bs, bs2 float64
			for dy := 0; dy < 8; dy++ {
				row := (by + dy) * w
				for dx := 0; dx < 8; dx++ {
					v := luma[row+bx+dx]
					bs += v
					bs2 += v * v
				}
			}
			m := bs / 64.0
			v := bs2/64.0 - m*m
			if v < 0 {
				v = 0
			}
			// Ignore clipped dark room background and pure-white highlights
			if m > 35 && m < 225 {
				blockStds = append(blockStds, math.Sqrt(v))
			}
		}
	}
	noiseFloor := 0.0
	if len(blockStds) > 0 {
		sort.Float64s(blockStds)
		idx := len(blockStds) * 25 / 100
		if idx >= len(blockStds) {
			idx = len(blockStds) - 1
		}
		noiseFloor = blockStds[idx]
	}

	snr := 0.0
	if noiseFloor > 0.05 && rmsContrast > 0 {
		snr = 20.0 * math.Log10(rmsContrast/noiseFloor)
	}

	mR, mG, mB := sumR/n, sumG/n, sumB/n
	avgRGB := (mR + mG + mB) / 3.0
	colorCast := (math.Abs(mR-avgRGB) + math.Abs(mG-avgRGB) + math.Abs(mB-avgRGB)) / 3.0

	return QualityMetrics{
		Width:         w,
		Height:        h,
		SharpnessLap:  round2(lapVar),
		EdgeTenengrad: round2(sobelSum / lapN),
		NoiseFloor:    round2(noiseFloor),
		SNR_dB:        round2(snr),
		DynamicRange:  float64(p99 - p1),
		RMSContrast:   round2(rmsContrast),
		MeanLuma:      round2(meanY),
		ColorCast:     round2(colorCast),
	}
}

func quickMeanLuma(rawJPEG []byte) (float64, bool) {
	img, err := jpeg.Decode(bytes.NewReader(rawJPEG))
	if err != nil {
		return 0, false
	}
	if yc, ok := img.(*image.YCbCr); ok && len(yc.Y) > 0 {
		var sum uint64
		var cnt uint64
		step := 17
		for i := 0; i < len(yc.Y); i += step {
			sum += uint64(yc.Y[i])
			cnt++
		}
		return float64(sum) / float64(cnt), true
	}
	b := img.Bounds()
	var sum float64
	var cnt float64
	for y := b.Min.Y; y < b.Max.Y; y += 8 {
		for x := b.Min.X; x < b.Max.X; x += 8 {
			r, g, bl, _ := img.At(x, y).RGBA()
			sum += 0.299*float64(r>>8) + 0.587*float64(g>>8) + 0.114*float64(bl>>8)
			cnt++
		}
	}
	if cnt == 0 {
		return 0, false
	}
	return sum / cnt, true
}

func setScreenPattern(screenURL, mode string) (time.Time, error) {
	resp, err := http.Get(fmt.Sprintf("%s/mode?m=%s", screenURL, mode))
	if err != nil {
		return time.Time{}, err
	}
	defer resp.Body.Close()
	var out struct {
		TsNs int64 `json:"ts_ns"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&out)
	if out.TsNs > 0 {
		return time.Unix(0, out.TsNs), nil
	}
	return time.Now(), nil
}

// MeasureGlassToGlassLatency flashes Black -> White on screenURL and measures exact end-to-end ms.
func MeasureGlassToGlassLatency(frameCh <-chan *stream.Frame, screenURL string, trials int) (med, mn, mx float64) {
	var samples []float64
	for i := 0; i < trials; i++ {
		_, err := setScreenPattern(screenURL, "black")
		if err != nil {
			return 0, 0, 0
		}
		// Let screen & camera settle on black for 450ms and measure baseline dark luma
		settleEnd := time.Now().Add(450 * time.Millisecond)
		var darkLuma float64
		var darkN int
		for time.Now().Before(settleEnd) {
			select {
			case f := <-frameCh:
				if l, ok := quickMeanLuma(f.JPEG); ok {
					darkLuma += l
					darkN++
				}
			case <-time.After(30 * time.Millisecond):
			}
		}
		if darkN > 0 {
			darkLuma /= float64(darkN)
		}

		// Drain buffered frames right before flash
		for len(frameCh) > 0 {
			<-frameCh
		}

		// Flash WHITE and wait for camera frame luma to jump by +20 (or +12 if bright room)
		flashTime, err := setScreenPattern(screenURL, "white")
		if err != nil {
			break
		}
		thresh := darkLuma + 18.0
		if thresh > 210 {
			thresh = darkLuma + 10.0
		}

		timeout := time.After(900 * time.Millisecond)
	waitLoop:
		for {
			select {
			case f := <-frameCh:
				if l, ok := quickMeanLuma(f.JPEG); ok && l >= thresh {
					latMs := float64(f.RecvTime.Sub(flashTime).Microseconds()) / 1000.0
					if latMs > 5 && latMs < 850 {
						samples = append(samples, latMs)
					}
					break waitLoop
				}
			case <-timeout:
				break waitLoop
			}
		}
	}
	_, _ = setScreenPattern(screenURL, "chart")
	if len(samples) == 0 {
		return 0, 0, 0
	}
	sort.Float64s(samples)
	return round2(percentile(samples, 50)), round2(samples[0]), round2(samples[len(samples)-1])
}

func RunBenchmark(host string, modes []string, secondsPerMode float64, outDir string, ispCfg isp.Config, screenURL string, useUDP bool) ([]ModeBenchResult, error) {
	if outDir != "" {
		if err := os.MkdirAll(outDir, 0755); err != nil {
			return nil, err
		}
	}
	cli := stream.NewClient(host)
	cli.UseUDP = useUDP
	frameCh := make(chan *stream.Frame, 8)

	done := make(chan struct{})
	go func() {
		defer close(done)
		cli.Stream(func(f *stream.Frame) {
			select {
			case frameCh <- f:
			default:
				// Drop oldest if consumer busy
				select {
				case <-frameCh:
				default:
				}
				frameCh <- f
			}
		})
	}()
	defer func() { cli.Stop(); <-done }()

	// Wait for initial frame
	select {
	case <-frameCh:
	case <-time.After(6 * time.Second):
		return nil, fmt.Errorf("timeout connecting to stream at %s", host)
	}

	pipe := isp.NewPipeline()
	pipe.SetConfig(ispCfg)

	var results []ModeBenchResult

	for _, m := range modes {
		fmt.Printf("\n[BENCH] Switching to mode: %s ...\n", m)
		if _, err := cli.SetMode(m); err != nil {
			return results, fmt.Errorf("SetMode(%s): %w", m, err)
		}
		pipe.ResetTemporal()

		// Warmup 1.2s so sensor AEC/AWB + stream stabilize in the new mode
		warmEnd := time.Now().Add(1200 * time.Millisecond)
		for time.Now().Before(warmEnd) {
			select {
			case f := <-frameCh:
				// Feed ISP temporal buffer during warmup
				if img, err := jpeg.Decode(bytes.NewReader(f.JPEG)); err == nil {
					_ = pipe.ProcessImage(img, ispCfg)
				}
			case <-time.After(100 * time.Millisecond):
			}
		}

		// Measure window
		var intervals []float64
		var totalBytes uint64
		var frames int
		var lastSeq uint32
		var seqGaps uint64
		var prevT time.Time
		var lastFrame *stream.Frame
		var rawImg image.Image
		var ispMsSum float64
		var ispSamples int

		startStats := cli.GetStats()
		t0 := time.Now()
		deadline := t0.Add(time.Duration(secondsPerMode * float64(time.Second)))

		for time.Now().Before(deadline) {
			select {
			case f := <-frameCh:
				if f.RecvTime.Before(t0) || stream.ModeName(f.Mode) != m {
					continue
				}
				pt0 := time.Now()
				img, err := jpeg.Decode(bytes.NewReader(f.JPEG))
				if err != nil {
					return results, fmt.Errorf("%s frame %d: %w", m, f.Seq, err)
				}
				if img.Bounds().Dx() != int(f.Width) || img.Bounds().Dy() != int(f.Height) {
					return results, fmt.Errorf("%s frame %d dimensions disagree with header", m, f.Seq)
				}
				if lastSeq != 0 && f.Seq > lastSeq+1 {
					seqGaps += uint64(f.Seq - lastSeq - 1)
				}
				lastSeq = f.Seq
				if !prevT.IsZero() {
					intervals = append(intervals, float64(f.RecvTime.Sub(prevT).Microseconds())/1000.0)
				}
				prevT = f.RecvTime
				totalBytes += uint64(stream.HeaderSize + len(f.JPEG))
				frames++
				lastFrame = f
				rawImg = img

				if frames <= 8 || frames%3 == 0 {
					_ = pipe.ProcessImage(img, ispCfg)
					ispMsSum += float64(time.Since(pt0).Microseconds()) / 1000
					ispSamples++
				}
			case <-time.After(500 * time.Millisecond):
			}
		}
		dt := time.Since(t0).Seconds()

		if frames == 0 {
			return results, fmt.Errorf("no %s frames received", m)
		}
		devSt, err := cli.GetStatus()
		if err != nil {
			return results, fmt.Errorf("reading %s telemetry: %w", m, err)
		}

		cStats := cli.GetStats()
		res := ModeBenchResult{
			Mode:          m,
			DurationSec:   round2(dt),
			Frames:        frames,
			RxFPS:         round2(float64(frames) / dt),
			Mbps:          round2((float64(totalBytes) * 8.0 / 1e6) / dt),
			SeqGaps:       seqGaps,
			UdpNacks:      cStats.UdpNacksSent - startStats.UdpNacksSent,
			UdpIncomplete: cStats.UdpIncomplete - startStats.UdpIncomplete,
		}
		if frames > 0 {
			res.AvgFrameKB = round2((float64(totalBytes) / float64(frames)) / 1024.0)
		}
		if ispSamples > 0 {
			res.ISPTimeMs = round2(ispMsSum / float64(ispSamples))
		}
		if devSt != nil {
			res.CaptureFPS = round2(devSt.CaptureFPS)
			res.TempC = round2(devSt.TempC)
			res.RSSI = devSt.RSSI
			res.Width = devSt.Width
			res.Height = devSt.Height
			res.QualityParam = devSt.Quality
		}
		if len(intervals) > 0 {
			sort.Float64s(intervals)
			res.P50IntervalMs = round2(percentile(intervals, 50))
			res.P95IntervalMs = round2(percentile(intervals, 95))
			res.P99IntervalMs = round2(percentile(intervals, 99))
			var mean float64
			for _, v := range intervals {
				mean += v
			}
			mean /= float64(len(intervals))
			var jsum float64
			for _, v := range intervals {
				jsum += math.Abs(v - mean)
			}
			res.JitterMs = round2(jsum / float64(len(intervals)))
		}

		// Analyze & save raw vs post-processed sample frames
		{
			res.RawQuality = AnalyzeImage(rawImg)
			procImg := pipe.ProcessImage(rawImg, ispCfg)
			res.ISPQuality = AnalyzeImage(procImg)

			if outDir != "" {
				rawPath := filepath.Join(outDir, fmt.Sprintf("%s_raw.jpg", m))
				ispPath := filepath.Join(outDir, fmt.Sprintf("%s_isp.jpg", m))
				splitPath := filepath.Join(outDir, fmt.Sprintf("%s_split.jpg", m))

				if err := os.WriteFile(rawPath, lastFrame.JPEG, 0644); err != nil {
					return results, err
				}
				if err := saveJPEG(ispPath, procImg, 94); err != nil {
					return results, err
				}

				splitCfg := ispCfg
				splitCfg.SplitCompare = 50
				splitImg := pipe.ProcessImage(rawImg, splitCfg)
				if err := saveJPEG(splitPath, splitImg, 94); err != nil {
					return results, err
				}

				res.RawSamplePath = rawPath
				res.ISPSamplePath = ispPath
				res.SplitPath = splitPath
			}
		}

		if screenURL != "" {
			med, mn, mx := MeasureGlassToGlassLatency(frameCh, screenURL, 5)
			res.LatencyMedianMs = med
			res.LatencyMinMs = mn
			res.LatencyMaxMs = mx
		}

		fmt.Printf("[BENCH] %-11s | %4dx%-4d Q=%-2d | Rx: %5.1f FPS (Cap: %5.1f) | %5.2f Mbps | %5.1f KB/f | p95: %5.1f ms | ISP: %4.1f ms | Temp: %.1fC\n",
			res.Mode, res.Width, res.Height, res.QualityParam,
			res.RxFPS, res.CaptureFPS, res.Mbps, res.AvgFrameKB,
			res.P95IntervalMs, res.ISPTimeMs, res.TempC)
		if res.LatencyMedianMs > 0 {
			fmt.Printf("        Latency     | Screen change to receipt: %.1f ms median (min %.1f / max %.1f ms) | UDP NACKs: %d | Incomplete: %d\n",
				res.LatencyMedianMs, res.LatencyMinMs, res.LatencyMaxMs, res.UdpNacks, res.UdpIncomplete)
		}
		fmt.Printf("        Fidelity    | Sharpness: %.1f -> %.1f | Noise: %.2f -> %.2f | SNR: %.1f -> %.1f dB | DynRange: %.0f -> %.0f | Cast: %.1f -> %.1f\n",
			res.RawQuality.SharpnessLap, res.ISPQuality.SharpnessLap,
			res.RawQuality.NoiseFloor, res.ISPQuality.NoiseFloor,
			res.RawQuality.SNR_dB, res.ISPQuality.SNR_dB,
			res.RawQuality.DynamicRange, res.ISPQuality.DynamicRange,
			res.RawQuality.ColorCast, res.ISPQuality.ColorCast)

		results = append(results, res)
	}

	if outDir != "" {
		b, err := json.MarshalIndent(results, "", "  ")
		if err != nil {
			return results, err
		}
		if err := os.WriteFile(filepath.Join(outDir, "benchmark_results.json"), b, 0644); err != nil {
			return results, err
		}
	}
	return results, nil
}

func saveJPEG(path string, img image.Image, q int) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	if err := jpeg.Encode(f, img, &jpeg.Options{Quality: q}); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func percentile(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(math.Ceil((p/100.0)*float64(len(sorted)))) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

func round2(v float64) float64 {
	return math.Round(v*100) / 100
}
