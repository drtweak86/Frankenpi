sudo tee /usr/local/frankenpi/phases/25_vault_secrets.sh >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail

say(){ echo "[vault] $*"; }
warn(){ echo "[vault][WARN] $*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

VAULT_PATH="${VAULT_PATH:-/home/pi/frankenpi-vault.age}"
TMP_DIR="/run/frankenpi-vault.$$"
mkdir -p "$TMP_DIR"

# 0) install age if missing
if ! have age; then
  say "Installing age…"
  apt-get update -y || true
  apt-get install -y --no-install-recommends age || true
fi
have age || { warn "age not available"; exit 0; }

# 1) get age identities (non-interactive)
KEY_DIR="/root/.config/age"
KEY_FILE="${KEY_DIR}/keys.txt"
if [ ! -r "$KEY_FILE" ]; then
  if [ -r /boot/frankenpi/age-keys.txt ]; then
    mkdir -p "$KEY_DIR"
    cp -f /boot/frankenpi/age-keys.txt "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    say "Installed keys from /boot/frankenpi/age-keys.txt"
  fi
fi
[ -r "$KEY_FILE" ] || { warn "No age keys at $KEY_FILE (and none on /boot). Skipping."; exit 0; }
export AGE_KEY_FILE="$KEY_FILE"

# 2) where will Kodi live?
KODI_HOME=""
for c in /root/.kodi /home/pi/.kodi /home/xbian/.kodi; do
  [ -d "$c" ] && { KODI_HOME="$c"; break; }
done
[ -n "$KODI_HOME" ] || KODI_HOME="/root/.kodi"
K_USER="$(stat -c %U "$(dirname "$KODI_HOME")" 2>/dev/null || echo root)"
K_GROUP="$(stat -c %G "$(dirname "$KODI_HOME")" 2>/dev/null || echo root)"
K_USERDATA="${KODI_HOME}/userdata"
K_ADDONDATA="${KODI_HOME}/userdata/addon_data"

# 3) decrypt vault
[ -f "$VAULT_PATH" ] || { warn "Vault not found: $VAULT_PATH"; exit 0; }
say "Decrypting vault: $VAULT_PATH"
if ! age -d -i "$KEY_FILE" -o "${TMP_DIR}/payload" "$VAULT_PATH"; then
  warn "age decrypt failed"; exit 0;
fi

# payload may be a tar.(gz|xz|zst) or a directory blob
PAY="${TMP_DIR}/payload"
WORK="${TMP_DIR}/work"
mkdir -p "$WORK"

file_type="$(file -b "$PAY" || true)"
case "$file_type" in
  *"tar archive"*) mkdir -p "$WORK"; tar -xf "$PAY" -C "$WORK" ;;
  *"gzip compressed"*|*"XZ compressed"*|*"Zstandard compressed"*)
      mkdir -p "$WORK"; tar -xf "$PAY" -C "$WORK" || true ;;
  *)
      # maybe it's already a directory serialized via age-plugin-tar? fallback: try to untar; if fail, treat as single file
      if tar -tf "$PAY" >/dev/null 2>&1; then tar -xf "$PAY" -C "$WORK"; else mkdir -p "$WORK/loose"; mv "$PAY" "$WORK/loose/"; fi
  ;;
esac

# Expected layout (relative to WORK):
#   kodi/addon_data/<addon.id>/settings.xml  (and any other files)
#   kodi/userdata/*                          (e.g., guisettings.xml etc.)
#   wg/*.conf                                -> /etc/wireguard
#   any other files are ignored unless mapped below

# 4) merge WireGuard
if compgen -G "$WORK/wg/*.conf" >/dev/null 2>&1; then
  mkdir -p /etc/wireguard
  cp -f "$WORK"/wg/*.conf /etc/wireguard/
  chmod 600 /etc/wireguard/*.conf
  say "Installed WireGuard configs to /etc/wireguard"
fi

# 5) merge Kodi userdata + addon_data
if [ -d "$WORK/kodi" ]; then
  mkdir -p "$K_USERDATA" "$K_ADDONDATA"
  # userdata root files (guisettings.xml, advancedsettings.xml, etc.)
  if [ -d "$WORK/kodi/userdata" ]; then
    rsync -a "$WORK/kodi/userdata/" "$K_USERDATA/"
  fi
  # addon_data (Seren, Umbrella, TMDbHelper, Trakt, etc.)
  if [ -d "$WORK/kodi/addon_data" ]; then
    rsync -a "$WORK/kodi/addon_data/" "$K_ADDONDATA/"
  fi
  chown -R "$K_USER:$K_GROUP" "$KODI_HOME"
  say "Merged Kodi secrets into $KODI_HOME"
fi

# 6) optional: move WG files from /boot if present (keeps /boot lean)
if compgen -G "/boot/wireguard/*.conf" >/dev/null 2>&1; then
  mkdir -p /etc/wireguard
  mv -f /boot/wireguard/*.conf /etc/wireguard/ || true
  chmod 600 /etc/wireguard/*.conf || true
  say "Imported WireGuard from /boot/wireguard"
fi

# 7) nudge wg-quick if a tunnel is defined by name file (optional)
if [ -f "$WORK/wg/autostart.txt" ]; then
  name="$(tr -d '\n\r' < "$WORK/wg/autostart.txt")"
  if [ -n "$name" ] && [ -f "/etc/wireguard/${name}.conf" ]; then
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable --now "wg-quick@${name}" || true
      say "Enabled wg-quick@${name}"
    else
      wg-quick up "$name" || true
    fi
  fi
fi

rm -rf "$TMP_DIR"
say "Vault phase complete."
SH
