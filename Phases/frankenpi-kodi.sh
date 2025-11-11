#!/bin/sh
# Kodi helpers for FrankenPi (POSIX sh)

. /usr/local/bin/frankenpi-compat.sh  # brings: log()

# --- Detect Kodi user/home (root on FrankenPi by default) ---
kodi_user() {
  if id xbian >/dev/null 2>&1; then echo xbian; else echo root; fi
}
kodi_home() {
  u="$(kodi_user)"
  [ "$u" = "root" ] && echo /root/.kodi || echo "/home/$u/.kodi"
}
kodi_addons_dir() { echo "$(kodi_home)/addons"; }
kodi_packages_dir() { echo "$(kodi_addons_dir)/packages"; }

# --- Process & control ---
kodi_running() { pgrep -f "kodi.bin|xbmc.bin" >/dev/null 2>&1; }
kodi_send() { command -v kodi-send >/dev/null 2>&1 && kodi-send "$@"; }

# --- Install an addon ZIP (local file) ---
kodi_install_zip_file() {
  zip="$1"
  [ -f "$zip" ] || { log "[kodi] zip not found: $zip"; return 1; }

  ADDONS_DIR="$(kodi_addons_dir)"
  PKG_DIR="$(kodi_packages_dir)"
  mkdir -p "$ADDONS_DIR" "$PKG_DIR"

  cp -f "$zip" "$PKG_DIR/" || true

  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/kodi.$$")"
  unzip -oq "$zip" -d "$tmp" || { rm -rf "$tmp"; return 1; }

  for d in "$tmp"/*; do
    [ -d "$d" ] || continue
    addon_id="$(basename "$d")"
    rm -rf "$ADDONS_DIR/$addon_id"
    mv "$d" "$ADDONS_DIR/$addon_id"
    chown -R "$(kodi_user)":"$(kodi_user)" "$ADDONS_DIR/$addon_id" 2>/dev/null || true
    log "[kodi] installed addon: $addon_id"
  done
  rm -rf "$tmp"
}

# --- Install an addon ZIP (URL) ---
kodi_install_zip_url() {
  url="$1"
  tmpzip="$(mktemp --suffix=.zip 2>/dev/null || echo "/tmp/kodi.$$")"
  if curl -fsSL -o "$tmpzip" "$url"; then
    log "[kodi] downloaded: $url"
    kodi_install_zip_file "$tmpzip"
  else
    log "[kodi][WARN] download failed: $url"
  fi
  rm -f "$tmpzip"
}
