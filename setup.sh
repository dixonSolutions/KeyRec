#!/usr/bin/env bash
#
# KeyRec interactive installer.
#
# Guides you through installing the recorder binary, a pre-configured system
# config file, the systemd service, and the global keyd hotkey.
#
#   sudo ./setup.sh
#
set -euo pipefail

# --- pretty helpers ---------------------------------------------------------
if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[90m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else
    B=""; DIM=""; G=""; Y=""; R=""; C=""; N=""
fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s%s\n' "$C" "$N" "$B" "$*"; printf '%s' "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
ask()  { local q="$1" def="${2:-}" ans; if [[ -n "$def" ]]; then read -rp "  $q [$def]: " ans || true; echo "${ans:-$def}"; else read -rp "  $q: " ans || true; echo "$ans"; fi; }
yesno(){ local q="$1" def="${2:-y}" ans; read -rp "  $q ($([[ $def == y ]] && echo 'Y/n' || echo 'y/N')): " ans || true; ans="${ans:-$def}"; [[ ${ans,,} == y* ]]; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<BANNER

${B}KeyRec${N} — hotkey-toggled microphone recorder ${DIM}(hides GNOME's mic indicator)${N}
${DIM}------------------------------------------------------------------${N}
BANNER

# --- must be root -----------------------------------------------------------
[[ $EUID -eq 0 ]] || die "please run with sudo:  sudo ./setup.sh"

# --- figure out the desktop user -------------------------------------------
step "Who is the desktop user?"
TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(ask 'Desktop username (the one recording audio)')"
fi
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
ok "installing for ${B}$TARGET_USER${N} (uid $TARGET_UID, home $TARGET_HOME)"

# --- dependencies -----------------------------------------------------------
step "Checking dependencies"
declare -A PKG=( [ffmpeg]=ffmpeg [pactl]=pulseaudio-utils [keyd]=keyd [zenity]=zenity [notify-send]=libnotify-bin )
MISSING=()
for cmd in ffmpeg pactl keyd zenity notify-send; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd"
    else
        warn "$cmd missing (package: ${PKG[$cmd]})"
        MISSING+=("${PKG[$cmd]}")
    fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    uniq_pkgs="$(printf '%s\n' "${MISSING[@]}" | sort -u | tr '\n' ' ')"
    if command -v apt-get >/dev/null 2>&1 && yesno "Install missing packages with apt ($uniq_pkgs)?" y; then
        apt-get update -qq || warn "apt update failed; continuing"
        # shellcheck disable=SC2086
        apt-get install -y $uniq_pkgs || warn "some packages failed to install"
    else
        warn "continuing without installing; KeyRec may not work until they are present"
    fi
fi
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is required"

# --- keyd group membership --------------------------------------------------
step "keyd access"
if getent group keyd >/dev/null 2>&1; then
    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx keyd; then
        ok "$TARGET_USER is already in the 'keyd' group"
    else
        usermod -aG keyd "$TARGET_USER"
        ok "added $TARGET_USER to the 'keyd' group"
        warn "a fresh login may be needed for group changes to fully apply"
    fi
else
    warn "no 'keyd' group found; is keyd installed and started? (systemctl status keyd)"
fi
systemctl is-active --quiet keyd 2>/dev/null && ok "keyd service is running" || warn "keyd service is not active — start it with: systemctl enable --now keyd"

# --- install the binary -----------------------------------------------------
step "Installing the keyrec program"
install -m 0755 "$SCRIPT_DIR/bin/keyrec" /usr/local/bin/keyrec
ok "/usr/local/bin/keyrec"

# --- system config ----------------------------------------------------------
step "System configuration file"
install -d -m 0755 /etc/keyrec
if [[ -f /etc/keyrec/config.toml ]]; then
    warn "/etc/keyrec/config.toml already exists — keeping it"
    warn "the shipped defaults are at /etc/keyrec/config.toml.new"
    install -m 0644 "$SCRIPT_DIR/config/config.toml" /etc/keyrec/config.toml.new
else
    install -m 0644 "$SCRIPT_DIR/config/config.toml" /etc/keyrec/config.toml
    ok "/etc/keyrec/config.toml"
fi

# --- choose the recordings folder ------------------------------------------
step "Where should recordings be saved?"
DEFAULT_DIR="$TARGET_HOME/Documents/Recordings"
say "  1) Default  ($DEFAULT_DIR)"
say "  2) Pick a folder with a GUI dialog"
say "  3) Type a path"
choice="$(ask 'Choose 1/2/3' 1)"
REC_DIR="$DEFAULT_DIR"
case "$choice" in
    2)
        picked="$(sudo -u "$TARGET_USER" \
            XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
            DISPLAY=":0" WAYLAND_DISPLAY="wayland-0" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
            zenity --file-selection --directory \
            --title="KeyRec — choose recordings folder" 2>/dev/null || true)"
        [[ -n "$picked" ]] && REC_DIR="$picked" || warn "no folder picked; using default"
        ;;
    3)
        typed="$(ask 'Folder path' "$DEFAULT_DIR")"
        [[ -n "$typed" ]] && REC_DIR="$typed"
        ;;
esac
# expand a leading ~ for the target user
REC_DIR="${REC_DIR/#\~/$TARGET_HOME}"
sudo -u "$TARGET_USER" mkdir -p "$REC_DIR" 2>/dev/null || mkdir -p "$REC_DIR"
ok "recordings folder: $REC_DIR"

# --- hotkey -----------------------------------------------------------------
step "Global hotkey"
say "  keyd syntax, e.g.  control+alt+5   super+r   control+alt+shift+m"
HOTKEY="$(ask 'Hotkey to toggle recording' 'control+alt+5')"
ok "hotkey: $HOTKEY"

# --- write per-user overrides so the choices above take effect -------------
step "Saving your choices"
USER_CFG_DIR="$TARGET_HOME/.config/keyrec"
sudo -u "$TARGET_USER" mkdir -p "$USER_CFG_DIR"
cat > "$USER_CFG_DIR/config.toml" <<EOF
# KeyRec user configuration (overrides /etc/keyrec/config.toml)
# Written by setup.sh. Change values with \`keyrec config set KEY VALUE\`.
output_dir = "$REC_DIR"
hotkey = "$HOTKEY"
EOF
chown "$TARGET_USER:$TARGET_GROUP" "$USER_CFG_DIR/config.toml"
ok "$USER_CFG_DIR/config.toml"

# --- render + install the systemd unit -------------------------------------
step "Installing the systemd service"
UNIT=/etc/systemd/system/keyrec.service
sed -e "s|@USER@|$TARGET_USER|g" \
    -e "s|@GROUP@|$TARGET_GROUP|g" \
    -e "s|@UID@|$TARGET_UID|g" \
    -e "s|@HOME@|$TARGET_HOME|g" \
    "$SCRIPT_DIR/systemd/keyrec.service.in" > "$UNIT"
ok "$UNIT"
systemctl daemon-reload
systemctl enable keyrec.service >/dev/null 2>&1 && ok "enabled at boot"
systemctl restart keyrec.service
ok "service started"

# --- wire the keyd hotkey ---------------------------------------------------
step "Binding the hotkey through keyd"
# give the daemon a moment to come up so apply-hotkey can read its config
sleep 1 2>/dev/null || true
if command -v keyd >/dev/null 2>&1; then
    /usr/local/bin/keyrec apply-hotkey || warn "could not bind hotkey; run 'sudo keyrec apply-hotkey' later"
else
    warn "keyd not installed — install it, then run: sudo keyrec apply-hotkey"
fi

# --- verify -----------------------------------------------------------------
step "Verifying"
sleep 1 2>/dev/null || true
if systemctl is-active --quiet keyrec.service; then
    ok "keyrec.service is active"
else
    warn "keyrec.service is not active — check: journalctl -u keyrec -e"
fi
# run doctor as the user against the live daemon
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" /usr/local/bin/keyrec doctor || true

cat <<DONE

${G}${B}KeyRec is installed.${N}

  ${B}Press ${HOTKEY}${N} to start recording; press it again to stop.
  Files are saved to: ${B}$REC_DIR${N}

  Handy commands:
    ${DIM}keyrec status${N}              show whether it is recording right now
    ${DIM}keyrec toggle${N}              start/stop from the terminal
    ${DIM}keyrec config path${N}         pick the folder with a GUI dialog
    ${DIM}keyrec config set format flac${N}   change anything (see: keyrec config get)
    ${DIM}keyrec doctor${N}              re-run health checks
    ${DIM}keyrec sources${N}             list microphones

  In stealth mode the GNOME microphone icon stays hidden while recording,
  so the desktop notification (and ${DIM}keyrec status${N}) is your cue.

DONE
