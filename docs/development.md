# Development workflow

How to change something and get it onto the phone safely. If you only want to install, the
[README quick start](../README.md#quick-start) is enough.

- [Environment](#environment)
- [Where the facts come from](#where-the-facts-come-from)
- [The DT loop](#the-dt-loop)
- [Packaging a change](#packaging-a-change)
- [Kernel builds](#kernel-builds)
- [Testing a single module](#testing-a-single-module)
- [Conventions](#conventions)

## Environment

`setup-host.sh` creates everything. On macOS, pmbootstrap needs a Linux VM. On Linux, it runs on the host. The scripts
hide the difference behind `vmsh` (in `scripts/common.sh`).

```mermaid
flowchart TB
    subgraph Mac["macOS host (Apple silicon)"]
        repoM["this repo"]
        fbM["fastboot (android-platform-tools)"]
        tpM["tinyproxy"]
        subgraph VM["OrbStack VM 'pmos'"]
            pmbM["pmbootstrap 3.12.1<br/>/opt/pmbootstrap"]
            workM["~/.local/var/pmbootstrap<br/>work dir, cache_git/pmaports"]
            ktM["~/src/linux-v7.0.0-sm8150"]
        end
    end
    subgraph Lin["Linux host"]
        repoL["this repo"]
        fbL["fastboot, tinyproxy, nc"]
        pmbL["pmbootstrap 3.12.1<br/>~/.local/share/pmbootstrap"]
        workL["~/.local/var/pmbootstrap"]
        ktL["~/src/linux-v7.0.0-sm8150"]
    end
    phone["Mi 9 over USB<br/>ssh 172.16.42.1 / fastboot"]

    repoM -- "vmsh: orb -m pmos sh -c" --> VM
    repoL -- "vmsh: sh -c" --> pmbL
    fbM --> phone
    fbL --> phone
```

What `setup-host.sh` does, in order (idempotent, 10–20 min):

```mermaid
flowchart LR
    s1["1. Tools<br/>macOS: brew + OrbStack<br/>Linux: check only"] --> s2["2. pmbootstrap 3.12.1<br/>VM or host"]
    s2 --> s3["3. pmbootstrap init,<br/>fetch cepheus.bundle,<br/>cherry-pick onto pmaports main"]
    s3 -- "conflict" --> s3b["reset to the exact<br/>bundle state (older)"]
    s3 --> s4["4. Kernel tree:<br/>v7.0.0-sm8150 tarball,<br/>git init, apply 0*.patch<br/>one commit each, olddefconfig"]
    s3b --> s4
    s4 --> s5["Verify: build DTB,<br/>compare with release DTB"]
```

| Thing | Path (VM on macOS, host on Linux) |
|---|---|
| pmbootstrap work dir | `~/.local/var/pmbootstrap` |
| pmaports (main + our commits) | `~/.local/var/pmbootstrap/cache_git/pmaports` |
| Kernel package | `…/pmaports/device/testing/linux-postmarketos-qcom-sm8150/` |
| Device package | `…/pmaports/device/testing/device-xiaomi-cepheus/` |
| Built packages | `~/.local/var/pmbootstrap/packages/edge/aarch64/` |
| Kernel tree | `~/src/linux-v7.0.0-sm8150` (git: `base` + one commit per patch) |
| The DTS | `~/src/linux-v7.0.0-sm8150/arch/arm64/boot/dts/qcom/sm8150-xiaomi-cepheus.dts` |

Settings live in `scripts/common.sh` and can be overridden from the environment: `PHONE_IP` (172.16.42.1),
`PHONE_USER` (user), `PHONE_PASS` (cepheus), `VM` (pmos).

## Where the facts come from

```mermaid
flowchart LR
    ds["Xiaomi downstream DT<br/>MiCode/Xiaomi_Kernel_OpenSource<br/>branch cepheus-p-oss<br/>(copies in kernel/downstream-reference/)"]
    sib["Sibling mainline boards<br/>raphael (Mi 9T Pro, same panel),<br/>vayu, nabu"]
    log["The phone itself<br/>dmesg, /proc/cmdline,<br/>stock partitions"]
    ds -- "ground truth:<br/>voltages, GPIOs, addresses,<br/>firmware names" --> dts["sm8150-xiaomi-cepheus.dts"]
    sib -- "template:<br/>mainline node shapes,<br/>bindings, driver choice" --> dts
    log -- "what actually happens" --> dts
```

Rule of thumb: take the **shape** from raphael and the **numbers** from downstream. When the two disagree, downstream wins
(UFS VCC is the example: mainline's value was wrong for this phone).

## The DT loop

Seconds per iteration, nothing flashed.

```mermaid
flowchart TB
    edit["Edit the DTS in the kernel tree"] --> build["scripts/vm-build-dtb.sh<br/>→ images/test.dtb (seconds)"]
    build --> test["scripts/test-dtb.sh<br/>boot.img built on the phone,<br/>fastboot boot (RAM only)"]
    test --> wait["wait ~60 s<br/>scripts/pm uptime"]
    wait -- "no answer" --> tn{"ping 172.16.42.1?"}
    tn -- "yes" --> shell["scripts/tn 'tail -40 /pmOS_init.log'"]
    tn -- "no" --> fb["Volume Down + Power → fastboot,<br/>or just reboot: flashed boot is untouched"]
    wait -- "up" --> check["scripts/pms 'dmesg | ...'<br/>ask someone to look at the screen"]
    check -- "not right" --> edit
    shell --> edit
    fb --> edit
    check -- "works" --> commit["git commit in the kernel tree"]
    commit --> pkg["Package it (next section)"]
```

```sh
$EDITOR ~/src/linux-v7.0.0-sm8150/arch/arm64/boot/dts/qcom/sm8150-xiaomi-cepheus.dts   # in the VM on macOS (orb -m pmos)
scripts/vm-build-dtb.sh     # -> images/test.dtb
scripts/test-dtb.sh         # builds a boot.img on the phone with the test DTB, fastboot-boots it
scripts/pm 'dmesg | tail'   # a normal reboot returns to the flashed image
```

If you're working over ssh, you can't see the screen. At each step that changes the display, have someone look at the
phone or send a screenshot.

## Packaging a change

```mermaid
sequenceDiagram
    participant KT as Kernel tree
    participant PA as pmaports
    participant PMB as pmbootstrap
    participant R as repo apks/
    participant P as Phone

    KT->>KT: git commit (one logical change)
    KT->>PA: git diff HEAD~1 > linux-postmarketos-qcom-sm8150/00NN-cepheus-WHAT.patch
    PA->>PA: add to source=, bump pkgrel
    PA->>PMB: pmbootstrap checksum linux-postmarketos-qcom-sm8150
    PMB->>PMB: pmbootstrap build --force linux-postmarketos-qcom-sm8150 (~4–7 min)
    PA->>PA: git commit in pmaports
    PMB->>R: copy .apk from packages/edge/aarch64/
    R->>P: scripts/pcp file.apk phone:/tmp/
    P->>P: apk add --allow-untrusted /tmp/file.apk (writes boot)
    P->>P: reboot, re-test
    PA->>R: git bundle create pmaports/cepheus.bundle $(cat pmaports/BASE_COMMIT)..HEAD
    PA->>R: git format-patch → pmaports/000N-*.patch, copy kernel/00NN-*.patch
```

After every pmaports commit, refresh the bundle (and the patch copies) so `setup-host.sh` on a new machine reproduces
your state:

```sh
cd ~/.local/var/pmbootstrap/cache_git/pmaports
git bundle create /path/to/repo/pmaports/cepheus.bundle $(cat /path/to/repo/pmaports/BASE_COMMIT)..HEAD
```

Details of the package structure and the patch ↔ `pkgrel` mapping are in [Packaging](packaging.md).

## Kernel builds

- Full package build: about 7 min on 17 cores, about 4 min warm.
- The package builds with **`LLVM=1`**. Build DTBs and modules in the tree with `LLVM=1` too, or you'll compare different
  toolchains' output.
- On x86_64 Linux hosts pmbootstrap cross-compiles. On Apple silicon the VM is native aarch64.
- The kernel's local version is `-sm8150-aurora` (`CONFIG_LOCALVERSION` in the package config, pmaports patch 0008).
  Drop it when upstreaming.

## Testing a single module

Faster than a package build when you're iterating on one driver: build the module in the kernel tree (with `LLVM=1`),
copy it over, and load it by hand.

```sh
# Only if the running kernel is an older build than the tree: strip BTF, or loading fails with "BTF: -22"
vmsh 'llvm-objcopy --remove-section=.BTF path/to/module.ko'
scripts/pcp path/to/module.ko phone:/tmp/ && scripts/pms 'insmod /tmp/module.ko'
```

The module's version magic still has to match the running kernel's release string.

## Conventions

- **One kernel patch per feature**, numbered `00NN-cepheus-<what>.patch`, applied in order on top of the package's own
  `0001`–`0003`. The DTS ends up as `kernel/sm8150-xiaomi-cepheus.dts.final`. Keep that copy in sync.
- **Comments in the DTS say where a value came from** (`/* downstream cepheus-sm8150.dtsi: … */`). Keep doing that.
- **Phone-side files** go in `phone-config/` under their real path *and* get an install line in `scripts/phone-setup.sh`.
  Keep the two in sync.
- Commits in the build environment without a git identity: `git -c user.name=… -c user.email=… commit`.
- Background jobs over ssh die with the session: `systemd-run --unit=x --collect sh -c '…'` on the phone, `setsid nohup`
  in the VM.
- `/tmp` on the phone is tmpfs: test images there disappear on reboot.
