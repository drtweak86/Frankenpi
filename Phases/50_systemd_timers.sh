#!/bin/sh
# 50_busybox_timers.sh — Install FrankenPi backup + maintenance cron jobs
set -eu

ts(){ date '+%F %T'; }

echo "[50_busybox_timers][$(ts)] Installing backup & maintenance scripts + cron jobs…"

# --- install scripts ---
SCRIPTS="/opt/frankenpi/phases/40_backup.sh /opt/frankenpi/phases/41_maintenance.sh /opt/frankenpi/phases/42_deepclean.sh"
DEST_DIR="/usr/local/sbin"

for s in $SCRIPTS; do
  if [ -f "$s" ]; then
    install -D -m 0755 "$s" "$DEST_DIR/$(basename "$s" .sh)"
    echo "[50_busybox_timers][$(ts)] Installed $(basename "$s")"
  else
    echo "[50_busybox_timers][WARN] Missing script: $s" >&2
  fi
done

# --- create cron entries ---
CRON_DIR="/etc/cron.d"
CRON_FILE="$CRON_DIR/frankenpi"

mkdir -p "$CRON_DIR"

cat > "$CRON_FILE" <<'EOF'
# FrankenPi cron jobs

# weekly cloud backup: Sunday 04:30
30 4 * * 0 root /usr/local/sbin/frankenpi-backup >/dev/null 2>&1

# weekly maintenance: Saturday 03:40
40 3 * * 6 root /usr/local/sbin/frankenpi-maint >/dev/null 2>&1

# monthly deep clean: 1st of month 04:10
10 4 1 * * root /usr/local/sbin/frankenpi-deepclean >/dev/null 2>&1
EOF

chmod 0644 "$CRON_FILE"

echo "[50_busybox_timers][$(ts)] Installed scripts and cron jobs."
echo "  Check cron entries with: cat $CRON_FILE"
echo "  Cron will now run backups, maintenance, and deep clean automatically."
