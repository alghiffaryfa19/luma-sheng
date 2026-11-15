# Luma on the Xiaomi Pad 6S Pro 12.4 (`sheng`)

The Xiaomi Pad 6S Pro 12.4 (`xiaomi,sheng`, Qualcomm Snapdragon 8 Gen 2 / `SM8550`) runs the Luma ARM image (`luma/1/aarch64/nightly`), plus the `sheng` device package (`luma-xiaomi-sheng`).

Two installation modes are supported:

1. **Mode A — Dual-Boot on `PARTLABEL=linux` (Recommended for testers)**: Keeps Android on Slot A (`userdata` + `super`) and installs Luma into a dedicated `linux` partition on Slot B (`boot_b`, `dtbo_b`), matching the partition layout used by `debian-sheng` and `fedora-sheng`.
2. **Mode B — Single-Boot on `userdata` (Standard Luma Device Kit)**: Replaces `userdata` with the generic Luma phone/tablet GPT image (`LumaBoot` + `LumaRoot`, 4096-byte sectors) and applies `luma-sheng-<version>-kit.sparse` on first boot.

> [!WARNING]
> Back up all important data before modifying partitions or flashing boot slots. Never flash or erase `persist`, `secdata`, `devinfo`, `fsg`, `fsc`, `modemst1`, `modemst2`, or bootloader (`xbl_*`, `abl_*`, `tz_*`, `hyp_*`) partitions.

---

## Prerequisites

- A Xiaomi Pad 6S Pro 12.4 (`sheng`) with an **unlocked bootloader**
- A USB-C data cable and a host computer with `fastboot` (Android Platform Tools 35+)
- Factory firmware files from the device's stock HyperOS firmware package or [ianchb/sheng-firmware](https://github.com/ianchb/sheng-firmware) matching the SHA-256 digests in `firmware.manifest`

---

## Mode A: Dual-Boot on `PARTLABEL=linux` (Slot B)

Use this mode if your tablet already has a `linux` partition (created by shrinking `userdata` in TWRP with `parted`, as in `debian-sheng` / `fedora-sheng`) and you want to keep Android or switch cleanly from `debian-sheng` / `fedora-sheng`.

### Files Needed (from the `Build Luma Sheng` workflow or local build)

- `luma-sheng-nightly-<build>-aarch64-linux.img` (OSTree `LumaRoot` image with all `sheng` RPM packages pre-layered)
- `luma-sheng-<version>-boot-linux.img` (Kernel + `sm8550-xiaomi-sheng.dtb` + Luma OSTree initramfs targeting `PARTLABEL=linux`)
- `dtbo-blank.img` (24 MiB blank DTBO image)

### Steps

1. Verify checksums:
   ```sh
   sha256sum -c SHA256SUMS
   ```
2. Boot the tablet into Fastboot mode (hold **Volume Down + Power**) and verify connection:
   ```sh
   fastboot devices
   fastboot getvar product
   ```
   `product` must report `sheng`.
3. Test the boot image in RAM first without modifying the boot partition (`fastboot boot`), or flash to Slot B:
   ```sh
   fastboot flash dtbo_b dtbo-blank.img
   fastboot flash boot_b luma-sheng-<version>-boot-linux.img
   fastboot flash linux luma-sheng-nightly-<build>-aarch64-linux.img
   fastboot --set-active=b
   fastboot boot luma-sheng-<version>-boot-linux.img
   ```
4. On first boot, `luma-grow-root.service` expands the `LumaRoot` ext4 filesystem to fill the `linux` partition, `luma-sheng-boot-success.service` marks Slot B successful via `qbootctl -m`, and Luma starts the graphical session. Default login is `luma` / `1234` (if built with the standard userdata user) or initial setup via `luma-setup`.

---

## Mode B: Single-Boot on `userdata` (Standard Luma Device Kit)

Use this mode to dedicate the entire `userdata` partition to Luma using the standard Luma ARM nightly image and device kit. **This erases all Android user data.**

### Files Needed

| File | Description |
|---|---|
| `luma-nightly-<build>-aarch64-disk.sparse` | The generic Luma ARM userdata image (`LumaBoot` + `LumaRoot`, 4096-byte UFS sectors) |
| `luma-sheng-<version>-kit.sparse` | The `xiaomi/sheng` offline device repository (`LumaBoot` sparse image) |
| `luma-sheng-<version>-boot.img` | Boot image with Luma's shared OSTree resolver (`pmos_root_uuid`, `pmos_boot_uuid`) |
| `dtbo-blank.img` | 24 MiB blank `dtbo` image |

### Steps

1. Verify checksums:
   ```sh
   sha256sum -c SHA256SUMS
   ```
2. Enter Fastboot mode and confirm the device:
   ```sh
   fastboot devices
   fastboot getvar product
   ```
   `product` must report `sheng`.
3. Flash the generic userdata image, the device kit, blank `dtbo`, and boot image in order:

```sh
fastboot flash userdata luma-nightly-<build>-aarch64-disk.sparse
fastboot flash userdata luma-sheng-<version>-kit.sparse
fastboot flash dtbo_a dtbo-blank.img
fastboot flash dtbo_b dtbo-blank.img
fastboot flash boot_a luma-sheng-<version>-boot.img
fastboot flash boot_b luma-sheng-<version>-boot.img
fastboot boot luma-sheng-<version>-boot.img
```
4. Leave the tablet alone for 5–8 minutes on the first start. `luma-device-layer.service` verifies the kit, layers the `luma-xiaomi-sheng` packages offline (`kernel-modules-luma-sheng`, `luma-sheng-firmware`, `luma-sheng-platform`, `xiaomi-sheng-thp`, `libssc`, `fastrpc`, `sheng-audio-fix`, `alsa-xiaomi-sheng`, `sheng-gnome-fix`, etc.), and restarts once automatically.

---

## Safety Rules

- Never erase or flash `persist`, `secdata`, `devinfo`, `fsg`, `fsc`, `modemst1`, or `modemst2`.
- Never relock the bootloader while running a custom boot image, and never change `vbmeta` unless required by your existing Android unlock setup.
