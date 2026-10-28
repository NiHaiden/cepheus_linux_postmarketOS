#!/bin/sh
# Test a DTB WITHOUT flashing: build a boot.img on the phone, then `fastboot boot` it (RAM only).
# If it fails, a normal reboot returns to the flashed, known-good boot partition.
#   scripts/test-dtb.sh [path/to/test.dtb]
. "$(dirname "$0")/common.sh"
D="$(dirname "$0")"; dtb="${1:-$HANDOFF_DIR/images/test.dtb}"
set -e
"$D/pcp" "$dtb" phone:/tmp/test.dtb
"$D/pcp" "$D/phone-mkboot.sh" phone:/tmp/
"$D/pm" 'sh /tmp/phone-mkboot.sh'
"$D/pcp" phone:/tmp/test-boot.img "$HANDOFF_DIR/images/test-boot.img"
"$D/pms" 'systemctl reboot --reboot-argument=bootloader' || true
for i in $(seq 40); do fastboot devices | grep -q . && break; sleep 2; done
sleep 2; fastboot boot "$HANDOFF_DIR/images/test-boot.img"
echo "booting test image from RAM; wait ~60s, then: scripts/pm uptime"
