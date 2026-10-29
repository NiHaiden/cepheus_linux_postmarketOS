# Boot and storage

What happens between pressing Power and seeing Plasma, which partitions are involved, and which ones you must never
write.

- [Boot chain](#boot-chain)
- [Partition layout](#partition-layout)
- [What's in boot.img](#whats-in-bootimg)
- [Kernel upgrades write boot automatically](#kernel-upgrades-write-boot-automatically)
- [Testing from RAM](#testing-from-ram)
- [Partition safety rules](#partition-safety-rules)

## Boot chain

Everything up to and including ABL is Qualcomm/Xiaomi code that this project never touches. That's why fastboot is
always reachable (Volume Down + Power), whatever state Linux is in.

```mermaid
sequenceDiagram
    autonumber
    participant ROM as Boot ROM (PBL)
    participant XBL as XBL
    participant ABL as ABL (fastboot)
    participant K as Linux kernel
    participant I as pmOS initramfs
    participant S as systemd
    participant F as msm-firmware-loader
    participant R as remoteprocs
    participant UI as Desktop

    ROM->>XBL: load + verify
    XBL->>ABL: hand off
    alt Volume Down held, or reboot to bootloader
        ABL->>ABL: stay in fastboot (flash / fastboot boot)
    else normal boot
        ABL->>K: load boot partition: kernel + appended DTB + initramfs + cmdline
    end
    Note over ABL,K: dtbo is erased and vbmeta has verification off, so ABL applies no Android overlay
    K->>K: probe UFS (needs L10A at 2.95 V), DSI panel, USB gadget ...
    K->>I: run /init from the ramdisk
    I->>I: USB network up (172.16.42.1)
    I->>I: find pmOS_boot + pmOS_root (pmos_root_uuid on cmdline)
    alt root not found or mount fails
        I->>I: debug shell on telnet :23 (scripts/tn)
    else
        I->>S: switch_root into pmOS_root
    end
    S->>F: mount modem, vendor, dsp, bluetooth, persist read-only
    F->>F: link blobs into /run/msm-firmware-loader/target, set firmware_class.path
    F-->>R: firmware now resolvable by bare name
    R->>R: MPSS (modem.mdt), ADSP, CDSP, SLPI (slpi_cp.mdt) boot
    S->>S: tqftpserv, rmtfs, hexagonrpcd-sdsp, NetworkManager, bluetooth
    S->>UI: plasma-mobile.service (autologin) or greetd + phrog (Phosh)
```

Where each step can fail and how to tell:

| Step | Failure looks like | First thing to check |
|---|---|---|
| ABL → kernel | Stuck on the Mi logo, no USB network at all | Last flashed `boot.img`. Reflash the previous one from fastboot |
| Kernel → UFS | Ping works, ssh doesn't; initramfs can't find root | `scripts/tn 'dmesg \| grep -i ufs'`: `link startup failed` means the `l10a` VCC level (see [storage](subsystems/storage.md)) |
| Initramfs | Ping works, ssh doesn't | `scripts/tn 'tail -40 /pmOS_init.log'` |
| systemd | Emergency mode: root locked, no ssh | A non-root mount without `nofail`. Hold Power ~10 s to power off |
| Firmware | Wi-Fi/sensors/audio missing, rest fine | `ls /run/msm-firmware-loader/target`, `dmesg \| grep -i remoteproc` |

More in [Troubleshooting](troubleshooting.md).

## Partition layout

The stock Android layout stays in place. postmarketOS lives inside `userdata` (the author's unit uses a non-stock
layout, but the standard install below is what the README describes).

```mermaid
flowchart TB
    classDef write fill:#d8f0d8,stroke:#3a3,color:#132
    classDef ro fill:#dde8f8,stroke:#36c,color:#123
    classDef never fill:#f8dddd,stroke:#c33,color:#311

    subgraph W["Written by this project"]
        boot["boot<br/>pmOS boot.img"]:::write
        userdata["userdata<br/>pmOS image: pmOS_boot + pmOS_root<br/>(4K sectors)"]:::write
        dtbo["dtbo<br/>erased"]:::write
        vbmeta["vbmeta<br/>stock, flashed with verification off"]:::write
    end
    subgraph RO["Read-only, used in place"]
        modem["modem<br/>DSP + WLAN firmware"]:::ro
        vendor["vendor<br/>GPU and other blobs"]:::ro
        dsp["dsp<br/>DSP userspace libraries"]:::ro
        bt["bluetooth<br/>BT firmware"]:::ro
        persist["persist<br/>Wi-Fi MAC, sensor registry,<br/>calibration"]:::ro
    end
    subgraph N["Never write"]
        efs["modemst1, modemst2, fsg, fsc<br/>IMEI / modem EFS"]:::never
        pb["persistbak"]:::never
        devinfo["devinfo<br/>unlock state"]:::never
        bl["xbl*, abl*<br/>bootloaders"]:::never
    end

    RO -- "msm-firmware-loader" --> target["/run/msm-firmware-loader/<br/>target"]
    efs -. "rmtfs, read-only" .-> mpss["Modem DSP at runtime"]
```

| Partition | Role here | Written? |
|---|---|---|
| `boot` | pmOS `boot.img` | Yes: at install and on every kernel package upgrade |
| `userdata` | pmOS image: `pmOS_boot` (kernel, initramfs, `boot.img` copy) + `pmOS_root` | Yes: at install |
| `dtbo` | Android DT overlays. Mainline doesn't want them | Erased once at install |
| `vbmeta` | Verified boot metadata | Flashed once with `--disable-verity --disable-verification` |
| `modem`, `vendor`, `dsp`, `bluetooth` | Firmware source | **No**, read-only mounts |
| `persist` | Per-unit data: `wlan_mac.bin`, sensor registry, calibration | **No**, read-only mount. Back it up offline |
| `modemst1/2`, `fsg`, `fsc` | Modem EFS, IMEI | **Never**. Back them up offline |
| `devinfo`, `abl*`, `xbl*`, `persistbak` | Bootloader state and code | **Never** |

## What's in boot.img

```mermaid
flowchart LR
    subgraph IMG["boot.img"]
        hdr["Header<br/>base, offsets, page size,<br/>header version, cmdline"]
        kern["kernel =<br/>vmlinuz + appended<br/>sm8150-xiaomi-cepheus.dtb"]
        rd["ramdisk =<br/>pmOS initramfs"]
    end
    vmlinuz["/boot/vmlinuz<br/>(kernel package)"] --> kern
    dtb["DTB<br/>(kernel package)"] --> kern
    mkinitfs["mkinitfs + boot-deploy"] --> rd
    mkinitfs --> hdr
```

- `deviceinfo_append_dtb=true`: the DTB is concatenated onto the kernel image, which is how ABL on this phone finds it.
- The cmdline carries `pmos_root_uuid=…`, which the initramfs uses to find the root partition.
  `scripts/phone-mkboot.sh` can swap it via `ROOT_UUID=` to boot a different root.
- The header values (base, offsets, page size, header version) are copied from the installed `/boot/boot.img` when we
  build a test image, so a test image differs from the real one only in its DTB.

## Kernel upgrades write boot automatically

`device-xiaomi-cepheus` sets `deviceinfo_flash_kernel_on_update="true"` (pmaports patch 0001). So:

```mermaid
flowchart LR
    apk["apk add / upgrade<br/>linux-postmarketos-qcom-sm8150"] --> mk["mkinitfs + boot-deploy<br/>rebuild initramfs + boot.img"]
    mk --> flash["writes /boot/boot.img<br/>to the boot partition"]
    flash --> reboot["next reboot runs it"]
```

Side effect: **any** `apk add` that triggers mkinitfs re-flashes `boot` from the installed kernel. If you're in the
middle of testing a DTB from RAM, the next reboot goes back to the installed DTB, not yours.

There's also `scripts/flash-boot-from-linux.sh boot.img` to write an arbitrary image from running Linux with a
checksum check. Normally you don't need it.

## Testing from RAM

`fastboot boot` loads an image into RAM and runs it once without writing anything. A failed test costs one reboot.

```mermaid
sequenceDiagram
    participant H as Host
    participant P as Phone (Linux)
    participant FB as Phone (fastboot)
    H->>P: scp test.dtb + phone-mkboot.sh to /tmp
    P->>P: unpackbootimg /boot/boot.img
    P->>P: cat /boot/vmlinuz test.dtb, mkbootimg with the same header values
    P->>H: scp /tmp/test-boot.img back
    H->>P: systemctl reboot --reboot-argument=bootloader
    P->>FB: reboot into fastboot
    H->>FB: fastboot boot test-boot.img
    FB->>P: boots the test image from RAM
    Note over P: a normal reboot later returns to the flashed boot partition
```

That's `scripts/test-dtb.sh` (it calls `scripts/phone-mkboot.sh` on the phone). Building the image on the phone
guarantees the kernel and initramfs match the installed modules.

## Partition safety rules

Before any `dd` to a partition, check its name:

```sh
scripts/pms 'findfs PARTLABEL=boot'                     # -> /dev/sdXN
scripts/pms 'grep PARTNAME /sys/class/block/sdXN/uevent' # double-check a device node
scripts/pm  'findmnt /'                                  # never mkfs/dd what this shows
```

Back up before you start, from a recovery, and keep the images offline (never in git; `.gitignore` blocks `backup/`
and `*.img`):

```sh
for p in persist modemst1 modemst2 fsg fsc devinfo; do
  adb exec-out dd if=/dev/block/by-name/$p > $p.img
done
```

If the IMEI/EFS is ever damaged, `dd` the offline `modemst1/2`, `fsg`, `fsc` dumps back, and only if you actually need to.
