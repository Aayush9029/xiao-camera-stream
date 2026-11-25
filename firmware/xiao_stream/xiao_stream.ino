/*
 * XIAO ESP32-S3 Sense Ultra-Performance Video Streaming Server (v4)
 *
 * Key Engineering Optimizations:
 * - Core 1: Camera Capture Task (prio 5) + Token-Bucket Paced UDP+NACK TX Task (prio 4)
 *           -> Leaves Core 0 100% free for Wi-Fi MAC, LwIP, Camera DMA ISR, and HTTP API!
 * - Port 83: Reliable Low-Latency Fragmented UDP + Selective NACK ARQ
 *            Microsecond token-bucket pacer (default 14 Mbps, live tunable 6-24 Mbps)
 *            matches 2.4GHz 802.11n airtime so the 8-slot Wi-Fi TX ring NEVER overflows!
 * - Adaptive Wi-Fi TX Power Control: 13 dBm when close (much cooler!), auto-boosts to
 *            19.5 dBm max range when far away on a power bank!
 * - Pure Wi-Fi STA + automatic Portable Power-Bank AP fallback (`XIAO-Cam`),
 *            WIFI_PS_NONE, BT/BLE completely disabled (100% dedicated 2.4GHz antenna).
 * - Port 82 (Binary TCP) + Port 81 (Multi-Client HTTP MJPEG) + Port 80 (Web UI & REST API)
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <esp_camera.h>
#include <esp_wifi.h>
#include <esp_http_server.h>
#include <esp_timer.h>
#include <esp_heap_caps.h>
#include <driver/temperature_sensor.h>
#include <lwip/sockets.h>
#include <lwip/netdb.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <atomic>

#include "camera_pins.h"
#include "modes.h"
#include "web_ui.h"

// ==================== Configuration ====================
static constexpr int    kXclkFreqHz      = 20000000;
static constexpr int    kRingSlots       = 4;
static constexpr size_t kMaxFrameBytes   = 768 * 1024;
static constexpr int    kMjpegStreamPort = 81;
static constexpr int    kBinStreamPort   = 82;
static constexpr int    kUdpStreamPort   = 83;
static constexpr int    kMaxBinClients   = 3;
static constexpr int    kMaxMjpegClients = 3;
static constexpr int    kMaxUdpSubs      = 4;
static constexpr size_t kUdpChunkPayload = 1400; // 32B hdr + 1400B = 1432B < 1472B MTU
static constexpr char   kMdnsHost[]      = "xiao-cam";
static constexpr char   kApSsid[]        = "XIAO-Cam";
#include "wifi_private.h"

// ==================== Protocols ====================
static constexpr uint32_t kTcpFrameMagic = 0x52545358; // "XSTR"
static constexpr uint32_t kUdpChunkMagic = 0x55545358; // "XSTU"

struct __attribute__((packed)) FrameHeader {
  uint32_t magic;
  uint32_t seq;
  uint64_t ts_us;
  uint16_t width;
  uint16_t height;
  uint8_t  mode;
  uint8_t  quality;
  int16_t  temp_c_x10;
  uint32_t payload_len;
};
static_assert(sizeof(FrameHeader) == 28, "FrameHeader size");

struct __attribute__((packed)) UdpChunkHeader {
  uint32_t magic;
  uint32_t seq;
  uint64_t ts_us;
  uint16_t width;
  uint16_t height;
  uint16_t chunk_idx;
  uint16_t chunk_count;
  uint32_t frame_len;
  uint8_t  mode;
  uint8_t  quality;
  int16_t  temp_c_x10;
};
static_assert(sizeof(UdpChunkHeader) == 32, "UdpChunkHeader size");

struct FrameSlot {
  uint8_t*  buf;
  size_t    jpeg_len;
  uint32_t  seq;
  uint64_t  ts_us;
  uint16_t  width;
  uint16_t  height;
  uint8_t   mode;
  uint8_t   quality;
  int16_t   temp_c_x10;
  int       refcount;
  bool      writing;
};

struct UdpSub {
  struct sockaddr_in addr;
  uint64_t last_seen_us;
  bool active;
};

// ==================== Global State ====================
static FrameSlot         g_slots[kRingSlots];
static portMUX_TYPE      g_ring_mux = portMUX_INITIALIZER_UNLOCKED;
static int               g_latest_slot = -1;
static uint32_t          g_frame_seq = 0;

static portMUX_TYPE      g_cfg_mux = portMUX_INITIALIZER_UNLOCKED;
static StreamMode        g_mode = MODE_BALANCED;
static CameraProfile     g_profile = kDefaultProfiles[MODE_BALANCED];
static volatile bool     g_profile_dirty = false;
static volatile uint32_t g_profile_gen = 0;
static std::atomic<uint32_t> g_applied_gen{0};

// Smooth UDP token-bucket target rate in Mbps (tunable live via ?udp_mbps=6..28)
static std::atomic<int>  g_udp_mbps{14};
static std::atomic<int>  g_tx_power_qdbm{60};

// Optional one-shot SCCB register write queued for captureTask
static volatile bool     g_reg_dirty = false;
static volatile int      g_reg_addr = 0;
static volatile int      g_reg_mask = 0xFF;
static volatile int      g_reg_val  = 0;

static bool              g_camera_ok = false;
static char              g_sensor_name[24] = "unknown";
static int               g_xclk_mhz = kXclkFreqHz / 1000000;

static UdpSub            g_udp_subs[kMaxUdpSubs];
static portMUX_TYPE      g_udp_mux = portMUX_INITIALIZER_UNLOCKED;

// Telemetry counters
static std::atomic<uint32_t> g_frames_captured{0};
static std::atomic<uint32_t> g_frames_sent{0};
static std::atomic<uint32_t> g_frames_dropped{0};
static std::atomic<uint32_t> g_cam_errors{0};
static std::atomic<uint32_t> g_nack_retrans{0};
static std::atomic<uint32_t> g_bytes_sent_window{0};
static std::atomic<uint32_t> g_frames_sent_window{0};
static std::atomic<uint32_t> g_frames_cap_window{0};
static std::atomic<int>      g_bin_clients{0};
static std::atomic<int>      g_mjpeg_clients{0};
static std::atomic<int>      g_udp_clients{0};

static float             g_capture_fps = 0.0f;
static float             g_stream_fps = 0.0f;
static float             g_tx_kbps = 0.0f;
static uint32_t          g_mean_frame_bytes = 0;
static float             g_temp_c = 0.0f;
static uint16_t          g_cur_width = 0;
static uint16_t          g_cur_height = 0;

static temperature_sensor_handle_t g_temp_handle = nullptr;
static bool              g_ap_mode = false;
static String            g_wifi_ssid;

// ==================== Ring Buffer Helpers ====================
static bool initRingBuffers() {
  for (int i = 0; i < kRingSlots; ++i) {
    size_t alloc_size = sizeof(FrameHeader) + kMaxFrameBytes;
    g_slots[i].buf = (uint8_t*)heap_caps_aligned_alloc(32, alloc_size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!g_slots[i].buf) return false;
    g_slots[i].jpeg_len = 0;
    g_slots[i].seq = 0;
    g_slots[i].refcount = 0;
  }
  return true;
}

static int acquireFreeSlot() {
  portENTER_CRITICAL(&g_ring_mux);
  int chosen = -1;
  uint32_t oldest_seq = 0xFFFFFFFF;
  for (int i = 0; i < kRingSlots; ++i) {
    if (g_slots[i].refcount == 0 && i != g_latest_slot) {
      if (g_slots[i].seq <= oldest_seq) {
        oldest_seq = g_slots[i].seq;
        chosen = i;
      }
    }
  }
  if (chosen >= 0) g_slots[chosen].writing = true;
  portEXIT_CRITICAL(&g_ring_mux);
  return chosen;
}

static void publishSlot(int idx) {
  portENTER_CRITICAL(&g_ring_mux);
  g_slots[idx].writing = false;
  g_latest_slot = idx;
  portEXIT_CRITICAL(&g_ring_mux);
}

static int acquireLatestSlot(uint32_t last_seq) {
  portENTER_CRITICAL(&g_ring_mux);
  int idx = g_latest_slot;
  if (idx >= 0 && g_slots[idx].seq != last_seq && g_slots[idx].jpeg_len > 0) {
    g_slots[idx].refcount++;
    portEXIT_CRITICAL(&g_ring_mux);
    return idx;
  }
  portEXIT_CRITICAL(&g_ring_mux);
  return -1;
}

static int acquireSlotBySeq(uint32_t seq) {
  portENTER_CRITICAL(&g_ring_mux);
  for (int i = 0; i < kRingSlots; ++i) {
    if (!g_slots[i].writing && g_slots[i].seq == seq && g_slots[i].jpeg_len > 0) {
      g_slots[i].refcount++;
      portEXIT_CRITICAL(&g_ring_mux);
      return i;
    }
  }
  portEXIT_CRITICAL(&g_ring_mux);
  return -1;
}

static void releaseSlot(int idx) {
  if (idx < 0) return;
  portENTER_CRITICAL(&g_ring_mux);
  if (g_slots[idx].refcount > 0) g_slots[idx].refcount--;
  portEXIT_CRITICAL(&g_ring_mux);
}

static bool hasActiveClients() {
  return (g_bin_clients.load() + g_mjpeg_clients.load() + g_udp_clients.load()) > 0;
}

// ==================== Socket Helpers ====================
static void tuneClientSocket(int fd) {
  int flag = 1;
  setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));
  struct timeval tv = {2, 0};
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  int keepalive = 1;
  setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, sizeof(keepalive));
}

static bool sendAll(int fd, const uint8_t* data, size_t len) {
  size_t sent = 0;
  while (sent < len) {
    ssize_t n = send(fd, data + sent, len - sent, 0);
    if (n <= 0) {
      if (errno == EINTR) continue;
      return false;
    }
    sent += (size_t)n;
  }
  return true;
}

// ==================== Camera Init & Async Mode Switching ====================
static bool initCamera() {
  camera_config_t cfg = {};
  cfg.ledc_channel = LEDC_CHANNEL_0;
  cfg.ledc_timer   = LEDC_TIMER_0;
  cfg.pin_d0       = Y2_GPIO_NUM;
  cfg.pin_d1       = Y3_GPIO_NUM;
  cfg.pin_d2       = Y4_GPIO_NUM;
  cfg.pin_d3       = Y5_GPIO_NUM;
  cfg.pin_d4       = Y6_GPIO_NUM;
  cfg.pin_d5       = Y7_GPIO_NUM;
  cfg.pin_d6       = Y8_GPIO_NUM;
  cfg.pin_d7       = Y9_GPIO_NUM;
  cfg.pin_xclk     = XCLK_GPIO_NUM;
  cfg.pin_pclk     = PCLK_GPIO_NUM;
  cfg.pin_vsync    = VSYNC_GPIO_NUM;
  cfg.pin_href     = HREF_GPIO_NUM;
  cfg.pin_sccb_sda = SIOD_GPIO_NUM;
  cfg.pin_sccb_scl = SIOC_GPIO_NUM;
  cfg.pin_pwdn     = PWDN_GPIO_NUM;
  cfg.pin_reset    = RESET_GPIO_NUM;

  cfg.xclk_freq_hz = kXclkFreqHz;
  cfg.pixel_format = PIXFORMAT_JPEG;
  cfg.frame_size   = FRAMESIZE_QXGA;
  cfg.jpeg_quality = 8;
  cfg.fb_count     = 2;
  cfg.fb_location  = CAMERA_FB_IN_PSRAM;
  cfg.grab_mode    = CAMERA_GRAB_LATEST;

  esp_err_t err = esp_camera_init(&cfg);
  if (err != ESP_OK) {
    Serial.printf("[ERR] esp_camera_init failed: 0x%x\n", err);
    return false;
  }

  sensor_t* s = esp_camera_sensor_get();
  if (!s) return false;

  switch (s->id.PID) {
    case OV3660_PID: snprintf(g_sensor_name, sizeof(g_sensor_name), "OV3660"); break;
    case OV2640_PID: snprintf(g_sensor_name, sizeof(g_sensor_name), "OV2640"); break;
    case OV5640_PID: snprintf(g_sensor_name, sizeof(g_sensor_name), "OV5640"); break;
    default:         snprintf(g_sensor_name, sizeof(g_sensor_name), "PID_0x%04X", s->id.PID); break;
  }

  applyProfileToSensor(s, g_profile);
  for (int i = 0; i < 3; ++i) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) esp_camera_fb_return(fb);
  }
  Serial.printf("[CAM] Sensor %s ready @ %d MHz XCLK, mode=%s\n",
                g_sensor_name, g_xclk_mhz, modeToName(g_mode));
  return true;
}

static void requestModeSwitch(StreamMode newMode) {
  if (newMode > MODE_QUALITY) return;
  portENTER_CRITICAL(&g_cfg_mux);
  g_mode = newMode;
  g_profile = kDefaultProfiles[newMode];
  g_profile_gen++;
  g_profile_dirty = true;
  portEXIT_CRITICAL(&g_cfg_mux);
}

static bool waitForProfileApply(uint32_t targetGen, uint32_t maxWaitMs) {
  uint32_t t0 = millis();
  while (g_applied_gen.load() != targetGen && (millis() - t0) < maxWaitMs) {
    vTaskDelay(pdMS_TO_TICKS(10));
  }
  return g_applied_gen.load() == targetGen;
}

static bool isValidJPEG(const uint8_t* buf, size_t len) {
  if (!buf || len < 128 || len > kMaxFrameBytes) return false;
  if (buf[0] != 0xFF || buf[1] != 0xD8 || memcmp(buf, buf + 4, 4) == 0) return false;
  size_t start = (len > 16) ? (len - 16) : 2;
  for (size_t i = len - 2; i >= start; --i) {
    if (buf[i] == 0xFF && buf[i + 1] == 0xD9) return true;
    if (i == 0) break;
  }
  return false;
}

// ==================== Core 1: Capture Task ====================
static void captureTask(void*) {
  uint32_t activeGeneration = 0;
  uint32_t smooth_len = 0;
  StreamMode activeMode = MODE_BALANCED;
  int activeQuality = kDefaultProfiles[MODE_BALANCED].quality;
  for (;;) {
    if (!g_camera_ok) {
      vTaskDelay(pdMS_TO_TICKS(100));
      continue;
    }

    if (g_profile_dirty) {
      CameraProfile p;
      uint32_t gen;
      portENTER_CRITICAL(&g_cfg_mux);
      p = g_profile;
      activeMode = g_mode;
      activeQuality = p.quality;
      gen = g_profile_gen;
      g_profile_dirty = false;
      portEXIT_CRITICAL(&g_cfg_mux);

      sensor_t* s = esp_camera_sensor_get();
      if (s) {
        applyProfileToSensor(s, p);
        for (int i = 0; i < 2; ++i) {
          camera_fb_t* fbt = esp_camera_fb_get();
          if (fbt) esp_camera_fb_return(fbt);
        }
      }
      activeGeneration = gen;
    }

    if (g_reg_dirty) {
      g_reg_dirty = false;
      sensor_t* s = esp_camera_sensor_get();
      if (s) s->set_reg(s, g_reg_addr, g_reg_mask, g_reg_val);
    }

    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
      g_cam_errors++;
      vTaskDelay(pdMS_TO_TICKS(2));
      continue;
    }

    uint64_t ts = (uint64_t)esp_timer_get_time();
    bool valid = (fb->format == PIXFORMAT_JPEG && isValidJPEG(fb->buf, fb->len));

    if (valid) {
      int slot = acquireFreeSlot();
      if (slot >= 0) {
        uint32_t seq = ++g_frame_seq;
        int16_t tx10 = (int16_t)(g_temp_c * 10.0f);

        FrameHeader hdr;
        hdr.magic       = kTcpFrameMagic;
        hdr.seq         = seq;
        hdr.ts_us       = ts;
        hdr.width       = (uint16_t)fb->width;
        hdr.height      = (uint16_t)fb->height;
        hdr.mode        = (uint8_t)activeMode;
        hdr.quality     = (uint8_t)activeQuality;
        hdr.temp_c_x10  = tx10;
        hdr.payload_len = (uint32_t)fb->len;

        uint8_t* dst = g_slots[slot].buf;
        memcpy(dst, &hdr, sizeof(FrameHeader));
        memcpy(dst + sizeof(FrameHeader), fb->buf, fb->len);

        g_slots[slot].jpeg_len   = fb->len;
        g_slots[slot].seq        = seq;
        g_slots[slot].ts_us      = ts;
        g_slots[slot].width      = (uint16_t)fb->width;
        g_slots[slot].height     = (uint16_t)fb->height;
        g_slots[slot].mode       = (uint8_t)activeMode;
        g_slots[slot].quality    = (uint8_t)activeQuality;
        g_slots[slot].temp_c_x10 = tx10;

        g_cur_width  = (uint16_t)fb->width;
        g_cur_height = (uint16_t)fb->height;
        smooth_len = smooth_len ? ((smooth_len * 7 + fb->len) >> 3) : fb->len;
        g_mean_frame_bytes = smooth_len;

        publishSlot(slot);
        g_applied_gen.store(activeGeneration);
        g_frames_captured++;
        g_frames_cap_window++;
      } else {
        g_frames_dropped++;
      }
    } else {
      g_cam_errors++;
    }

    esp_camera_fb_return(fb);

    if (!hasActiveClients()) {
      vTaskDelay(pdMS_TO_TICKS(180));
    }
  }
}

// ==================== Port 83: Core 1 Paced UDP + Selective NACK ARQ ====================
static bool sendUdpChunk(int sock, const struct sockaddr_in& dst,
                         const FrameSlot& sl, uint16_t ci, uint16_t chunks,
                         uint8_t* pktBuf, uint32_t& sentBytesOut) {
  size_t jlen = sl.jpeg_len;
  size_t offset = (size_t)ci * kUdpChunkPayload;
  if (offset >= jlen) return false;
  size_t clen = jlen - offset;
  if (clen > kUdpChunkPayload) clen = kUdpChunkPayload;

  UdpChunkHeader uh;
  uh.magic       = kUdpChunkMagic;
  uh.seq         = sl.seq;
  uh.ts_us       = sl.ts_us;
  uh.width       = sl.width;
  uh.height      = sl.height;
  uh.chunk_idx   = ci;
  uh.chunk_count = chunks;
  uh.frame_len   = (uint32_t)jlen;
  uh.mode        = sl.mode;
  uh.quality     = sl.quality;
  uh.temp_c_x10  = sl.temp_c_x10;

  memcpy(pktBuf, &uh, sizeof(UdpChunkHeader));
  memcpy(pktBuf + sizeof(UdpChunkHeader), sl.buf + sizeof(FrameHeader) + offset, clen);
  size_t pktLen = sizeof(UdpChunkHeader) + clen;

  for (int tries = 0; tries < 6; ++tries) {
    ssize_t sn = sendto(sock, pktBuf, pktLen, 0, (const struct sockaddr*)&dst, sizeof(dst));
    if (sn >= 0) {
      sentBytesOut += (uint32_t)sn;
      return true;
    }
    if (errno == ENOMEM || errno == EAGAIN || errno == EWOULDBLOCK) {
      vTaskDelay(1);
    } else {
      return false;
    }
  }
  return false;
}

static void drainUdpControl(int sock, uint8_t* pktBuf) {
  uint8_t cmd[96];
  for (int iter = 0; iter < 8; ++iter) {
    struct sockaddr_in src = {};
    socklen_t srclen = sizeof(src);
    ssize_t rn = recvfrom(sock, cmd, sizeof(cmd), 0, (struct sockaddr*)&src, &srclen);
    if (rn <= 0) break;

    uint64_t now_us = (uint64_t)esp_timer_get_time();

    if (rn >= 10 && memcmp(cmd, "NACK", 4) == 0) {
      uint32_t seq;
      uint16_t cnt;
      memcpy(&seq, cmd + 4, 4);
      memcpy(&cnt, cmd + 8, 2);
      if (cnt > 24) cnt = 24;
      if (rn >= (ssize_t)(10 + cnt * 2)) {
        int rslot = acquireSlotBySeq(seq);
        if (rslot >= 0) {
          uint16_t chunks = (uint16_t)((g_slots[rslot].jpeg_len + kUdpChunkPayload - 1) / kUdpChunkPayload);
          uint32_t rbytes = 0;
          for (uint16_t k = 0; k < cnt; ++k) {
            uint16_t ci;
            memcpy(&ci, cmd + 10 + k * 2, 2);
            if (ci < chunks) {
              if (sendUdpChunk(sock, src, g_slots[rslot], ci, chunks, pktBuf, rbytes)) {
                g_nack_retrans++;
              }
              if ((k & 1) == 1) vTaskDelay(1);
            }
          }
          g_bytes_sent_window += rbytes;
          releaseSlot(rslot);
        }
      }
      continue;
    }

    bool isStop = (rn >= 4 && memcmp(cmd, "BYE!", 4) == 0);
    portENTER_CRITICAL(&g_udp_mux);
    int match = -1, freeIdx = -1;
    for (int i = 0; i < kMaxUdpSubs; ++i) {
      if (g_udp_subs[i].active &&
          g_udp_subs[i].addr.sin_addr.s_addr == src.sin_addr.s_addr &&
          g_udp_subs[i].addr.sin_port == src.sin_port) {
        match = i;
        break;
      }
      if (!g_udp_subs[i].active && freeIdx < 0) freeIdx = i;
    }
    if (isStop) {
      if (match >= 0) g_udp_subs[match].active = false;
    } else {
      int idx = (match >= 0) ? match : freeIdx;
      if (idx >= 0) {
        g_udp_subs[idx].addr = src;
        g_udp_subs[idx].last_seen_us = now_us;
        g_udp_subs[idx].active = true;
      }
    }
    portEXIT_CRITICAL(&g_udp_mux);
  }
}

static void udpServerTask(void*) {
  int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (sock < 0) {
    vTaskDelete(nullptr);
    return;
  }

  int opt = 1;
  setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
  int flags = fcntl(sock, F_GETFL, 0);
  fcntl(sock, F_SETFL, flags | O_NONBLOCK);

  struct sockaddr_in bindAddr = {};
  bindAddr.sin_family      = AF_INET;
  bindAddr.sin_addr.s_addr = htonl(INADDR_ANY);
  bindAddr.sin_port        = htons(kUdpStreamPort);

  if (bind(sock, (struct sockaddr*)&bindAddr, sizeof(bindAddr)) != 0) {
    close(sock);
    vTaskDelete(nullptr);
    return;
  }
  Serial.printf("[NET] Core-1 Paced UDP+NACK stream listening on :%d\n", kUdpStreamPort);

  uint8_t pkt[sizeof(UdpChunkHeader) + kUdpChunkPayload];
  uint32_t last_seq = 0;

  for (;;) {
    drainUdpControl(sock, pkt);

    uint64_t now_us = (uint64_t)esp_timer_get_time();
    struct sockaddr_in activeAddrs[kMaxUdpSubs];
    int activeCount = 0;
    portENTER_CRITICAL(&g_udp_mux);
    for (int i = 0; i < kMaxUdpSubs; ++i) {
      if (g_udp_subs[i].active) {
        if (now_us - g_udp_subs[i].last_seen_us > 6000000ULL) {
          g_udp_subs[i].active = false;
        } else {
          activeAddrs[activeCount++] = g_udp_subs[i].addr;
        }
      }
    }
    portEXIT_CRITICAL(&g_udp_mux);
    g_udp_clients.store(activeCount);

    if (activeCount == 0) {
      vTaskDelay(pdMS_TO_TICKS(10));
      continue;
    }

    int slot = acquireLatestSlot(last_seq);
    if (slot < 0) {
      vTaskDelay(1);
      continue;
    }

    last_seq = g_slots[slot].seq;
    size_t jlen = g_slots[slot].jpeg_len;
    uint16_t chunks = (uint16_t)((jlen + kUdpChunkPayload - 1) / kUdpChunkPayload);

    // Smooth microsecond token-bucket pacer matched to target Mbps:
    // Prevents overflowing ESP32-S3's 8 static Wi-Fi TX buffers!
    int targetMbps = g_udp_mbps.load();
    if (targetMbps < 4) targetMbps = 4;
    if (targetMbps > 32) targetMbps = 32;
    // Time per 1432B packet in microseconds = (1432 * 8) / targetMbps
    int64_t usPerPkt = (1432 * 8) / targetMbps;
    int64_t nextSendUs = esp_timer_get_time();

    uint32_t sentBytesTotal = 0;
    for (uint16_t ci = 0; ci < chunks; ++ci) {
      for (int a = 0; a < activeCount; ++a) {
        sendUdpChunk(sock, activeAddrs[a], g_slots[slot], ci, chunks, pkt, sentBytesTotal);
      }
      nextSendUs += usPerPkt * activeCount;

      int64_t now = esp_timer_get_time();
      int64_t ahead = nextSendUs - now;
      if (ahead >= 1000) {
        // Sleep whole milliseconds via FreeRTOS tick (zero CPU burn!)
        vTaskDelay(pdMS_TO_TICKS(ahead / 1000));
        drainUdpControl(sock, pkt);
      } else if (ahead < -4000) {
        // Reset token debt after an OS pause so we don't burst blindly
        nextSendUs = now;
      }
    }

    releaseSlot(slot);

    g_frames_sent += activeCount;
    g_frames_sent_window += activeCount;
    g_bytes_sent_window += sentBytesTotal;
  }
}

// ==================== Port 82: Binary TCP Stream Server ====================
static void binClientTask(void* arg) {
  int fd = (int)(intptr_t)arg;
  tuneClientSocket(fd);
  g_bin_clients++;

  uint32_t last_seq = 0;
  for (;;) {
    int slot = acquireLatestSlot(last_seq);
    if (slot < 0) {
      vTaskDelay(1);
      continue;
    }
    last_seq = g_slots[slot].seq;
    size_t total_len = sizeof(FrameHeader) + g_slots[slot].jpeg_len;
    bool ok = sendAll(fd, g_slots[slot].buf, total_len);
    releaseSlot(slot);
    if (!ok) break;
    g_frames_sent++;
    g_frames_sent_window++;
    g_bytes_sent_window += (uint32_t)total_len;
  }

  close(fd);
  g_bin_clients--;
  vTaskDelete(nullptr);
}

static void binServerTask(void*) {
  int srv = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
  int opt = 1;
  setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  struct sockaddr_in addr = {};
  addr.sin_family      = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port        = htons(kBinStreamPort);

  if (bind(srv, (struct sockaddr*)&addr, sizeof(addr)) != 0 || listen(srv, 4) != 0) {
    close(srv);
    vTaskDelete(nullptr);
    return;
  }
  Serial.printf("[NET] Binary TCP stream listening on :%d\n", kBinStreamPort);

  for (;;) {
    struct sockaddr_in cli = {};
    socklen_t clilen = sizeof(cli);
    int fd = accept(srv, (struct sockaddr*)&cli, &clilen);
    if (fd < 0) {
      vTaskDelay(pdMS_TO_TICKS(10));
      continue;
    }
    if (g_bin_clients.load() >= kMaxBinClients) {
      close(fd);
      continue;
    }
    xTaskCreatePinnedToCore(binClientTask, "bin_tx", 4096, (void*)(intptr_t)fd, 3, nullptr, 1);
  }
}

// ==================== Port 81: Multi-Client HTTP MJPEG Server ====================
static const char kMjpegHeader[] =
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
    "Access-Control-Allow-Origin: *\r\n"
    "Cache-Control: no-store, no-cache, must-revalidate\r\n"
    "Pragma: no-cache\r\n"
    "Connection: close\r\n\r\n";

static void mjpegClientTask(void* arg) {
  int fd = (int)(intptr_t)arg;
  tuneClientSocket(fd);

  struct timeval rtv = {1, 0};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rtv, sizeof(rtv));
  char reqbuf[512];
  recv(fd, reqbuf, sizeof(reqbuf) - 1, 0);

  if (!sendAll(fd, (const uint8_t*)kMjpegHeader, sizeof(kMjpegHeader) - 1)) {
    close(fd);
    vTaskDelete(nullptr);
    return;
  }

  g_mjpeg_clients++;
  uint32_t last_seq = 0;
  char part_hdr[128];

  for (;;) {
    int slot = acquireLatestSlot(last_seq);
    if (slot < 0) {
      vTaskDelay(pdMS_TO_TICKS(2));
      continue;
    }
    last_seq = g_slots[slot].seq;
    size_t jlen = g_slots[slot].jpeg_len;
    const uint8_t* jpeg = g_slots[slot].buf + sizeof(FrameHeader);

    int hlen = snprintf(part_hdr, sizeof(part_hdr),
                        "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n",
                        (unsigned)jlen);

    bool ok = sendAll(fd, (const uint8_t*)part_hdr, (size_t)hlen) &&
              sendAll(fd, jpeg, jlen) &&
              sendAll(fd, (const uint8_t*)"\r\n", 2);
    releaseSlot(slot);

    if (!ok) break;
    g_frames_sent++;
    g_frames_sent_window++;
    g_bytes_sent_window += (uint32_t)(hlen + jlen + 2);
  }

  close(fd);
  g_mjpeg_clients--;
  vTaskDelete(nullptr);
}

static void mjpegServerTask(void*) {
  int srv = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
  int opt = 1;
  setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  struct sockaddr_in addr = {};
  addr.sin_family      = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port        = htons(kMjpegStreamPort);

  if (bind(srv, (struct sockaddr*)&addr, sizeof(addr)) != 0 || listen(srv, 4) != 0) {
    close(srv);
    vTaskDelete(nullptr);
    return;
  }
  Serial.printf("[NET] MJPEG stream listening on :%d/stream\n", kMjpegStreamPort);

  for (;;) {
    struct sockaddr_in cli = {};
    socklen_t clilen = sizeof(cli);
    int fd = accept(srv, (struct sockaddr*)&cli, &clilen);
    if (fd < 0) {
      vTaskDelay(pdMS_TO_TICKS(10));
      continue;
    }
    if (g_mjpeg_clients.load() >= kMaxMjpegClients) {
      close(fd);
      continue;
    }
    xTaskCreatePinnedToCore(mjpegClientTask, "mjpeg_tx", 4096, (void*)(intptr_t)fd, 3, nullptr, 1);
  }
}

// ==================== Port 80: HTTP Control & Telemetry API ====================
static void addCors(httpd_req_t* req) {
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
}

static bool getQueryParam(httpd_req_t* req, const char* key, char* out, size_t out_len) {
  size_t qlen = httpd_req_get_url_query_len(req);
  if (qlen == 0 || qlen >= 512) return false;
  char qbuf[512];
  if (httpd_req_get_url_query_str(req, qbuf, sizeof(qbuf)) != ESP_OK) return false;
  return httpd_query_key_value(qbuf, key, out, out_len) == ESP_OK;
}

static void urlDecodeInPlace(char* s) {
  char* dst = s;
  while (*s) {
    if (*s == '%' && s[1] && s[2]) {
      char hex[3] = {s[1], s[2], 0};
      *dst++ = (char)strtol(hex, nullptr, 16);
      s += 3;
    } else if (*s == '+') {
      *dst++ = ' ';
      s++;
    } else {
      *dst++ = *s++;
    }
  }
  *dst = '\0';
}

static esp_err_t handleRoot(httpd_req_t* req) {
  httpd_resp_set_type(req, "text/html");
  return httpd_resp_send(req, kWebUiHtml, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t handleCapture(httpd_req_t* req) {
  addCors(req);
  int slot = acquireLatestSlot(0);
  if (slot < 0) {
    httpd_resp_send_500(req);
    return ESP_FAIL;
  }
  httpd_resp_set_type(req, "image/jpeg");
  esp_err_t res = httpd_resp_send(req,
                                  (const char*)(g_slots[slot].buf + sizeof(FrameHeader)),
                                  g_slots[slot].jpeg_len);
  releaseSlot(slot);
  return res;
}

static esp_err_t handleStatus(httpd_req_t* req) {
  addCors(req);
  httpd_resp_set_type(req, "application/json");
  String ip = g_ap_mode ? WiFi.softAPIP().toString() : WiFi.localIP().toString();
  int rssi = g_ap_mode ? 0 : WiFi.RSSI();

  char json[1200];
  int n = snprintf(json, sizeof(json),
    "{\"device\":\"xiao-esp32s3-stream\",\"fw\":\"4.1\",\"sensor\":\"%s\",\"xclk_mhz\":%d,"
    "\"mode\":\"%s\",\"framesize\":%d,\"width\":%u,\"height\":%u,\"quality\":%d,"
    "\"capture_fps\":%.2f,\"stream_fps\":%.2f,\"tx_kbps\":%.1f,\"mean_frame_bytes\":%u,"
    "\"frames_captured\":%u,\"frames_sent\":%u,\"frames_dropped\":%u,\"cam_errors\":%u,"
    "\"nack_retrans\":%u,\"udp_mbps\":%d,\"tx_power_dbm\":%.2f,"
    "\"clients_udp\":%d,\"clients_bin\":%d,\"clients_mjpeg\":%d,"
    "\"temp_c\":%.1f,\"rssi\":%d,\"wifi_mode\":\"%s\",\"ssid\":\"%s\",\"ip\":\"%s\","
    "\"free_heap\":%u,\"free_psram\":%u,\"uptime_s\":%u,"
    "\"brightness\":%d,\"contrast\":%d,\"saturation\":%d,\"sharpness\":%d,\"denoise\":%d,"
    "\"ae_level\":%d,\"aec2\":%d,\"gainceiling\":%d,\"night_mode\":%d,\"hmirror\":%d,\"vflip\":%d}",
    g_sensor_name, g_xclk_mhz,
    modeToName(g_mode), (int)g_profile.framesize, g_cur_width, g_cur_height, g_profile.quality,
    g_capture_fps, g_stream_fps, g_tx_kbps, g_mean_frame_bytes,
    (unsigned)g_frames_captured.load(), (unsigned)g_frames_sent.load(),
    (unsigned)g_frames_dropped.load(), (unsigned)g_cam_errors.load(),
    (unsigned)g_nack_retrans.load(), g_udp_mbps.load(), g_tx_power_qdbm.load() * 0.25f,
    g_udp_clients.load(), g_bin_clients.load(), g_mjpeg_clients.load(),
    g_temp_c, rssi, g_ap_mode ? "AP" : "STA", g_wifi_ssid.c_str(), ip.c_str(),
    (unsigned)esp_get_free_heap_size(), (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
    (unsigned)(esp_timer_get_time() / 1000000ULL),
    g_profile.brightness, g_profile.contrast, g_profile.saturation, g_profile.sharpness, g_profile.denoise,
    g_profile.ae_level, g_profile.aec2, g_profile.gainceiling, g_profile.night_mode,
    g_profile.hmirror, g_profile.vflip
  );
  return httpd_resp_send(req, json, n);
}

static esp_err_t handleMode(httpd_req_t* req) {
  addCors(req);
  char m[32] = {};
  if (!getQueryParam(req, "mode", m, sizeof(m))) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Missing ?mode=performance|balanced|quality");
    return ESP_FAIL;
  }
  StreamMode next;
  if (strcasecmp(m, "performance") == 0 || strcmp(m, "0") == 0) next = MODE_PERFORMANCE;
  else if (strcasecmp(m, "balanced") == 0 || strcmp(m, "1") == 0) next = MODE_BALANCED;
  else if (strcasecmp(m, "quality") == 0 || strcmp(m, "2") == 0) next = MODE_QUALITY;
  else {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Unknown mode");
    return ESP_FAIL;
  }
  requestModeSwitch(next);
  if (!waitForProfileApply(g_profile_gen, 1500)) {
    httpd_resp_set_status(req, "503 Service Unavailable");
    return httpd_resp_sendstr(req, "No frame from requested profile");
  }
  return handleStatus(req);
}

static esp_err_t handleSettings(httpd_req_t* req) {
  addCors(req);
  char val[32];
  bool changed = false;

  if (getQueryParam(req, "udp_mbps", val, sizeof(val))) {
    g_udp_mbps.store(constrain(atoi(val), 4, 32));
  }
  if (getQueryParam(req, "reg", val, sizeof(val))) {
    char vstr[16] = {}, mstr[16] = {};
    if (getQueryParam(req, "val", vstr, sizeof(vstr))) {
      g_reg_addr = (int)strtol(val, nullptr, 0);
      g_reg_val  = (int)strtol(vstr, nullptr, 0);
      g_reg_mask = getQueryParam(req, "mask", mstr, sizeof(mstr)) ? (int)strtol(mstr, nullptr, 0) : 0xFF;
      g_reg_dirty = true;
    }
  }

  CameraProfile profile = g_profile;
  StreamMode mode = g_mode;
  if (getQueryParam(req, "framesize", val, sizeof(val))) {
    char* end;
    long size = strtol(val, &end, 10);
    if (!*val || *end || size < 0 || size > FRAMESIZE_QXGA) {
      httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Unsupported frame size");
      return ESP_FAIL;
    }
    profile.framesize = (framesize_t)size;
    mode = MODE_CUSTOM;
    changed = true;
  }
  if (getQueryParam(req, "quality", val, sizeof(val))) {
    profile.quality = constrain(atoi(val), 4, 63);
    changed = true;
  }
  if (getQueryParam(req, "brightness", val, sizeof(val))) {
    profile.brightness = constrain(atoi(val), -3, 3);
    changed = true;
  }
  if (getQueryParam(req, "contrast", val, sizeof(val))) {
    profile.contrast = constrain(atoi(val), -3, 3);
    changed = true;
  }
  if (getQueryParam(req, "saturation", val, sizeof(val))) {
    profile.saturation = constrain(atoi(val), -4, 4);
    changed = true;
  }
  if (getQueryParam(req, "sharpness", val, sizeof(val))) {
    profile.sharpness = constrain(atoi(val), -3, 3);
    changed = true;
  }
  if (getQueryParam(req, "denoise", val, sizeof(val))) {
    profile.denoise = constrain(atoi(val), 0, 8);
    changed = true;
  }
  if (getQueryParam(req, "ae_level", val, sizeof(val))) {
    profile.ae_level = constrain(atoi(val), -5, 5);
    changed = true;
  }
  if (getQueryParam(req, "aec2", val, sizeof(val))) {
    profile.aec2 = atoi(val) ? 1 : 0;
    changed = true;
  }
  if (getQueryParam(req, "gainceiling", val, sizeof(val))) {
    profile.gainceiling = constrain(atoi(val), 0, 6);
    changed = true;
  }
  if (getQueryParam(req, "night_mode", val, sizeof(val))) {
    profile.night_mode = atoi(val) ? 1 : 0;
    changed = true;
  }
  if (getQueryParam(req, "hmirror", val, sizeof(val))) {
    profile.hmirror = atoi(val) ? 1 : 0;
    changed = true;
  }
  if (getQueryParam(req, "vflip", val, sizeof(val))) {
    profile.vflip = atoi(val) ? 1 : 0;
    changed = true;
  }
  portENTER_CRITICAL(&g_cfg_mux);
  if (changed) {
    g_profile = profile;
    g_mode = mode;
    g_profile_gen++;
    g_profile_dirty = true;
  }
  uint32_t target = g_profile_gen;
  portEXIT_CRITICAL(&g_cfg_mux);

  if (changed && !waitForProfileApply(target, 1500)) {
    httpd_resp_set_status(req, "503 Service Unavailable");
    return httpd_resp_sendstr(req, "No frame from requested settings");
  }
  return handleStatus(req);
}

static esp_err_t handleRegDump(httpd_req_t* req) {
  addCors(req);
  httpd_resp_set_type(req, "application/json");
  sensor_t* s = esp_camera_sensor_get();
  if (!s) {
    httpd_resp_send_500(req);
    return ESP_FAIL;
  }
  char json[256];
  int n = snprintf(json, sizeof(json),
    "{\"r3034\":%d,\"r3035\":%d,\"r3036\":%d,\"r3037\":%d,\"r3108\":%d,\"r380c\":%d,\"r380d\":%d,\"r380e\":%d,\"r380f\":%d,\"r3a00\":%d}",
    s->get_reg(s, 0x3034, 0xFF), s->get_reg(s, 0x3035, 0xFF),
    s->get_reg(s, 0x3036, 0xFF), s->get_reg(s, 0x3037, 0xFF),
    s->get_reg(s, 0x3108, 0xFF),
    s->get_reg(s, 0x380C, 0xFF), s->get_reg(s, 0x380D, 0xFF),
    s->get_reg(s, 0x380E, 0xFF), s->get_reg(s, 0x380F, 0xFF),
    s->get_reg(s, 0x3A00, 0xFF));
  return httpd_resp_send(req, json, n);
}

static esp_err_t handleWifi(httpd_req_t* req) {
  addCors(req);
  char ssid[64] = {}, pass[64] = {};
  if (!getQueryParam(req, "ssid", ssid, sizeof(ssid))) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Missing ssid");
    return ESP_FAIL;
  }
  getQueryParam(req, "pass", pass, sizeof(pass));
  urlDecodeInPlace(ssid);
  urlDecodeInPlace(pass);

  Preferences prefs;
  if (prefs.begin("vstream", false)) {
    prefs.putString("ssid", ssid);
    prefs.putString("pass", pass);
    prefs.end();
  }
  httpd_resp_set_type(req, "application/json");
  httpd_resp_sendstr(req, "{\"ok\":true,\"rebooting\":true}");
  vTaskDelay(pdMS_TO_TICKS(400));
  ESP.restart();
  return ESP_OK;
}

static void startControlServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.max_uri_handlers = 12;
  config.stack_size = 8192;
  config.server_port      = 80;
  config.ctrl_port        = 32768;
  config.max_open_sockets = 6;
  config.lru_purge_enable = true;
  config.core_id          = 0;

  httpd_handle_t srv = nullptr;
  if (httpd_start(&srv, &config) == ESP_OK) {
    httpd_uri_t u_root = {"/",             HTTP_GET,  handleRoot,     nullptr};
    httpd_uri_t u_cap  = {"/capture",      HTTP_GET,  handleCapture,  nullptr};
    httpd_uri_t u_stat = {"/api/status",   HTTP_GET,  handleStatus,   nullptr};
    httpd_uri_t u_reg  = {"/api/regs",     HTTP_GET,  handleRegDump,  nullptr};
    httpd_uri_t u_mg   = {"/api/mode",     HTTP_GET,  handleMode,     nullptr};
    httpd_uri_t u_mp   = {"/api/mode",     HTTP_POST, handleMode,     nullptr};
    httpd_uri_t u_sg   = {"/api/settings", HTTP_GET,  handleSettings, nullptr};
    httpd_uri_t u_sp   = {"/api/settings", HTTP_POST, handleSettings, nullptr};
    httpd_uri_t u_wg   = {"/api/wifi",     HTTP_GET,  handleWifi,     nullptr};
    httpd_uri_t u_wp   = {"/api/wifi",     HTTP_POST, handleWifi,     nullptr};
    httpd_register_uri_handler(srv, &u_root);
    httpd_register_uri_handler(srv, &u_cap);
    httpd_register_uri_handler(srv, &u_stat);
    httpd_register_uri_handler(srv, &u_reg);
    httpd_register_uri_handler(srv, &u_mg);
    httpd_register_uri_handler(srv, &u_mp);
    httpd_register_uri_handler(srv, &u_sg);
    httpd_register_uri_handler(srv, &u_sp);
    httpd_register_uri_handler(srv, &u_wg);
    httpd_register_uri_handler(srv, &u_wp);
    Serial.println("[NET] HTTP control API listening on :80");
  }
}

// ==================== Wi-Fi Setup (STA + Portable Power-Bank AP Fallback) ====================
static bool loadWifiCreds(String& ssid, String& pass) {
  Preferences prefs;
  if (prefs.begin("vstream", true)) {
    ssid = prefs.getString("ssid", "");
    pass = prefs.getString("pass", "");
    prefs.end();
    if (ssid.length() > 0) return true;
  }
  if (prefs.begin("ojo", true)) {
    ssid = prefs.getString("ssid", "");
    pass = prefs.getString("pass", "");
    prefs.end();
    if (ssid.length() > 0) return true;
  }
  return false;
}

static void startApMode() {
  g_ap_mode = true;
  g_wifi_ssid = kApSsid;
  WiFi.disconnect(true);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(kApSsid, kApPass, 6, 0, 4);
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_protocol(WIFI_IF_AP, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N);
  esp_wifi_set_max_tx_power(68);
  g_tx_power_qdbm.store(68);
  Serial.printf("[WIFI] Portable AP active: SSID=%s IP=%s\n",
                kApSsid, WiFi.softAPIP().toString().c_str());
}

static void initWifi() {
  String ssid, pass;
  bool hasCreds = loadWifiCreds(ssid, pass);

  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);

  if (hasCreds) {
    g_ap_mode = false;
    g_wifi_ssid = ssid;
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid.c_str(), pass.c_str());

    Serial.printf("[WIFI] Connecting to STA '%s'...\n", ssid.c_str());
    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - t0) < 8000) {
      delay(100);
    }

    if (WiFi.status() == WL_CONNECTED) {
      esp_wifi_set_ps(WIFI_PS_NONE);
      esp_wifi_set_max_tx_power(60); // 15 dBm initial; adaptive TPC adjusts every 2s
      g_tx_power_qdbm.store(60);
      Serial.printf("[WIFI] Connected! IP=%s RSSI=%d dBm\n",
                    WiFi.localIP().toString().c_str(), WiFi.RSSI());
    } else {
      Serial.println("[WIFI] STA timeout -> Portable AP mode");
      startApMode();
    }
  } else {
    startApMode();
  }

  if (MDNS.begin(kMdnsHost)) {
    MDNS.addService("http", "tcp", 80);
    MDNS.addService("xiao-camera", "udp", kUdpStreamPort);
    Serial.printf("[NET] mDNS ready: http://%s.local\n", kMdnsHost);
  }
}

// ==================== Telemetry, Adaptive TX Power & Thermals ====================
static void initTempSensor() {
  temperature_sensor_config_t tcfg = TEMPERATURE_SENSOR_CONFIG_DEFAULT(20, 100);
  if (temperature_sensor_install(&tcfg, &g_temp_handle) == ESP_OK) {
    temperature_sensor_enable(g_temp_handle);
  }
}

static void telemetryTask(void*) {
  uint64_t last_us = esp_timer_get_time();
  int tpcCounter = 0;
  for (;;) {
    vTaskDelay(pdMS_TO_TICKS(1000));
    uint64_t now_us = esp_timer_get_time();
    float dt = (float)(now_us - last_us) / 1e6f;
    last_us = now_us;

    uint32_t cap = g_frames_cap_window.exchange(0);
    uint32_t snt = g_frames_sent_window.exchange(0);
    uint32_t byt = g_bytes_sent_window.exchange(0);

    if (dt > 0.1f) {
      g_capture_fps = (float)cap / dt;
      g_stream_fps  = (float)snt / dt;
      g_tx_kbps     = ((float)byt * 8.0f) / (dt * 1000.0f);
    }

    if (g_temp_handle) {
      float t = 0.0f;
      if (temperature_sensor_get_celsius(g_temp_handle, &t) == ESP_OK) {
        g_temp_c = t;
      }
    }

    // Adaptive Wi-Fi TX Power Control every 2s: saves heat when close, full power at range!
    if (!g_ap_mode && WiFi.status() == WL_CONNECTED && (++tpcCounter & 1) == 0) {
      int rssi = WiFi.RSSI();
      int desired = 60; // 15 dBm default
      if (rssi > -52)      desired = 52; // 13 dBm (strong link -> cooler chip!)
      else if (rssi > -65) desired = 64; // 16 dBm
      else                 desired = 78; // 19.5 dBm (max portable range!)
      if (desired != g_tx_power_qdbm.load()) {
        esp_wifi_set_max_tx_power((int8_t)desired);
        g_tx_power_qdbm.store(desired);
      }
    }

    digitalWrite(STATUS_LED_GPIO, hasActiveClients() ? LOW : HIGH);
  }
}

// ==================== Arduino Entry Points ====================
void setup() {
  pinMode(STATUS_LED_GPIO, OUTPUT);
  digitalWrite(STATUS_LED_GPIO, HIGH);

  Serial.begin(115200);
  delay(250);
  Serial.println("\n=== XIAO ESP32-S3 Ultra Stream Firmware v4.1 ===");
  Serial.printf("[SYS] CPU=%u MHz, Heap=%u B, PSRAM=%u B\n",
                getCpuFrequencyMhz(),
                (unsigned)esp_get_free_heap_size(),
                (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));

  initTempSensor();
  if (!initRingBuffers()) {
    Serial.println("[FATAL] PSRAM ring buffer alloc failed!");
    return;
  }

  g_camera_ok = initCamera();
  initWifi();
  startControlServer();

  // Pin Capture + UDP TX to Core 1 -> Core 0 stays 100% free for Wi-Fi, LwIP, Camera DMA ISR!
  xTaskCreatePinnedToCore(captureTask,     "cam_cap",   6144, nullptr, 5, nullptr, 1);
  xTaskCreatePinnedToCore(udpServerTask,   "udp_srv",   6144, nullptr, 4, nullptr, 1);
  xTaskCreatePinnedToCore(binServerTask,   "bin_srv",   4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(mjpegServerTask, "mjpeg_srv", 4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(telemetryTask,   "telemetry", 3072, nullptr, 1, nullptr, 0);
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line == "perf")      requestModeSwitch(MODE_PERFORMANCE);
    else if (line == "bal")  requestModeSwitch(MODE_BALANCED);
    else if (line == "qual") requestModeSwitch(MODE_QUALITY);
    else if (line == "info") {
      Serial.printf("[INFO] ip=%s mode=%s res=%ux%u cap=%.1ffps tx=%.1ffps %.2fMbps nacks=%u temp=%.1fC rssi=%d txp=%.1fdBm err=%u\n",
                    (g_ap_mode ? WiFi.softAPIP() : WiFi.localIP()).toString().c_str(),
                    modeToName(g_mode), g_cur_width, g_cur_height,
                    g_capture_fps, g_stream_fps, g_tx_kbps / 1000.0f,
                    (unsigned)g_nack_retrans.load(),
                    g_temp_c, g_ap_mode ? 0 : WiFi.RSSI(),
                    g_tx_power_qdbm.load() * 0.25f, (unsigned)g_cam_errors.load());
    }
  }
  vTaskDelay(pdMS_TO_TICKS(100));
}
