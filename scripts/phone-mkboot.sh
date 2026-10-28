#!/bin/sh
# RUNS ON THE PHONE. Builds /tmp/test-boot.img = installed /boot/vmlinuz + /tmp/test.dtb
# + installed initramfs, with the same header values as the installed /boot/boot.img.
# (boot.img kernel is "vmlinuz + appended dtb" because deviceinfo_append_dtb=true)
set -e
rm -rf /tmp/bi && mkdir /tmp/bi && cd /tmp/bi
unpackbootimg -i /boot/boot.img -o . >/dev/null
cat /boot/vmlinuz /tmp/test.dtb > kernel-test
cmdline="$(cat boot.img-cmdline)"
# optional: ROOT_UUID=<uuid> boots a different rootfs
[ -z "$ROOT_UUID" ] || cmdline="$(echo "$cmdline" | sed "s/pmos_root_uuid=[^ ]*/pmos_root_uuid=$ROOT_UUID/")"
mkbootimg-osm0sis --kernel kernel-test --ramdisk boot.img-ramdisk --cmdline "$cmdline" \
  --base "$(cat boot.img-base)" --kernel_offset "$(cat boot.img-kernel_offset)" \
  --ramdisk_offset "$(cat boot.img-ramdisk_offset)" --second_offset "$(cat boot.img-second_offset)" \
  --tags_offset "$(cat boot.img-tags_offset)" --pagesize "$(cat boot.img-pagesize)" \
  --header_version "$(cat boot.img-header_version)" -o /tmp/test-boot.img
ls -la /tmp/test-boot.img
