#!/bin/sh
# FrankenPi: weekly system + Kodi maintenance
set -eu
. /usr/local/bin/frankenpi-compat.sh   # log, svc_*

BIN="/usr/local/sbin/frankenpi-maint"
SVC="/etc/systemd/system/frankenpi-maint.service"
TMR="/etc/systemd/system/frankenpi-maint.timer"

# helper to resolve Kodi home
kodi_home() {
  if id xbian >/dev/null 2>&1; then echo /home/xbian/.kodi; else echo /root/.kodi; fi
}

# ---- maintenance worker ----
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu

ts(){ date '+%F %T'; }
log(){ echo "[maint] $*"; }

# figure out Kodi home
if id xbian >/dev/null 2>&1; then KH="/home/xbian/.kodi"; else KH="/root/.kodi"; fi
DBDIR="$KH/userdata/Database"
TMPDIR="$KH/temp"
THUMBS="$KH/userdata/Thumbnails"

log "===== $(ts) ===== starting weekly maintenance"

# 1) APT housekeeping (Debian only; no-op elsewhere)
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

# 2) Kodi: compact databases (VACUUM + REINDEX)
if [ -d "$DBDIR" ]; then
  if command -v sqlite3 >/dev/null 2>&1; then
    for db in "$DBDIR"/*.db; do
      [ -f "$db" ] || continue
      log "sqlite: VACUUM + REINDEX $(basename "$db")"
      sqlite3 "$db" 'PRAGMA foreign_keys=OFF; VACUUM; REINDEX;' >/dev/null 2>&1 || true
    done
  else
    log "sqlite3 not found; skipping DB vacuum"
  fi
fi

# 3) Kodi: ask to clean libraries (best-effort)
if command -v kodi-send >/dev/null 2>&1; then
  log "kodi: CleanLibrary(video)"
  kodi-send -a 'CleanLibrary(video)'  >/dev/null 2>&1 || true
  log "kodi: CleanLibrary(music)"
  kodi-send -a 'CleanLibrary(music)'  >/dev/null 2>&1 || true
fi

# 4) Temp / cache tidy (safe)
#    - purge temp files older than 7 days
#    - purge very old thumbnails (older than 60 days), keep DB intact (we vacuumed it)
[ -d "$TMPDIR" ]    && find "$TMPDIR" -type f -mtime +7  -delete 2>/dev/null || true
[ -d "$THUMBS" ]   && find "$THUMBS" -type f -mtime +60 -delete 2>/dev/null || true
#    - remove Kodi crashlogs older than 30 days
find "$KH" -maxdepth 1 -type f -name 'kodi_crashlog*' -mtime +30 -delete 2>/dev/null || true

# 5) Journald trim (if present)
if command -v journalctl >/dev/null 2>&1; then
  log "journald: vacuum to 200M or 14 days (whichever smaller)"
  journalctl --vacuum-size=200M >/dev/null 2>&1 || true
  journalctl --vacuum-time=14d  >/dev/null 2>&1 || true
fi

log "done."
SH
chmod 0755 "$BIN"

# ---- oneshot service + weekly timer (Sat 03:40) ----
cat >"$SVC"<<'UNIT'
[Unit]
Description=FrankenPi Weekly Maintenance
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/frankenpi-maint
Nice=10
IOSchedulingClass=best-effort
UNIT

cat >"$TMR"<<'UNIT'
[Unit]
Description=Weekly FrankenPi Maintenance

[Timer]
OnCalendar=Sat *-*-* 03:40:00
Persistent=true
AccuracySec=1m

[Install]
WantedBy=timers.target
UNIT

svc_enable frankenpi-maint.timer || true
svc_start  frankenpi-maint.timer || true

log "[40_maintenance] Installed frankenpi-maint + weekly timer."
