#!/bin/sh
# FrankenPi: Install Exo2 fonts + Font.xml for AF²
set -eu
. /usr/local/bin/frankenpi-compat.sh  # log, svc_* if needed

ASSETS_ROOT="/usr/local/share/frankenpi/assets"
FONT_XML_SRC="${ASSETS_ROOT}/config/Font.xml"
FONTS_SRC_DIR="${ASSETS_ROOT}/fonts"

CANDIDATE_SKINS="skin.arctic.fuse.2"

ts(){ date '+%F %T'; }

need_file() { [ -f "$1" ] || { echo "[fonts][WARN][$(ts)] missing: $1" >&2; exit 0; }; }

need_file "$FONT_XML_SRC"
need_file "${FONTS_SRC_DIR}/Exo2-Regular.ttf"
need_file "${FONTS_SRC_DIR}/Exo2-Light.ttf"
need_file "${FONTS_SRC_DIR}/Exo2-Bold.ttf"

install_into_skin() {
  skin_dir="$1"
  [ -d "$skin_dir" ] || return 1
  fonts_dir="$skin_dir/media/fonts"
  layout_dir="$skin_dir/1080i"
  mkdir -p "$fonts_dir" "$layout_dir"
  cp -fv "$FONTS_SRC_DIR"/*.ttf "$fonts_dir/"
  cp -fv "$FONT_XML_SRC" "$layout_dir/Font.xml"
  chown -R "$(stat -c '%U:%G' "$skin_dir")" "$skin_dir" 2>/dev/null || true
  echo "[fonts][$(ts)] Patched skin at: $skin_dir"
  return 0
}

install_into_kodi_media() {
  kh="$1"
  [ -d "$kh" ] || return 0
  mkdir -p "$kh/media/Fonts"
  cp -fv "$FONTS_SRC_DIR"/*.ttf "$kh/media/Fonts/"
  chown -R "$(stat -c '%U:%G' "$kh")" "$kh/media/Fonts" 2>/dev/null || true
  echo "[fonts][$(ts)] Copied TTFs to: $kh/media/Fonts"
}

patched=0

for kh in /root/.kodi /home/*/.kodi; do
  [ -d "$kh" ] || continue
  install_into_kodi_media "$kh"
  for sid in $CANDIDATE_SKINS; do
    sdir="$kh/addons/$sid"
    if install_into_skin "$sdir"; then
      patched=1
    fi
  done
done

if [ "$patched" -eq 0 ]; then
  echo "[fonts][WARN][$(ts)] Target skin not installed yet; run again after addons."
  exit 0
fi

# Best-effort reload
if command -v kodi-send >/dev/null 2>&1; then
  sleep 2
  kodi-send --action="ReloadSkin()" >/dev/null 2>&1 || true
fi

echo "[fonts][$(ts)] EXO2 fonts + Font.xml installed."
