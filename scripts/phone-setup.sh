#!/bin/sh
# Runs ON THE PHONE as root. Called by cli-setup.sh / kde-setup.sh / phosh-setup.sh on the Mac,
# which unpack the bundle payload next to this script first.
#   sh phone-setup.sh cli|kde|phosh
# Idempotent: safe to re-run, e.g. to switch the default UI.
set -e
UI="${1:-cli}"
cd "$(dirname "$0")/.."  # payload root: apks/, phone-config/, scripts/
C=phone-config

case "$UI" in cli|kde|phosh) ;; *) echo "usage: $0 cli|kde|phosh" >&2; exit 1;; esac

echo "==> packages (base)"
# Our builds: kernel (patches 0004-0011, -aurora), device package (+ bootmac), firmware glue, sensor-proxy fork.
apk add --allow-untrusted apks/*.apk \
	hexagonrpcd hexagonrpcd-systemd \
	msm-firmware-loader-hexagonrpcd msm-firmware-loader-hexagonrpcd-systemd \
	bluez networkmanager networkmanager-cli networkmanager-wifi \
	alsa-ucm-conf alsa-utils kbd terminus-font \
	htop vim usbutils i2c-tools evtest rsync zstd

echo "==> hand-made config files"
# Wi-Fi: firmware feature flags + board data from the stock 'modem' partition (never linux-firmware-ath10k, see README: How it works)
install -Dm644 $C/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin
ln -sfn "$(cat $C/lib/firmware/ath10k/WCN3990/hw1.0/board.bin.SYMLINK_TARGET)" /lib/firmware/ath10k/WCN3990/hw1.0/board.bin
# Real Wi-Fi MAC, read from this phone's persist partition at every boot (replaces the old hardcoded .link)
install -Dm755 $C/usr/local/sbin/cepheus-wlan-mac -t /usr/local/sbin/
install -Dm644 $C/etc/udev/rules.d/80-cepheus-wlan-mac.rules -t /etc/udev/rules.d/
rm -f /etc/systemd/network/10-cepheus-wlan-mac.link
install -Dm644 $C/etc/NetworkManager/conf.d/50-cepheus-wifi-mac.conf -t /etc/NetworkManager/conf.d/
# Sensors: accelerometer mount matrix (auto-rotate)
install -Dm644 $C/etc/udev/rules.d/81-libssc-xiaomi-cepheus.rules -t /etc/udev/rules.d/
# Audio: speaker UCM
install -Dm644 "$C/usr/share/alsa/ucm2/conf.d/sm8150/Xiaomi Mi 9.conf" -t /usr/share/alsa/ucm2/conf.d/sm8150/
install -Dm644 $C/usr/share/alsa/ucm2/Xiaomi/cepheus/HiFi.conf -t /usr/share/alsa/ucm2/Xiaomi/cepheus/
# Console: big font
install -Dm644 $C/etc/vconsole.conf -t /etc/

systemctl enable hexagonrpcd-sdsp.service bluetooth.service NetworkManager.service

if [ -n "$WIFI_SSID" ] && ! grep -qsx "ssid=$WIFI_SSID" /etc/NetworkManager/system-connections/*; then
	# Keyfile instead of nmcli: works without NetworkManager running (starting it could drop the USB ssh link).
	echo "==> Wi-Fi profile '$WIFI_SSID' (connects after reboot)"
	f="/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection"
	install -d -m700 /etc/NetworkManager/system-connections
	printf '[connection]\nid=%s\ntype=wifi\nautoconnect=true\n\n[wifi]\nssid=%s\n\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n' \
		"$WIFI_SSID" "$WIFI_SSID" "$WIFI_PSK" > "$f"
	chmod 600 "$f"
fi

echo "==> UI: $UI"
case "$UI" in
cli)
	systemctl disable greetd.service plasma-mobile.service 2>/dev/null || true
	;;
kde)
	# postmarketos-ui-plasma-mobile + its _pmb_recommends
	apk add postmarketos-ui-plasma-mobile \
		dolphin kclock krecorder kweather plasma-camera plasma-dialer plasma-mobile-sounds \
		plasma-phonebook qmlkonsole spacebar ttyescape vvmplayer discover plasma-systemmonitor
	echo "${SUDO_USER:-user}" > /etc/default_user
	systemctl disable greetd.service 2>/dev/null || true
	systemctl enable plasma-mobile.service
	;;
phosh)
	# postmarketos-ui-phosh + _pmb_recommends of phosh, base-ui-gnome, base-ui-gnome-mobile
	apk add postmarketos-ui-phosh postmarketos-ui-phosh-systemd phosh-mobile-settings phosh-tour \
		calls chatty lpa-gtk mobile-config-firefox firefox-esr \
		decibels g4music gnome-calculator gnome-calendar gnome-clocks gnome-console gnome-contacts \
		gnome-maps gnome-text-editor gnome-weather loupe nautilus papers showtime snapshot \
		gst-libav gst-plugins-bad gst-plugins-good gvfs-full tuned-ppd flatpak
	systemctl disable plasma-mobile.service 2>/dev/null || true
	systemctl enable greetd.service
	;;
esac

echo "==> done. Reboot to apply (kernel/firmware/UI changes): systemctl reboot"
