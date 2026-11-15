# SPDX-License-Identifier: Apache-2.0
"""Xiaomi Pad 6S Pro 12.4 (sheng) rules that the shared device checks cannot express."""
import re
import tomllib
import unittest
from pathlib import Path

DEVICE = Path(__file__).resolve().parents[1]
ROOT = DEVICE.parents[2]


def toml(path):
    return tomllib.loads(path.read_text())


class XiaomiSheng(unittest.TestCase):
    def setUp(self):
        self.device = toml(DEVICE / "device.toml")
        self.boot = toml(DEVICE / "boot.toml")
        self.soc = toml(ROOT / "socs" / "qcom" / "sm8550" / "soc.toml")
        self.guide = (DEVICE / "INSTALL.md").read_text()

    def test_uses_the_shared_sm8550_soc(self):
        self.assertEqual(self.device["soc"], "qcom/sm8550")
        self.assertEqual(self.device["form_factor"], "tablet")
        self.assertEqual(self.soc["kernel"]["branch"], "sm8550")
        self.assertEqual(self.soc["boot"]["page_size"], 4096)

    def test_guide_covers_both_dual_boot_and_kit_order(self):
        # Dual-boot on PARTLABEL=linux and single-boot kit on userdata are both documented.
        self.assertIn("fastboot flash linux ", self.guide)
        names = {
            "userdata": "luma-nightly-<build>-aarch64-disk.sparse",
            "kit": "luma-sheng-<version>-kit.sparse",
            "boot": "luma-sheng-<version>-boot.img",
            "dtbo": "dtbo-blank.img",
        }
        commands = "\n".join("fastboot " + line.format(**names) for line in self.device["kit"]["flash"])
        self.assertIn(commands, self.guide)

    def test_guide_never_touches_preserved_partitions(self):
        must_preserve = {"persist", "fsg", "fsc", "modemst1", "modemst2", "secdata", "devinfo"}
        self.assertLessEqual(must_preserve, set(self.device["install"]["preserve"]))
        self.assertNotRegex(
            self.guide,
            r"fastboot\s+(flash|erase|format)\s+(persist|fsg|fsc|modemst1|modemst2|secdata|devinfo|xbl|abl|tz|hyp)",
        )

    def test_blank_dtbo_and_boot_partition_sizes(self):
        dtbo = self.boot["dtbo"]
        self.assertEqual(dtbo["policy"], "blank")
        self.assertEqual(dtbo["size"], 24 * 1024 * 1024)
        self.assertEqual(self.boot["partition_size"], 96 * 1024 * 1024)
        self.assertEqual(self.boot["avb"]["vbmeta"], "untouched")

    def test_fuse_and_selinux_and_binder_are_built_in(self):
        fragments = self.device["kernel"]["config_fragments"]
        text = "".join((ROOT / f).read_text() for f in fragments)
        for option in (
            "CONFIG_FUSE_FS=y",
            "CONFIG_OVERLAY_FS=y",
            "CONFIG_EROFS_FS=y",
            "CONFIG_SECURITY_SELINUX=y",
            "CONFIG_ANDROID_BINDER_IPC=y",
            "CONFIG_ANDROID_BINDERFS=y",
            "CONFIG_DMABUF_HEAPS=y",
            "CONFIG_DMABUF_HEAPS_SYSTEM=y",
        ):
            self.assertRegex(text, rf"(?m)^{re.escape(option)}$")

    def test_device_repo_lists_required_sheng_packages(self):
        repo = self.device["device_repo"]
        self.assertEqual(repo["replace"], ["iio-sensor-proxy"])
        required = {
            "kernel-modules-luma-sheng",
            "luma-sheng-firmware",
            "luma-sheng-platform",
            "libssc",
            "fastrpc",
            "xiaomi-sheng-thp",
            "sheng-devauth",
            "xiaomi-mipps-auth",
            "xiaomi-charger-mode",
            "xiaomi-sheng-keyboard-helper",
            "xiaomi-sheng-keyboard-backlight",
            "xiaomi-pen-status",
            "xiaomi-sheng-fingerprint",
            "sheng-sensors",
            "alsa-xiaomi-sheng",
            "sheng-audio-fix",
            "sheng-gnome-fix",
            "qbootctl",
        }
        self.assertLessEqual(required, set(repo["install"]))

    def test_firmware_is_listed_not_shipped(self):
        rows = (DEVICE / "firmware.manifest").read_text().splitlines()
        device_files = [r.split("\t")[3] for r in rows[1:] if r.startswith("F\t")]
        sheng_files = [p for p in device_files if p.startswith("qcom/sm8550/")]
        self.assertEqual(len(device_files), self.device["firmware"]["files"])
        self.assertGreaterEqual(len(sheng_files), 14)
        blobs = [p for p in DEVICE.rglob("*") if p.suffix in (".mbn", ".mdt", ".bin", ".zst", ".jsn", ".elf", ".wmfw")]
        self.assertEqual(blobs, [])

    def test_sheng_rpm_specs_are_ostree_compatible(self):
        rpm_dir = ROOT / "packaging" / "rpm"
        specs = [
            "luma-sheng-platform.spec",
            "luma-sheng-firmware.spec",
            "kernel-modules-luma-sheng.spec",
            "libssc.spec",
            "fastrpc.spec",
            "iio-sensor-proxy.spec",
            "xiaomi-sheng-thp.spec",
            "sheng-devauth.spec",
            "xiaomi-mipps-auth.spec",
            "xiaomi-charger-mode.spec",
            "xiaomi-sheng-keyboard-helper.spec",
            "xiaomi-sheng-keyboard-backlight.spec",
            "xiaomi-pen-status.spec",
            "xiaomi-sheng-fingerprint.spec",
            "sheng-sensors.spec",
            "alsa-xiaomi-sheng.spec",
            "sheng-audio-fix.spec",
            "sheng-gnome-fix.spec",
        ]
        for spec_name in specs:
            spec_path = rpm_dir / spec_name
            self.assertTrue(spec_path.is_file(), f"missing spec: {spec_name}")
            text = spec_path.read_text()
            self.assertNotIn("Conflicts:      linux-firmware", text)
            self.assertNotRegex(text, r"(?m)^/usr/local/")


if __name__ == "__main__":
    unittest.main()
