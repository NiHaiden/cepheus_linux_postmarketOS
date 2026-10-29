# Documentation

Mainline Linux (postmarketOS edge, kernel `7.0.0-sm8150-aurora`) on the Xiaomi Mi 9 (`cepheus`, Snapdragon 855 / SM8150).
The top-level [README](../README.md) has the status table and quick start. These pages explain how everything fits together.

Diagrams are [Mermaid](https://mermaid.js.org/); GitHub renders them inline.

## Start here

| Page | What it covers |
|---|---|
| [Architecture](architecture.md) | The whole system on one page: SoC, coprocessors, kernel, userspace, and how this repo fits around pmbootstrap |
| [Hardware map](hardware.md) | Every peripheral with its bus, address, GPIOs, regulators and driver; reserved memory; what is and isn't enabled |
| [Boot and storage](boot-and-storage.md) | Boot chain from ROM to Plasma, partition layout, `boot.img`, which partitions must never be written |
| [Firmware and coprocessors](firmware-and-coprocessors.md) | msm-firmware-loader, the four Hexagon DSPs, QRTR/QMI, tqftpserv, rmtfs, pd-mapper |

## Subsystems

One page each: the data path as a diagram, the DT nodes, drivers, firmware, userspace, what we had to fix, how to check it, and what's still open.

| Subsystem | Status | Page |
|---|---|---|
| UFS storage | works | [subsystems/storage.md](subsystems/storage.md) |
| Display, backlight | works | [subsystems/display.md](subsystems/display.md) |
| GPU (Adreno 640) | works, fault burst at session start | [subsystems/gpu.md](subsystems/gpu.md) |
| Touchscreen (ST FTM5) | works | [subsystems/touch.md](subsystems/touch.md) |
| Wi-Fi (WCN3990 / ath10k) | works | [subsystems/wifi.md](subsystems/wifi.md) |
| Bluetooth (WCN3998) | works | [subsystems/bluetooth.md](subsystems/bluetooth.md) |
| Audio | speaker works; mics, earpiece don't | [subsystems/audio.md](subsystems/audio.md) |
| Sensors (SLPI) | accel/light/compass work; proximity doesn't | [subsystems/sensors.md](subsystems/sensors.md) |
| Battery, charging | basic charging works | [subsystems/power.md](subsystems/power.md) |
| Buttons, USB | works | [subsystems/input-and-usb.md](subsystems/input-and-usb.md) |
| Cellular, cameras, NFC, fingerprint, … | not started | [hardware.md#not-enabled](hardware.md#not-enabled) |

## Working on it

| Page | What it covers |
|---|---|
| [Development workflow](development.md) | Host/VM layout, the DT edit → RAM-boot → package loop, kernel builds, refreshing the bundle |
| [Docker build environment](docker.md) | Everything above in one container on a Linux host (`scripts/docker-env`) |
| [Packaging](packaging.md) | The three packages we change, how kernel patches map to pmaports commits and `pkgrel`s, dependency graph |
| [Phone setup](phone-setup.md) | What `cli/kde/phosh-setup.sh` do on the phone, file by file |
| [Troubleshooting and recovery](troubleshooting.md) | Getting back to a working phone, the initramfs debug shell, symptoms → causes |
| [Known issues and roadmap](known-issues.md) | What's broken, the suspected causes, and the order we plan to tackle them |

## Ground rules (repeated everywhere because they matter)

- **Never write** `modemst1`, `modemst2`, `fsg`, `fsc` (IMEI/EFS), `persist`, `persistbak`, `devinfo`, `abl*`, `xbl*`.
- **Test new DTBs and kernels from RAM first** (`scripts/test-dtb.sh`). Flash only once it boots.
- **Don't install `linux-firmware-ath10k`.** It silently replaces the Mi 9 Wi-Fi calibration.
- **Don't raise the speaker's analog gain.** The speaker-protection DSP isn't running.
- **Never commit** partition dumps or anything from `persist`.
