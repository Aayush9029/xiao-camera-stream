---
name: xiaocam
description: See the physical world through the XIAO Wi-Fi camera with the xiaocam command. Use when a task needs eyes on a real scene, for example to check a device, read a screen or a label, watch for a change over time, or record motion. Covers status, snap, grid, clip, modes, settings, timestamps, and failures.
---

# xiaocam

The XiaoCam Mac app connects to a XIAO ESP32-S3 camera on the local network. The `xiaocam` command talks to the app. If the app is not running, the command opens it and waits.

Each capture command prints one absolute file path on stdout. Read that file with your image tool to see the scene.

## Check the camera first

1. Run `xiaocam status`.
2. Make sure that the first line is `camera    live <host>`.
3. If the exit code is not 0, go to "Failures".

## Take a photo

1. Run `xiaocam snap`.
2. Read the file at the printed path.

Options:

- `--mode quality`: use full 3 MP detail for this photo only. The camera then goes back to its mode and settings. Use it to read text, small labels, or fine parts.
- `--enhance`: remove noise and sharpen. Use it in dim light. It takes more time.
- `--no-timestamp`: do not put the time on the image.
- `--out PATH`: write to a file or a folder that you choose.
- `--json`: print metadata (path, frame times, width, height, mode) instead of the bare path.

## Watch for a change over time

Use a grid to see change: a moving object, a light that blinks, a print that grows. One grid image is cheaper to read than many photos.

1. Run `xiaocam grid --every 5 --for 30` as a background command.
2. Do other work. The command exits when the grid is done.
3. Read the file at the printed path.

- The grid shows the photos left to right, then top to bottom.
- `--every` is the seconds between photos (0.5 or more). `--for` is the total seconds (up to 3600).
- A grid holds 36 photos or less. For a longer run, the app spreads the photos over the full time.
- `--columns N` sets the columns. The long edge of the grid is 2000 px or less.
- `--detach` prints a job id at once. Later, run `xiaocam job <id> --wait` to get the path.

## Record motion

1. Run `xiaocam clip --for 10`.
2. Use the printed `.mp4` path.

- `--for` is 1 to 60 seconds. `--fps` is the highest frame rate to keep (default 10).
- The camera mode sets the real frame rate. Use `performance` mode for smooth motion.
- If you cannot watch video, use a grid with a short interval instead, for example `--every 0.5 --for 6`.

## Modes

| Mode | Size | Use it for |
|------|------|------------|
| `performance` | 480x320 | Motion and the highest frame rate |
| `balanced` | 1024x768 | The default, for most photos |
| `quality` | 2048x1536 | Text, small labels, and fine detail |

- Run `xiaocam mode <name>` to set a mode for all captures.
- A mode change resets the image settings to the defaults of that mode.
- To change only one photo, use `xiaocam snap --mode quality`.
- When your task is done, run `xiaocam mode balanced` if you changed the mode.

## Settings

1. Run `xiaocam config` to see each setting, its value, and its range.
2. Run `xiaocam set key=value` to change one or more settings.

| Key | Range | Use it when |
|-----|-------|-------------|
| `brightness` | -3 to 3 | The image is too dark or too bright |
| `ae_level` | -5 to 5 | The exposure is wrong |
| `contrast` | -3 to 3 | Edges are hard to see |
| `saturation` | -4 to 4 | Colors are too weak or too strong |
| `sharpness` | -3 to 3 | Fine detail is soft |
| `denoise` | 0 to 8 | The image has grain |
| `night_mode` | on or off | The room is dim. The frame rate goes down |
| `hmirror`, `vflip` | on or off | The image is mirrored or upside down |

The command rejects a value outside its range. To go back to the defaults, set the mode again.

## Timestamps

- A photo shows the local date and time at the bottom left, for example `2026-11-27 14:03:22`.
- Each grid cell shows its number, its time, and the seconds since the first photo, for example `#3  14:03:32  +10s`.
- Each video frame shows the date, the time, and the seconds since the start.
- For exact times, use `--json`. The `frames` list gives `captured_at` in ISO 8601 and `offset` in seconds.

## Files

- The default folder is `~/Library/Caches/XiaoCam/captures`. The CLI keeps only the newest 24 captures there.
- To keep a capture, use `--out PATH`. The CLI does not delete files that you name.

## Without the Mac app

If `xiaocam` is not available (Linux, a container, another computer on the same network), ask the camera directly over HTTP. Use `xiao-cam.local`, or the IP address of the camera.

- Photo: `curl -s http://xiao-cam.local/capture -o frame.jpg`, then read `frame.jpg`.
- Status: `curl -s http://xiao-cam.local/api/status`
- Mode: `curl -s -X POST 'http://xiao-cam.local/api/mode?mode=quality'`
- Setting: `curl -s -X POST 'http://xiao-cam.local/api/settings?brightness=1'`

These photos have no timestamp and no grid. Record the time yourself.

## Failures

The CLI writes errors to stderr and exits with a code that is not 0.

| Exit | Meaning | Action |
|------|---------|--------|
| 2 | Camera offline | Run `xiaocam discover`. If it finds a host, run `xiaocam connect <host>`. If not, tell the user to power the camera and check its Wi-Fi |
| 3 | App not running, or it quit during the command | Run `xiaocam status`. Do not repeat a `mode` or `set` command until you see the camera state. If it still fails, tell the user to open XiaoCam.app one time, or to allow Local Network access in System Settings |
| 4 | Busy | Wait a few seconds, then try again. The app runs 4 captures at a time or less |
| 5 | Job or result not found | Run `xiaocam jobs`. A result is given one time only |
| 64 | Bad arguments | Read the message and fix the command |

- Do not loop `xiaocam snap` quickly to watch a scene. Use `xiaocam grid`.
- If a photo is dark or blurred, try `--enhance`, then `brightness`, then `--mode quality`.
