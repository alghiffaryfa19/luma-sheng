# Porting Luma OS Mobile — Xiaomi Pad 6S Pro 12.4 (`xiaomi/sheng`)

Dokumen ini merangkum hasil porting **Luma OS Mobile** untuk **Xiaomi Pad 6S Pro 12.4 (`xiaomi/sheng`, Qualcomm Snapdragon 8 Gen 2 / `SM8550`)** mengikuti panduan resmi [`https://simplyluma.com/agents/port-a-phone.md`](https://simplyluma.com/agents/port-a-phone.md) serta mengadaptasi paket spesifik perangkat dari [`mumuxiao722/fedora-sheng`](https://github.com/mumuxiao722/fedora-sheng) dan [`mumuxiao722/sheng-gnome-fix`](https://github.com/mumuxiao722/sheng-gnome-fix).

---

## 1. Struktur File Porting di Repository `luma` (Branch `devices/sheng`)

Seluruh manifest perangkat, SoC, konfigurasi kernel, paket RPM, dan skrip build telah disiapkan di `.`:

### Manifest Perangkat & SoC (Standar `port-a-phone.md`)
- [`socs/qcom/sm8550/soc.toml`](socs/qcom/sm8550/soc.toml) — Manifest SoC Qualcomm Snapdragon 8 Gen 2 (`SM8550` / `kalama`), offset `android-boot-v2` (`page_size = 4096`, `kernel = 0x8000`, `ramdisk = 0x01000000`, `tags = 0x01e00000`, `dtb = 0x01f00000`).
- [`devices/xiaomi/sheng/device.toml`](devices/xiaomi/sheng/device.toml) — Manifest utama Xiaomi Pad 6S Pro 12.4 (`xiaomi,sheng`, `qcom,sm8550`), konfigurasi layar 12.4" 3048×2032 @ 144Hz, daftar `[device_repo]` (19 paket `install` + 1 paket `replace`), `[kit]`, dan `[boot_update]`.
- [`devices/xiaomi/sheng/boot.toml`](devices/xiaomi/sheng/boot.toml) — Kebijakan boot (`boot_a`/`boot_b` 96 MiB, `dtbo` blank 24 MiB, `vbmeta` untouched, `udmabuf.size_limit_mb=256`, `enforcing=1`).
- [`devices/xiaomi/sheng/firmware.manifest`](devices/xiaomi/sheng/firmware.manifest) — Daftar 37 file firmware + 1 symlink beserta SHA-256 (tanpa menyimpan binary blob di dalam Git sesuai aturan Section 10 `port-a-phone.md`).
- [`devices/xiaomi/sheng/INSTALL.md`](devices/xiaomi/sheng/INSTALL.md) — Panduan instalasi lengkap untuk **Mode A (Dual-Boot `PARTLABEL=linux` di Slot B)** dan **Mode B (Single-Boot `userdata` Device Kit)**.
- [`devices/xiaomi/sheng/SUPPORT.md`](devices/xiaomi/sheng/SUPPORT.md) — Tabel status dukungan hardware (`Working`, `Partial`, `Not working`).
- [`devices/xiaomi/sheng/tests/test_xiaomi_sheng.py`](devices/xiaomi/sheng/tests/test_xiaomi_sheng.py) — Unit test otomatis untuk memvalidasi manifest, Kconfig fragment, firmware manifest, dan kompatibilitas OSTree dari seluruh `.spec` RPM.
- [`config/kernel/sm8550-sheng.config`](config/kernel/sm8550-sheng.config) & [`config/kernel/sheng.fragment`](config/kernel/sheng.fragment) — Defconfig dasar SM8550 ditambah fragment wajib Luma OS (`CONFIG_FUSE_FS=y`, `CONFIG_OVERLAY_FS=y`, `CONFIG_EROFS_FS=y`, `CONFIG_SECURITY_SELINUX=y`, `CONFIG_ANDROID_BINDERFS=y`, `CONFIG_DMABUF_HEAPS=y`).

---

## 2. Adaptasi Paket RPM `fedora-sheng` untuk Luma OS (`rpm-ostree`)

Berbeda dengan Fedora konvensional di `fedora-sheng` yang menggunakan rootfs mutable, Luma OS menggunakan **OSTree (`rpm-ostree`)** dengan `/usr` immutable dan `/usr/local -> /var/usrlocal`. Berikut 18 spesifikasi RPM di [`packaging/rpm/`](packaging/rpm/) beserta penyesuaian khusus Luma OS:

| Paket RPM | File Spec | Fungsi & Penyesuaian untuk Luma OS (`rpm-ostree`) |
|---|---|---|
| `luma-sheng-platform` | [`luma-sheng-platform.spec`](packaging/rpm/luma-sheng-platform.spec) | Paket platform Luma (`etc/luma-device-class=tablet`, `etc/luma/update.conf`, `boot.automount`, `luma-sheng-boot-success.service` (`qbootctl -m`), `luma-clock-save/restore`, Wi-Fi WCN7850 power-save off). Symlink `.wants` dibuat langsung di `%install` agar aktif pada offline compose. |
| `luma-sheng-firmware` | [`luma-sheng-firmware.spec`](packaging/rpm/luma-sheng-firmware.spec) | Menggantikan `firmware-xiaomi-sheng.spec`. **Menghapus `Conflicts: linux-firmware`** (karena `linux-firmware` ada di base commit Luma) dan memasang 37 firmware terverifikasi SHA-256 ke `/usr/lib/firmware/updates/` serta `/usr/lib/firmware/qcom/sm8550/xiaomi/sheng/`. Menyediakan `Provides: firmware-xiaomi-sheng`. |
| `kernel-modules-luma-sheng` | [`kernel-modules-luma-sheng.spec`](packaging/rpm/kernel-modules-luma-sheng.spec) | Menggantikan `kernel-sheng.spec`. Hanya memasang `/usr/lib/modules/<kver>` dan `/usr/lib/luma/device-boot/xiaomi-sheng` **tanpa menulis ke `/boot/*`** agar `rpm-ostree` dapat melakukan layering. |
| `fastrpc` | [`fastrpc.spec`](packaging/rpm/fastrpc.spec) | Daemon & library FastRPC (`adsprpcd-sensorspd.service`). Menambahkan `/etc/ld.so.conf.d/fastrpc.conf` (`/usr/lib`) agar `ldconfig` di Fedora `aarch64` mengenali `libadsprpc.so.1`. |
| `libssc` | [`libssc.spec`](packaging/rpm/libssc.spec) | Library Qualcomm Snapdragon Sensor Core (`linux-sheng` branch). |
| `iio-sensor-proxy` | [`iio-sensor-proxy.spec`](packaging/rpm/iio-sensor-proxy.spec) | Menggantikan (`[device_repo] replace`) `iio-sensor-proxy` bawaan Fedora dengan backend `libssc` untuk rotasi layar otomatis & sensor cahaya. |
| `xiaomi-sheng-thp` | [`xiaomi-sheng-thp.spec`](packaging/rpm/xiaomi-sheng-thp.spec) | Userspace Touch Host Processing driver untuk layar sentuh FocalTech FT3683G + Xiaomi Smart Pen Gen 2. |
| `sheng-devauth` | [`sheng-devauth.spec`](packaging/rpm/sheng-devauth.spec) | Daemon otentikasi magnetik Xiaomi Smart Pen Gen 2. |
| `xiaomi-mipps-auth` | [`xiaomi-mipps-auth.spec`](packaging/rpm/xiaomi-mipps-auth.spec) | Otentikasi Xiaomi Smart Touch Keyboard melalui protokol MiPPS. |
| `xiaomi-charger-mode` | [`xiaomi-charger-mode.spec`](packaging/rpm/xiaomi-charger-mode.spec) | Handler mode off-mode charging saat tablet dicolok charger dalam keadaan mati. |
| `xiaomi-sheng-keyboard-helper` | [`xiaomi-sheng-keyboard-helper.spec`](packaging/rpm/xiaomi-sheng-keyboard-helper.spec) | Daemon hotplug pogo-pin keyboard resmi. |
| `xiaomi-sheng-keyboard-backlight` | [`xiaomi-sheng-keyboard-backlight.spec`](packaging/rpm/xiaomi-sheng-keyboard-backlight.spec) | **Diperbaiki untuk OSTree**: memindahkan binary dari `/usr/local/sbin/kbd-backlight*` (dilarang oleh `rpm-ostree`) ke `/usr/bin/kbd-backlight*` serta mem-patch unit systemd & udev rules. |
| `xiaomi-pen-status` | [`xiaomi-pen-status.spec`](packaging/rpm/xiaomi-pen-status.spec) | Pembaca level baterai stylus Xiaomi Smart Pen. |
| `xiaomi-sheng-fingerprint` | [`xiaomi-sheng-fingerprint.spec`](packaging/rpm/xiaomi-sheng-fingerprint.spec) | Driver FPC1553 QTEE (`qteesupplicant`, `sfsconfig`, `libfprint-2.so` override). Diubah `Requires: firmware-xiaomi-sheng` menjadi `Requires: luma-sheng-firmware`. |
| `sheng-sensors` | [`sheng-sensors.spec`](packaging/rpm/sheng-sensors.spec) | Konfigurasi sensor QCOM ADSP/CDSP (`sensors.service` + `99-qcom-CDSP.rules`). |
| `alsa-xiaomi-sheng` | [`alsa-xiaomi-sheng.spec`](packaging/rpm/alsa-xiaomi-sheng.spec) | File profil ALSA UCM2 untuk 8 speaker Cirrus Logic CS35L41 (`SM8550-MTP-WCD9385-VA-DMIC`). |
| `sheng-audio-fix` | [`sheng-audio-fix.spec`](packaging/rpm/sheng-audio-fix.spec) | Workaround speaker pop & disable suspend audio node WirePlumber. |
| `sheng-gnome-fix` | [`sheng-gnome-fix.spec`](packaging/rpm/sheng-gnome-fix.spec) | Fake tablet mode switch (`SW_TABLET_MODE`), tombol power sebagai toggle layar (karena deep sleep S3 belum bisa wake di SM8550), dan penonaktifan suspend sistem. |

---

## 3. Cara Build (Lokal via Podman/Docker atau GitHub Actions)

### Opsi 1: GitHub Actions (Otomatis)
Workflow GitHub Actions telah disediakan di [`.github/workflows/build-luma-sheng.yml`](.github/workflows/build-luma-sheng.yml).
1. Push branch `devices/sheng` ke fork GitHub Anda.
2. Buka tab **Actions** → **Build Luma OS (Xiaomi Pad 6S Pro / sheng)** → klik **Run workflow**.
3. Pilih `boot_mode`:
   - `both` (default): Menghasilkan image **Mode A (`PARTLABEL=linux`)** sekaligus **Mode B (`userdata` Device Kit)**.
   - `linux`: Hanya menghasilkan image Dual-Boot untuk partisi `linux` (Slot B).
   - `userdata`: Hanya menghasilkan Device Kit standar Luma untuk partisi `userdata`.

### Opsi 2: Build Lokal di Mesin `aarch64` (Misalnya langsung di Tablet / Server ARM64)

1. **Build Kernel SM8550 Mainline dengan Kconfig Fragment Luma**:
   ```bash
   git clone --depth 1 --branch sheng-7.2.2 https://github.com/ianchb/sm8550-mainline.git /tmp/linux-sheng
   cp ./config/kernel/sm8550-sheng.config /tmp/linux-sheng/.config
   cat ./config/kernel/sheng.fragment >> /tmp/linux-sheng/.config
   cd /tmp/linux-sheng
   make ARCH=arm64 olddefconfig
   make -j"$(nproc)" ARCH=arm64 LOCALVERSION=-sm8550 Image.gz dtbs modules
   KREL=$(make -s ARCH=arm64 LOCALVERSION=-sm8550 kernelrelease)
   mkdir -p /tmp/kernel-staging
   make ARCH=arm64 LOCALVERSION=-sm8550 INSTALL_MOD_PATH=/tmp/kernel-staging modules_install
   cp arch/arm64/boot/Image.gz /tmp/kernel-staging/Image.gz
   cp arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb /tmp/kernel-staging/sm8550-xiaomi-sheng.dtb
   ```

2. **Build `boot.img` & `dtbo-blank.img`** ([`scripts/mobile/build-sheng-boot-image.sh`](scripts/mobile/build-sheng-boot-image.sh)):
   ```bash
   cd .
   ./scripts/mobile/build-sheng-boot-image.sh \
     --kernel /tmp/kernel-staging/Image.gz \
     --dtb /tmp/kernel-staging/sm8550-xiaomi-sheng.dtb \
     --modules-dir /tmp/kernel-staging/lib/modules \
     --mode both \
     --version 0.1.0 \
     --output-dir build/sheng-boot
   ```

3. **Build Seluruh 18 RPM `sheng` & Repo `rpm-md` di Kontainer Fedora** ([`scripts/devices/build-sheng-rpms.sh`](scripts/devices/build-sheng-rpms.sh)):
   ```bash
   git clone --depth 1 https://github.com/ianchb/sheng-firmware.git /tmp/sheng-firmware
   ./scripts/devices/build-sheng-rpms.sh \
     --output-dir build/sheng-repo \
     --firmware-dir /tmp/sheng-firmware \
     --kernel-modules-dir /tmp/kernel-staging \
     --kernel-release "$KREL" \
     --boot-image build/sheng-boot/luma-sheng-0.1.0-boot.img
   ```

4. **Build Rootfs OSTree (`PARTLABEL=linux`) & Device Kit (`userdata`)** ([`scripts/devices/build-sheng-image.sh`](scripts/devices/build-sheng-image.sh)):
   ```bash
   ./scripts/devices/build-sheng-image.sh \
     --device-repo build/sheng-repo \
     --boot-dir build/sheng-boot \
     --layout both \
     --version 0.1.0 \
     --output-dir build/sheng-images
   ```

---

## 4. Verifikasi Manifest & Unit Tests

Seluruh validasi skema JSON (`device.schema.json`, `boot.schema.json`, `soc.schema.json`) dan unit test pohon perangkat telah dijalankan dan lulus 100%:

```bash
cd .
python3 -B tools/check-devices.py --root .
python3 -B -m unittest tests/unit/test_device_tree.py devices/xiaomi/sheng/tests/test_xiaomi_sheng.py
```

