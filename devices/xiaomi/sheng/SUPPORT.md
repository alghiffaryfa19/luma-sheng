# Xiaomi Pad 6S Pro 12.4 (`xiaomi/sheng`) Hardware Support Matrix

| Subsystem | Status | Package / Driver | Notes |
|---|---|---|---|
| SoC / Boot | Working | `qcom/sm8550` (`sm8550-xiaomi-sheng.dtb`) | A/B slot management via `qbootctl` (`luma-sheng-boot-success.service`) |
| UFS Storage | Working | `ufshcd-qcom` (built-in, 4096B sectors) | Supports both `PARTLABEL=linux` dual-boot and `userdata` GPT layout |
| Display (3048x2032 @ 144Hz) | Working | `msm_drm` / `dpu1` + Panel driver | Native resolution, high refresh rate, brightness control |
| Touchscreen & Stylus | Working | `xiaomi-sheng-thp` + `novatek_nt36532` | Finger multitouch and Xiaomi Focus Pen input via THP userspace daemon |
| Stylus Battery / Status | Working | `xiaomi-pen-status` | Bluetooth auto-connect and status indicator |
| Wi-Fi 7 (WCN7850) | Working | `ath12k` + `luma-sheng-firmware` | Requires `board-2.bin` and `board.bin` alias in `/usr/lib/firmware/ath12k/WCN7850/hw2.0/` |
| Bluetooth | Working | `btqca` + `qca/hmtbtfw20.tlv` | Audio (A2DP/HFP), HID accessories and stylus |
| Audio (6x Speakers + Mic) | Working | `sheng-audio-fix` + `alsa-xiaomi-sheng` | SoundWire + WCD938x + 6x Cirrus Logic CS35L43 amplifiers + AudioReach topology |
| Sensors & Auto-Rotation | Working | `fastrpc` + `libssc` + `iio-sensor-proxy` + `sheng-sensors` | `adsprpcd-sensorspd.service` + patched `iio-sensor-proxy` + `sheng-fake-tablet-mode` |
| Pogo-pin Keyboard & Touchpad | Working | `sheng-devauth` + `xiaomi-sheng-keyboard-helper` + `xiaomi-sheng-keyboard-backlight` | QTEE authentication, hinge angle disable, mic mute LED, and keyboard backlight |
| Fast Charging (120W MIPPS) | Working | `xiaomi-mipps-auth` + `xiaomi-charger-mode` | Negotiates MIPPS fast charging and off-mode charging display |
| Fingerprint (FPC1553) | Working | `xiaomi-sheng-fingerprint` (`fprintd`) | Uses `qteesupplicant` + `sfs_config` + custom `libfprint-2` backend |
| GPU (Adreno 740) | Working | `msm` (`a740_sqe.fw`, `gmu_gen70200.bin`, `a740_zap.mbn`) | Hardware-accelerated Wayland (Freedreno / Turnip Vulkan) and Android container |
| Power Key & Display Sleep | Working | `sheng-gnome-fix` + `luma-sheng-platform` | Blanks/wakes display via Mutter `PowerSaveMode`; deep S3 suspend disabled (`AllowSuspend=no`) |

