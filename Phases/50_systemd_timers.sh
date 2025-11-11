#!/bin/sh
# 50_busybox_timers.sh — Install FrankenPi backup + maintenance cron jobs
set -eu

echo "[50_busybox_timers] Installing backup & maintenance scripts + cron jobs…"

# --- install scripts ---
install -D -m 0755 /opt/frankenpi/phases/40_backup.sh /usr/local/sbin/frankenpi-backup
install -D -m 0755 /opt/frankenpi/phases/41_maintenance.sh /usr/local/sbin/frankenpi-maint
install -D -m 0755 /opt/frankenpi/phases/42_deepclean.sh /usr/local/sbin/frankenpi-deepclean

# --- create cron entries ---
CRON_FILE="/etc/cron.d/frankenpi"

# backup: weekly Sunday 04:30
# maintenance: weekly Saturday 03:40
# deep clean: monthly 1st day 04:10
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

echo "[50_busybox_timers] Installed scripts and cron jobs."
echo "  Check cron entries with: cat $CRON_FILE"
echo "  Cron should now run backups, maintenance, and deep clean automatically."
