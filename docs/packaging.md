# Packaging

Everything we ship is a normal postmarketOS/Alpine package, built by pmbootstrap from pmaports. This page explains which
packages we change, how the patches are organised, and how versions move.

- [Packages](#packages)
- [Dependency graph](#dependency-graph)
- [Patch map](#patch-map)
- [How the pmaports changes are distributed](#how-the-pmaports-changes-are-distributed)
- [Release assets](#release-assets)

## Packages

| Package | pmaports path | Current | What we changed |
|---|---|---|---|
| `linux-postmarketos-qcom-sm8150` | `device/testing/linux-postmarketos-qcom-sm8150` | **7.0.0-r8** | Kernel patches 0004–0011, `CONFIG_..._I2C_EXTRA=m`, local version `-sm8150-aurora` |
| `device-xiaomi-cepheus` | `device/testing/device-xiaomi-cepheus` | **7-r1** | `flash_kernel_on_update`, depends on `bootmac`, masks bootmac's Wi-Fi rule |
| `device-xiaomi-cepheus-nonfree-firmware` | (subpackage of the above) | **7-r1** | New: pulls in msm-firmware-loader, qrtr, tqftpserv, rmtfs |
| `iio-sensor-proxy` (+ `-systemd`, `-udev`, …) | `temp/iio-sensor-proxy` | **3.9-r3** | Fork of Alpine's, with the startup fix. Must stay above Alpine's r2 |

## Dependency graph

What ends up on the phone and why. Solid arrows are package dependencies; dashed are what `phone-setup.sh` installs on
top.

```mermaid
flowchart TB
    classDef ours fill:#d8f0d8,stroke:#3a3,color:#132

    dev["device-xiaomi-cepheus 7-r1"]:::ours
    nf["device-xiaomi-cepheus-nonfree-firmware 7-r1"]:::ours
    kern["linux-postmarketos-qcom-sm8150 7.0.0-r8"]:::ours
    isp["iio-sensor-proxy 3.9-r3"]:::ours

    dev --> kern
    dev --> bootmac["bootmac"]
    dev --> mkbootimg["mkbootimg"]
    dev --> base["postmarketos-base"]
    nf --> fwl["msm-firmware-loader"]
    nf --> qrtr["qrtr"]
    nf --> tq["tqftpserv"]
    nf --> rm["rmtfs"]
    isp --> libssc["libssc"]
    isp --> dbus["dbus"]

    setup["scripts/phone-setup.sh"]
    setup -.-> dev
    setup -.-> nf
    setup -.-> isp
    setup -.-> hr["hexagonrpcd (+ -systemd)"]
    setup -.-> fwlhr["msm-firmware-loader-hexagonrpcd (+ -systemd)"]
    setup -.-> misc["bluez, networkmanager (+ -cli, -wifi),<br/>alsa-ucm-conf, alsa-utils, kbd, terminus-font,<br/>htop, vim, usbutils, i2c-tools, evtest, rsync, zstd"]
    setup -.-> ui["UI: postmarketos-ui-plasma-mobile or<br/>postmarketos-ui-phosh + recommends"]
```

`iio-sensor-proxy` is built with `-Dssc-support=enabled` (hence `libssc-dev` at build time).

## Patch map

Each feature is one kernel patch, carried into pmaports by one pmaports commit that also bumps `pkgrel`. The
`pmaports/000N-*.patch` files are `git format-patch` output of those commits; `kernel/00NN-*.patch` are the kernel
patches inside them.

```mermaid
flowchart LR
    subgraph Kernel["Kernel patches"]
        k4["0004 UFS VCC + display"]
        k5["0005 remoteprocs + Wi-Fi"]
        k6["0006 GPU"]
        k7["0007 touch (FTM5 I2C)"]
        k8["0008 battery"]
        k9["0009 SLPI sensors"]
        k10["0010 speaker"]
        k11["0011 Bluetooth"]
    end
    subgraph Pmaports["pmaports commits"]
        p1["0001 → kernel r1, device 6"]
        p2["0002 → kernel r2, device 7 + nonfree-firmware"]
        p3["0003 → kernel r3"]
        p4["0004 → kernel r4 + config I2C_EXTRA=m"]
        p5["0005 → kernel r5"]
        p6["0006 → kernel r6 + iio-sensor-proxy 3.9-r3"]
        p7["0007 → kernel r7"]
        p8["0008 → kernel r8, device 7-r1, -aurora"]
    end
    k4 --> p1
    k5 --> p2
    k6 --> p3
    k7 --> p4
    k8 --> p5
    k9 --> p6
    k10 --> p7
    k11 --> p8
```

| Kernel patch | Touches | pmaports commit | Kernel | Device | Other |
|---|---|---|---|---|---|
| `0004-cepheus-ufs-vcc-and-display` | DTS | `0001` | r1 | 6-r0: `deviceinfo_flash_kernel_on_update="true"` | |
| `0005-cepheus-remoteprocs-wifi` | DTS | `0002` | r2 | 7-r0: `nonfree-firmware` subpackage | |
| `0006-cepheus-gpu` | DTS | `0003` | r3 | | |
| `0007-cepheus-touchscreen-ftm5-i2c` | DTS, `fts_touch/` | `0004` | r4 | | kernel config `CONFIG_TOUCHSCREEN_STM_FTS_DOWNSTREAM_I2C_EXTRA=m` |
| `0008-cepheus-battery` | DTS | `0005` | r5 | | |
| `0009-cepheus-slpi-sensors` | DTS, `drivers/misc/fastrpc.c` | `0006` | r6 | | `temp/iio-sensor-proxy` 3.9-r3 |
| `0010-cepheus-audio-speaker` | DTS, `sound/soc/qcom/sm8150.c` | `0007` | r7 | | |
| `0011-cepheus-bluetooth` | DTS | `0008` | r8 | 7-r1: depends on `bootmac`, `90-bootmac-wifi.rules` | `CONFIG_LOCALVERSION="-sm8150-aurora"` |

The kernel package's own `0001-enable-ufs.patch`, `0002-libbpf-Fix-UAF-in-strset__add_str.patch` and
`0003-xiaomi-vayu-fix-otg.patch` are upstream pmaports, not ours. That's why our numbering starts at 0004.

## How the pmaports changes are distributed

```mermaid
flowchart LR
    base["pmaports commit<br/>1eb4dce2…<br/>(pmaports/BASE_COMMIT)"] --> c1["our 8 commits"] --> head["HEAD 9fe9dc96…"]
    head -- "git bundle create<br/>BASE..HEAD" --> bundle["pmaports/cepheus.bundle"]
    bundle -- "setup-host.sh:<br/>git fetch bundle" --> branch["branch cepheus-handoff"]
    branch -- "cherry-pick onto<br/>current main" --> main["pmaports main + ours"]
    branch -. "if that conflicts:<br/>reset --hard" .-> old["exact old state"]
```

- The bundle contains only our commits, so it needs `BASE_COMMIT` in the target repo. `setup-host.sh` unshallows the
  pmaports clone if needed.
- The cherry-pick keeps you on current upstream. If upstream changed the same files (most likely the kernel APKBUILD),
  it falls back to the exact old state and warns. Then rebase by hand.
- The `.patch` copies in `pmaports/` and `kernel/` are for reading and for upstreaming. The bundle is what setup uses.

## Release assets

Built `.apk` files aren't in git (`apks/*.apk` is ignored). They're published as GitHub Release assets;
`apks/SHA256SUMS` lists them, including older builds kept for rollback (kernel r6, r7; device 7-r0).

```sh
cd apks && sha256sum -c SHA256SUMS --ignore-missing
```

`cli-setup.sh` copies only the newest build of each package to the phone.

Installing on the phone uses `apk add --allow-untrusted` because these aren't signed with a key the phone trusts.
