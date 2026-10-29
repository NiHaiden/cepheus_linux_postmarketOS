#!/bin/sh
# Recreate the cepheus (Xiaomi Mi 9) mainline-Linux dev environment on a new host (macOS or Linux).
# Idempotent: safe to re-run. Takes ~10-20 min (mostly downloads).
#
#   ./setup-host.sh
#
# What it does:
#   1. Tools. macOS (Apple silicon): Homebrew android-platform-tools, tinyproxy, OrbStack.
#      Linux: checks that the build tools are installed (use your package manager), installs nothing system-wide.
#   2. pmbootstrap 3.12.1. macOS: in an OrbStack machine "pmos" (Alpine edge, aarch64) with doas.
#      Linux: on the host, cloned to ~/.local/share/pmbootstrap (uses sudo or doas when it needs root).
#   3. pmbootstrap config + pmaports with our cepheus commits (from pmaports/cepheus.bundle)
#   4. Kernel source tree ~/src/linux-v7.0.0-sm8150 (VM on macOS, host on Linux) with all patches applied
set -eu
H="$(cd "$(dirname "$0")" && pwd)"
VM="${VM:-pmos}"
PMB_TAG="3.12.1"
KTAG="v7.0.0-sm8150"
OS="$(uname -s)"
say() { printf '\n==> %s\n' "$*"; }
# Where pmbootstrap runs: the OrbStack VM on macOS, the host itself on Linux.
run() { if [ "$OS" = Darwin ]; then orb -m "$VM" sh -c "$1"; else sh -c "$1"; fi; }

if [ "$OS" = Darwin ]; then
  [ "$(uname -m)" = arm64 ] || { echo "needs an Apple-silicon Mac (the VM must be native aarch64)"; exit 1; }
  command -v brew >/dev/null || { echo "install Homebrew first: https://brew.sh"; exit 1; }

  say "1/4 Homebrew packages"
  brew list android-platform-tools >/dev/null 2>&1 || brew install --cask android-platform-tools
  for p in tinyproxy; do brew list "$p" >/dev/null 2>&1 || brew install "$p"; done
  command -v orb >/dev/null || brew install --cask orbstack
  orb start >/dev/null 2>&1 || true

  say "2/4 OrbStack machine '$VM' (Alpine edge) + pmbootstrap $PMB_TAG"
  orb list 2>/dev/null | grep -qw "$VM" || orb create alpine:edge "$VM"
  orb -m "$VM" -u root sh -c "
    set -e
    apk add -q git python3 doas openssl losetup multipath-tools coreutils \
               build-base flex bison dtc bc perl openssl-dev elfutils-dev linux-headers curl clang lld llvm bash
    echo 'permit nopass $(whoami)' > /etc/doas.d/pmb.conf && chmod 600 /etc/doas.d/pmb.conf
    [ -d /opt/pmbootstrap ] || git clone -q --depth 1 --branch $PMB_TAG https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git /opt/pmbootstrap
    ln -sf /opt/pmbootstrap/pmbootstrap.py /usr/local/bin/pmbootstrap
  "
else
  say "1/4 checking host tools"
  missing=
  for c in git python3 fastboot curl make clang ld.lld llvm-objcopy dtc flex bison bc perl; do
    command -v "$c" >/dev/null || missing="$missing $c"
  done
  command -v sudo >/dev/null || command -v doas >/dev/null || missing="$missing sudo/doas"
  [ -z "$missing" ] || { echo "install first:$missing (also the openssl + libelf development headers)"; exit 1; }
  for c in tinyproxy nc; do command -v "$c" >/dev/null || echo "optional, missing: $c (internet for a fresh phone / initramfs shell helper)"; done

  say "2/4 pmbootstrap $PMB_TAG on the host"
  P="$HOME/.local/share/pmbootstrap"
  [ -d "$P" ] || git clone -q --depth 1 --branch "$PMB_TAG" https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$P"
  mkdir -p "$HOME/.local/bin" && ln -sf "$P/pmbootstrap.py" "$HOME/.local/bin/pmbootstrap"
  export PATH="$HOME/.local/bin:$PATH"
fi

say "3/4 pmbootstrap config + pmaports (cepheus commits)"
run "
  set -e
  mkdir -p ~/.config
  [ -f ~/.config/pmbootstrap_v3.cfg ] || cp '$H/config/pmbootstrap_v3.cfg' ~/.config/pmbootstrap_v3.cfg
  # init clones pmaports; answers come from the config (all defaults)
  yes '' | pmbootstrap -q init >/dev/null 2>&1 || true
  cd ~/.local/var/pmbootstrap/cache_git/pmaports
  git fetch -q '$H/pmaports/cepheus.bundle' HEAD:refs/heads/cepheus-handoff 2>/dev/null || {
    # bundle needs its base commit; make sure full history is there
    git fetch -q --unshallow origin 2>/dev/null || git fetch -q origin
    git fetch -q '$H/pmaports/cepheus.bundle' HEAD:refs/heads/cepheus-handoff
  }
  if git merge-base --is-ancestor cepheus-handoff HEAD; then
    echo 'cepheus commits already present'
  else
    base=\$(cat '$H/pmaports/BASE_COMMIT')
    # try to carry our commits onto current upstream main; fall back to the exact old state
    if git -c user.name=cepheus -c user.email=cepheus@local cherry-pick \$base..cepheus-handoff >/dev/null 2>&1; then
      echo 'cepheus commits cherry-picked onto current pmaports main'
    else
      git cherry-pick --abort 2>/dev/null || true
      git reset -q --hard cepheus-handoff
      echo 'WARNING: cherry-pick conflicted; pmaports reset to the exact handoff state (older than upstream main)'
    fi
  fi
  git log --oneline -3
"

say "4/4 kernel source tree for DTB work (~/src/linux-v7.0.0-sm8150)"
run "
  set -e
  mkdir -p ~/src && cd ~/src
  if [ ! -d linux-$KTAG/.git ]; then
    [ -d linux-$KTAG ] || curl -sfL https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/archive/$KTAG/linux-$KTAG.tar.gz | tar xz
    cd linux-$KTAG
    git init -q && git add -A >/dev/null && git -c user.name=b -c user.email=b@l commit -qm base
    for p in ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sm8150/0*.patch; do
      git apply --whitespace=nowarn \"\$p\" && git add -A && git -c user.name=b -c user.email=b@l commit -qm \"\$(basename \$p)\"
    done
    cp ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sm8150/config-postmarketos-qcom-sm8150.aarch64 .config
    make -s ARCH=arm64 LLVM=1 olddefconfig >/dev/null 2>&1
  fi
  cd ~/src/linux-$KTAG && git log --oneline | head -6
"

say "verify: DTB build reproduces the one on the phone"
"$H/scripts/vm-build-dtb.sh" >/dev/null
ref="$H/images/sm8150-xiaomi-cepheus-current.dtb"   # not in git; from the release assets, if present
if [ ! -f "$ref" ]; then echo "DTB built (no reference DTB in images/ to compare with)"
elif cmp -s "$H/images/test.dtb" "$ref"; then echo "DTB identical - environment OK"
else echo "DTB differs (expected if pmaports or the patches moved on)"; fi
rm -f "$H/images/test.dtb"

cat <<EOF

Done. Next:
  - plug the phone in (USB-C), then:  scripts/pm uptime
  - read README.md and docs/ (how everything works) and CLAUDE.md (state + next steps for an AI agent)
EOF
