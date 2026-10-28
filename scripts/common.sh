# Shared settings for the cepheus helper scripts. Source this, don't run it.
# Override any of these in the environment before calling a script.
: "${PHONE_IP:=172.16.42.1}"        # phone side of the USB network (pmOS default)
: "${PHONE_USER:=user}"
: "${PHONE_PASS:=cepheus}"          # login + sudo password set at install time
: "${VM:=pmos}"                     # macOS only: OrbStack machine that runs pmbootstrap

# Run a shell command where pmbootstrap and the kernel tree live: the OrbStack VM on macOS, the host on Linux.
vmsh() { if [ "$(uname -s)" = Darwin ]; then orb -m "$VM" sh -c "$1"; else sh -c "$1"; fi; }
sha256() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-64; }

HANDOFF_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Password auth without sshpass: OpenSSH asks this script for the password.
# Key auth (if your key is in the phone's authorized_keys) is tried first automatically.
_ASKPASS="${TMPDIR:-/tmp}/cepheus-askpass.sh"
printf '#!/bin/sh\necho "%s"\n' "$PHONE_PASS" > "$_ASKPASS"
chmod 700 "$_ASKPASS"
export SSH_ASKPASS="$_ASKPASS" SSH_ASKPASS_REQUIRE=force

# Host key changes on every reflash, so don't pin it.
# IdentityAgent=none: this Mac's Bitwarden SSH agent blocks on an approval prompt, so scripts use the password.
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentityAgent=none -o ConnectTimeout=5"
