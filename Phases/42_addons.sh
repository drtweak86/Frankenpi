#!/bin/sh
# FrankenPi: Install Kodi repos + core addons (local-first, url fallback)
set -eu
. /usr/local/bin/frankenpi-compat.sh  # log, svc_*

BIN="/usr/local/sbin/frankenpi-install-addons"
CFG="/etc/frankenpi/addons.conf"
CACHE="/usr/local/share/frankenpi/repos"   # place your .zip files here in the image
STAMP="/var/lib/frankenpi/.addons-installed"
SVC="/etc/systemd/system/frankenpi-addons.service"

mkdir -p "$(dirname "$STAMP")" /etc/frankenpi "$CACHE"

# Seed editable config
if [ ! -f "$CFG" ]; then
  cat >"$CFG"<<'CFG'
KODI_RPC="http://127.0.0.1:8080/jsonrpc"
CACHE_DIR="/usr/local/share/frankenpi/repos"

REPOS="
Umbrella|https://umbrella-plugins.github.io/repository.umbrella-*.zip
Nixgates|https://nixgates.github.io/packages/repository.nixgates-*.zip
A4KSubtitles|https://a4k-openproject.github.io/a4kSubtitles/packages/repository.a4k*.zip
Otaku|https://goldenfreddy0703.github.io/repository.otaku/repository.otaku-*.zip
CocoScrapers|https://cocojoe2411.github.io/repository.cocoscrapers-*.zip
jurialmunkey|https://jurialmunkey.github.io/repository.jurialmunkey/repository.jurialmunkey-*.zip
RectorStuff|https://github.com/rmrector/repository.rector.stuff/raw/master/latest/repository.rector.stuff-latest.zip
"

ADDONS="
plugin.video.umbrella
plugin.video.seren
service.subtitles.a4ksubtitles
plugin.video.otaku
script.module.cocoscrapers
script.trakt
script.artwork.dump
plugin.video.themoviedb.helper
skin.arctic.fuse.2
"

EXTRA_ZIPS="
OptiKlean.zip
Seren-BBViking.zip
"
CFG
fi

# Worker
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu

ts(){ date '+%F %T'; }
say(){ printf '[addons][%s] %s\n' "$(ts)" "$*"; }
warn(){ printf '[addons][WARN][%s] %s\n' "$(ts)" "$*" >&2; }

CONF="/etc/frankenpi/addons.conf"
[ -r "$CONF" ] && . "$CONF"

KODI_RPC="${KODI_RPC:-http://127.0.0.1:8080/jsonrpc}"
CACHE_DIR="${CACHE_DIR:-/usr/local/share/frankenpi/repos}"
SETTLE_SECS="${SETTLE_SECS:-5}"

jsonrpc() { curl -sS -H 'Content-Type: application/json' -X POST "$KODI_RPC" -d "$1" 2>/dev/null || true; }
wait_rpc(){
  t="${1:-60}"; i=0
  while [ "$i" -lt "$t" ]; do
    curl -s "$KODI_RPC" >/dev/null 2>&1 && return 0
    i=$((i+2)); sleep 2
  done
  return 1
}

install_zip_via_files(){
  zip="$1"
  for KH in /root/.kodi /home/*/.kodi; do
    [ -d "$KH" ] || continue
    mkdir -p "$KH/addons/packages"
    cp -f "$zip" "$KH/addons/packages/" 2>/dev/null || true
  done
  body=$(printf '{"jsonrpc":"2.0","id":1,"method":"Addons.Install","params":{"addonid":null,"addonpath":"%s"}}' "$zip")
  jsonrpc "$body" >/dev/null || true
}

install_addon_id(){
  id="$1"
  body=$(printf '{"jsonrpc":"2.0","id":1,"method":"Addons.Install","params":{"addonid":"%s"}}' "$id")
  jsonrpc "$body" >/dev/null || true
}

fetch_to_cache(){
  name="$1"; src="$2"
  if [ -f "$src" ]; then echo "$src"; return 0; fi
  if printf '%s' "$src" | grep -q '\*'; then
    match=$(ls -1 "$CACHE_DIR"/$(basename "$src") 2>/dev/null | head -n1 || true)
    [ -n "$match" ] && { echo "$match"; return 0; }
  fi
  if printf '%s' "$src" | grep -vq '\*'; then
    out="$CACHE_DIR/${name}.zip"; mkdir -p "$CACHE_DIR"
    curl -fsSL -o "$out" "$src" && { echo "$out"; return 0; }
  fi
  return 1
}

sleep "$SETTLE_SECS"
wait_rpc 90 || warn "Kodi JSON-RPC not reachable; will try file installs anyway."

# 1) Repos
echo "$REPOS" | while IFS= read -r line; do
  [ -n "$line" ] || continue
  name=$(printf '%s' "$line" | awk -F'|' '{print $1}')
  url=$(printf  '%s' "$line" | awk -F'|' '{print $2}')
  [ -n "$name" ] && [ -n "$url" ] || continue
  say "Repo: $name"

  cand=""
  if printf '%s' "$url" | grep -q '^https\?://'; then
    base=$(basename "$url")
    [ "$(echo "$base" | grep -c '\*')" -gt 0 ] && cand=$(ls -1 "$CACHE_DIR"/"$base" 2>/dev/null | head -n1 || true)
    [ -z "$cand" ] && cand=$(fetch_to_cache "$name" "$url" || true)
  else
    cand=$(fetch_to_cache "$name" "$url" || true)
  fi
  [ -z "$cand" ] && cand=$(ls -1 "$CACHE_DIR"/*"$name"*repository*.zip 2>/dev/null | head -n1 || true)

  if [ -n "$cand" ] && [ -f "$cand" ]; then
    say "Installing repo zip: $(basename "$cand")"
    install_zip_via_files "$cand"
    sleep "$SETTLE_SECS"
  else
    warn "No zip found for repo: $name"
  fi
done

# 2) Core addons
echo "$ADDONS" | while IFS= read -r a; do
  [ -n "$a" ] || continue
  say "Install addon: $a"
  install_addon_id "$a"
  sleep "$SETTLE_SECS"

  if [ "$a" = "plugin.video.seren" ]; then
    patch=$(ls -1 "$CACHE_DIR"/Seren*.zip 2>/dev/null | head -n1 || true)
    [ -f "$patch" ] && { say "Applying Seren patch: $(basename "$patch")"; install_zip_via_files "$patch"; sleep "$SETTLE_SECS"; }
  fi
done

# 3) Extra zips
echo "$EXTRA_ZIPS" | while IFS= read -r z; do
  [ -n "$z" ] || continue
  match=$(ls -1 "$CACHE_DIR"/"$z" 2>/dev/null | head -n1 || true)
  [ -f "$match" ] && { say "Installing extra zip: $(basename "$match")"; install_zip_via_files "$match"; sleep "$SETTLE_SECS"; }
done

say "Addons phase complete."
SH

chmod 0755 "$BIN"

# One-shot service
cat >"$SVC"<<'UNIT'
[Unit]
Description=FrankenPi: Install Kodi repos + addons (first boot)
After=kodi.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '[ -f /var/lib/frankenpi/.addons-installed ] || { /usr/local/sbin/frankenpi-install-addons && touch /var/lib/frankenpi/.addons-installed; }'
UNIT

svc_enable frankenpi-addons.service || true

log "[42_addons] staged. Place repo/addon zips in $CACHE for local-first installs."
