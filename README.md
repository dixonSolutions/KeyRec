# KeyRec

**Two keys: one toggles microphone recording, one toggles camera recording — and GNOME's "mic is on" icon stays hidden.**

KeyRec is a tiny Linux daemon with two independent hotkeys, bound through
[keyd](https://github.com/rvaiya/keyd):

- **Ctrl+Alt+6** — toggle **audio** recording (microphone)
- **Ctrl+Alt+7** — toggle **video** recording (camera, with audio by default)

Press a key to start, press it again to stop. Both recorders are independent and
can run at the same time; when they do, they draw from the **same shared
microphone settings**, so they never fight over the device. Audio and video
each save to their own folder (created automatically), named after the exact
moment they began:

```
~/Documents/Recordings/keyrec_2026-09-03_12-08-45.opus
~/Videos/Camera/keyrec_video_2026-09-03_12-09-10.mp4
```

While it records audio, KeyRec suppresses the GNOME top-bar microphone
indicator, so the desktop shows no "microphone in use" icon. A desktop
notification and `keyrec status` tell you the real state.

- 🎙️ **One-key audio toggle** (default `Ctrl+Alt+6`)
- 🎥 **One-key video toggle** (default `Ctrl+Alt+7`) — camera + mic, or silent video
- 🧩 **Independent & concurrent** — record audio and video separately or together
- 🔊 **Shared mic settings** — one source, one volume; software gain never touches your real device level
- ⚡ **Instant** — the hotkey starts/stops in well under a tenth of a second
- 🫥 **Stealth** — hides GNOME's microphone indicator while recording
- 🔔 **Notifications** on start/stop that you can toggle (`keyrec notify off`)
- 🗂️ **Separate folders** — audio in `~/Documents/Recordings`, video in `~/Videos/Camera` (either configurable, GUI picker available)
- 🕒 **Timestamped files** — named by the start date and exact time
- 🛠️ **Everything tweakable from the CLI** — format, bitrate, source, mic volume, camera, hotkeys, stealth…
- ⚙️ **Runs as a systemd daemon**, with a pre-configured system config file

> **⚠️ Camera LED:** A webcam's physical activity light is wired to the sensor in
> hardware, specifically so software can't suppress it. It **lights whenever
> video records and cannot be turned off in software** — there is no stealth mode
> for video, only for the microphone icon. KeyRec is honest about this.

> **Scope:** Linux desktop with **GNOME on Wayland/X11**, audio via
> **PipeWire or PulseAudio**, a **V4L2 camera** (`/dev/video*`) for video, and
> **keyd** for the hotkeys. Built and verified on Ubuntu 26.04 / GNOME Shell 50.
> Recording works on any GNOME/Pulse setup; the mic-icon hiding is specific to
> GNOME.

---

## Install

```bash
git clone https://github.com/dixonSolutions/KeyRec.git
cd KeyRec
sudo ./setup.sh
```

The setup script guides you through everything: it checks dependencies (and
offers to `apt install` any that are missing), adds you to the `keyd` group,
installs the program and the system config file, asks where to save recordings
(default, GUI picker, or a typed path) and which two hotkeys to use, then
installs and starts the systemd service.

When it finishes, just **press your hotkey**.

### Dependencies

`ffmpeg`, `keyd`, `pulseaudio-utils` (`pactl`), and — optionally — `zenity`
(GUI folder picker), `libnotify-bin` (`notify-send` notifications), and
`v4l-utils` (`v4l2-ctl`, nicer `keyrec cameras` output). setup.sh offers to
install them. Video recording needs a camera at `/dev/video*`.

---

## Usage

```bash
keyrec status              # what's recording right now?  (add --json for scripts)

keyrec toggle              # start / stop AUDIO (default target)
keyrec toggle video        # start / stop VIDEO
keyrec start video         # start video recording
keyrec stop audio          # stop and save the audio recording

keyrec notify off          # silence start/stop notifications (on | off | toggle)
keyrec where               # print the audio folder (add `video` for the video folder)
keyrec sources             # list available microphones
keyrec cameras             # list available cameras
keyrec doctor              # health checks
```

`keyrec status` with both recorders running:

```
● AUDIO recording   00:42
    file    : /home/you/Documents/Recordings/keyrec_2026-09-03_12-08-45.opus
● VIDEO recording   00:12  (camera LED on)
    file    : /home/you/Videos/Camera/keyrec_video_2026-09-03_12-09-10.mp4
    audio dir : /home/you/Documents/Recordings
    video dir : /home/you/Videos/Camera
    audio fmt : opus
    video fmt : mp4   camera: /dev/video0
    mic vol   : 100%
    video mic : on (video has audio)
    stealth   : on  (GNOME mic icon hidden)
    notify    : on
    hotkeys   : audio control+alt+6   video control+alt+7
```

---

## Configure anything

Settings live in `/etc/keyrec/config.toml` (system defaults) and
`~/.config/keyrec/config.toml` (your overrides). Change them from the CLI — the
daemon applies changes immediately:

```bash
keyrec config get                       # show everything

# shared microphone (used by BOTH audio and video)
keyrec config set source default        # or a name from `keyrec sources`
keyrec config set channels 2            # stereo
keyrec config set mic_volume 100        # capture gain %, applied in software

# audio recording
keyrec config set format flac           # opus | vorbis | mp3 | aac | flac | wav
keyrec config set bitrate 96k
keyrec config set hotkey control+alt+6  # re-binds via keyd (prompts for sudo)

# video recording
keyrec config set camera /dev/video2    # or `default`; see `keyrec cameras`
keyrec config set video_format webm     # mp4 | mkv | webm
keyrec config set video_resolution 1280x720
keyrec config set video_framerate 30
keyrec config set video_audio false     # record SILENT video (audio rec is never muted)
keyrec config set video_hotkey control+alt+7

# shared behaviour
keyrec config set stealth false         # show the mic icon like normal apps
keyrec config set notify false

keyrec config path                      # pick the AUDIO folder with a GUI dialog
keyrec set-dir ~/Voice                   # ...or set the audio folder directly
keyrec set-dir --video ~/Videos/Camera   # set the video folder (or --video --gui)
keyrec where video                       # print the video folder
```

| Key | Default | Meaning |
|-----|---------|---------|
| `output_dir` | `~/Documents/Recordings` | where **audio** recordings are saved |
| `video_dir` | `~/Videos/Camera` | where **video** recordings are saved |
| **`source`** | `default` | **shared** input source (`keyrec sources`) |
| **`channels`** | `1` | **shared** 1 = mono, 2 = stereo |
| **`samplerate`** | `48000` | **shared** sample rate (Hz) |
| **`mic_volume`** | `100` | **shared** capture gain %, applied in software |
| `format` | `opus` | audio: `opus`/`vorbis`/`mp3`/`aac`/`flac`/`wav` |
| `bitrate` | `48k` | audio bitrate for lossy formats |
| `hotkey` | `control+alt+6` | keyd binding — toggles audio |
| `camera` | `default` | video: device path or `default` (`keyrec cameras`) |
| `video_format` | `mp4` | video: `mp4`/`mkv`/`webm` |
| `video_resolution` | `default` | video: `WxH` or `default` |
| `video_framerate` | `default` | video: fps or `default` |
| `video_bitrate` | `4M` | video: target bitrate |
| `video_audio` | `true` | include mic in video (`false` = silent video) |
| `video_hotkey` | `control+alt+7` | keyd binding — toggles video |
| `camera_led_off_cmd` | `` (empty) | optional command run before video (see LED note) |
| `camera_led_on_cmd` | `` (empty) | optional command run after video (see LED note) |
| `filename_prefix` | `keyrec` | filename prefix |
| `stealth` | `true` | hide GNOME's mic indicator (mic only) |
| `notify` | `true` | desktop notification on start/stop |

**Shared microphone settings** (bold rows) are used by both the audio recorder
and the video recorder's audio track. `mic_volume` is applied as a per-stream
software gain, so it never changes your real system mic level — which is exactly
why two simultaneous captures don't interfere with each other.

---

## How it works

Short version: a small daemon holds two independent record/idle states;
**keyd** runs `keyrec toggle audio` / `keyrec toggle video` on your hotkeys
(installed as a non-destructive `include` in your keyd config); and `ffmpeg`
captures the mic with an `application.id` that GNOME's shell treats as internal,
so no mic icon appears. Video adds a V4L2 camera input alongside the shared mic.

**On the camera light:** the LED is a hardware privacy feature tied to the camera
sensor's power. No V4L2 ioctl, kernel flag, or ffmpeg option can disable it, and
KeyRec doesn't pretend otherwise — the mic icon is software (hideable), the
camera LED is hardware (not).

Full explanation, including the exact GNOME shell logic and how to verify it:
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

---

## Uninstall

```bash
sudo ./uninstall.sh            # keeps /etc/keyrec and your recordings
sudo ./uninstall.sh --purge    # also removes /etc/keyrec
```

Your recordings are never touched.

---

## Troubleshooting

- **Hotkey does nothing** — make sure `keyd` is running (`systemctl status keyd`),
  then re-wire the bindings with `sudo keyrec apply-hotkey` and check
  `keyrec doctor`. If another keyd tool rewrote its config it may have dropped the
  `include keyrec` line; `apply-hotkey` puts it back. `keyrec toggle` from a
  terminal always works regardless.
- **No audio / empty file** — check `keyrec sources` and set `source`, and
  confirm the daemon can reach your session (`keyrec doctor`).
- **Video fails / empty file** — check `keyrec cameras`; the camera may not
  support the requested `video_resolution`/`video_framerate` (try `default`), or
  it may be in use by another app. See `journalctl -u keyrec -e`.
- **Icon still shows** — another app may also be recording; GNOME shows the icon
  for it. With only KeyRec recording and `stealth = true`, the icon stays hidden.
- **Camera light is on** — expected and unavoidable; it's hardware (see above).
- **Logs** — `journalctl -u keyrec -e`.

## License

MIT — see [LICENSE](LICENSE).
