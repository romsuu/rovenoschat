#!/usr/bin/env bash
set -e

echo "=== RovenChat PRO + GUI + Tailscale Installer v12 ==="

if [[ -z "$SUDO_USER" ]]; then
  echo "Käivita: sudo ./install_rovenchat.sh"
  exit 1
fi

USER_NAME="$SUDO_USER"
USER_HOME=$(eval echo "~$USER_NAME")

APP_DIR="$USER_HOME/.rovenchat"
GUI_DIR="$APP_DIR/gui"
BIN_DIR="$USER_HOME/.local/bin"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
INFO_FILE="$APP_DIR/info.json"

# GUI fail GitHubist
GITHUB_GUI_URL="https://raw.githubusercontent.com/romsuu/rovenoschat/main/gui/rovenchat_gui.py"

echo "Kasutaja: $USER_NAME"
echo "Kodu: $USER_HOME"

echo "Paigaldan paketid..."
pacman -S --noconfirm --needed openbsd-netcat libnotify jq openssl python python-pip python-pyqt6 tailscale curl

echo "Loome kaustad..."
sudo -u "$USER_NAME" mkdir -p "$APP_DIR" "$GUI_DIR" "$BIN_DIR" "$SYSTEMD_DIR"

# --- ID ja võtmed ---
ID_FILE="$APP_DIR/id.json"
PRIV="$APP_DIR/private.pem"
PUB="$APP_DIR/public.pem"

if [[ ! -f "$ID_FILE" ]]; then
  echo "Genereerin RovenChat ID ja võtmed..."
  sudo -u "$USER_NAME" openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$PRIV"
  sudo -u "$USER_NAME" openssl rsa -in "$PRIV" -pubout -out "$PUB"
  RAW=$(sudo -u "$USER_NAME" openssl rand -hex 8)
  ID=$(echo "$RAW" | tr 'a-f' 'A-F')
  PUB_INLINE=$(tr -d '\n' < "$PUB")

  sudo -u "$USER_NAME" bash -c "cat > '$ID_FILE' <<EOF
{
  \"id\": \"$ID\",
  \"name\": \"$USER_NAME\",
  \"public_key\": \"$PUB_INLINE\"
}
EOF"
  chmod 600 "$PRIV"
else
  ID=$(jq -r '.id' "$ID_FILE")
  echo "ID juba olemas: $ID"
fi

# --- Kontaktid ---
CONTACTS="$APP_DIR/contacts.json"
if [[ ! -f "$CONTACTS" ]]; then
  echo "Loon kontaktide faili..."
  sudo -u "$USER_NAME" bash -c "cat > '$CONTACTS' <<EOF
{
  \"friends\": []
}
EOF"
fi

# --- CLI: rovenchat-send ---
SEND="$BIN_DIR/rovenchat-send"
echo "Loon rovenchat-send..."
sudo -u "$USER_NAME" bash -c "cat > '$SEND' << 'EOF'
#!/usr/bin/env bash
APP="$HOME/.rovenchat"
ID_FILE="$APP/id.json"
CONTACTS="$APP/contacts.json"

if [[ $# -lt 2 ]]; then
  echo "Kasutus: rovenchat-send FRIEND_ID \"message\""
  exit 1
fi

FRIEND_ID="$1"; shift
MSG="$*"

MY_ID=$(jq -r '.id' "$ID_FILE")
MY_NAME=$(jq -r '.name' "$ID_FILE")
FRIEND_IP=$(jq -r --arg ID "$FRIEND_ID" '.friends[] | select(.id==$ID) | .ip' "$CONTACTS")

if [[ -z "$FRIEND_IP" || "$FRIEND_IP" == "null" ]]; then
  echo "Friend ID not found: $FRIEND_ID"
  exit 1
fi

JSON=$(jq -n --arg from_id "$MY_ID" --arg from_name "$MY_NAME" --arg msg "$MSG" \
  '{from_id:$from_id, from_name:$from_name, message:$msg}')

echo "$JSON" | nc "$FRIEND_IP" 5555
EOF"
chmod +x "$SEND"

# --- CLI: rovenchat-listen ---
LISTEN="$BIN_DIR/rovenchat-listen"
echo "Loon rovenchat-listen..."
sudo -u "$USER_NAME" bash -c "cat > '$LISTEN' << 'EOF'
#!/usr/bin/env bash
APP="$HOME/.rovenchat"
CONTACTS="$APP/contacts.json"
PORT=5555

while true; do
  nc -l -p "$PORT" | while read -r line; do
    FROM_ID=$(echo "$line" | jq -r '.from_id // empty')
    NAME=$(echo "$line" | jq -r '.from_name // "Tundmatu"')
    MSG=$(echo "$line" | jq -r '.message // empty')

    [[ -z "$FROM_ID" || -z "$MSG" ]] && continue

    IN_LIST=$(jq -r --arg ID "$FROM_ID" '.friends[] | select(.id==$ID) | .name' "$CONTACTS")
    [[ -z "$IN_LIST" || "$IN_LIST" == "null" ]] && continue

    notify-send "RovenChat: $NAME" "$MSG"
  done
done
EOF"
chmod +x "$LISTEN"

# --- systemd teenus ---
SERVICE="$SYSTEMD_DIR/rovenchat.service"
echo "Loon systemd teenuse faili..."
sudo -u "$USER_NAME" bash -c "cat > '$SERVICE' <<EOF
[Unit]
Description=RovenChat Listener

[Service]
ExecStart=$BIN_DIR/rovenchat-listen
Restart=always

[Install]
WantedBy=default.target
EOF"

# --- Tailscale seadistamine ---
echo "Seadistan Tailscale..."
systemctl enable --now tailscaled || true

echo "Annan kasutajale Tailscale operator-õiguse..."
tailscale set --operator="$USER_NAME" || true

echo "Käivitan Tailscale login'i..."
runuser -l "$USER_NAME" -c 'tailscale up' || true

TS_IP=$(runuser -l "$USER_NAME" -c 'tailscale ip -4 2>/dev/null | head -n1' || true)

sudo -u "$USER_NAME" bash -c "cat > '$INFO_FILE' <<EOF
{
  \"id\": \"$ID\",
  \"tailscale_ip\": \"${TS_IP:-unknown}\"
}
EOF"

# --- GUI GitHubist ---
echo "Tõmban GUI GitHubist..."
curl -L "$GITHUB_GUI_URL" -o "$GUI_DIR/rovenchat_gui.py"
chmod +x "$GUI_DIR/rovenchat_gui.py"

# --- käivitusfail ---
LAUNCH="$BIN_DIR/rovenchat-gui"
echo "Loon käivitusfaili..."
cat > "$LAUNCH" <<EOF
#!/usr/bin/env bash
python3 "$GUI_DIR/rovenchat_gui.py"
EOF
chmod +x "$LAUNCH"

# --- uninstaller käsk ---
UNINSTALL_BIN="/usr/local/bin/rovenchat-gui-uninstall"
echo "Loon unistalleri käsu: $UNINSTALL_BIN"
cat > "$UNINSTALL_BIN" << 'EOF'
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
EOF
chmod +x "$UNINSTALL_BIN"

chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME/.rovenchat" "$BIN_DIR" "$SYSTEMD_DIR" || true

echo
echo "=== RovenChat PRO + GUI + Tailscale paigaldatud ==="
echo "Sinu RovenChat ID: $ID"
echo
echo "Käivita listener:"
echo "  systemctl --user enable --now rovenchat.service"
echo
echo "Käivita GUI:"
echo "  rovenchat-gui"
echo
echo "Uninstall:"
echo "  sudo rovenchat-gui-uninstall"
