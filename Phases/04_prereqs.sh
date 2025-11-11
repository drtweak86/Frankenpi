#!/bin/sh
# FrankenPi prereqs: base tools + cron
# Works on Buildroot (no apt) and Debian/Xbian (apt present)

set -eu
. /usr/local/bin/frankenpi-compat.sh   # provides log/pkg_install/svc_* helpers

log "[04_prereqs] Installing base packages if available…"

# Only try pkg_install if helper exists
if type pkg_install >/dev/null 2>&1; then
  pkg_install curl wget git jq zip unzip ca-certificates rng-tools rsync dnsutils \
              net-tools python3 python3-pip ffmpeg nano vim tmux build-essential \
              file lsof strace ncdu htop iotop nload cron || \
              log "[04_prereqs] Some packages failed to install, continuing…"
else
  log "[04_prereqs] pkg_install not found; skipping package installation"
fi

# Ensure cron service is enabled/started (support several service names)
log "[04_prereqs] Ensuring cron service is enabled…"
for svc in cronie.service cron.service busybox-crond.service crond.service; do
  if systemctl list-unit-files | grep -q "^$svc"; then
    log "[04_prereqs] Found service: $svc"
    svc_enable "$svc" || log "[04_prereqs] Failed to enable $svc"
    svc_start  "$svc" || log "[04_prereqs] Failed to start $svc"
    log "[04_prereqs] Enabled & started $svc"
    break
  fi
done

# Optional: rclone install (best-effort)
if ! command -v rclone >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    log "[04_prereqs] Installing rclone (best-effort)…"
    if sh -c 'curl -fsSL https://rclone.org/install.sh | sh'; then
      log "[04_prereqs] rclone installed successfully"
    else
      log "[04_prereqs] rclone installation failed/skipped"
    fi
  else
    log "[04_prereqs] curl not available; skipping rclone install"
  fi
else
  log "[04_prereqs] rclone already installed"
fi

log "[04_prereqs] Done."
