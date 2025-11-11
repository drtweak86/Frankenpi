#!/bin/sh
# FrankenPi: weekly snapshot -> cloud via rclone (busybox/cron version)
set -eu

. /usr/local/bin/frankenpi-compat.sh   # log, svc_*

BIN="/usr/local/sbin/frankenpi-backup"
CFG="/etc/default/frankenpi-backup"
LOGDIR="/var/log/frankenpi"
CRON="/etc/cron.d/frankenpi-backup"

mkdir -p /etc/default "$LOGDIR"

# Seed editable config on first install
if [ ! -f "$CFG" ]; then
  cat >"$CFG" <<'CFG'
# rclone remote (create with: rclone config)
REMOTE_NAME="cloud"
REMOTE_PATH="frankenpi-backups"

# Archive name prefix
ZIP_LABEL="frankenpi_backup"

# What to include (space-separated paths). Edit as you wish.
INCLUDE_LIST="/root/.kodi /etc/wireguard /usr/local/bin/frankenpi-phases"
CFG
fi

# Install worker
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu
CFG="/etc/default/frankenpi-backup"
[ -r "$CFG" ] && . "$CFG"

LOGDIR="/var/log/frankenpi"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/backup.log"

ts() { date '+%F %T'; }

BACKUP_ROOT="${BACKUP_ROOT:-/var/cache/frankenpi/backups}"
mkdir -p "$BACKUP_ROOT"
DATE="$(date +%F_%H-%M-%S)"
ZIP_PATH="${BACKUP_ROOT}/${ZIP_LABEL}_${DATE}.zip"
REMOTE="${REMOTE_NAME}:${REMOTE_PATH}"

{
  echo "[backup] ===== $(ts) ====="

  # Require rclone
  if ! command -v rclone >/dev/null 2>&1; then
    echo "[backup] rclone unavailable — abort"
    exit 1
  fi

  rclone mkdir "$REMOTE" || true

  TO_ZIP=""
  for p in $INCLUDE_LIST; do
    [ -e "$p" ] && TO_ZIP="$TO_ZIP \"$p\"" || echo "[backup] skip missing: $p"
  done
  [ -n "$TO_ZIP" ] || { echo "[backup] nothing to back up"; exit 1; }

  [ -x "$(command -v zip)" ] || { echo "[backup] zip not found"; exit 1; }

  echo "[backup] zipping → $ZIP_PATH"
  eval zip -qr "\"$ZIP_PATH\"" $TO_ZIP

  LOCAL_SIZE=$(stat -c '%s' "$ZIP_PATH" 2>/dev/null || echo 0)
  [ "$LOCAL_SIZE" -gt 1024 ] || { echo "[backup] zip too small"; rm -f "$ZIP_PATH"; exit 1; }

  echo "[backup] uploading to $REMOTE"
  rclone copyto "$ZIP_PATH" "${REMOTE}/$(basename "$ZIP_PATH")"

  REMOTE_SIZE=$(rclone lsjson --files-only "${REMOTE}/$(basename "$ZIP_PATH")" \
                | sed -n 's/.*"Size":\s*\([0-9]\+\).*/\1/p')
  [ -n "$REMOTE_SIZE" ] && [ "$REMOTE_SIZE" -eq "$LOCAL_SIZE" ] || { echo "[backup] verify FAILED"; exit 1; }

  rm -f "$ZIP_PATH"
  echo "[backup] DONE"
} >>"$LOGFILE" 2>&1
SH

chmod 0755 "$BIN"

# ---- cron weekly (Sun 04:30) ----
mkdir -p /etc/cron.d
echo '30 4 * * 0 root /usr/local/sbin/frankenpi-backup >/dev/null 2>&1' > "$CRON"

log "[40_backup] Installed backup tool; cron active weekly at Sun 04:30."
