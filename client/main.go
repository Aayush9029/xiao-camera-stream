package main

import (
	"crypto/sha1"
	_ "embed"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Aayush9029/xiao-camera-stream/client/bench"
	"github.com/Aayush9029/xiao-camera-stream/client/isp"
	"github.com/Aayush9029/xiao-camera-stream/client/stream"
)

//go:embed ui/index.html
var studioHTML []byte

// Minimal zero-dependency RFC 6455 binary WebSocket hub
type wsHub struct {
	mu      sync.Mutex
	clients map[net.Conn]struct{}
}

func newWSHub() *wsHub {
	return &wsHub{clients: make(map[net.Conn]struct{})}
}

func (h *wsHub) serveWS(w http.ResponseWriter, r *http.Request) {
	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		http.Error(w, "websocket required", http.StatusBadRequest)
		return
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijack unsupported", http.StatusInternalServerError)
		return
	}
	conn, rw, err := hj.Hijack()
	if err != nil {
		return
	}

	sum := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	accept := base64.StdEncoding.EncodeToString(sum[:])

	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
	if _, err := rw.WriteString(resp); err != nil {
		conn.Close()
		return
	}
	_ = rw.Flush()

	h.mu.Lock()
	h.clients[conn] = struct{}{}
	h.mu.Unlock()

	// Keep connection open until peer disconnects
	buf := make([]byte, 256)
	for {
		if _, err := conn.Read(buf); err != nil {
			break
		}
	}
	h.mu.Lock()
	delete(h.clients, conn)
	h.mu.Unlock()
	conn.Close()
}

func (h *wsHub) broadcastBinary(payload []byte) {
	h.mu.Lock()
	if len(h.clients) == 0 {
		h.mu.Unlock()
		return
	}
	conns := make([]net.Conn, 0, len(h.clients))
	for c := range h.clients {
		conns = append(conns, c)
	}
	h.mu.Unlock()

	// Build RFC 6455 binary frame header once
	var hdr [10]byte
	hdr[0] = 0x82 // FIN + binary opcode
	n := len(payload)
	var hlen int
	if n < 126 {
		hdr[1] = byte(n)
		hlen = 2
	} else if n < 65536 {
		hdr[1] = 126
		binary.BigEndian.PutUint16(hdr[2:4], uint16(n))
		hlen = 4
	} else {
		hdr[1] = 127
		binary.BigEndian.PutUint64(hdr[2:10], uint64(n))
		hlen = 10
	}

	for _, c := range conns {
		_ = c.SetWriteDeadline(time.Now().Add(200 * time.Millisecond))
		frame := net.Buffers{hdr[:hlen], payload}
		if _, err := frame.WriteTo(c); err != nil {
			h.mu.Lock()
			delete(h.clients, c)
			h.mu.Unlock()
			c.Close()
		}
	}
}

func autoDiscoverHost(given string) string {
	if given != "" {
		return given
	}
	candidates := []string{"xiao-cam.local", "192.168.2.106", "192.168.4.1"}
	for _, h := range candidates {
		c, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", h, stream.BinPort), 1200*time.Millisecond)
		if err == nil {
			c.Close()
			return h
		}
	}
	return "xiao-cam.local"
}

func main() {
	hostFlag := flag.String("host", "", "ESP32-S3 IP or hostname (default: auto-discover xiao-cam.local / LAN / AP)")
	listenFlag := flag.String("listen", "127.0.0.1:8090", "Local studio web UI address")
	benchFlag := flag.Bool("benchmark", false, "Run automated multi-mode performance & image fidelity benchmark")
	benchSec := flag.Float64("seconds", 5.0, "Duration per mode during benchmark")
	benchOut := flag.String("out", "./bench_output", "Output directory for benchmark samples and JSON report")
	modesFlag := flag.String("modes", "performance,balanced,quality", "Comma-separated modes to benchmark")
	screenURL := flag.String("screen-url", "", "Optional screen_test control URL (e.g. http://127.0.0.1:8099) for glass-to-glass latency")
	protoFlag := flag.String("proto", "udp", "Stream protocol: udp (fastest, port 83) or tcp (port 82)")
	flag.Parse()

	host := autoDiscoverHost(*hostFlag)
	log.Printf("[CLIENT] Target ESP32-S3 host: %s (proto=%s)", host, *protoFlag)

	if *benchFlag {
		modes := strings.Split(*modesFlag, ",")
		_, err := bench.RunBenchmark(host, modes, *benchSec, *benchOut, isp.DefaultConfig(), *screenURL, *protoFlag != "tcp")
		if err != nil {
			log.Fatalf("[BENCH] Failed: %v", err)
		}
		log.Printf("[BENCH] Done! Results saved in %s", *benchOut)
		return
	}

	cli := stream.NewClient(host)
	cli.UseUDP = (*protoFlag != "tcp")
	pipe := isp.NewPipeline()
	hub := newWSHub()

	var latestMu sync.RWMutex
	var latestJPEG []byte
	var ispMsAtomic atomic.Int64 // stored in microseconds

	// Latest-frame processing goroutine (never backs up TCP receiver!)
	rawCh := make(chan *stream.Frame, 2)
	go func() {
		for f := range rawCh {
			t0 := time.Now()
			_, outJPEG, err := pipe.ProcessJPEG(f.JPEG)
			if err != nil {
				outJPEG = f.JPEG
			}
			ispMsAtomic.Store(time.Since(t0).Microseconds())

			latestMu.Lock()
			latestJPEG = outJPEG
			latestMu.Unlock()

			hub.broadcastBinary(outJPEG)
		}
	}()

	go cli.Stream(func(f *stream.Frame) {
		select {
		case rawCh <- f:
		default:
			select {
			case <-rawCh:
			default:
			}
			rawCh <- f
		}
	})

	// Poll device status in background so UI telemetry is always instant
	var devMu sync.RWMutex
	var devStatus *stream.DeviceStatus
	go func() {
		for {
			if st, err := cli.GetStatus(); err == nil {
				devMu.Lock()
				devStatus = st
				devMu.Unlock()
			}
			time.Sleep(1 * time.Second)
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(studioHTML)
	})
	mux.HandleFunc("/ws", hub.serveWS)
	mux.HandleFunc("/snapshot.jpg", func(w http.ResponseWriter, r *http.Request) {
		latestMu.RLock()
		data := latestJPEG
		latestMu.RUnlock()
		if len(data) == 0 {
			http.Error(w, "no frame yet", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(data)
	})
	mux.HandleFunc("/api/telemetry", func(w http.ResponseWriter, r *http.Request) {
		devMu.RLock()
		ds := devStatus
		devMu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"client": cli.GetStats(),
			"device": ds,
			"isp":    pipe.GetConfig(),
			"isp_ms": float64(ispMsAtomic.Load()) / 1000.0,
		})
	})
	mux.HandleFunc("/api/mode", func(w http.ResponseWriter, r *http.Request) {
		m := r.URL.Query().Get("mode")
		st, err := cli.SetMode(m)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		pipe.ResetTemporal()
		devMu.Lock()
		devStatus = st
		devMu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st)
	})
	mux.HandleFunc("/api/camera", func(w http.ResponseWriter, r *http.Request) {
		params := make(map[string]string)
		for k, v := range r.URL.Query() {
			if len(v) > 0 {
				params[k] = v[0]
			}
		}
		st, err := cli.SetSettings(params)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		devMu.Lock()
		devStatus = st
		devMu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st)
	})
	mux.HandleFunc("/api/isp", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			var cfg isp.Config
			if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			pipe.SetConfig(cfg)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(pipe.GetConfig())
	})

	log.Printf("[STUDIO] Open http://%s in your browser!", *listenFlag)
	log.Fatal(http.ListenAndServe(*listenFlag, mux))
}
