#!/usr/bin/env bash
set -e

USER_NAME="${SUDO_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$USER_NAME")

APP_DIR="$USER_HOME/.rovenchat"
BIN_DIR="$USER_HOME/.local/bin"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
SERVICE="$SYSTEMD_DIR/rovenchat.service"

echo "Peatan RovenChati teenuse..."
runuser -l "$USER_NAME" -c 'systemctl --user disable --now rovenchat.service' 2>/dev/null || true

echo "Kustutan failid..."
rm -f "$BIN_DIR/rovenchat-gui" "$BIN_DIR/rovenchat-send" "$BIN_DIR/rovenchat-listen"
rm -f "$SERVICE"
rm -rf "$APP_DIR"

echo "RovenChat eemaldatud."
