# Agent brief: mainline Linux on Xiaomi Mi 9 (cepheus)

You're working on postmarketOS (mainline kernel `7.0.0-sm8150-aurora`) on a physical Xiaomi Mi 9 connected over USB.
README.md is the overview; `docs/` has the architecture, hardware map, per-subsystem pages (with the rationale for each fix),
workflow and troubleshooting. This file is what you need to act safely and quickly.
If a `CLAUDE.local.md` exists, it describes the specific unit on the desk and overrides this file.

## Hard rules (owner's data and hardware)
- **Never write** `modemst1`, `modemst2`, `fsg`, `fsc` (IMEI/EFS), `persist`, `persistbak`, `devinfo`, `abl*`, `xbl*`. Read-only only.
- Never mkfs/dd the partition that holds the live root (`findmnt /`) or `/boot` without asking.
- **Test new DTBs/kernels from RAM first** (`scripts/test-dtb.sh` = `fastboot boot`). Only flash once it boots.
- Before any `dd` to a partition, check the name: `findfs PARTLABEL=<name>` or `grep PARTNAME /sys/class/block/<dev>/uevent`.
- Don't install `linux-firmware-ath10k` (its generic `board-2.bin` entry for board_id 0xff would override the Mi 9 calibration).
- Never commit partition dumps or anything from `persist` (IMEI, MAC, calibration).
- Destructive or irreversible steps: ask first.

## Access
- Phone: `172.16.42.1` (USB NCM), host side `172.16.42.2`. User `user`, placeholder password `cepheus` (login and sudo; `PHONE_PASS=`).
- `scripts/pm '<cmd>'` runs as user, `scripts/pms '<cmd>'` as root (no single quotes inside), and `scripts/pcp a phone:/b` copies files.
- Internet for the phone: Wi-Fi. On a fresh install, `cli-setup.sh` shares the host's internet for its run (temporary tinyproxy).
- Initramfs debug shell (when boot fails): telnet :23, `scripts/tn '<cmd>'`.
- Fastboot: from Linux `scripts/pms 'systemctl reboot --reboot-argument=bootloader'`; otherwise ask the user for Volume Down + Power.
- Screen: you can't see it. Ask the user to look, or to send a screenshot, at each checkpoint that changes the display.
- Build environment: macOS = OrbStack machine `pmos`, Linux = the host itself; `vmsh '…'` in `scripts/common.sh` picks the right one.
  pmbootstrap 3.12.1, work dir `~/.local/var/pmbootstrap`, pmaports at `…/cache_git/pmaports` (main + our commits),
  kernel tree `~/src/linux-v7.0.0-sm8150` (git, patches applied).

## Current state
- Working: UFS, display (AMS639RQ08/EA8076), backlight, touch (`ftm5_i2c`), GPU (Adreno 640, freedreno), Wi-Fi (real MAC from
  `persist` via udev helper), Bluetooth (WCN3998, `hci_qca`; BD address from `bootmac`), speaker (CS35L41 + UCM, analog gain 10:
  no protection DSP), battery/charger, sensors + auto-rotate (SLPI + hexagonrpcd + libssc + forked iio-sensor-proxy 3.9-r3),
  Plasma Mobile and Phosh.
- Packages: `linux-postmarketos-qcom-sm8150-7.0.0-r8` (patches 0004–0011), `device-xiaomi-cepheus-7-r1` (+ `-nonfree-firmware`;
  depends on `bootmac`, masks its wlan rule), `iio-sensor-proxy-3.9-r3` (keep it above Alpine's r2).
- Hand-made phone files live in `phone-config/`; `scripts/{cli,kde,phosh}-setup.sh` (→ `phone-setup.sh` on the phone) install them.
  Keep the two in sync when adding phone-side files.
- Known issue: a burst of GPU faults + 1 hangcheck recover right after Plasma starts (README: Known issues).
- Not working / not started: mics, earpiece, fast charging, cellular, proximity, cameras, panel polish (rounded corners).

## Notes
- Background jobs started over ssh die with the session: use `systemd-run --unit=x --collect sh -c '…'` on the phone, `setsid nohup` in the VM.
- Full kernel package build: ~7 min on 17 cores, ~4 min warm. The package uses `LLVM=1`; build modules/DTBs in the tree with `LLVM=1` too.
- Testing a module on an older running kernel: strip `.BTF` (`llvm-objcopy --remove-section=.BTF`) or it fails with `BTF: -22`.
- Commits in the build environment: `git -c user.name=… -c user.email=… commit` if no identity is configured.
- Emergency mode on boot = root locked, no ssh: hold Power ~10 s. Keep `nofail` on non-root mounts.

## Next steps
README "Known issues": GPU-fault burst → panel polish → mics/earpiece → cellular → proximity.

## Workflow that worked well
- Ground truth = Xiaomi downstream DT (`MiCode/Xiaomi_Kernel_OpenSource`, branch `cepheus-p-oss`, under `arch/arm64/boot/dts/qcom/`:
  `cepheus-sm8150.dtsi`, `cepheus-pinctrl.dtsi`, `dsi-panel-*`) plus a sibling mainline board as template (`sm8150-xiaomi-raphael.dts`,
  the same Xiaomi SM8150 family, which uses the same panel).
- Loop: edit the DTS → `scripts/vm-build-dtb.sh` → `scripts/test-dtb.sh` → check dmesg + the screen → commit in the kernel tree →
  new `00NN-*.patch` in pmaports + bump pkgrel + `pmbootstrap checksum` + `build --force` → `apk add --allow-untrusted` on the phone → reboot test.
- After pmaports commits, refresh: `git bundle create pmaports/cepheus.bundle $(cat pmaports/BASE_COMMIT)..HEAD` and copy the patches.
- The phone's `/tmp` is tmpfs (wiped on reboot).
- When a subsystem changes, update its page in `docs/subsystems/` (and `docs/known-issues.md`) in the same commit.
- A cold reboot is the reliable reset for remoteproc/ath10k state. Hot-reloading ath10k after the WLAN firmware is up fails.
- `modetest` needs a pty (`ssh -tt`) to print its `freq:` lines. Use `-v` for continuous page flips on this command-mode panel.
