#!/bin/sh
# Set up a freshly installed postmarketOS on the Mi 9 (README: Quick start 3): our kernel/device packages,
# firmware glue, Wi-Fi/BT/sensors/audio config. Console only (no graphical session at boot).
#   scripts/cli-setup.sh                      # console
#   WIFI_SSID=x WIFI_PSK=y scripts/cli-setup.sh   # also store a Wi-Fi profile
# kde-setup.sh / phosh-setup.sh call this with their UI name.
. "$(dirname "$0")/common.sh"
D="$(dirname "$0")"; UI="${1:-cli}"
set -e

ls "$HANDOFF_DIR"/apks/*.apk >/dev/null 2>&1 || { echo "apks/ is empty: download the release assets into apks/ or build them (README: Development)" >&2; exit 1; }
"$D/pm" true || { echo "phone not reachable at $PHONE_IP (USB plugged in, booted?)" >&2; exit 1; }

# Fresh installs have no Wi-Fi yet (this setup installs its firmware glue): share the host's internet over USB
# with a temporary tinyproxy that only the phone's USB subnet may use.
PROXY=
if ! "$D/pm" 'wget -q -T 5 -O /dev/null http://dl-cdn.alpinelinux.org/alpine/'; then
	command -v tinyproxy >/dev/null || { echo "phone has no internet: install tinyproxy on this host" >&2; exit 1; }
	t="${TMPDIR:-/tmp}/cepheus-tinyproxy"
	printf 'Port 8888\nListen 0.0.0.0\nTimeout 600\nPidFile "%s.pid"\nAllow 172.16.42.0/24\nAllow 127.0.0.1\nConnectPort 443\nConnectPort 80\n' "$t" > "$t.conf"
	tinyproxy -c "$t.conf" 2>/dev/null && sleep 1 && trap 'kill $(cat "$t.pid") 2>/dev/null' EXIT
	PROXY=http://172.16.42.2:8888
fi
# The RTC is read-only; a wrong clock breaks TLS for apk. Set it from the host if it's off.
"$D/pms" "n=$(date +%s); t=\$(date +%s); [ \$((n-t)) -gt 60 -o \$((t-n)) -gt 60 ] && date -s @\$n >/dev/null; true"

echo "==> copying payload"
cd "$HANDOFF_DIR"
# Newest build of each of our packages only (the bundle also keeps older ones for rollback).
APKS=$(ls apks/*.apk | sed -E 's/-[0-9][^/]*-r[0-9]+\.apk$//' | sort -u | while read -r n; do ls "$n"-[0-9]*.apk | sort -V | tail -1; done)
tar -czf - scripts/phone-setup.sh phone-config $APKS \
	| "$D/pm" 'rm -rf /tmp/cepheus-setup && mkdir /tmp/cepheus-setup && tar -xzf - -C /tmp/cepheus-setup'

"$D/pms" "env http_proxy=$PROXY https_proxy=$PROXY WIFI_SSID=\"$WIFI_SSID\" WIFI_PSK=\"$WIFI_PSK\" SUDO_USER=$PHONE_USER sh /tmp/cepheus-setup/scripts/phone-setup.sh $UI"
echo "Reboot when ready: scripts/pms reboot"
