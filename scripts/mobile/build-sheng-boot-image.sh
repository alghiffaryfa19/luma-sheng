#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build the Xiaomi Pad 6S Pro 12.4 (xiaomi/sheng) Android boot image(s) and
# blank DTBO image using the parameters in socs/qcom/sm8550/soc.toml and
# devices/xiaomi/sheng/boot.toml.
#
# Supports two boot modes:
#   - linux    (Mode A): Dual-boot on PARTLABEL=linux (Slot B: boot_b + dtbo_b)
#                        preserving Android on Slot A.
#   - userdata (Mode B): Single-boot standard Luma Device Kit on userdata
#                        (LumaBoot UUID 032D-57AD + LumaRoot UUID 03797c05-cf87-4eda-adc4-6ce111baf2d3).
#   - both     (default): Builds both boot images + dtbo-blank.img.
#
# Usage:
#   scripts/mobile/build-sheng-boot-image.sh \
#     --kernel /path/to/Image.gz \
#     --dtb /path/to/sm8550-xiaomi-sheng.dtb \
#     [--modules-dir /path/to/modules_staging] \
#     [--base-initramfs /path/to/initramfs.cpio.gz] \
#     [--mode both|linux|userdata] \
#     [--version 0.1.0] \
#     --output-dir build/sheng-boot

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
kernel_image=""
dtb_file=""
modules_dir=""
base_initramfs=""
mode="both"
version="0.1.0"
output_dir="$repo_root/build/sheng-boot"

while [ $# -gt 0 ]; do
  case "$1" in
    --kernel) kernel_image=$(realpath -e "$2"); shift 2 ;;
    --dtb) dtb_file=$(realpath -e "$2"); shift 2 ;;
    --modules-dir) modules_dir=$(realpath -e "$2"); shift 2 ;;
    --base-initramfs) base_initramfs=$(realpath -e "$2"); shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,23p' "$0"
      exit 0
      ;;
    *)
      printf 'build-sheng-boot-image: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

[ -n "$kernel_image" ] || { printf 'build-sheng-boot-image: --kernel Image.gz is required\n' >&2; exit 2; }
[ -n "$dtb_file" ] || { printf 'build-sheng-boot-image: --dtb sm8550-xiaomi-sheng.dtb is required\n' >&2; exit 2; }

for tool in cpio gzip mkbootimg sha256sum truncate; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'build-sheng-boot-image: missing required tool: %s\n' "$tool" >&2
    exit 1
  }
done

mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")
work_dir=$(mktemp -d "$output_dir/work.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT INT TERM

# SM8550 (socs/qcom/sm8550/soc.toml) & sheng (devices/xiaomi/sheng/boot.toml) parameters
PAGE_SIZE=4096
BASE_ADDR=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x01e00000
DTB_OFFSET=0x01f00000
BOOT_PARTITION_MAX=$((96 * 1024 * 1024))
DTBO_BLANK_SIZE=$((24 * 1024 * 1024))

LUMA_BOOT_UUID="032D-57AD"
LUMA_ROOT_UUID="03797c05-cf87-4eda-adc4-6ce111baf2d3"
BASE_CMDLINE="console=tty0 earlycon clk_ignore_unused pd_ignore_unused rw quiet splash loglevel=4 systemd.show_status=auto udmabuf.size_limit_mb=256 enforcing=1"

# 1. Generate 24 MiB blank dtbo image (devices/xiaomi/sheng/boot.toml: policy = "blank", size = 25165824)
dtbo_out="$output_dir/dtbo-blank.img"
rm -f "$dtbo_out"
truncate -s "$DTBO_BLANK_SIZE" "$dtbo_out"
printf 'Built blank DTBO image: %s (%d bytes)\n' "$dtbo_out" "$DTBO_BLANK_SIZE"

# 2. Build initramfs with Luma's shared OSTree resolver (scripts/mobile/common/initramfs)
build_initramfs() {
  local target_mode="$1"
  local out_ramdisk="$2"
  local stage="$work_dir/initramfs-$target_mode"
  rm -rf "$stage"
  mkdir -p "$stage"/{bin,dev,etc,lib,mnt,proc,sys,sysroot,usr/bin,usr/sbin}

  if [ -n "$base_initramfs" ]; then
    (
      cd "$stage"
      gzip -dc "$base_initramfs" | cpio -idmu --quiet
    )
  fi

  # Install shared Luma OSTree boot hook
  install -D -m 0755 "$repo_root/scripts/mobile/common/initramfs/luma-ostree-boot.sh" \
    "$stage/usr/lib/luma/luma-ostree-boot.sh"
  if [ -f "$repo_root/scripts/mobile/common/initramfs/hooks-extra/50-luma-ostree-default.sh" ]; then
    install -D -m 0755 "$repo_root/scripts/mobile/common/initramfs/hooks-extra/50-luma-ostree-default.sh" \
      "$stage/etc/luma-ostree-default.sh"
  fi

  # If no base initramfs was provided, install busybox + minimal /init that invokes luma-ostree-boot.sh
  if [ ! -e "$stage/init" ]; then
    if command -v busybox >/dev/null 2>&1; then
      install -D -m 0755 "$(command -v busybox)" "$stage/bin/busybox"
      for applet in sh mount umount mkdir ln ls cat sed awk grep cut head tr sleep switch_root blkid findfs modprobe insmod; do
        ln -sf busybox "$stage/bin/$applet"
      done
    fi
    cat > "$stage/init" <<'EOF'
#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Load UFS / storage modules if modular
for mod in phy_qcom_qmp_ufs ufs_qcom ufshcd_core ufshcd_pltfrm ext4; do
  modprobe "$mod" 2>/dev/null || true
done

# Wait up to 10s for UFS partitions (/dev/sda*)
i=0
while [ $i -lt 100 ]; do
  if ls /dev/sd* >/dev/null 2>&1 || ls /dev/disk/by-partlabel/* >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

if [ -r /usr/lib/luma/luma-ostree-boot.sh ]; then
  . /usr/lib/luma/luma-ostree-boot.sh
fi

ROOT_DEV=""
BOOT_DEV=""
for arg in $(cat /proc/cmdline); do
  case "$arg" in
    root=PARTLABEL=*)
      label="${arg#root=PARTLABEL=}"
      ROOT_DEV=$(findfs "PARTLABEL=$label" 2>/dev/null || blkid -t "PARTLABEL=$label" -o device 2>/dev/null | head -n 1)
      ;;
    root=UUID=*|pmos_root_uuid=*)
      uuid="${arg#*=}"
      uuid="${uuid#UUID=}"
      ROOT_DEV=$(findfs "UUID=$uuid" 2>/dev/null || blkid -t "UUID=$uuid" -o device 2>/dev/null | head -n 1)
      ;;
    pmos_boot_uuid=*)
      buuid="${arg#pmos_boot_uuid=}"
      BOOT_DEV=$(findfs "UUID=$buuid" 2>/dev/null || blkid -t "UUID=$buuid" -o device 2>/dev/null | head -n 1)
      ;;
  esac
done

[ -n "$ROOT_DEV" ] || ROOT_DEV="/dev/sda30"
mkdir -p /sysroot
mount -o rw "$ROOT_DEV" /sysroot

if [ -n "$BOOT_DEV" ] && [ -b "$BOOT_DEV" ]; then
  mkdir -p /sysroot/boot
  mount -o ro "$BOOT_DEV" /sysroot/boot || true
fi

if command -v luma_ostree_resolve >/dev/null 2>&1 && luma_ostree_resolve /sysroot; then
  luma_ostree_apply /sysroot "$(cat /proc/cmdline)" || true
  if [ -n "${LUMA_OSTREE_DEPLOY:-}" ] && [ -d "/sysroot/ostree/${LUMA_OSTREE_DEPLOY}" ]; then
    DEPLOY_PATH="/sysroot/ostree/${LUMA_OSTREE_DEPLOY}"
    mount --bind /sysroot "$DEPLOY_PATH/sysroot" 2>/dev/null || true
    exec switch_root "$DEPLOY_PATH" /sbin/init
  fi
fi

exec switch_root /sysroot /sbin/init
EOF
    chmod 0755 "$stage/init"
  fi

  if [ -n "$modules_dir" ] && [ -d "$modules_dir" ]; then
    mkdir -p "$stage/lib/modules"
    cp -a "$modules_dir/." "$stage/lib/modules/"
  fi

  (
    cd "$stage"
    find . -print0 | sort -z | cpio --null -o -H newc --quiet | gzip -9 > "$out_ramdisk"
  )
}

build_one_boot_img() {
  local target_mode="$1"
  local out_file="$2"
  local cmdline="$3"
  local ramdisk="$work_dir/initramfs-$target_mode.cpio.gz"

  build_initramfs "$target_mode" "$ramdisk"

  mkbootimg \
    --header_version 2 \
    --kernel "$kernel_image" \
    --ramdisk "$ramdisk" \
    --dtb "$dtb_file" \
    --pagesize "$PAGE_SIZE" \
    --base "$BASE_ADDR" \
    --kernel_offset "$KERNEL_OFFSET" \
    --ramdisk_offset "$RAMDISK_OFFSET" \
    --tags_offset "$TAGS_OFFSET" \
    --dtb_offset "$DTB_OFFSET" \
    --cmdline "$cmdline" \
    -o "$out_file"

  size=$(stat -c '%s' "$out_file")
  if [ "$size" -gt "$BOOT_PARTITION_MAX" ]; then
    printf 'build-sheng-boot-image: %s (%d bytes) exceeds 96 MiB boot partition size\n' "$out_file" "$size" >&2
    exit 1
  fi
  printf 'Built %s (%d bytes)\n' "$out_file" "$size"
}

if [ "$mode" = "linux" ] || [ "$mode" = "both" ]; then
  build_one_boot_img "linux" \
    "$output_dir/luma-sheng-$version-boot-linux.img" \
    "root=PARTLABEL=linux $BASE_CMDLINE"
fi

if [ "$mode" = "userdata" ] || [ "$mode" = "both" ]; then
  build_one_boot_img "userdata" \
    "$output_dir/luma-sheng-$version-boot.img" \
    "pmos_boot_uuid=$LUMA_BOOT_UUID pmos_root_uuid=$LUMA_ROOT_UUID $BASE_CMDLINE"
fi

(
  cd "$output_dir"
  sha256sum ./*.img > SHA256SUMS
)
printf 'Boot images written to %s\n' "$output_dir"

