#!/bin/sh
# FrankenPi: weekly system + Kodi maintenance (cron/busybox version)
set -eu
. /usr/local/bin/frankenpi-compat.sh   # log, svc_*

BIN="/usr/local/sbin/frankenpi-maint"
CRON="/etc/cron.d/frankenpi-maint"

# helper to resolve Kodi home
kodi_home() {
  if id xbian >/dev/null 2>&1; then
    echo /home/xbian/.kodi
  else
    echo /root/.kodi
  fi
}

# ---- maintenance worker ----
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu

ts(){ date '+%F %T'; }
log(){ echo "[maint] $(ts) $*"; }

kodi_home() {
  if id xbian >/dev/null 2>&1; then echo /home/xbian/.kodi; else echo /root/.kodi; fi
}

KH="$(kodi_home)"
DBDIR="$KH/userdata/Database"
TMPDIR="$KH/temp"
THUMBS="$KH/userdata/Thumbnails"

log "===== starting weekly maintenance ====="

# 1) APT housekeeping (Debian only)
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  log "apt: update/upgrade/autoremove/clean"
  apt-get update -y >/dev/null 2>&1 || true
  apt-get -o Dpkg::Options::="--force-confdef" \
          -o Dpkg::Options::="--force-confold" \
          dist-upgrade -y >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get clean -y >/dev/null 2>&1 || true
fi

# 2) Kodi: compact databases
if [ -d "$DBDIR" ] && command -v sqlite3 >/dev/null 2>&1; then
  for db in "$DBDIR"/*.db; do
    [ -f "$db" ] || continue
    log "sqlite: VACUUM + REINDEX $(basename "$db")"
    sqlite3 "$db" 'PRAGMA foreign_keys=OFF; VACUUM; REINDEX;' >/dev/null 2>&1 || true
  done
fi

# 3) Kodi: library cleanup
if command -v kodi-send >/dev/null 2>&1; then
  log "kodi: CleanLibrary(video)"
  kodi-send -a 'CleanLibrary(video)' >/dev/null 2>&1 || true
  log "kodi: CleanLibrary(music)"
  kodi-send -a 'CleanLibrary(music)' >/dev/null 2>&1 || true
fi

# 4) Temp/cache cleanup
[ -d "$TMPDIR" ] && find "$TMPDIR" -mindepth 1 -type f -mtime +7  -delete 2>/dev/null || true
[ -d "$THUMBS" ] && find "$THUMBS" -mindepth 1 -type f -mtime +60 -delete 2>/dev/null || true
find "$KH" -maxdepth 1 -type f -name 'kodi_crashlog*' -mtime +30 -delete 2>/dev/null || true

# 5) Journald trim (if present)
if command -v journalctl >/dev/null 2>&1; then
  log "journald: vacuum to 200M or 14 days"
  journalctl --vacuum-size=200M >/dev/null 2>&1 || true
  journalctl --vacuum-time=14d  >/dev/null 2>&1 || true
fi

log "done."
SH

chmod 0755 "$BIN"

# ---- cron weekly (Sat 03:40) ----
mkdir -p /etc/cron.d
echo '40 3 * * 6 root /usr/local/sbin/frankenpi-maint >/dev/null 2>&1' > "$CRON"

log "[40_maintenance] Installed frankenpi-maint; cron active weekly at Sat 03:40."
