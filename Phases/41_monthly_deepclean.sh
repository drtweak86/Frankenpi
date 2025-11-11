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
log(){ echo "[deepclean] $(ts) $*"; }

KH="$(id -u xbian >/dev/null 2>&1 && echo /home/xbian/.kodi || echo /root/.kodi)"
PKG="$KH/addons/packages"
ADDONS="$KH/addons"
TMPDIR="$KH/temp"

log "===== monthly deep clean start ====="

# 1) Prune old addon package zips (>90d)
if [ -d "$PKG" ]; then
  log "pruning old addon zips (>90d) in $PKG"
  find "$PKG" -mindepth 1 -type f -name '*.zip' -mtime +90 -print -delete 2>/dev/null || true
fi

# 2) Prune temp leftovers (>30d)
if [ -d "$TMPDIR" ]; then
  log "pruning temp files (>30d) in $TMPDIR"
  find "$TMPDIR" -mindepth 1 -type f -mtime +30 -print -delete 2>/dev/null || true
fi

# 3) Prune orphaned addon dirs (no addon.xml)
if [ -d "$ADDONS" ]; then
  log "pruning orphaned addon dirs in $ADDONS"
  find "$ADDONS" -mindepth 1 -maxdepth 1 -type d ! -name 'packages' \
    -exec sh -c '[ -f "$1/addon.xml" ] || { echo "[deepclean] orphan: $1"; rm -rf "$1"; }' sh {} \; 2>/dev/null || true
fi

# 4) System caches
if [ -d /var/cache/apt ]; then
  log "cleaning /var/cache/apt (>30d)"
  find /var/cache/apt -type f -mtime +30 -print -delete 2>/dev/null || true
fi

if [ -d /var/cache ]; then
  log "cleaning large files in /var/cache (>50M)"
  find /var/cache -type f -size +50M -print -delete 2>/dev/null || true
fi

# 5) Journald trim
if command -v journalctl >/dev/null 2>&1; then
  log "trimming journald logs (>30d)"
  journalctl --vacuum-time=30d >/dev/null 2>&1 || true
fi

log "deep clean done."
SH

chmod 0755 "$BIN"

# ---- cron monthly (1st day 04:10) ----
mkdir -p /etc/cron.d
echo '10 4 1 * * root /usr/local/sbin/frankenpi-deepclean >/dev/null 2>&1' > "$CRON"

log "[41_monthly_deepclean] Installed + cron active monthly at 1st 04:10."
