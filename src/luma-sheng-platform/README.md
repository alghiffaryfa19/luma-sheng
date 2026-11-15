# luma-sheng-platform

Xiaomi Pad 6S Pro 12.4 (`xiaomi,sheng`) platform services for the shared Luma ARM image, installed from the `xiaomi-sheng` device repository as a client-side layer:

- the A/B slot marked successful after each boot (`qbootctl -m`), except while `luma-device-boot` has a boot image on trial;
- wall clock kept across shutdown (`/var/lib/luma/clock`, `luma-clock-restore.service`, `luma-clock-save.timer`);
- Wi-Fi power-save policy (`wifi.powersave=2`) for Qualcomm FastConnect 7800 (`ath12k` WCN7850);
- the handheld/tablet device class (`/etc/luma-device-class`, `LUMA_DEVICE_CLASS=handheld`) and shared handheld dconf defaults;
- systemd preset and `.wants` links enabling all Xiaomi Pad 6S Pro (`sheng`) hardware services (`xiaomi-sheng-thp`, `sheng-devauth`, `xiaomi-mipps-auth`, `xiaomi-charger-mode`, `xiaomi-sheng-keyboard-helper-angle`, `adsprpcd-sensorspd`, `sheng-audio-init`, `sheng-fake-tablet-mode`, `sheng-power-key-toggle`, `qteesupplicant`, `sfsconfig`).

