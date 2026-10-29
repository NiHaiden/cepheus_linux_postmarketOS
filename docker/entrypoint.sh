#!/bin/sh
# Container start (as root): prepare what pmbootstrap needs from the kernel, then drop to 'builder'.
set -e

# aarch64 chroots on an x86_64 host run through qemu-user, which pmbootstrap registers with binfmt_misc.
# binfmt_misc is shared with the host kernel, so registrations stay after the container exits.
if [ "$(uname -m)" != aarch64 ] && [ ! -e /proc/sys/fs/binfmt_misc/register ]; then
	mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null \
		|| echo "warning: binfmt_misc not available (container not --privileged?): aarch64 builds will fail" >&2
fi

# /dev here is a snapshot taken at container start: make sure 'pmbootstrap install' finds loop devices.
[ -e /dev/loop-control ] || mknod -m 660 /dev/loop-control c 10 237 2>/dev/null || true
for i in 0 1 2 3 4 5 6 7; do
	[ -e /dev/loop$i ] || mknod -m 660 /dev/loop$i b 7 $i 2>/dev/null || true
done

# A fresh named volume for the home directory may come up root-owned
chown builder: /home/builder 2>/dev/null || true

[ -d /home/builder/.local/var/pmbootstrap ] || [ "$1" != bash ] \
	|| echo "First time? Run ./setup-host.sh in here (pmbootstrap, pmaports with our commits, kernel tree; 10-20 min)."

export HOME=/home/builder USER=builder LOGNAME=builder
exec su-exec builder "$@"
