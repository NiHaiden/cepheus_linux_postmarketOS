# Mainline Linux on the Xiaomi Mi 9 (cepheus)

postmarketOS edge on a **mainline kernel (`7.0.0-sm8150-aurora`)** on the Xiaomi Mi 9, with Plasma Mobile or Phosh.
Kernel and device-tree patches, pmaports changes, setup scripts for the phone, and a dev environment for macOS or Linux.
**A tech demo: it works on one phone, use at your own risk. THIS NEEDS SERIOUS CLEANUP. USE ONLY AT YOUR OWN RISK. I DID THIS BECAUSE I HAD THE PHONE LAYING AROUND AND DECIDED TO HAVE FUN!**

<table><tr>
<td><img src="docs/screenshots/plasma-system-info.png" width="260" alt="Plasma Mobile System Information: kernel 7.0.0-sm8150-aurora"></td>
<td><img src="docs/screenshots/bluetooth-airpods.png" width="260" alt="AirPods Pro connected over Bluetooth, adapter Xiaomi Mi 9"></td>
<td><img src="docs/screenshots/browser-youtube.png" width="260" alt="YouTube in the browser on Plasma Mobile"></td>
</tr><tr>
<td>Plasma Mobile 6.8, kernel <code>7.0.0-sm8150-aurora</code></td>
<td>AirPods Pro paired over Bluetooth</td>
<td>YouTube in the browser, GPU-accelerated</td>
</tr></table>

## Status

| Works | Notes |
|---|---|
| Boot, UFS storage | Needed a UFS VCC fix (see [How it works](#how-it-works)) |
| Display, backlight | Samsung AMS639RQ08 (EA8076), command mode, 1080×2340@60 Hz, existing mainline driver |
| Touch | ST FTM5 on I2C (`ftm5_i2c`) |
| GPU | Adreno 640, freedreno, GLES 3.2 |
| Wi-Fi | WCN3990 (`ath10k_snoc`), real MAC from `persist` |
| Bluetooth | WCN3998 (`hci_qca`), pairs AirPods |
| Speaker | CS35L41, conservative gain (no speaker-protection DSP) |
| Battery, charging | Fuel gauge + charger, basic charging |
| Sensors, auto-rotate | Accelerometer, light, compass via the SLPI DSP |
| UI | Plasma Mobile 6.8 or Phosh 0.58 |
| USB networking | ssh at `172.16.42.1` |

**Not yet:** cellular, cameras, microphones, earpiece, proximity, fast/wireless charging. See [Known issues](#known-issues-and-todo).

## Quick start

### 1. Host (macOS or Linux)
- **macOS:** Apple silicon, Homebrew, ~15 GB disk. pmbootstrap runs in an OrbStack VM (`pmos`, Alpine edge).
- **Linux:** install `git python3 fastboot curl make clang lld llvm dtc flex bison bc perl`, openssl + libelf headers,
  `sudo` or `doas`; optional `tinyproxy` and `netcat`. pmbootstrap runs on the host (on x86_64 it cross-compiles).

```sh
git clone <this repo> cepheus-linux && cd cepheus-linux
./setup-host.sh     # tools/VM (macOS) or tool check (Linux), pmbootstrap 3.12.1, our pmaports, kernel tree
```

It applies `pmaports/cepheus.bundle` on top of current pmaports (or resets to our exact base if that conflicts) and creates
the kernel tree `~/src/linux-v7.0.0-sm8150` with all patches. The scripts call `vmsh` (in `scripts/common.sh`), which runs
build commands in the VM on macOS and on the host on Linux.

### 2. Install postmarketOS on the phone
Needs an unlocked bootloader and intact stock firmware partitions (`modem`, `vendor`, `dsp`, `bluetooth`, `persist`):
the firmware is used in place from them. **Back up `persist`, `modemst1/2`, `fsg`, `fsc` (IMEI!) and `devinfo` first**
(e.g. from a recovery: `adb exec-out dd if=/dev/block/by-name/persist > persist.img`) and keep them offline.

```sh
pmbootstrap install --password cepheus      # VM on macOS
pmbootstrap export                          # -> /tmp/postmarketOS-export (on macOS: copy it out of the VM)
# phone in fastboot (Volume Down + Power):
fastboot erase dtbo                         # mainline needs no Android DTBO
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img   # your stock vbmeta
fastboot flash userdata xiaomi-cepheus.img
fastboot flash boot boot.img
fastboot reboot
```
On a Linux host, `pmbootstrap flasher flash_rootfs` / `flash_kernel` / `flash_vbmeta` do the same. This is the standard
pmOS flow; the author's unit was installed onto a non-stock partition layout.

### 3. Set up the phone
Built packages aren't in git: download the Release assets into `apks/` (kernel 7.0.0-r8, `device-xiaomi-cepheus` 7-r1
+ `-nonfree-firmware`, `iio-sensor-proxy` 3.9-r3), or build them (see [Development](#development)). Then, phone on USB:

```sh
scripts/kde-setup.sh        # Plasma Mobile
scripts/phosh-setup.sh      # Phosh (greetd + phrog; lists Plasma too if installed)
scripts/cli-setup.sh        # console only
WIFI_SSID=MyNet WIFI_PSK=secret scripts/kde-setup.sh   # also store a Wi-Fi profile
scripts/pms reboot
```
All three run `cli-setup.sh` → `phone-setup.sh` (as root on the phone; safe to re-run, also to switch UI). They install our
packages plus hexagonrpcd, bluez and NetworkManager, put the files from `phone-config/` in place and pick the boot UI.
A fresh phone has no Wi-Fi until this has run, so the script shares the host's internet for the run
(temporary tinyproxy, USB subnet only) and sets the phone's clock if it's off.

### 4. Daily use
- `ssh user@172.16.42.1` (placeholder password `cepheus`, also for `sudo`). The host gets `172.16.42.2` by DHCP over USB.
- `scripts/pm '<cmd>'` runs as user, `scripts/pms '<cmd>'` as root, `scripts/pcp file phone:/path` copies.
- Kernel upgrades write the `boot` partition automatically (`deviceinfo_flash_kernel_on_update`).
- Fastboot: Volume Down + Power, or `sudo systemctl reboot --reboot-argument=bootloader`.

## How it works

Facts came from Xiaomi's downstream kernel (`MiCode/Xiaomi_Kernel_OpenSource`, branch `cepheus-p-oss`; relevant files in
`kernel/downstream-reference/`); the DT shape from sibling mainline boards (raphael = Mi 9T Pro/K20 Pro, vayu, nabu).
All DT changes are in `sm8150-xiaomi-cepheus.dts` (full result: `kernel/sm8150-xiaomi-cepheus.dts.final`).

**Partitions.** `boot` = pmOS boot.img (kernel + appended DTB + initramfs). `userdata` = pmOS image (`pmOS_boot` +
`pmOS_root`, 4K sectors). `dtbo` erased, `vbmeta` with verification off. Stock `modem`/`vendor`/`dsp`/`bluetooth`/`persist`
are mounted **read-only** by msm-firmware-loader, which links all blobs into `/run/msm-firmware-loader/target` and sets
`firmware_class.path`; that's why DT firmware names are bare (`modem.mdt`). Never write `persist`, `modemst*`, `fsg`, `fsc`.

**UFS (patch 0004).** The UFS 2.1 chip (WDC, `ufsid=0x145`) never came up: `link startup failed`. The DT let VCC (`ldo10`)
range from 2.504 V, and the regulator core picks the minimum, a UFS 3.0 level. Fix: minimum 2.95 V, as downstream.
Without it no cepheus with this UFS boots.

**Display (0004).** The command-mode panel keeps its own frame memory, so simplefb never updates it. The bootloader names
the panel (`dsi_samsung_fhd_ea8076_f1mp_cmd_display`); its init sequence matches mainline's `panel-samsung-ams639rq08`
(raphael, same 6.39" module, EA8076 = its controller), so no new driver. Wiring: `&mdss_dsi0` + panel (vddio `l14a`,
vdd3p3 = fixed regulator on tlmm 21, reset tlmm 6), TE on gpio8, 4 lanes. `modetest -v` (over `ssh -tt`) for page flips.

**Coprocessors and Wi-Fi (0005).** The WCN3990 Wi-Fi firmware runs on the modem DSP: MPSS boots `modem.mdt` → fetches
`wlanmdsp.mbn` via tqftpserv → talks QMI to `ath10k_snoc` (plus qrtr, rmtfs read-only, in-kernel pd-mapper).
- Board data: ath10k reports `board_id 0xff`; Xiaomi's cnss-daemon falls back to `bdwlan.bin`, so
  `board.bin → /run/msm-firmware-loader/target/bdwlan.bin`. Only `firmware-5.bin` (60-byte feature flags) is copied from
  linux-firmware. **Don't install `linux-firmware-ath10k`**: its generic `board-2.bin` entry for board_id 0xff wins over
  `board.bin` and silently replaces the Mi 9 calibration.
- MAC: ath10k picks a random one. A udev rule runs `cepheus-wlan-mac` when `wlan0` appears; it reads `Intf0MacAddress`
  from `persist/wlan_mac.bin` and sets it. NetworkManager is told to keep it (`50-cepheus-wifi-mac.conf`).
- A cold reboot is the reliable reset; reloading ath10k or restarting the modem by hand fails.

**GPU (0006).** `&gmu` + `&gpu` on, zap shader `a640_zap.mdt`. The other blobs load from `vendor` by bare name.

**Touch (0007).** The sm8150 fork has ST's downstream FTM5 driver, but SPI-only (for the Pixel 4). The patch builds a
second I2C module, `ftm5_i2c`. The Xiaomi touch firmware reports MP flag 0 and refuses to store one, so the driver re-ran
a 40 s panel init on every probe; new DT property `st,ignore-mp-flag` skips that. Chip on `i2c17` @0x49.

**Battery (0008).** Drivers existed; the patch adds a `simple-battery` node and enables charger + fuel gauge. The max
voltage (4.4 V, downstream `fv-max-uv`) is written into the charger's float-voltage register, so it must match the cell.

**Sensors (0009 + iio-sensor-proxy fork).** SLPI DSP (`slpi_cp.mdt`) → FastRPC → hexagonrpcd (serves the sensor registry
from `persist` read-only) → libssc → iio-sensor-proxy. Three fixes: a 16 MiB FastRPC heap + `qcom,vmids` in the DT; a
one-line fastrpc kernel fix from LKML (the sensors PD crashed right after attach); and an iio-sensor-proxy patch so
sensors claimed during startup actually start polling (auto-rotate stayed "undefined" otherwise). The firmware reports no
mount matrix: `81-libssc-xiaomi-cepheus.rules` sets X/Y inverted.

**Speaker (0010).** CS35L41 amp on `i2c4`, fed by Quaternary MI2S. The sm8150 machine driver never gave the codec its bit
clock, so the amp's PLL never locked; the patch sets the sysclk to 3.072 MHz. UCM in `phone-config/`: mono, analog gain 10.
Xiaomi runs the amp's speaker-protection DSP firmware with calibration; we don't, so **don't raise the analog gain**.

**Bluetooth (0011).** Kernel config and firmware (`qca/crbtfw21.tlv`, `crnv21.bin` from the `bluetooth` partition) were
already there; only the DT was missing: `qcom,wcn3998-bt` on `uart13` with downstream supplies, and proper default/sleep
pin states (sm8150.dtsi has none for uart13). The chip has no address of its own, so `bootmac` sets a stable one derived
from the serial; `device-xiaomi-cepheus` masks bootmac's Wi-Fi rule so it doesn't overwrite the real Wi-Fi MAC.

**Kernel name.** `CONFIG_LOCALVERSION="-sm8150-aurora"` in the package config. Drop it when upstreaming.

## Development

Edit the DT, build only the DTB (seconds), boot it **from RAM**, check, then package:

```sh
$EDITOR ~/src/linux-v7.0.0-sm8150/arch/arm64/boot/dts/qcom/sm8150-xiaomi-cepheus.dts   # in the VM on macOS (orb -m pmos)
scripts/vm-build-dtb.sh     # -> images/test.dtb
scripts/test-dtb.sh         # builds a boot.img on the phone with the test DTB, fastboot-boots it (nothing flashed)
scripts/pm 'dmesg | tail'   # a normal reboot returns to the flashed image
```

Package it: commit in the kernel tree, `git diff HEAD~1 > …/linux-postmarketos-qcom-sm8150/00NN-cepheus-<what>.patch`,
add it to `source=` and bump `pkgrel` in the APKBUILD, then `pmbootstrap checksum linux-postmarketos-qcom-sm8150` and
`pmbootstrap build --force linux-postmarketos-qcom-sm8150` (~7 min on 17 cores). Copy the `.apk` from
`~/.local/var/pmbootstrap/packages/edge/aarch64/` into `apks/`, `scripts/pcp` it to the phone and
`apk add --allow-untrusted` it (this flashes `boot`). Refresh the bundle after pmaports commits:
`git bundle create pmaports/cepheus.bundle $(cat pmaports/BASE_COMMIT)..HEAD`.

Tips:
- Boot fails but ping works → the initramfs debug shell on port 23: `scripts/tn 'tail -40 /pmOS_init.log'`.
- Testing a module on an older running kernel: strip `.BTF` (`llvm-objcopy --remove-section=.BTF`), or loading fails with `-22`.
- Any `apk add` that triggers mkinitfs re-flashes `boot` from the installed kernel, which replaces a RAM-tested DTB.
- Long jobs over ssh: `systemd-run --unit=x --collect sh -c '…'` on the phone.

## Recovery and safety

Fastboot lives in the bootloader, which none of this touches: **you can always get back to fastboot** (Volume Down + Power).

- Kernel/DTB doesn't boot: `fastboot flash boot` the last good boot.img (keep a copy of `/boot/boot.img` before upgrading).
- Rootfs broken: reinstall (Quick start 2), then run a setup script.
- IMEI/EFS damaged: `dd` your offline `modemst1/2`, `fsg`, `fsc` dumps back, **only if actually needed**.
- Never commit partition dumps (`.gitignore` blocks `backup/` and `*.img`).
- `cepheus` is a placeholder password and is in `scripts/common.sh`. Change it (`passwd`, then `PHONE_PASS=…`) if that
  matters; with key login you can disable SSH password auth.

## Known issues and TODO

1. **GPU faults at Plasma start**: a burst of `gpu fault` + one hangcheck recover in the first seconds of the session,
   none afterwards. Suspect UBWC/highest-bank-bit config for A640; try `FD_MESA_DEBUG=noubwc`.
2. **Panel polish**: Mi-9-specific `E9` OFC values and `D9`/`C0` blocks from the downstream panel dtsi; rounded corners clip the console.
3. **Audio**: microphones (`AFE enable … ADSP_EALREADY` on SLIMBUS_0_TX), earpiece (TAS2557, no mainline driver), speaker protection.
4. **Cellular**: the modem boots; needs ModemManager over QMI/qrtr and testing with a SIM.
5. **Charging**: fast charging (SMB1390, QC/PD), wireless, Xiaomi's fuel-gauge profile. Battery temperature limits read −30 °C (cosmetic).
6. **Sensors**: proximity isn't exposed; if the SLPI crashes, sensors stay dead until reboot.
7. **Touch**: no suspend/wake integration; the driver also registers gesture keys.
8. **Bluetooth**: audio profiles beyond the AirPods test are untested.
9. **Variants**: the DT assumes the f1mp panel and WDC UFS. Other Mi 9 units may differ (panel `f1p2`, other UFS vendors).

## Patches that were done

- pmaports: `pmaports/0001…0008-*.patch` against `device/testing/{linux-postmarketos-qcom-sm8150,device-xiaomi-cepheus}`.
  Package `board.bin` + `firmware-5.bin` properly, or send a `board-2.bin` entry
  (`bus=snoc,qmi-board-id=ff,qmi-chip-id=30224,variant=xiaomi_cepheus`) to ath10k-firmware.
- Kernel: `kernel/0004…0011`
  The UFS VCC fix matters most.
- iio-sensor-proxy: `pmaports/iio-sensor-proxy-0001-*.patch`

## Repository layout

```
setup-host.sh          dev environment (macOS VM or Linux host)
scripts/               {cli,kde,phosh}-setup.sh + phone-setup.sh; pm/pms/pcp (ssh helpers); tn (initramfs shell);
                       vm-build-dtb.sh, test-dtb.sh, phone-mkboot.sh (DT loop); flash-boot-from-linux.sh; common.sh (settings)
phone-config/          hand-made files installed on the phone, under their real paths
kernel/                kernel patches 0004–0011, the full resulting DTS, Xiaomi's downstream DT sources
pmaports/              our pmaports commits as a git bundle (+ BASE_COMMIT) and as patches
config/                pmbootstrap config
docs/screenshots/      screenshots
apks/, images/         built packages / local scratch (not in git)
CLAUDE.md              brief for an AI agent continuing the work
```

## Acknowledgements

Nearly everything here stands on other people's work. Thank you:

- **[postmarketOS](https://postmarketos.org)** and its community for pmbootstrap, pmaports, the packaging and the wiki.
- **Alexey Minnekhanov (Alexey Min)**, who created the cepheus port (device package and mainline DTS) and maintains it
  ([wiki page](https://wiki.postmarketos.org/wiki/Xiaomi_Mi_9_(xiaomi-cepheus))).
- The **SM8150 mainline** effort ([#sm8150-mainline:matrix.org](https://matrix.to/#/#sm8150-mainline:matrix.org)): Pan Ortiz and
  Viola Guerrera (maintainers of `linux-postmarketos-qcom-sm8150`), and Casey Connolly, Uclydde, Arseniy Velikanov (Adomerle),
  Omnidapps and Shadowsvanish, as listed on the [SoC wiki page](https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_855_(SM8150)).
- Authors of the sibling boards used as templates: Piyush Raj Chouhan (raphael), Degdag Mohamed, Arseniy Velikanov and
  Ali Nasrullayev (vayu), map220v (nabu, and the sm8150 sound machine driver).
- Driver authors: Danila Tikhonov (AMS639RQ08 panel), Casey Connolly, Joel Selvaraj and Yassine Oudjana (charger and fuel
  gauge), STMicroelectronics (FTM5 touch driver), and Robin Snyders and Piyush Raj Chouhan for the fastrpc sensors fix
  (reviewed by Dmitry Baryshkov).
- Userspace: Richard Acayan ([hexagonrpc](https://github.com/linux-msm/hexagonrpc)), Dylan Van Assche
  ([libssc](https://codeberg.org/DylanVanAssche/libssc), [bootmac](https://gitlab.postmarketos.org/postmarketOS/bootmac)),
  Bastien Nocera ([iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy)), [linux-msm](https://github.com/linux-msm)
  (qrtr, tqftpserv, rmtfs) and the msm-firmware-loader contributors.
- The upstream Linux Qualcomm (arm64/qcom, freedreno, ath10k, ASoC) maintainers and contributors.
- Xiaomi, for publishing the downstream kernel sources the device facts come from.

This bring-up: Niklas, with an AI coding agent (Claude) doing much of the hands-on work.

Licence: MIT for scripts and docs; kernel patches, DTS and downstream sources are GPL-2.0 (see `LICENSE`).
