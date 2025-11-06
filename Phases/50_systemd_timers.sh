#!/usr/bin/env bash
# 50_systemd_timers.sh — Install FrankenPi backup + maintenance timers
set -euo pipefail

echo "[50_systemd_timers] Installing systemd backup & maintenance units…"

# --- install script binaries ---
install -D -m 0755 /opt/frankenpi/phases/40_backup.sh /usr/local/bin/frankenpi-backup
install -D -m 0755 /opt/frankenpi/phases/41_maintenance.sh /usr/local/bin/frankenpi-maintenance

# --- systemd service + timer: backup ---
tee /etc/systemd/system/frankenpi-backup.service >/dev/null <<'EOF'
[Unit]
Description=FrankenPi weekly cloud backup
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frankenpi-backup
Nice=10

[Install]
WantedBy=multi-user.target
EOF

tee /etc/systemd/system/frankenpi-backup.timer >/dev/null <<'EOF'
[Unit]
Description=Run FrankenPi backup weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- systemd service + timer: maintenance ---
tee /etc/systemd/system/frankenpi-maintenance.service >/dev/null <<'EOF'
[Unit]
Description=FrankenPi weekly maintenance tasks
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frankenpi-maintenance
Nice=10

[Install]
WantedBy=multi-user.target
EOF

tee /etc/systemd/system/frankenpi-maintenance.timer >/dev/null <<'EOF'
[Unit]
Description=Run FrankenPi maintenance weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- enable & start ---
systemctl daemon-reload
systemctl enable --now frankenpi-backup.timer
systemctl enable --now frankenpi-maintenance.timer

echo "[50_systemd_timers] Done — timers active."
echo "  Check with: systemctl list-timers --all | grep frankenpi"
