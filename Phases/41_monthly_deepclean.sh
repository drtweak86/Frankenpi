#!/bin/sh
# FrankenPi: monthly deep clean (cron/busybox)
set -eu
. /usr/local/bin/frankenpi-compat.sh  # log, svc_*

BIN="/usr/local/sbin/frankenpi-deepclean"
CRON="/etc/cron.d/frankenpi-deepclean"

# Write worker
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu
ts(){ date '+%F %T'; }
log(){ echo "[deepclean] $*"; }

if id xbian >/dev/null 2>&1; then KH="/home/xbian/.kodi"; else KH="/root/.kodi"; fi
PKG="$KH/addons/packages"
ADDONS="$KH/addons"

log "===== $(ts) ===== monthly deep clean start"

# 1) Prune old addon package zips (>90d)
[ -d "$PKG" ] && find "$PKG" -type f -name '*.zip' -mtime +90 -print -delete 2>/dev/null || true

# 2) Prune temp leftovers (>30d)
[ -d "$KH/temp" ] && find "$KH/temp" -type f -mtime +30 -print -delete 2>/dev/null || true

# 3) Prune orphaned addon dirs
[ -d "$ADDONS" ] && find "$ADDONS" -mindepth 1 -maxdepth 1 -type d ! -name 'packages' \
  -exec sh -c '[ -f "$1/addon.xml" ] || { echo "[deepclean] orphan: $1"; rm -rf "$1"; }' sh {} \; 2>/dev/null || true

# 4) System caches
[ -d /var/cache/apt ] && find /var/cache/apt -type f -mtime +30 -delete 2>/dev/null || true
[ -d /var/cache ] && find /var/cache -type f -size +50M -delete 2>/dev/null || true

# 5) Journald trim
command -v journalctl >/dev/null 2>&1 && journalctl --vacuum-time=30d >/dev/null 2>&1 || true

log "deep clean done."
SH

chmod 0755 "$BIN"

# ---- cron monthly (1st day 04:10) ----
mkdir -p /etc/cron.d
echo '10 4 1 * * root /usr/local/sbin/frankenpi-deepclean >/dev/null 2>&1' > "$CRON"

log "[41_monthly_deepclean] Installed + cron active monthly at 1st 04:10."
