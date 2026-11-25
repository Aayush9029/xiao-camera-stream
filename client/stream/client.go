package stream

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"sync"
	"sync/atomic"
	"time"
)

const (
	FrameMagic    uint32 = 0x52545358 // "XSTR" little-endian (TCP)
	UdpChunkMagic uint32 = 0x55545358 // "XSTU" little-endian (UDP)
	HeaderSize           = 28
	UdpHeaderSize        = 32
	UdpChunkBytes        = 1400
	BinPort              = 82
	UdpPort              = 83
	ControlPort          = 80
)

type Frame struct {
	Seq        uint32
	DeviceTsUs uint64
	RecvTime   time.Time
	Width      uint16
	Height     uint16
	Mode       uint8
	Quality    uint8
	TempC      float32
	JPEG       []byte
}

func ModeName(m uint8) string {
	switch m {
	case 0:
		return "performance"
	case 1:
		return "balanced"
	case 2:
		return "quality"
	default:
		return "custom"
	}
}

type DeviceStatus struct {
	Device         string  `json:"device"`
	Sensor         string  `json:"sensor"`
	XclkMHz        int     `json:"xclk_mhz"`
	Mode           string  `json:"mode"`
	Framesize      int     `json:"framesize"`
	Width          int     `json:"width"`
	Height         int     `json:"height"`
	Quality        int     `json:"quality"`
	CaptureFPS     float64 `json:"capture_fps"`
	StreamFPS      float64 `json:"stream_fps"`
	TxKbps         float64 `json:"tx_kbps"`
	MeanFrameBytes int     `json:"mean_frame_bytes"`
	FramesCaptured uint32  `json:"frames_captured"`
	FramesSent     uint32  `json:"frames_sent"`
	FramesDropped  uint32  `json:"frames_dropped"`
	CamErrors      uint32  `json:"cam_errors"`
	ClientsUDP     int     `json:"clients_udp"`
	ClientsBin     int     `json:"clients_bin"`
	ClientsMjpeg   int     `json:"clients_mjpeg"`
	TempC          float64 `json:"temp_c"`
	RSSI           int     `json:"rssi"`
	WifiMode       string  `json:"wifi_mode"`
	SSID           string  `json:"ssid"`
	IP             string  `json:"ip"`
	FreeHeap       uint32  `json:"free_heap"`
	FreePSRAM      uint32  `json:"free_psram"`
	UptimeS        uint32  `json:"uptime_s"`
	Brightness     int     `json:"brightness"`
	Contrast       int     `json:"contrast"`
	Saturation     int     `json:"saturation"`
	Sharpness      int     `json:"sharpness"`
	Denoise        int     `json:"denoise"`
	AeLevel        int     `json:"ae_level"`
	Aec2           int     `json:"aec2"`
	GainCeiling    int     `json:"gainceiling"`
	HMirror        int     `json:"hmirror"`
	VFlip          int     `json:"vflip"`
}

type Stats struct {
	Connected     bool    `json:"connected"`
	Protocol      string  `json:"protocol"`
	RxFPS         float64 `json:"rx_fps"`
	RxMbps        float64 `json:"rx_mbps"`
	AvgFrameKB    float64 `json:"avg_frame_kb"`
	JitterMs      float64 `json:"jitter_ms"`
	TotalFrames   uint64  `json:"total_frames"`
	SeqGaps       uint64  `json:"seq_gaps"`
	UdpIncomplete uint64  `json:"udp_incomplete"`
	UdpNacksSent  uint64  `json:"udp_nacks_sent"`
	Width         int     `json:"width"`
	Height        int     `json:"height"`
	Mode          string  `json:"mode"`
	Quality       int     `json:"quality"`
	TempC         float32 `json:"temp_c"`
	LastFrameAge  float64 `json:"last_frame_age_ms"`
}

type Client struct {
	Host       string
	UseUDP     bool
	httpClient *http.Client

	mu       sync.RWMutex
	stats    Stats
	lastRecv time.Time
	running  atomic.Bool
	stopCh   chan struct{}
}

func NewClient(host string) *Client {
	return &Client{
		Host:   host,
		UseUDP: true, // Default to ultra-fast Port 83 UDP!
		httpClient: &http.Client{
			Timeout: 4 * time.Second,
		},
		stopCh: make(chan struct{}),
	}
}

func (c *Client) ControlURL(path string) string {
	return fmt.Sprintf("http://%s:%d%s", c.Host, ControlPort, path)
}

func (c *Client) GetStatus() (*DeviceStatus, error) {
	resp, err := c.httpClient.Get(c.ControlURL("/api/status"))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("status HTTP %d", resp.StatusCode)
	}
	var st DeviceStatus
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		return nil, err
	}
	return &st, nil
}

func (c *Client) SetMode(mode string) (*DeviceStatus, error) {
	u := c.ControlURL("/api/mode?mode=" + url.QueryEscape(mode))
	resp, err := c.httpClient.Post(u, "text/plain", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("mode HTTP %d", resp.StatusCode)
	}
	var st DeviceStatus
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		return nil, err
	}
	return &st, nil
}

func (c *Client) SetSettings(params map[string]string) (*DeviceStatus, error) {
	q := url.Values{}
	for k, v := range params {
		q.Set(k, v)
	}
	u := c.ControlURL("/api/settings?" + q.Encode())
	resp, err := c.httpClient.Post(u, "text/plain", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("settings HTTP %d", resp.StatusCode)
	}
	var st DeviceStatus
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		return nil, err
	}
	return &st, nil
}

func (c *Client) GetStats() Stats {
	c.mu.RLock()
	st := c.stats
	lr := c.lastRecv
	c.mu.RUnlock()
	if !lr.IsZero() {
		st.LastFrameAge = float64(time.Since(lr).Microseconds()) / 1000.0
	}
	return st
}

func (c *Client) Stop() {
	if c.running.Swap(false) {
		close(c.stopCh)
	}
}

func (c *Client) Stream(onFrame func(*Frame)) {
	c.running.Store(true)
	for c.running.Load() {
		var err error
		if c.UseUDP {
			err = c.streamUDP(onFrame)
		} else {
			err = c.streamTCP(onFrame)
		}
		c.mu.Lock()
		c.stats.Connected = false
		c.mu.Unlock()
		if !c.running.Load() {
			return
		}
		_ = err
		select {
		case <-c.stopCh:
			return
		case <-time.After(350 * time.Millisecond):
		}
	}
}

type udpAssembly struct {
	seq        uint32
	tsUs       uint64
	width      uint16
	height     uint16
	mode       uint8
	quality    uint8
	tempX10    int16
	frameLen   uint32
	chunkCount uint16
	gotCount   uint16
	maxSeenIdx uint16
	nackSent   bool
	startedAt  time.Time
	buf        []byte
	seen       []bool
}

func sendNack(conn *net.UDPConn, a *udpAssembly, limit uint16) int {
	var missing []uint16
	for i := uint16(0); i < limit && len(missing) < 24; i++ {
		if !a.seen[i] {
			missing = append(missing, i)
		}
	}
	if len(missing) == 0 {
		return 0
	}
	buf := make([]byte, 10+len(missing)*2)
	copy(buf[0:4], "NACK")
	binary.LittleEndian.PutUint32(buf[4:8], a.seq)
	binary.LittleEndian.PutUint16(buf[8:10], uint16(len(missing)))
	for i, ci := range missing {
		binary.LittleEndian.PutUint16(buf[10+i*2:12+i*2], ci)
	}
	_, _ = conn.Write(buf)
	return len(missing)
}

func (c *Client) streamUDP(onFrame func(*Frame)) error {
	raddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", c.Host, UdpPort))
	if err != nil {
		return err
	}
	conn, err := net.DialUDP("udp4", nil, raddr)
	if err != nil {
		return err
	}
	defer func() {
		_, _ = conn.Write([]byte("BYE!"))
		conn.Close()
	}()
	_ = conn.SetReadBuffer(4 * 1024 * 1024)

	c.mu.Lock()
	c.stats.Protocol = "UDP+NACK"
	c.mu.Unlock()

	_, _ = conn.Write([]byte("SUB!"))
	keepDone := make(chan struct{})
	go func() {
		t := time.NewTicker(1500 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-keepDone:
				return
			case <-c.stopCh:
				return
			case <-t.C:
				_, _ = conn.Write([]byte("SUB!"))
			}
		}
	}()
	defer close(keepDone)

	pkt := make([]byte, 2048)
	// Keep up to 3 in-flight frame assemblies so NACK retransmits never collide with newer frames!
	inFlight := make(map[uint32]*udpAssembly, 4)
	var highestSeq uint32
	var lastDeliveredSeq uint32
	var winFrames, winBytes uint64
	winStart := time.Now()
	var prevFrameTime time.Time
	var emaIntervalMs, emaJitterMs float64

	for c.running.Load() {
		_ = conn.SetReadDeadline(time.Now().Add(2500 * time.Millisecond))
		n, err := conn.Read(pkt)
		if err != nil {
			return err
		}
		if n < UdpHeaderSize {
			continue
		}
		magic := binary.LittleEndian.Uint32(pkt[0:4])
		if magic != UdpChunkMagic {
			continue
		}

		seq := binary.LittleEndian.Uint32(pkt[4:8])
		tsUs := binary.LittleEndian.Uint64(pkt[8:16])
		w := binary.LittleEndian.Uint16(pkt[16:18])
		h := binary.LittleEndian.Uint16(pkt[18:20])
		cidx := binary.LittleEndian.Uint16(pkt[20:22])
		ccnt := binary.LittleEndian.Uint16(pkt[22:24])
		flen := binary.LittleEndian.Uint32(pkt[24:28])
		mode := pkt[28]
		qual := pkt[29]
		tempX10 := int16(binary.LittleEndian.Uint16(pkt[30:32]))

		if ccnt == 0 || cidx >= ccnt || flen < 64 || flen > 1024*1024 {
			continue
		}
		expectedChunks := (int(flen) + UdpChunkBytes - 1) / UdpChunkBytes
		payloadSize := min(UdpChunkBytes, int(flen)-int(cidx)*UdpChunkBytes)
		if int(ccnt) != expectedChunks || n-UdpHeaderSize != payloadSize {
			continue
		}
		if seq <= lastDeliveredSeq {
			continue
		}

		cur := inFlight[seq]
		if cur == nil {
			if seq > highestSeq {
				highestSeq = seq
			}
			// Evict stale incomplete frames older than highestSeq-2
			for s, old := range inFlight {
				if highestSeq > 2 && s < highestSeq-2 {
					if old.gotCount < old.chunkCount {
						c.mu.Lock()
						c.stats.UdpIncomplete++
						c.mu.Unlock()
					}
					delete(inFlight, s)
				}
			}
			// If an earlier frame is almost done when a new frame begins, trigger one NACK for it!
			for s, old := range inFlight {
				if s < seq && !old.nackSent && old.gotCount < old.chunkCount && (old.chunkCount-old.gotCount) <= 24 {
					old.nackSent = true
					if sendNack(conn, old, old.chunkCount) > 0 {
						c.mu.Lock()
						c.stats.UdpNacksSent++
						c.mu.Unlock()
					}
				}
			}
			cur = &udpAssembly{
				seq:        seq,
				tsUs:       tsUs,
				width:      w,
				height:     h,
				mode:       mode,
				quality:    qual,
				tempX10:    tempX10,
				frameLen:   flen,
				chunkCount: ccnt,
				startedAt:  time.Now(),
				buf:        make([]byte, flen),
				seen:       make([]bool, ccnt),
			}
			inFlight[seq] = cur
		}

		if cur.frameLen != flen || cur.chunkCount != ccnt {
			continue
		}
		if !cur.seen[cidx] {
			payload := pkt[UdpHeaderSize:n]
			off := int(cidx) * UdpChunkBytes
			if off+len(payload) <= len(cur.buf) {
				copy(cur.buf[off:off+len(payload)], payload)
				cur.seen[cidx] = true
				cur.gotCount++
				if cidx > cur.maxSeenIdx {
					cur.maxSeenIdx = cidx
				}
			}
		}

		// If last chunk arrived OR we're >4 chunks past a missing gap, trigger proactive NACK!
		if cur.gotCount < cur.chunkCount && !cur.nackSent {
			if cidx == cur.chunkCount-1 || (cur.maxSeenIdx >= 8 && int(cur.maxSeenIdx)-int(cur.gotCount) >= 3) {
				cur.nackSent = true
				if sendNack(conn, cur, cur.maxSeenIdx+1) > 0 {
					c.mu.Lock()
					c.stats.UdpNacksSent++
					c.mu.Unlock()
				}
			}
		} else if cidx == cur.chunkCount-1 && cur.gotCount < cur.chunkCount && time.Since(cur.startedAt) > 12*time.Millisecond {
			// Second-chance NACK on tail packet if earlier holes remain
			if sendNack(conn, cur, cur.maxSeenIdx+1) > 0 {
				c.mu.Lock()
				c.stats.UdpNacksSent++
				c.mu.Unlock()
			}
		}

		if cur.gotCount == cur.chunkCount {
			delete(inFlight, seq)
			// Clean up any older abandoned frames
			for s, old := range inFlight {
				if s < seq {
					if old.gotCount < old.chunkCount {
						c.mu.Lock()
						c.stats.UdpIncomplete++
						c.mu.Unlock()
					}
					delete(inFlight, s)
				}
			}

			now := time.Now()
			var gap uint64
			if lastDeliveredSeq != 0 && cur.seq > lastDeliveredSeq+1 {
				gap = uint64(cur.seq - lastDeliveredSeq - 1)
			}
			lastDeliveredSeq = cur.seq

			if !prevFrameTime.IsZero() {
				dtMs := float64(now.Sub(prevFrameTime).Microseconds()) / 1000.0
				if emaIntervalMs == 0 {
					emaIntervalMs = dtMs
				} else {
					diff := dtMs - emaIntervalMs
					if diff < 0 {
						diff = -diff
					}
					emaJitterMs = emaJitterMs*0.85 + diff*0.15
					emaIntervalMs = emaIntervalMs*0.85 + dtMs*0.15
				}
			}
			prevFrameTime = now

			winFrames++
			winBytes += uint64(cur.frameLen) + uint64(cur.chunkCount)*UdpHeaderSize

			c.mu.Lock()
			c.stats.Connected = true
			c.lastRecv = now
			c.stats.TotalFrames++
			c.stats.SeqGaps += gap
			c.stats.Width = int(cur.width)
			c.stats.Height = int(cur.height)
			c.stats.Mode = ModeName(cur.mode)
			c.stats.Quality = int(cur.quality)
			c.stats.TempC = float32(cur.tempX10) / 10.0
			c.stats.JitterMs = emaJitterMs

			elapsed := now.Sub(winStart).Seconds()
			if elapsed >= 0.5 {
				c.stats.RxFPS = float64(winFrames) / elapsed
				c.stats.RxMbps = (float64(winBytes) * 8.0 / 1e6) / elapsed
				c.stats.AvgFrameKB = (float64(winBytes) / float64(winFrames)) / 1024.0
				winFrames = 0
				winBytes = 0
				winStart = now
			}
			c.mu.Unlock()

			f := &Frame{
				Seq:        cur.seq,
				DeviceTsUs: cur.tsUs,
				RecvTime:   now,
				Width:      cur.width,
				Height:     cur.height,
				Mode:       cur.mode,
				Quality:    cur.quality,
				TempC:      float32(cur.tempX10) / 10.0,
				JPEG:       cur.buf,
			}
			onFrame(f)
		}
	}
	return nil
}

func (c *Client) streamTCP(onFrame func(*Frame)) error {
	addr := net.JoinHostPort(c.Host, fmt.Sprint(BinPort))
	conn, err := net.DialTimeout("tcp", addr, 3*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	if tc, ok := conn.(*net.TCPConn); ok {
		_ = tc.SetNoDelay(true)
		_ = tc.SetReadBuffer(512 * 1024)
	}

	c.mu.Lock()
	c.stats.Connected = true
	c.stats.Protocol = "TCP"
	c.mu.Unlock()

	reader := bufio.NewReaderSize(conn, 256*1024)
	var hdr [HeaderSize]byte

	var lastSeq uint32
	var winFrames, winBytes uint64
	winStart := time.Now()
	var prevFrameTime time.Time
	var emaIntervalMs, emaJitterMs float64

	for c.running.Load() {
		_ = conn.SetReadDeadline(time.Now().Add(4 * time.Second))
		if _, err := io.ReadFull(reader, hdr[:]); err != nil {
			return err
		}

		magic := binary.LittleEndian.Uint32(hdr[0:4])
		if magic != FrameMagic {
			return errors.New("stream desync: bad magic")
		}

		seq := binary.LittleEndian.Uint32(hdr[4:8])
		tsUs := binary.LittleEndian.Uint64(hdr[8:16])
		w := binary.LittleEndian.Uint16(hdr[16:18])
		h := binary.LittleEndian.Uint16(hdr[18:20])
		mode := hdr[20]
		qual := hdr[21]
		tempX10 := int16(binary.LittleEndian.Uint16(hdr[22:24]))
		plen := binary.LittleEndian.Uint32(hdr[24:28])

		if plen < 64 || plen > 1024*1024 {
			return fmt.Errorf("invalid payload len: %d", plen)
		}

		payload := make([]byte, plen)
		if _, err := io.ReadFull(reader, payload); err != nil {
			return err
		}

		now := time.Now()
		var gap uint64
		if lastSeq != 0 && seq > lastSeq+1 {
			gap = uint64(seq - lastSeq - 1)
		}
		lastSeq = seq

		if !prevFrameTime.IsZero() {
			dtMs := float64(now.Sub(prevFrameTime).Microseconds()) / 1000.0
			if emaIntervalMs == 0 {
				emaIntervalMs = dtMs
			} else {
				diff := dtMs - emaIntervalMs
				if diff < 0 {
					diff = -diff
				}
				emaJitterMs = emaJitterMs*0.85 + diff*0.15
				emaIntervalMs = emaIntervalMs*0.85 + dtMs*0.15
			}
		}
		prevFrameTime = now

		winFrames++
		winBytes += uint64(HeaderSize + plen)

		c.mu.Lock()
		c.lastRecv = now
		c.stats.TotalFrames++
		c.stats.SeqGaps += gap
		c.stats.Width = int(w)
		c.stats.Height = int(h)
		c.stats.Mode = ModeName(mode)
		c.stats.Quality = int(qual)
		c.stats.TempC = float32(tempX10) / 10.0
		c.stats.JitterMs = emaJitterMs

		elapsed := now.Sub(winStart).Seconds()
		if elapsed >= 0.5 {
			c.stats.RxFPS = float64(winFrames) / elapsed
			c.stats.RxMbps = (float64(winBytes) * 8.0 / 1e6) / elapsed
			c.stats.AvgFrameKB = (float64(winBytes) / float64(winFrames)) / 1024.0
			winFrames = 0
			winBytes = 0
			winStart = now
		}
		c.mu.Unlock()

		f := &Frame{
			Seq:        seq,
			DeviceTsUs: tsUs,
			RecvTime:   now,
			Width:      w,
			Height:     h,
			Mode:       mode,
			Quality:    qual,
			TempC:      float32(tempX10) / 10.0,
			JPEG:       payload,
		}
		onFrame(f)
	}
	return nil
}
