# How KeyRec works

KeyRec is deliberately small. Three moving parts do all the work.

## 1. The daemon

`keyrec daemon` is a long-running process started by systemd
(`/etc/systemd/system/keyrec.service`). It runs **as your desktop user** so it
can reach your PipeWire/PulseAudio session, and it listens on a Unix socket at
`/run/keyrec/keyrec.sock`.

It holds one piece of state: *are we recording or not?* On a toggle it either
spawns an `ffmpeg` capture process or stops the running one. State is also
mirrored to `/run/keyrec/state.json` so `keyrec status` can answer instantly.

## 2. The hotkey (keyd)

The hotkey is installed as a keyd **include payload** — a file at
`/etc/keyd/keyrec` (no extension, which is how keyd distinguishes an include
from a top-level config):

```
[control+alt]
5 = command(/usr/local/bin/keyrec toggle --source=hotkey)
```

`keyd`'s `command()` action runs that line (as root) every time the key is
pressed, which pokes the daemon over the socket. `[control+alt]` is a keyd
*composite layer*: the binding fires only while both Control and Alt are held.

`keyrec apply-hotkey` then adds a single line — `include keyrec` — after the
`[ids]` section of each keyd config that owns a keyboard, so the binding merges
into those configs.

Why an include rather than a standalone config file? A machine can have several
keyd configs, and *"a device id may only be listed in a single config file."* A
second `[ids] *` config would compete for devices and could silently win (and
disable the other tool's remaps) or lose (and never fire). Including into the
configs that already own your keyboards sidesteps that completely:

- it never competes for device ownership;
- runtime `keyd bind` can't create composite modifier layers, so a modifier
  hotkey like Ctrl+Alt+5 genuinely needs a config file — and this is the
  least-invasive one, a single reversible line.

Each edited config is backed up to `<name>.conf.keyrec-bak`, the edit is
idempotent, and `keyrec unbind-hotkey` (run by the uninstaller) removes it.
Changing the hotkey (`keyrec config set hotkey …`) rewrites the payload and
reloads keyd for you (via `sudo`).

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
