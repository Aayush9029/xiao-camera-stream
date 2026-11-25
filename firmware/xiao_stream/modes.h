#pragma once
#include <esp_camera.h>
#include <stdint.h>

enum StreamMode : uint8_t {
  MODE_PERFORMANCE = 0,
  MODE_BALANCED    = 1,
  MODE_QUALITY     = 2,
  MODE_CUSTOM      = 3
};

struct CameraProfile {
  const char* name;
  framesize_t framesize;
  int quality;         // OV3660: lower = higher quality (6..40)
  int brightness;      // -3..3
  int contrast;        // -3..3
  int saturation;      // -4..4
  int sharpness;       // -3..3
  int denoise;         // 0..8
  int ae_level;        // -5..5
  int aec2;            // 0 or 1
  int gainceiling;     // 0..6 (2x..128x)
  int night_mode;      // 0 = fixed max FPS, 1 = auto exposure slowdown in dim scenes
  int hmirror;
  int vflip;
};

// Empirically tuned OV3660 profiles for Seeed XIAO ESP32S3 Sense
static const CameraProfile kDefaultProfiles[3] = {
  // MODE_PERFORMANCE: Maximum FPS, lowest latency, 480x320
  {
    .name        = "performance",
    .framesize   = FRAMESIZE_HVGA,
    .quality     = 14,
    .brightness  = 0,
    .contrast    = 0,
    .saturation  = 0,
    .sharpness   = 0,
    .denoise     = 2,
    .ae_level    = 1,               // Lift slightly from conservative OV3660 AEC
    .aec2        = 1,
    .gainceiling = GAINCEILING_16X,
    .night_mode  = 0,               // Lock high FPS
    .hmirror     = 0,
    .vflip       = 1
  },
  // MODE_BALANCED: Crisp 1024x768 full 4:3 FOV with smooth high FPS
  {
    .name        = "balanced",
    .framesize   = FRAMESIZE_XGA,   // 1024x768
    .quality     = 13,
    .brightness  = 0,
    .contrast    = 0,
    .saturation  = 0,
    .sharpness   = 0,
    .denoise     = 2,
    .ae_level    = 1,
    .aec2        = 1,
    .gainceiling = GAINCEILING_8X,
    .night_mode  = 0,               // Lock high FPS
    .hmirror     = 0,
    .vflip       = 1
  },
  // MODE_QUALITY: Full 3MP (2048x1536) QXGA detail, near-lossless JPEG, low noise
  {
    .name        = "quality",
    .framesize   = FRAMESIZE_QXGA,  // 2048x1536 (full 3MP!)
    .quality     = 12,
    .brightness  = 0,
    .contrast    = 0,
    .saturation  = 0,
    .sharpness   = 1,
    .denoise     = 3,
    .ae_level    = 1,
    .aec2        = 1,
    .gainceiling = GAINCEILING_4X,
    .night_mode  = 1,               // Allow longer exposure for clean low-ISO 3MP frames
    .hmirror     = 0,
    .vflip       = 1
  }
};

inline const char* modeToName(StreamMode m) {
  switch (m) {
    case MODE_PERFORMANCE: return "performance";
    case MODE_BALANCED:    return "balanced";
    case MODE_QUALITY:     return "quality";
    default:               return "custom";
  }
}

inline void applyProfileToSensor(sensor_t* s, const CameraProfile& p) {
  if (!s) return;

  if (s->status.framesize != p.framesize) {
    s->set_framesize(s, p.framesize);
  }
  s->set_quality(s, p.quality);
  s->set_brightness(s, p.brightness);
  s->set_contrast(s, p.contrast);
  s->set_saturation(s, p.saturation);
  s->set_sharpness(s, p.sharpness);
  s->set_denoise(s, p.denoise);

  s->set_whitebal(s, 1);
  s->set_awb_gain(s, 1);
  s->set_wb_mode(s, 0);

  s->set_exposure_ctrl(s, 1);
  s->set_aec2(s, p.aec2);
  s->set_ae_level(s, p.ae_level);

  s->set_gain_ctrl(s, 1);
  s->set_gainceiling(s, (gainceiling_t)p.gainceiling);

  s->set_hmirror(s, p.hmirror);
  s->set_vflip(s, p.vflip);

  // OV3660 register 0x3A00 bit 2 = Night mode enable (auto FPS drop in low light)
  if (s->id.PID == OV3660_PID) {
    // A warm MCU reset can preserve the sensor divider and corrupt JPEG capture.
    s->set_reg(s, 0x3108, 0xFF, 0x16);
    s->set_reg(s, 0x3A00, 0x04, p.night_mode ? 0x04 : 0x00);
  }
}
