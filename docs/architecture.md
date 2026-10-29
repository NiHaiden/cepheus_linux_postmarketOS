# Architecture

How a Xiaomi Mi 9 runs mainline Linux here, from silicon to the desktop, and how this repository fits around postmarketOS.
The per-subsystem pages go deeper; this page is the map.

- [The phone in one picture](#the-phone-in-one-picture)
- [The SoC and what's around it](#the-soc-and-whats-around-it)
- [Software stack](#software-stack)
- [How the processors talk to each other](#how-the-processors-talk-to-each-other)
- [Feature slices](#feature-slices)
- [How this repository fits around postmarketOS](#how-this-repository-fits-around-postmarketos)
- [Design decisions](#design-decisions)

## The phone in one picture

Five layers. Each one depends on the one below. Most bring-up bugs were at the boundary between two of them: a wrong
voltage in the device tree, a missing clock in a driver, a firmware file under the wrong name.

```mermaid
flowchart TB
    L4["<b>Desktop</b><br/>Plasma Mobile 6.8 or Phosh 0.58"]
    L3["<b>Userspace services</b> (postmarketOS edge, systemd)<br/>Mesa freedreno · NetworkManager · BlueZ · sound server + ALSA UCM<br/>iio-sensor-proxy + libssc · msm-firmware-loader · hexagonrpcd · tqftpserv · rmtfs · bootmac"]
    L2["<b>Kernel</b> linux-postmarketos-qcom-sm8150 7.0.0 (-sm8150-aurora)<br/>drm/msm (DPU, DSI, Adreno) · ath10k_snoc · hci_qca · ASoC (q6afe/q6asm, cs35l41)<br/>remoteproc · QRTR · fastrpc · ufs-qcom · ftm5_i2c · charger + fuel gauge"]
    L1["<b>Device tree</b> sm8150-xiaomi-cepheus.dts<br/>which parts exist, where they sit, which voltages and GPIOs they need"]
    L0["<b>Hardware + vendor firmware</b><br/>SM8150 SoC (CPU, GPU, display engine) · Hexagon DSPs running Qualcomm firmware from the stock partitions<br/>panel · touch · UFS · WCN3998 · amp · PMICs"]
    L4 --> L3 --> L2 --> L1 --> L0
```

The device tree layer is where most of this project's work went: eight kernel patches (`kernel/0004…0011`), of which
five touch only the DTS and three also change a driver (touch, FastRPC, and the sound machine driver).

## The SoC and what's around it

The Snapdragon 855 (SM8150) is not one processor but several: the ARM cores that run Linux, plus four Hexagon DSPs that
each run their own Qualcomm firmware, plus the GPU's own management core. Linux has to start each of them with the
right firmware and then talk to them over shared memory.

```mermaid
flowchart LR
    subgraph SOC["Snapdragon 855"]
        direction TB
        CPU["Kryo 485 CPU cores<br/><b>Linux</b>"]
        GPU["Adreno 640 GPU + GMU"]
        MDSS["MDSS display engine<br/>DPU + DSI0"]
        I2C17["QUP: i2c17"]
        I2C4["QUP: i2c4"]
        MI2S["LPASS: Quaternary MI2S"]
        SLIM["LPASS: SLIMbus"]
        UART13["QUP: uart13"]
        WLAN["WLAN core"]
        subgraph DSPs["Hexagon DSPs"]
            MPSS["MPSS<br/>modem + WLAN firmware"]
            ADSP["ADSP<br/>audio"]
            CDSP["CDSP<br/>compute"]
            SLPI["SLPI<br/>sensor hub"]
        end
        UFSHC["UFS host controller"]
        USB["USB DWC3"]
    end

    PMIC["PMICs<br/>PM8150: regulators, power key<br/>PM8150B: charger, fuel gauge<br/>PM8150L: regulators, BOB"]
    PANEL["Samsung AMS639RQ08 AMOLED<br/>EA8076 controller, 1080x2340"]
    TOUCH["ST FTM5 touch controller"]
    AMP["CS35L41 amp"] --> SPK["Bottom speaker"]
    CODEC["WCD9340 codec"] --- MICS["Microphones"]
    WCN["WCN3998<br/>Wi-Fi radio + Bluetooth"]
    SENS["Motion, light, proximity<br/>and magnetic sensors"]
    UFS["UFS 2.1 storage (WDC)"]
    USBC["USB-C port"]
    BAT["3300 mAh battery"]

    MDSS -- "DSI, 4 lanes" --> PANEL
    I2C17 -- "@0x49" --> TOUCH
    I2C4 -- "@0x40, control" --> AMP
    MI2S -- "audio data" --> AMP
    SLIM --- CODEC
    UART13 -- "Bluetooth HCI" --> WCN
    WLAN -- "Wi-Fi" --- WCN
    SLPI --- SENS
    UFSHC --- UFS
    USB --- USBC
    PMIC --- BAT
    PMIC -. "power rails for everything" .- SOC
```

The [hardware map](hardware.md) has the exact addresses, GPIOs and supply rails for each of these.

## Software stack

The stack per function, from the app at the top down to the chip. Grey boxes are firmware we don't control: it comes
from Xiaomi's stock partitions and runs on a DSP.

```mermaid
flowchart TB
    classDef fw fill:#e8e8e8,stroke:#888,color:#333
    classDef ours fill:#d8f0d8,stroke:#3a3,color:#132

    subgraph Display
        direction TB
        d1["KWin / phoc"] --> d2["Mesa freedreno"] --> d3["drm/msm<br/>(DPU + Adreno)"] --> d4["panel-samsung-ams639rq08"] --> d5["Panel"]
        d3 --> d6["GMU + zap shader"]:::fw
    end
    subgraph WiFi["Wi-Fi"]
        direction TB
        w1["NetworkManager"] --> w2["ath10k_snoc"] -- "QMI over QRTR" --> w3["WLAN firmware<br/>on MPSS"]:::fw --> w4["WCN3998 radio"]
        w5["cepheus-wlan-mac<br/>(udev)"]:::ours --> w2
    end
    subgraph BT["Bluetooth"]
        direction TB
        b1["BlueZ"] --> b2["hci_qca"] -- "uart13" --> b3["WCN3998 BT"]
        b4["bootmac"] --> b2
    end
    subgraph Audio
        direction TB
        a1["Sound server + UCM"]:::ours --> a2["ASoC sm8150 card"] -- "APR" --> a3["ADSP firmware"]:::fw -- "MI2S" --> a4["CS35L41"] --> a5["Speaker"]
    end
    subgraph Sensors
        direction TB
        s1["KWin / Phosh auto-rotate"] --> s2["iio-sensor-proxy (fork)"]:::ours --> s3["libssc"] -- "QMI over QRTR" --> s4["SLPI firmware"]:::fw --> s5["Sensors"]
        s6["hexagonrpcd"] -- "FastRPC: serves files from persist" --> s4
    end
```

Green boxes are our own work in userspace (the kernel-side work is in every column). The [feature slices](#feature-slices)
table below links each column to its page.

## How the processors talk to each other

Linux and the DSPs share memory and exchange messages through a few kernel transports. Knowing which feature uses which
transport explains most of the dependencies between services.

```mermaid
flowchart LR
    subgraph Linux["Linux (apps processor)"]
        rproc["remoteproc<br/>qcom_q6v5_pas"]
        glink["GLINK + SMEM"]
        qrtr["QRTR"]
        pdm["pd-mapper<br/>(in kernel)"]
        apr["APR<br/>q6afe, q6asm, q6routing"]
        frpc["fastrpc<br/>/dev/fastrpc-*"]
        ath["ath10k_snoc"]
        tq["tqftpserv"]
        rm["rmtfs<br/>(read-only)"]
        ssc["libssc"]
        hr["hexagonrpcd"]
    end
    subgraph DSPs["Hexagon DSPs"]
        mpss["MPSS"]
        adsp["ADSP"]
        slpi["SLPI"]
        cdsp["CDSP"]
    end

    rproc -- "loads firmware, starts, stops" --> DSPs
    DSPs <--> glink
    glink <--> qrtr
    glink <--> apr
    glink <--> frpc
    qrtr <--> pdm
    qrtr <--> ath
    qrtr <--> tq
    qrtr <--> rm
    qrtr <--> ssc
    frpc <--> hr
```

| Transport | What travels over it here | Users |
|---|---|---|
| remoteproc | Firmware loading (`*.mdt` + segments), start/stop, crash recovery | All four DSPs |
| QRTR (IPC router) + QMI | Service discovery and control messages | `ath10k_snoc` (WLAN), `tqftpserv` (firmware files for the modem), `rmtfs` (modem EFS), libssc (sensors), pd-mapper |
| APR | Audio routing and stream commands | ASoC `q6afe`, `q6asm`, `q6routing` → ADSP |
| FastRPC | DSP calls back into Linux, e.g. to read files | `hexagonrpcd` serving the SLPI's sensor registry from `persist` |

Details: [Firmware and coprocessors](firmware-and-coprocessors.md).

## Feature slices

Each feature cuts through all layers. The page for each one has its own diagram.

| Feature | Device tree | Kernel driver | Firmware | Userspace | Page |
|---|---|---|---|---|---|
| Storage | `&ufs_mem_hc`, L10A ≥ 2.95 V | `ufs-qcom` | none | none | [storage](subsystems/storage.md) |
| Display | `&mdss_dsi0` + `panel@0` | `drm/msm`, `panel-samsung-ams639rq08` | none | KWin / phoc | [display](subsystems/display.md) |
| GPU | `&gpu`, `&gmu`, zap shader | `drm/msm` (adreno) | `a640_zap.mdt` + GPU blobs | Mesa freedreno | [gpu](subsystems/gpu.md) |
| Touch | `&i2c17` `touchscreen@49` | `ftm5_i2c` (patched) | on the touch IC | libinput | [touch](subsystems/touch.md) |
| Wi-Fi | `&wifi`, `&remoteproc_mpss` | `ath10k_snoc` | `modem.mdt`, `wlanmdsp.mbn`, `bdwlan.bin` | NetworkManager, `cepheus-wlan-mac` | [wifi](subsystems/wifi.md) |
| Bluetooth | `&uart13` `bluetooth` | `hci_qca` | `crbtfw21.tlv`, `crnv21.bin` | BlueZ, bootmac | [bluetooth](subsystems/bluetooth.md) |
| Speaker | `&sound`, `&i2c4` `cs35l41`, `&q6afedai` | ASoC `sm8150` (patched), `cs35l41` | `adsp.mdt` | UCM `HiFi.conf` | [audio](subsystems/audio.md) |
| Sensors | `&remoteproc_slpi`, FastRPC heap | `fastrpc` (patched) | `slpi_cp.mdt` | hexagonrpcd, libssc, iio-sensor-proxy (fork) | [sensors](subsystems/sensors.md) |
| Battery | `battery`, `&pm8150b_charger`, `&pm8150b_fg` | charger + fuel gauge | none | UPower | [power](subsystems/power.md) |
| Keys, USB | `gpio_keys`, `&pon_*`, `&usb_1*` | `gpio-keys`, `pm8941-pwrkey`, `dwc3` | none | none | [input-and-usb](subsystems/input-and-usb.md) |

## How this repository fits around postmarketOS

This repo is not a fork of postmarketOS. It's a set of changes plus the tooling to apply them. The real build happens in
pmbootstrap, against a pmaports checkout with our commits on top.

```mermaid
flowchart LR
    subgraph Repo["This repository"]
        kp["kernel/0004…0011<br/>kernel patches"]
        pp["pmaports/cepheus.bundle<br/>+ 0001…0008 patches"]
        pc["phone-config/<br/>hand-made phone files"]
        sc["scripts/<br/>host + phone helpers"]
        sh["setup-host.sh"]
        apks["apks/<br/>(release assets, not in git)"]
    end
    subgraph Build["Build env: VM or host"]
        pmb["pmbootstrap 3.12.1"]
        pma["pmaports<br/>main + our commits"]
        kt["~/src/linux-v7.0.0-sm8150<br/>kernel tree, patches applied"]
    end
    subgraph Phone["Xiaomi Mi 9"]
        boot["boot partition<br/>boot.img"]
        root["pmOS rootfs<br/>(in userdata)"]
    end

    sh -- "creates" --> Build
    pp -- "git fetch + cherry-pick" --> pma
    kp -. "same patches, also inside the bundle" .-> pma
    pma --> pmb
    kt -- "vm-build-dtb.sh: test DTB" --> sc
    pmb -- "build: .apk" --> apks
    pmb -- "install / export: first image" --> root
    apks -- "cli/kde/phosh-setup.sh<br/>(ssh over USB)" --> root
    pc -- "phone-setup.sh" --> root
    sc -- "test-dtb.sh: fastboot boot (RAM only)" --> Phone
    root -- "kernel upgrade: flash_kernel_on_update" --> boot
```

The two flows that matter:

1. **Iterating on hardware support:** edit the DTS in the kernel tree, build only the DTB, boot it from RAM, look at
   `dmesg` and the screen. Nothing is written to flash. See [Development workflow](development.md).
2. **Shipping a change:** turn the kernel commit into a `00NN-*.patch` in pmaports, bump `pkgrel`, build the package,
   install it on the phone. The kernel package's install hook writes `boot`. See [Packaging](packaging.md).

## Design decisions

These choices shape everything else. Each one is explained in more detail on the page it links to.

| Decision | Why | Consequence |
|---|---|---|
| Use firmware **in place** from the stock partitions, mounted read-only ([firmware](firmware-and-coprocessors.md)) | Qualcomm firmware is signed per OEM and can't be redistributed. The phone already has the right versions. | Stock `modem`, `vendor`, `dsp`, `bluetooth` and `persist` must be intact. DT firmware names are bare (`modem.mdt`). |
| **Sibling mainline boards as templates**, downstream DT as ground truth ([development](development.md#where-the-facts-come-from)) | raphael (Mi 9T Pro) uses the same panel and Wi-Fi/BT supplies, and its DT already follows mainline conventions. Xiaomi's downstream DT has the real voltages and GPIOs. | Most nodes are copied from raphael, then corrected against `kernel/downstream-reference/`. |
| **No new kernel drivers where an existing one fits** | Less code to maintain or upstream. | The panel reuses `panel-samsung-ams639rq08`. Touch reuses ST's downstream FTM5 driver, built a second time for I2C. |
| **Test from RAM, flash only what boots** ([development](development.md#the-dt-loop)) | `fastboot boot` never writes `boot`, so a bad DTB costs a reboot, not a recovery. | `scripts/test-dtb.sh` builds the test image on the phone so the kernel and initramfs match exactly. |
| **Conservative speaker gain** ([audio](subsystems/audio.md)) | Xiaomi protects the speaker with DSP firmware and per-unit calibration. We don't run either. | Analog gain is 10 (Xiaomi uses 17 with protection). Don't raise it. |
| **The Wi-Fi MAC comes from `persist`, the BT address from `bootmac`** ([wifi](subsystems/wifi.md), [bluetooth](subsystems/bluetooth.md)) | ath10k picks a random MAC each boot. The BT chip has no address of its own. | A udev helper sets the real Wi-Fi MAC. bootmac's Wi-Fi rule is masked so it doesn't overwrite it. |
