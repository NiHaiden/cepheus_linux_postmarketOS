#!/bin/sh
# Write a boot image to the boot partition FROM RUNNING LINUX (no fastboot), with checksum check.
# Normally not needed: kernel package upgrades do this automatically (flash_kernel_on_update).
#   scripts/flash-boot-from-linux.sh path/to/boot.img
. "$(dirname "$0")/common.sh"
D="$(dirname "$0")"; img="$1"; [ -f "$img" ] || { echo "usage: $0 boot.img"; exit 1; }
set -e
"$D/pcp" "$img" phone:/tmp/flash-boot.img
want=$(sha256 "$img")
got=$("$D/pms" 'p=$(findfs PARTLABEL=boot); dd if=/tmp/flash-boot.img of=$p bs=4M conv=fsync 2>/dev/null; head -c $(stat -c%s /tmp/flash-boot.img) $p | sha256sum | cut -c1-64')
[ "$want" = "$got" ] && echo "boot partition written and verified ($want)" || { echo "CHECKSUM MISMATCH: $got"; exit 1; }
