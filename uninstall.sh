#!/usr/bin/env bash
#
# Remove KeyRec. Leaves your recordings untouched.
#
#   sudo ./uninstall.sh
#
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo ./uninstall.sh" >&2; exit 1; }

echo "Removing the keyd hotkey binding..."
if [[ -x /usr/local/bin/keyrec ]]; then
    /usr/local/bin/keyrec unbind-hotkey 2>/dev/null || true
fi

echo "Stopping and disabling the service..."
systemctl disable --now keyrec.service 2>/dev/null || true
rm -f /etc/systemd/system/keyrec.service
systemctl daemon-reload 2>/dev/null || true

echo "Removing files..."
rm -f /usr/local/bin/keyrec
rm -rf /run/keyrec

KEEP_CONF="${1:-}"
if [[ "$KEEP_CONF" == "--purge" ]]; then
    rm -rf /etc/keyrec
    echo "Removed /etc/keyrec (config)."
    echo "Note: per-user config at ~/.config/keyrec was left in place."
else
    echo "Left /etc/keyrec and ~/.config/keyrec in place (use --purge to remove /etc/keyrec)."
fi

echo "Done. Your recordings were not touched."
