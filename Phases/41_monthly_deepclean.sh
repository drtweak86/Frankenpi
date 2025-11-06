#!/bin/sh
# FrankenPi: monthly deep clean (safe pruning beyond weekly maintenance)
set -eu
. /usr/local/bin/frankenpi-compat.sh  # log, svc_*

BIN="/usr/local/sbin/frankenpi-deepclean"
SVC="/etc/systemd/system/frankenpi-deepclean.service"
TMR="/etc/systemd/system/frankenpi-deepclean.timer"

# Write worker
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu
ts(){ date '+%F %T'; }
log(){ echo "[deepclean] $*"; }

# Detect Kodi home
if id xbian >/dev/null 2>&1; then KH="/home/xbian/.kodi"; else KH="/root/.kodi"; fi
PKG="$KH/addons/packages"            # where Kodi stores downloaded zips
ADDONS="$KH/addons"

log "===== $(ts) ===== monthly deep clean start"

# 1) Prune old addon package zips (>90d)
if [ -d "$PKG" ]; then
  find "$PKG" -type f -name '*.zip' -mtime +90 -print -delete 2>/dev/null || true
  log "pruned old addon package zips (>90d) in $PKG"
fi

# 2) Prune temp leftovers (>30d) just in case
if [ -d "$KH/temp" ]; then
  find "$KH/temp" -type f -mtime +30 -print -delete 2>/dev/null || true
  log "pruned old temp files (>30d)"
fi

# 3) Optional: prune orphaned addon dirs with no addon.xml (rare; safe)
if [ -d "$ADDONS" ]; then
  find "$ADDONS" -mindepth 1 -maxdepth 1 -type d ! -name 'packages' \
    -exec sh -c '[ -f "$1/addon.xml" ] || { echo "[deepclean] orphan: $1"; rm -rf "$1"; }' sh {} \; 2>/dev/null || true
fi

# 4) System caches (only if present)
[ -d /var/cache/apt ]    && find /var/cache/apt    -type f -mtime +30 -delete 2>/dev/null || true
[ -d /var/cache ]        && find /var/cache        -type f -size +50M -delete 2>/dev/null || true

# 5) Journald extra trim (older than 30d)
if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time=30d >/dev/null 2>&1 || true
fi

log "deep clean done."
SH
chmod 0755 "$BIN"

# Service + monthly timer (runs on the 1st at 04:10)
cat >"$SVC"<<'UNIT'
[Unit]
Description=FrankenPi Monthly Deep Clean

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/frankenpi-deepclean
Nice=10
IOSchedulingClass=best-effort
UNIT

cat >"$TMR"<<'UNIT'
[Unit]
Description=Run FrankenPi deep clean monthly

[Timer]
OnCalendar=*-*-01 04:10:00
Persistent=true
AccuracySec=2m

[Install]
WantedBy=timers.target
UNIT

svc_enable frankenpi-deepclean.timer || true
svc_start  frankenpi-deepclean.timer || true

log "[41_monthly_deepclean] Installed + enabled monthly timer."
