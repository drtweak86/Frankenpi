#!/bin/sh
# FrankenPi: Wi-Fi autoswitch (BSSID-aware) - busybox/cron version
set -eu
. /usr/local/bin/frankenpi-compat.sh   # log, svc_*

BIN="/usr/local/sbin/wifi-autoswitch"
CFG="/etc/default/wifi-autoswitch"
CRON="/etc/cron.d/frankenpi-wifi-autoswitch"

# ---- seed config (editable) ----
if [ ! -f "$CFG" ]; then
  mkdir -p /etc/default
  cat >"$CFG"<<'CFG'
# Preferred networks (SSID|BSSID format, space-separated)
PREFERRED_BSSIDS="Batcave|20:B8:2B:18:58:99 Batcave|20:B8:2B:18:58:98"

# Wi-Fi interface
WIFI_IFACE="wlan0"

# Thresholds
MIN_SIGNAL_PCT=50    # NM % signal
MIN_RSSI="-75"       # fallback RSSI in dBm

# Kodi notification on switch (1=yes, 0=no)
KODI_NOTIFY=1
CFG
fi

# ---- install worker (POSIX sh) ----
cat >"$BIN"<<'SH'
#!/bin/sh
set -eu
CONF="/etc/default/wifi-autoswitch"
[ -r "$CONF" ] && . "$CONF"

notify() {
  if [ "$KODI_NOTIFY" = "1" ] && command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(WiFi,$1,3000)" >/dev/null 2>&1 || true
  fi
  echo "[wifi-autoswitch] $1"
}

has(){ command -v "$1" >/dev/null 2>&1; }

nm_best() {
  nmcli -f BSSID,SSID,SIGNAL dev wifi list ifname "$WIFI_IFACE" 2>/dev/null \
    | awk -v pref="$PREFERRED_BSSIDS" '
      BEGIN{
        n=split(pref,P," ");
        for(i=1;i<=n;i++) { split(P[i],pair,"|"); map[pair[1]"|"pair[2]]=i }
      }
      NR>1 && $1!=""{
        bssid=$1; ssid=$2; sig=$3;
        rank=(ssid "|" bssid in map)?map[ssid "|" bssid]:9999;
        printf("%s|%s|%s|%d\n", ssid, bssid, sig, rank)
      }
    ' | sort -t'|' -k4,4n -k3,3nr | head -n1
}

nm_current_bssid() {
  nmcli -t -f ACTIVE,BSSID connection show --active 2>/dev/null \
    | awk -F: '$1=="yes"{print $2; exit}'
}

nm_switch() {
  ssid="$1"; bssid="$2"
  nmcli device wifi connect "$ssid" bssid "$bssid" ifname "$WIFI_IFACE" >/dev/null 2>&1
}

scan_rssi() {
  if has iw; then
    iw dev "$WIFI_IFACE" scan 2>/dev/null \
      | awk '/^BSS /{b=$2} /SSID:/ {s=$0; sub(/^.*SSID: /,"",s)} /signal:/ {sig=$0; sub(/^.*signal: /,"",sig); printf("%s|%s|%s\n",s,b,sig)}'
  elif has wpa_cli; then
    wpa_cli -i "$WIFI_IFACE" scan >/dev/null 2>&1 || true
    sleep 1
    wpa_cli -i "$WIFI_IFACE" scan_results 2>/dev/null \
      | awk 'NR>2{printf("%s|%s|%s\n",$5,$1,$3)}'
  fi
}

wpa_current_bssid() {
  iw dev "$WIFI_IFACE" link | awk '/Connected/ {print $2; exit}'
}

wpa_switch() {
  ssid="$1"; bssid="$2"
  nid="$(wpa_cli -i "$WIFI_IFACE" list_networks 2>/dev/null | awk -F'\t' -v s="$ssid" '$2==s{print $1; exit}')"
  [ -n "$nid" ] && wpa_cli -i "$WIFI_IFACE" select_network "$nid" >/dev/null 2>&1
}

main() {
  [ -n "$PREFERRED_BSSIDS" ] || exit 0

  if has nmcli; then
    best="$(nm_best || true)"
    [ -n "$best" ] || exit 0
    b_ssid="$(echo "$best" | cut -d'|' -f1)"
    b_bssid="$(echo "$best" | cut -d'|' -f2)"
    b_sig="$(echo "$best" | cut -d'|' -f3)"
    cur="$(nm_current_bssid || true)"
    [ "${b_sig:-0}" -ge "$MIN_SIGNAL_PCT" ] || exit 0
    [ "$cur" = "$b_bssid" ] && exit 0
    nm_switch "$b_ssid" "$b_bssid" && notify "Switching → $b_ssid ($b_bssid, ${b_sig}%)"
    exit 0
  fi

  if has iw || has wpa_cli; then
    best_ssid=""; best_bssid=""; best_rssi=-999
    scan_rssi | while IFS='|' read -r ssid bssid rssi; do
      for pair in $PREFERRED_BSSIDS; do
        pref_ssid="$(echo $pair | cut -d'|' -f1)"
        pref_bssid="$(echo $pair | cut -d'|' -f2)"
        if [ "$ssid" = "$pref_ssid" ] && [ "$bssid" = "$pref_bssid" ] && [ "$rssi" -gt "$best_rssi" ]; then
          best_ssid="$ssid"; best_bssid="$bssid"; best_rssi="$rssi"
        fi
      done
    done
    [ -n "$best_bssid" ] || exit 0
    [ "$best_rssi" -ge "$MIN_RSSI" ] || exit 0
    cur="$(wpa_current_bssid || true)"
    [ "$cur" = "$best_bssid" ] && exit 0
    wpa_switch "$best_ssid" "$best_bssid" && notify "Switching → $best_ssid ($best_bssid, ${best_rssi} dBm)"
  fi
}
main "$@"
SH

chmod 0755 "$BIN"

# ---- cron fallback for busybox ----
mkdir -p /etc/cron.d
echo '*/2 * * * * root /usr/local/sbin/wifi-autoswitch >/dev/null 2>&1' > "$CRON"

log "[33_wifi_autoswitch] installed; cron active every 2 minutes."
