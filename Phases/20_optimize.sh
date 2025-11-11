#!/bin/sh
# FrankenPi: system/network optimizations (safe on Debian/Xbian; no-op on pure Buildroot)
set -eu

. /usr/local/bin/frankenpi-compat.sh   # log, pkg_install, svc_*

log "[20_optimize] Installing unbound (DNS cache) + rng-tools if available…"

if type pkg_install >/dev/null 2>&1; then
  pkg_install unbound rng-tools || log "[20_optimize] package install failed/skipped"
else
  log "[20_optimize] pkg_install not available; skipping package install"
fi

# Attempt BBR; fallback to cubic
TCP_CC="bbr"
if ! modprobe tcp_bbr 2>/dev/null; then
  TCP_CC="cubic"
fi
log "[20_optimize] tcp_congestion_control=$TCP_CC"

# Apply sysctl settings
SYSCTL_DROP="/etc/sysctl.d/99-frankenpi.conf"
SYSCTL_CONF="
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_rmem = 4096 87380 2097152
net.ipv4.tcp_wmem = 4096 65536 2097152
net.ipv4.tcp_congestion_control = ${TCP_CC}
"

if [ -d /etc/sysctl.d ]; then
  echo "$SYSCTL_CONF" >"$SYSCTL_DROP"
  sysctl --system >/dev/null 2>&1 || log "[20_optimize] sysctl apply failed/skipped"
else
  # fallback to /etc/sysctl.conf
  sed -i '/^net\.ip/d;/^net\.core/d' /etc/sysctl.conf 2>/dev/null || true
  echo "$SYSCTL_CONF" >>/etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || log "[20_optimize] sysctl apply failed/skipped"
fi

# Enable/start optional services
for svc in unbound rng-tools rngd; do
  systemctl list-unit-files | grep -q "^$svc\.service" || continue
  svc_enable "$svc" || log "[20_optimize] failed to enable $svc"
  svc_start  "$svc" || log "[20_optimize] failed to start $svc"
  log "[20_optimize] enabled & started $svc"
done

log "[20_optimize] Done."
