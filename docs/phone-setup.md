# Phone setup

What `scripts/cli-setup.sh`, `kde-setup.sh` and `phosh-setup.sh` do to a freshly installed phone, and every file they put
in place. All three are safe to re-run, which is also how you switch the boot UI.

## Overview

```mermaid
sequenceDiagram
    autonumber
    participant H as Host: cli-setup.sh
    participant T as Host: tinyproxy :8888
    participant P as Phone (root): phone-setup.sh
    participant M as Alpine / pmOS mirrors

    H->>H: apks/ has packages? phone reachable (scripts/pm true)?
    H->>P: wget mirror (5 s timeout)
    alt phone has no internet (fresh install: no Wi-Fi yet)
        H->>T: start, allow 172.16.42.0/24 only, stop on exit
        Note over H,T: phone uses http_proxy=http://172.16.42.2:8888
    end
    H->>P: clock off by more than 60 s? date -s from the host<br/>(RTC is read-only, a wrong clock breaks TLS)
    H->>P: tar | ssh: phone-setup.sh, phone-config/, newest .apk of each package → /tmp/cepheus-setup
    H->>P: sudo sh phone-setup.sh cli|kde|phosh (WIFI_SSID/WIFI_PSK passed through)
    P->>M: apk add our .apks + hexagonrpcd, bluez, NetworkManager, …
    P->>P: install phone-config files
    P->>P: systemctl enable hexagonrpcd-sdsp, bluetooth, NetworkManager
    opt WIFI_SSID set and no profile for it yet
        P->>P: write a NetworkManager keyfile<br/>(not nmcli: starting NM could drop the USB ssh link)
    end
    P->>M: UI packages (kde / phosh)
    P->>P: enable the UI's service, disable the other
    H->>H: "Reboot when ready: scripts/pms reboot"
```

## Choosing the UI

```mermaid
flowchart LR
    arg{"phone-setup.sh argument"}
    arg -- "cli" --> cli["disable greetd + plasma-mobile<br/>console at boot"]
    arg -- "kde" --> kde["apk add postmarketos-ui-plasma-mobile + apps<br/>/etc/default_user = the ssh user<br/>disable greetd, enable plasma-mobile.service"]
    arg -- "phosh" --> phosh["apk add postmarketos-ui-phosh + GNOME apps<br/>disable plasma-mobile, enable greetd<br/>(phrog greeter; Plasma stays selectable if installed)"]
```

| Script | Calls | Boot UI |
|---|---|---|
| `scripts/cli-setup.sh` | `phone-setup.sh cli` | Console (Terminus 16×32 bold font) |
| `scripts/kde-setup.sh` | `cli-setup.sh kde` | Plasma Mobile, autologin as `user` |
| `scripts/phosh-setup.sh` | `cli-setup.sh phosh` | Phosh via greetd + phrog |

Add `WIFI_SSID=… WIFI_PSK=…` in front of any of them to store a Wi-Fi profile that connects after the reboot.

## Files put on the phone

Everything lives in `phone-config/` under its real path.

| File | Purpose | Details |
|---|---|---|
| `/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin` | ath10k feature flags (copied from linux-firmware) | [wifi](subsystems/wifi.md#board-data-calibration) |
| `/lib/firmware/ath10k/WCN3990/hw1.0/board.bin` | Symlink to `/run/msm-firmware-loader/target/bdwlan.bin` (target in `board.bin.SYMLINK_TARGET`) | [wifi](subsystems/wifi.md#board-data-calibration) |
| `/usr/local/sbin/cepheus-wlan-mac` | Sets the real Wi-Fi MAC from `persist/wlan_mac.bin` | [wifi](subsystems/wifi.md#mac-address) |
| `/etc/udev/rules.d/80-cepheus-wlan-mac.rules` | Runs it when an ath10k `wlan*` appears | [wifi](subsystems/wifi.md#mac-address) |
| `/etc/NetworkManager/conf.d/50-cepheus-wifi-mac.conf` | NetworkManager keeps that MAC, no scan randomisation | [wifi](subsystems/wifi.md#mac-address) |
| `/etc/udev/rules.d/81-libssc-xiaomi-cepheus.rules` | Accelerometer mount matrix (X, Y inverted) | [sensors](subsystems/sensors.md#mount-matrix) |
| `/usr/share/alsa/ucm2/conf.d/sm8150/Xiaomi Mi 9.conf` | UCM entry point for the card named "Xiaomi Mi 9" | [audio](subsystems/audio.md#ucm) |
| `/usr/share/alsa/ucm2/Xiaomi/cepheus/HiFi.conf` | Speaker routing and gain | [audio](subsystems/audio.md#ucm) |
| `/etc/vconsole.conf` | `FONT=ter-v32b`: readable console on a 1080×2340 panel | |
| `/etc/default_user` | Default user for the Plasma Mobile session (`kde` only; written from `SUDO_USER`, not copied) | |
| `/etc/udev/rules.d/90-bootmac-wifi.rules` | Reference copy only: the **device package** installs it | [bluetooth](subsystems/bluetooth.md#bd-address) |

The script also removes `/etc/systemd/network/10-cepheus-wlan-mac.link`, the old hard-coded MAC approach.

## Adding a phone-side file

1. Put it in `phone-config/` at its real path.
2. Add an `install` line to `scripts/phone-setup.sh`.
3. If it's something every cepheus user needs, consider moving it into `device-xiaomi-cepheus` instead. That's where it
   belongs long-term, and it's how `90-bootmac-wifi.rules` ended up there.

## Internet for a fresh phone

The phone gets Wi-Fi only after this setup has installed the firmware glue, but the setup needs internet to install
packages. The way out:

```mermaid
flowchart LR
    phone["Phone<br/>172.16.42.1"] -- "http_proxy" --> proxy["tinyproxy on host<br/>172.16.42.2:8888<br/>Allow 172.16.42.0/24 only,<br/>CONNECT 443/80 only"]
    proxy --> net["Internet<br/>(Alpine / pmOS mirrors)"]
```

The proxy runs only while `cli-setup.sh` runs (it's killed by an `EXIT` trap). Install `tinyproxy` on the host for this.
