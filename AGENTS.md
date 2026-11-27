# XIAO Camera Stream

Wi-Fi video from a XIAO ESP32-S3 Sense (OV3660): firmware, a Go viewer with a benchmark, and XiaoCam, a macOS menu bar app with a CLI for coding agents. Status: active, personal use.

## Commands

| Task | Command |
|------|---------|
| Build, package, and relaunch the Mac app | `cd mac && ./Scripts/compile_and_run.sh` |
| Swift tests | `cd mac && swift test` |
| Run the Go viewer | `cd client && go run . -host CAMERA_IP` |
| Build and flash the firmware | See `README.md` |

## Architecture

| Part | Path | Role |
|------|------|------|
| Firmware | `firmware/xiao_stream` | HTTP control on port 80, MJPEG on 81, binary TCP stream on 82, UDP stream on 83 |
| Go viewer | `client/` | Browser viewer, image pipeline, benchmark |
| Swift core | `mac/Sources/XiaoCamCore` | `CameraClient` and `DiscoveryClient` dependencies, the port 82 frame parser, imaging (timestamp, grid, clip) |
| Swift kit | `mac/Sources/XiaoCamKit` | `CameraModel`, capture jobs, the Unix-socket local API, the views |
| Mac app | `mac/Sources/XiaoCam` | Status item, popup panel, Settings window |
| CLI | `mac/Sources/XiaoCamCLI` | `xiaocam`; it talks only to the app socket |
| Skill | `skills/xiaocam` | Tells an agent how to use `xiaocam` and the HTTP fallback |

- The app owns the camera connection. The CLI sends requests over a socket in `~/Library/Application Support/XiaoCam/` (mode `0600`).
- The port 82 stream runs only while the popup or the Camera settings tab is open, or a clip records. Photos and grids use `/capture`.
- Captures stay in memory in the app. The CLI writes results to `~/Library/Caches/XiaoCam/captures` and keeps the newest 24.
- `CameraAccess` serializes a temporary mode change (`snap --mode`) with all other camera work.

## Rules

- `firmware/xiao_stream/wifi_private.h` holds the access point passphrase. Never commit it.
- The app signs with the Developer ID identity, so the macOS Local Network grant stays after a rebuild. An ad-hoc signature resets the grant.
- When the firmware HTTP API or the frame header changes, change `mac/Sources/XiaoCamCore` and `client/stream` together, then update the skill.
- The Settings chrome copies Beam, and the popup panel copies WalkingPad. Keep them aligned.
- The toggle card images are in `mac/Sources/XiaoCam/Resources`; the package script copies them into the bundle.
