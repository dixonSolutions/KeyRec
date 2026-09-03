# KeyRec

**One key toggles microphone recording — and GNOME's "mic is on" icon stays hidden.**

KeyRec is a tiny Linux daemon that records your microphone when you press a
global hotkey (default **Ctrl+Alt+5**, bound through [keyd](https://github.com/rvaiya/keyd))
and stops when you press it again. Recordings are saved to a folder of your
choice, named after the exact moment they began:

```
~/Documents/Recordings/keyrec_2026-09-03_12-08-45.opus
```

While it records, KeyRec suppresses the GNOME top-bar microphone indicator, so
the desktop shows no "microphone in use" icon. A desktop notification and
`keyrec status` tell you the real state.

- 🎙️ **One-key toggle** via a keyd hotkey (default `Ctrl+Alt+5`)
- 🫥 **Stealth** — hides GNOME's microphone indicator while recording
- 🗂️ **Your folder** — default `~/Documents/Recordings`, or pick one with a GUI dialog
- 🕒 **Timestamped files** — named by the start date and exact time
- 🛠️ **Everything tweakable from the CLI** — format, bitrate, source, hotkey, stealth…
- ⚙️ **Runs as a systemd daemon**, with a pre-configured system config file
- 📟 **Current recording state** available any time (`keyrec status`)

> **Scope:** Linux desktop with **GNOME on Wayland/X11**, audio via
> **PipeWire or PulseAudio**, and **keyd** for the hotkey. Built and verified on
> Ubuntu 26.04 / GNOME Shell 50. Recording works on any GNOME/Pulse setup; the
> mic-icon hiding is specific to GNOME.

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
(default, GUI picker, or a typed path) and which hotkey to use, then installs
and starts the systemd service.

When it finishes, just **press your hotkey**.

### Dependencies

`ffmpeg`, `keyd`, `pulseaudio-utils` (`pactl`), and — optionally — `zenity`
(GUI folder picker) and `libnotify-bin` (`notify-send` notifications). setup.sh
offers to install them.

---

## Usage

```bash
keyrec status              # is it recording right now?  (add --json for scripts)
keyrec toggle              # start / stop from the terminal
keyrec start               # start recording
keyrec stop                # stop and save
keyrec where               # print the recordings folder
keyrec sources             # list available microphones
keyrec doctor              # health checks
```

`keyrec status` while recording:

```
● RECORDING   00:42
    file    : /home/you/Documents/Recordings/keyrec_2026-09-03_12-08-45.opus
    folder  : /home/you/Documents/Recordings
    format  : opus
    stealth : on  (GNOME mic icon hidden)
    hotkey  : control+alt+5
```

---

## Configure anything

Settings live in `/etc/keyrec/config.toml` (system defaults) and
`~/.config/keyrec/config.toml` (your overrides). Change them from the CLI — the
daemon applies changes immediately:

```bash
keyrec config get                     # show everything
keyrec config set format flac         # opus | vorbis | mp3 | aac | flac | wav
keyrec config set bitrate 96k
keyrec config set channels 2          # stereo
keyrec config set source default      # or a name from `keyrec sources`
keyrec config set stealth false       # show the mic icon like normal apps
keyrec config set hotkey super+r      # re-binds via keyd (prompts for sudo)
keyrec config set notify false

keyrec config path                    # pick the recordings folder with a GUI dialog
keyrec set-dir ~/Voice                 # ...or set it directly
keyrec set-dir --gui                   # ...or open the picker
```

| Key | Default | Meaning |
|-----|---------|---------|
| `output_dir` | `~/Documents/Recordings` | where recordings are saved |
| `format` | `opus` | `opus`/`vorbis`/`mp3`/`aac`/`flac`/`wav` |
| `bitrate` | `48k` | bitrate for lossy formats |
| `channels` | `1` | 1 = mono, 2 = stereo |
| `samplerate` | `48000` | sample rate (Hz) |
| `source` | `default` | input source (`keyrec sources`) |
| `filename_prefix` | `keyrec` | filename prefix |
| `stealth` | `true` | hide GNOME's mic indicator |
| `hotkey` | `control+alt+5` | keyd binding |
| `notify` | `true` | desktop notification on start/stop |

---

## How it works

Short version: a small daemon holds the record/idle state; **keyd** runs
`keyrec toggle` on your hotkey (installed as a non-destructive `include` in your
keyd config); and `ffmpeg` captures the mic with an `application.id` that
GNOME's shell treats as internal, so no icon appears.

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
  then re-wire the binding with `sudo keyrec apply-hotkey` and check
  `keyrec doctor`. If another keyd tool rewrote its config it may have dropped the
  `include keyrec` line; `apply-hotkey` puts it back. `keyrec toggle` from a
  terminal always works regardless.
- **No audio / empty file** — check `keyrec sources` and set `source`, and
  confirm the daemon can reach your session (`keyrec doctor`).
- **Icon still shows** — another app may also be recording; GNOME shows the icon
  for it. With only KeyRec recording and `stealth = true`, the icon stays hidden.
- **Logs** — `journalctl -u keyrec -e`.

## License

MIT — see [LICENSE](LICENSE).
