# How KeyRec works

KeyRec is deliberately small. A few moving parts do all the work.

## 1. The daemon

`keyrec daemon` is a long-running process started by systemd
(`/etc/systemd/system/keyrec.service`). It runs **as your desktop user** so it
can reach your PipeWire/PulseAudio session and camera, and it listens on a Unix
socket at `/run/keyrec/keyrec.sock`.

It holds two independent recorders — **audio** and **video** — each with its own
*recording or not?* state. On a toggle for a given target it either spawns an
`ffmpeg` capture process for that recorder or stops the running one; the two are
completely independent and can be active at the same time. State is mirrored to
`/run/keyrec/state.json` so `keyrec status` can answer instantly.

### Sharing the microphone

Both recorders draw their audio from **one shared block of microphone settings**
(`source`, `channels`, `samplerate`, `mic_volume`). Sharing is achieved the
simple, robust way: each `ffmpeg` opens the same PulseAudio source independently,
and PulseAudio duplicates one microphone into as many capture streams as ask for
it. Nothing changes the device. `mic_volume` is applied as a per-stream software
gain filter (`-af volume=…`), so adjusting it never alters your real system mic
level — which is precisely why running audio and video at once can't make them
interfere with each other. Video includes the mic by default; set
`video_audio = false` for silent video (audio recording is never muted).

## 2. The hotkeys (keyd)

The hotkeys are installed as a single keyd **include payload** — a file at
`/etc/keyd/keyrec` (no extension, which is how keyd distinguishes an include
from a top-level config):

```
[control+alt]
6 = command(/usr/local/bin/keyrec toggle audio --source=hotkey)
7 = command(/usr/local/bin/keyrec toggle video --source=hotkey)
```

`keyd`'s `command()` action runs the matching line (as root) every time the key
is pressed, which pokes the daemon over the socket. `[control+alt]` is a keyd
*composite layer*: the bindings fire only while both Control and Alt are held.
Both hotkeys share that layer, so they live in one block.

`keyrec apply-hotkey` then adds a single line — `include keyrec` — after the
`[ids]` section of each keyd config that owns a keyboard, so the bindings merge
into those configs.

Why an include rather than a standalone config file? A machine can have several
keyd configs, and *"a device id may only be listed in a single config file."* A
second `[ids] *` config would compete for devices and could silently win (and
disable the other tool's remaps) or lose (and never fire). Including into the
configs that already own your keyboards sidesteps that completely:

- it never competes for device ownership;
- runtime `keyd bind` can't create composite modifier layers, so a modifier
  hotkey like Ctrl+Alt+6 genuinely needs a config file — and this is the
  least-invasive one, a couple of reversible lines.

Each edited config is backed up to `<name>.conf.keyrec-bak`, the edit is
idempotent, and `keyrec unbind-hotkey` (run by the uninstaller) removes it.
Changing either hotkey (`keyrec config set hotkey …` / `… video_hotkey …`)
rewrites the payload and reloads keyd for you (via `sudo`).

## 3. The stealth trick (hiding GNOME's mic indicator)

When any application records from the microphone, GNOME shows a microphone icon
in the top bar. KeyRec makes that icon **not appear** while it records.

GNOME's shell decides whether to show the icon in `volume.js`
(`InputIndicator._maybeShowInput`). Paraphrased:

```js
const skippedApps = ['org.gnome.VolumeControl', 'org.PulseAudio.pavucontrol'];
showIcon = control.get_source_outputs().some(
    output => !skippedApps.includes(output.get_application_id()));
```

In other words: the icon shows only if some recording stream has an
`application.id` that is **not** on the shell's skip list (those two apps are
skipped because they only monitor the input level).

So KeyRec launches `ffmpeg` with:

```
PULSE_PROP="application.id=org.gnome.VolumeControl"
```

`libpulse` stamps that `application.id` onto the capture stream. GNOME sees a
stream it already ignores, and — as long as nothing *else* is recording — the
icon stays hidden. The audio is captured for real; only the indicator is
suppressed.

This is honest about its scope: if another genuine app is recording at the same
time, GNOME will (correctly) still show the icon for *that* app. KeyRec only
hides its own contribution.

Turn it off any time with `keyrec config set stealth false`, and the icon
behaves normally.

## 4. The camera light — why it can't be hidden

The mic indicator is a *software* icon drawn by the GNOME shell, so software can
choose not to draw it. The camera's activity LED is the opposite: on
essentially every webcam (laptop built-ins and USB cameras alike) the LED is
wired to the sensor's power/data rail **in hardware**, specifically so that no
software — driver, kernel, or userspace — can light the sensor without lighting
the LED. It's a deliberate privacy guarantee.

That means there is no V4L2 ioctl, kernel module option, or `ffmpeg` flag that
turns the LED off while capturing. KeyRec doesn't try to, and doesn't pretend it
can: when video records, the light is on. The only ways to have a dark LED are
physical (a camera whose firmware genuinely decouples it — rare and not something
software controls, or simply covering the lens, which of course also blocks the
image). If you need to record with no visible indicator, use **audio recording**,
where the indicator really is software and really can be hidden.

### Verifying it

You can check the exact decision the shell makes using the shell's own audio
library:

```python
import gi
gi.require_version('Gvc', '1.0')          # GI_TYPELIB_PATH=/usr/lib/gnome-shell
from gi.repository import Gvc, GLib       # LD_LIBRARY_PATH=/usr/lib/gnome-shell
# open a Gvc.MixerControl, list get_source_outputs(), and apply the skip test.
```

`keyrec doctor` reports the current state and configuration.
