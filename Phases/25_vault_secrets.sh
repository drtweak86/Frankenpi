#!/usr/bin/env bash
# FrankenPi: decrypt + deploy secrets from age vault
set -euo pipefail

say(){ echo "[vault] $*"; }
warn(){ echo "[vault][WARN] $*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

VAULT_PATH="${VAULT_PATH:-/home/pi/frankenpi-vault.age}"
TMP_DIR="${TMP_DIR:-/run/frankenpi-vault.$$}"

# Fallback TMP_DIR if /run is not writable
if ! mkdir -p "$TMP_DIR" 2>/dev/null; then
    TMP_DIR="/tmp/frankenpi-vault.$$"
    mkdir -p "$TMP_DIR"
    warn "Using fallback TMP_DIR: $TMP_DIR"
fi

# Ensure TMP cleanup on exit/interruption
trap 'rm -rf "$TMP_DIR"' EXIT

# --- 0) install age if missing ---
if ! have age; then
    if have apt-get; then
        say "Installing age via apt-get…"
        apt-get update -y || true
        apt-get install -y --no-install-recommends age || true
    elif have curl; then
        say "Installing age via official installer…"
        curl -fsSL https://github.com/FiloSottile/age/releases/latest/download/age-linux-amd64.tar.gz | tar -xz -C /usr/local/bin --strip-components=1 age
    else
        warn "age not found; skipping installation"
    fi
fi
have age || { warn "age not available; cannot proceed"; exit 0; }

# --- 1) get age identities (non-interactive) ---
KEY_DIR="/root/.config/age"
KEY_FILE="${KEY_DIR}/keys.txt"
if [ ! -r "$KEY_FILE" ] && [ -r /boot/frankenpi/age-keys.txt ]; then
    mkdir -p "$KEY_DIR"
    cp -f /boot/frankenpi/age-keys.txt "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    say "Installed keys from /boot/frankenpi/age-keys.txt"
fi
[ -r "$KEY_FILE" ] || { warn "No age keys found at $KEY_FILE (nor on /boot). Skipping."; exit 0; }
export AGE_KEY_FILE="$KEY_FILE"

# --- 2) detect Kodi home ---
KODI_HOME=""
for c in /root/.kodi /home/pi/.kodi /home/xbian/.kodi; do
    [ -d "$c" ] && { KODI_HOME="$c"; break; }
done
if [ -z "$KODI_HOME" ]; then
    warn "Could not detect Kodi home, defaulting to /root/.kodi"
    KODI_HOME="/root/.kodi"
fi
K_USER="$(stat -c %U "$(dirname "$KODI_HOME")" 2>/dev/null || echo root)"
K_GROUP="$(stat -c %G "$(dirname "$KODI_HOME")" 2>/dev/null || echo root)"
K_USERDATA="${KODI_HOME}/userdata"
K_ADDONDATA="${KODI_HOME}/userdata/addon_data"

# --- 3) decrypt vault ---
[ -f "$VAULT_PATH" ] || { warn "Vault not found: $VAULT_PATH"; exit 0; }
say "Decrypting vault: $VAULT_PATH"
if ! age -d -i "$KEY_FILE" -o "${TMP_DIR}/payload" "$VAULT_PATH"; then
    warn "age decrypt failed"; exit 0
fi

PAY="${TMP_DIR}/payload"
WORK="${TMP_DIR}/work"
mkdir -p "$WORK"

# Unpack payload
if tar -tf "$PAY" >/dev/null 2>&1; then
    tar -xf "$PAY" -C "$WORK"
else
    mkdir -p "$WORK/loose"
    mv "$PAY" "$WORK/loose/"
fi

# --- 4) deploy WireGuard configs ---
if compgen -G "$WORK/wg/*.conf" >/dev/null 2>&1; then
    mkdir -p /etc/wireguard
    cp -f "$WORK"/wg/*.conf /etc/wireguard/
    chmod 600 /etc/wireguard/*.conf
    say "Installed WireGuard configs to /etc/wireguard"
fi

# --- 5) merge Kodi userdata + addon_data ---
if [ -d "$WORK/kodi" ]; then
    mkdir -p "$K_USERDATA" "$K_ADDONDATA"
    [ -d "$WORK/kodi/userdata" ] && rsync -a "$WORK/kodi/userdata/" "$K_USERDATA/"
    [ -d "$WORK/kodi/addon_data" ] && rsync -a "$WORK/kodi/addon_data/" "$K_ADDONDATA/"
    chown -R "$K_USER:$K_GROUP" "$KODI_HOME"
    say "Merged Kodi secrets into $KODI_HOME"
fi

# --- 6) optional: move WG from /boot ---
if compgen -G "/boot/wireguard/*.conf" >/dev/null 2>&1; then
    mkdir -p /etc/wireguard
    mv -f /boot/wireguard/*.conf /etc/wireguard/ || true
    chmod 600 /etc/wireguard/*.conf || true
    say "Imported WireGuard from /boot/wireguard"
fi

# --- 7) autostart wg tunnel if defined ---
if [ -f "$WORK/wg/autostart.txt" ]; then
    name="$(tr -d '\n\r' < "$WORK/wg/autostart.txt")"
    if [ -n "$name" ] && [ -f "/etc/wireguard/${name}.conf" ]; then
        if have systemctl; then
            systemctl enable --now "wg-quick@${name}" || true
            say "Enabled wg-quick@${name}"
        elif have wg-quick; then
            wg-quick up "$name" || true
            say "Brought up wg-quick $name"
        else
            warn "wg-quick not available; cannot bring up $name"
        fi
    fi
fi

say "Vault phase complete."
