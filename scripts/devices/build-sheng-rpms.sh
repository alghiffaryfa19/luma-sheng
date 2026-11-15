#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build all Xiaomi Pad 6S Pro 12.4 (xiaomi/sheng) device RPMs for Luma OS and
# assemble a signed/unsigned rpm-md repository ready for:
#   - scripts/devices/build-device-kit.py (Mode B: userdata device kit)
#   - scripts/devices/rpm-ostree-offline.sh (Mode A: pre-layered PARTLABEL=linux image)
#
# Usage:
#   scripts/devices/build-sheng-rpms.sh \
#     --output-dir build/sheng-repo \
#     [--firmware-dir /path/to/sheng-firmware] \
#     [--kernel-modules-dir /path/to/modules_staging] \
#     [--kernel-release 7.2.0-sm8550] \
#     [--boot-image /path/to/luma-sheng-boot.img] \
#     [--container registry.fedoraproject.org/fedora:44]

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output_dir="$repo_root/build/sheng-repo"
firmware_dir=""
kernel_modules_dir=""
kernel_release=""
boot_image=""
container_image=${LUMA_SHENG_RPM_CONTAINER:-registry.fedoraproject.org/fedora:44}
in_container=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir) output_dir=$2; shift 2 ;;
    --firmware-dir) firmware_dir=$2; shift 2 ;;
    --kernel-modules-dir) kernel_modules_dir=$2; shift 2 ;;
    --kernel-release) kernel_release=$2; shift 2 ;;
    --boot-image) boot_image=$2; shift 2 ;;
    --container) container_image=$2; shift 2 ;;
    --in-container) in_container=1; shift ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      printf 'build-sheng-rpms: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")

if [ -z "$kernel_release" ]; then
  kernel_release=$(sed -n 's/^release = "\(.*\)"/\1/p' "$repo_root/devices/xiaomi/sheng/device.toml" | head -n 1)
fi

# Verify firmware manifest hash matches device.toml before building
manifest="$repo_root/devices/xiaomi/sheng/firmware.manifest"
expected_manifest_sha=$(sed -n 's/^manifest_sha256 = "\(.*\)"/\1/p' "$repo_root/devices/xiaomi/sheng/device.toml")
printf '%s  %s\n' "$expected_manifest_sha" "$manifest" | sha256sum -c --quiet - || {
  printf 'build-sheng-rpms: firmware.manifest SHA-256 does not match device.toml\n' >&2
  exit 1
}

# If not already running inside a Fedora environment with rpmbuild, re-exec in Podman/Docker
if [ "$in_container" -eq 0 ] && ! command -v rpmbuild >/dev/null 2>&1; then
  engine=""
  if command -v podman >/dev/null 2>&1; then
    engine=podman
  elif command -v docker >/dev/null 2>&1; then
    engine=docker
  else
    printf 'build-sheng-rpms: neither rpmbuild nor podman/docker found\n' >&2
    exit 1
  fi

  mounts=(-v "$repo_root:/work/luma:Z" -v "$output_dir:/work/out:Z")
  inner_args=(--in-container --output-dir /work/out --kernel-release "$kernel_release")
  if [ -n "$firmware_dir" ]; then
    firmware_dir=$(realpath -e "$firmware_dir")
    mounts+=(-v "$firmware_dir:/work/firmware:ro,Z")
    inner_args+=(--firmware-dir /work/firmware)
  fi
  if [ -n "$kernel_modules_dir" ]; then
    kernel_modules_dir=$(realpath -e "$kernel_modules_dir")
    mounts+=(-v "$kernel_modules_dir:/work/kmod:ro,Z")
    inner_args+=(--kernel-modules-dir /work/kmod)
  fi
  if [ -n "$boot_image" ]; then
    boot_image=$(realpath -e "$boot_image")
    mounts+=(-v "$boot_image:/work/boot.img:ro,Z")
    inner_args+=(--boot-image /work/boot.img)
  fi

  exec "$engine" run --rm "${mounts[@]}" "$container_image" \
    /work/luma/scripts/devices/build-sheng-rpms.sh "${inner_args[@]}"
fi

echo "=== Installing Fedora RPM build dependencies for xiaomi/sheng ==="
dnf install -y \
  rpm-build rpmdevtools createrepo_c git curl wget tar xz gzip zstd patch \
  gcc gcc-c++ make cmake meson ninja-build autoconf automake libtool pkgconf-pkg-config \
  systemd-devel systemd-rpm-macros glib2-devel libgudev-devel polkit-devel \
  protobuf-c-devel protobuf-c-compiler protobuf-compiler libqrtr-glib-devel libqmi-devel libmbim-devel json-c-devel \
  alsa-lib-devel tinycompress-devel openssl-devel libnl3-devel \
  libyaml-devel libbsd-devel libgusb-devel patchelf python3-devel \
  qt6-qtbase-devel qt6-qtsvg-devel qt6-qtnetworkauth-devel qt6-qtbase-private-devel

TOP="/tmp/rpmbuild-sheng"
SRC="/tmp/src-sheng"
SPECS_DIR="$repo_root/packaging/rpm"
SHENG_SOURCES="$SPECS_DIR/sheng-sources"
PATCHES_DIR="$SHENG_SOURCES/patches"

rm -rf "$TOP" "$SRC"
mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$SRC"

build_spec() {
  local spec="$1"
  shift
  echo ">>> Building $spec ..."
  cp "$SPECS_DIR/$spec" "$TOP/SPECS/"
  rpmbuild --define "_topdir $TOP" "$@" -bb "$TOP/SPECS/$spec"
}

# 1. luma-sheng-platform
echo "=== [1/18] Building luma-sheng-platform ==="
mkdir -p "$SRC/luma-sheng-platform-0.1.0"
cp -a "$repo_root/src/luma-sheng-platform/." "$SRC/luma-sheng-platform-0.1.0/"
tar -czf "$TOP/SOURCES/luma-sheng-platform-0.1.0.tar.gz" -C "$SRC" luma-sheng-platform-0.1.0
build_spec luma-sheng-platform.spec

# 2. luma-sheng-firmware (if --firmware-dir supplied)
if [ -n "$firmware_dir" ]; then
  echo "=== [2/18] Building luma-sheng-firmware ==="
  fw_stage="$SRC/luma-sheng-firmware-20260417/firmware"
  mkdir -p "$fw_stage"
  while IFS=$'\t' read -r kind mode sha256 relpath target; do
    [ "$kind" = "F" ] || continue
    src_file=""
    if [ -f "$firmware_dir/$relpath" ]; then
      src_file="$firmware_dir/$relpath"
    elif [ -f "$firmware_dir/lib/firmware/$relpath" ]; then
      src_file="$firmware_dir/lib/firmware/$relpath"
    else
      printf 'build-sheng-rpms: missing firmware file: %s\n' "$relpath" >&2
      exit 1
    fi
    printf '%s  %s\n' "$sha256" "$src_file" | sha256sum -c --quiet - || {
      printf 'build-sheng-rpms: SHA-256 mismatch for firmware %s\n' "$relpath" >&2
      exit 1
    }
    # Place files under updates/ so they override base linux-firmware cleanly in rpm-ostree
    # AND under qcom/sm8550/xiaomi/sheng for paths not in base linux-firmware.
    install -D -m "$mode" "$src_file" "$fw_stage/updates/$relpath"
    case "$relpath" in
      qcom/sm8550/*|cirrus/*|focaltech/*)
        install -D -m "$mode" "$src_file" "$fw_stage/$relpath"
        ;;
    esac
  done < "$manifest"
  ln -sf board-2.bin "$fw_stage/updates/ath12k/WCN7850/hw2.0/board.bin"
  tar -czf "$TOP/SOURCES/luma-sheng-firmware-20260417.tar.gz" -C "$SRC" luma-sheng-firmware-20260417
  build_spec luma-sheng-firmware.spec
fi

# 3. kernel-modules-luma-sheng (if --kernel-modules-dir supplied)
if [ -n "$kernel_modules_dir" ]; then
  echo "=== [3/18] Building kernel-modules-luma-sheng ($kernel_release) ==="
  rpmver=$(echo "$kernel_release" | tr '-' '_')
  kmod_stage="$SRC/kernel-modules-luma-sheng-$rpmver"
  mkdir -p "$kmod_stage/modules/$kernel_release"
  if [ -d "$kernel_modules_dir/lib/modules/$kernel_release" ]; then
    cp -a "$kernel_modules_dir/lib/modules/$kernel_release/." "$kmod_stage/modules/$kernel_release/"
  elif [ -d "$kernel_modules_dir/usr/lib/modules/$kernel_release" ]; then
    cp -a "$kernel_modules_dir/usr/lib/modules/$kernel_release/." "$kmod_stage/modules/$kernel_release/"
  elif [ -f "$kernel_modules_dir/modules.dep" ]; then
    cp -a "$kernel_modules_dir/." "$kmod_stage/modules/$kernel_release/"
  else
    printf 'build-sheng-rpms: cannot find modules for %s in %s\n' "$kernel_release" "$kernel_modules_dir" >&2
    exit 1
  fi
  rm -f "$kmod_stage/modules/$kernel_release"/{build,source,vmlinuz,initramfs.img,aboot.img}

  mkdir -p "$kmod_stage/device-boot/xiaomi-sheng"
  if [ -n "$boot_image" ] && [ -f "$boot_image" ]; then
    kernel_sha=$(sha256sum "$boot_image" | awk '{print $1}')
    python3 "$repo_root/scripts/devices/device-boot-manifest.py" \
      --device "$repo_root/devices/xiaomi/sheng" \
      --boot-image "$boot_image" \
      --kernel-sha256 "$kernel_sha" \
      --output "$kmod_stage/device-boot/xiaomi-sheng"
  fi
  tar -czf "$TOP/SOURCES/kernel-modules-luma-sheng-$rpmver.tar.gz" -C "$SRC" "kernel-modules-luma-sheng-$rpmver"
  build_spec kernel-modules-luma-sheng.spec --define "kver $kernel_release" --define "rpmver $rpmver"
fi

# 4. fastrpc
echo "=== [4/18] Building fastrpc ==="
git clone --depth 1 --branch v1.0.2 https://github.com/qualcomm/fastrpc.git "$SRC/fastrpc-1.0.2"
tar -czf "$TOP/SOURCES/fastrpc-1.0.2.tar.gz" -C "$SRC" --exclude=.git fastrpc-1.0.2
cp "$PATCHES_DIR/adsprpcd-sensorspd.service" "$TOP/SOURCES/"
build_spec fastrpc.spec
rpm -Uvh --force "$TOP"/RPMS/aarch64/fastrpc-*.rpm

# 5. libssc (depends on fastrpc)
echo "=== [5/18] Building libssc ==="
git clone https://codeberg.org/DylanVanAssche/libssc.git "$SRC/libssc-0.3.0"
tar -czf "$TOP/SOURCES/libssc-0.3.0.tar.gz" -C "$SRC" --exclude=.git libssc-0.3.0
cp "$PATCHES_DIR/wait_for_qmi_service.patch" "$TOP/SOURCES/"
build_spec libssc.spec
rpm -Uvh --force "$TOP"/RPMS/aarch64/libssc-*.rpm
rpm -Uvh --force "$TOP"/RPMS/aarch64/libssc-devel-*.rpm

# 6. iio-sensor-proxy (replaces stock iio-sensor-proxy with libssc backend)
echo "=== [6/18] Building iio-sensor-proxy ==="
git clone --depth 1 --branch 3.9 https://gitlab.freedesktop.org/hadess/iio-sensor-proxy.git "$SRC/iio-sensor-proxy-3.9"
tar -czf "$TOP/SOURCES/iio-sensor-proxy-3.9.tar.gz" -C "$SRC" --exclude=.git iio-sensor-proxy-3.9
build_spec iio-sensor-proxy.spec

# 7. xiaomi-sheng-thp
echo "=== [7/18] Building xiaomi-sheng-thp ==="
git clone --depth 1 --branch v0.3.9 https://github.com/ianchb/xiaomi-sheng-thp.git "$SRC/xiaomi-sheng-thp-0.3.9"
tar -czf "$TOP/SOURCES/xiaomi-sheng-thp-0.3.9.tar.gz" -C "$SRC" --exclude=.git xiaomi-sheng-thp-0.3.9
build_spec xiaomi-sheng-thp.spec
rpm -Uvh --force "$TOP"/RPMS/aarch64/xiaomi-sheng-thp-*.rpm

# 8. sheng-devauth
echo "=== [8/18] Building sheng-devauth ==="
git clone --depth 1 https://github.com/ianchb/sheng_devauth.git "$SRC/sheng_devauth-1.0"
tar -czf "$TOP/SOURCES/sheng-devauth-1.0.tar.gz" -C "$SRC" --exclude=.git sheng_devauth-1.0
cp "$PATCHES_DIR/sheng-devauth.service" "$TOP/SOURCES/"
cp "$PATCHES_DIR/sheng-devauth.service.d-qtee.conf" "$TOP/SOURCES/"
build_spec sheng-devauth.spec

# 9. xiaomi-mipps-auth
echo "=== [9/18] Building xiaomi-mipps-auth ==="
git clone --depth 1 --branch 0.21 https://github.com/ianchb/xiaomi-mipps-auth.git "$SRC/xiaomi-mipps-auth-0.21"
tar -czf "$TOP/SOURCES/xiaomi-mipps-auth-0.21.tar.gz" -C "$SRC" --exclude=.git xiaomi-mipps-auth-0.21
build_spec xiaomi-mipps-auth.spec

# 10. xiaomi-charger-mode
echo "=== [10/18] Building xiaomi-charger-mode ==="
git clone --depth 1 --branch 0.20 https://github.com/ianchb/xiaomi-charger-mode.git "$SRC/xiaomi-charger-mode-0.20"
tar -czf "$TOP/SOURCES/xiaomi-charger-mode-0.20.tar.gz" -C "$SRC" --exclude=.git xiaomi-charger-mode-0.20
build_spec xiaomi-charger-mode.spec

# 11. xiaomi-sheng-keyboard-helper
echo "=== [11/18] Building xiaomi-sheng-keyboard-helper ==="
git clone --depth 1 --branch v0.2.0 https://github.com/ianchb/xiaomi-sheng-keyboard-helper.git "$SRC/xiaomi-sheng-keyboard-helper-0.2.0"
tar -czf "$TOP/SOURCES/xiaomi-sheng-keyboard-helper-0.2.0.tar.gz" -C "$SRC" --exclude=.git xiaomi-sheng-keyboard-helper-0.2.0
build_spec xiaomi-sheng-keyboard-helper.spec

# 12. xiaomi-sheng-keyboard-backlight
echo "=== [12/18] Building xiaomi-sheng-keyboard-backlight ==="
git clone --depth 1 https://github.com/slhssb/xiaomi-sheng-keyboard-backlight.git "$SRC/xiaomi-sheng-keyboard-backlight-1.0"
tar -czf "$TOP/SOURCES/xiaomi-sheng-keyboard-backlight-1.0.tar.gz" -C "$SRC" --exclude=.git xiaomi-sheng-keyboard-backlight-1.0
build_spec xiaomi-sheng-keyboard-backlight.spec

# 13. xiaomi-pen-status
echo "=== [13/18] Building xiaomi-pen-status ==="
git clone --depth 1 --branch v0.2.3 https://github.com/ianchb/xiaomi-pen-status.git "$SRC/xiaomi-pen-status-0.2.3"
tar -czf "$TOP/SOURCES/xiaomi-pen-status-0.2.3.tar.gz" -C "$SRC" --exclude=.git xiaomi-pen-status-0.2.3
build_spec xiaomi-pen-status.spec

# 14. xiaomi-sheng-fingerprint
echo "=== [14/18] Building xiaomi-sheng-fingerprint ==="
git clone --depth 1 --branch v0.1.4 https://github.com/ianchb/xiaomi-sheng-fingerprint.git "$SRC/xiaomi-sheng-fingerprint-0.1.4"
tar -czf "$TOP/SOURCES/xiaomi-sheng-fingerprint-0.1.4.tar.gz" -C "$SRC" --exclude=.git xiaomi-sheng-fingerprint-0.1.4
build_spec xiaomi-sheng-fingerprint.spec

# 15. sheng-sensors
echo "=== [15/18] Building sheng-sensors ==="
git clone --depth 1 https://github.com/alghiffaryfa19/sheng-sensors-file.git "$SRC/sheng-sensors-file"
tar -czf "$TOP/SOURCES/sheng-sensors-20240917.tar.gz" -C "$SRC/sheng-sensors-file" --exclude=.git .
cp "$PATCHES_DIR/99-qcom-CDSP.rules" "$TOP/SOURCES/"
cp "$PATCHES_DIR/sensors.service" "$TOP/SOURCES/"
build_spec sheng-sensors.spec

# 16. alsa-xiaomi-sheng
echo "=== [16/18] Building alsa-xiaomi-sheng ==="
git clone --depth 1 --sparse https://github.com/ianchb/debian-sheng.git "$SRC/debian-sheng"
(
  cd "$SRC/debian-sheng"
  git sparse-checkout set alsa-xiaomi-sheng
)
tar -czf "$TOP/SOURCES/alsa-xiaomi-sheng-1.0.tar.gz" -C "$SRC/debian-sheng/alsa-xiaomi-sheng" .
build_spec alsa-xiaomi-sheng.spec

# 17. sheng-audio-fix
echo "=== [17/18] Building sheng-audio-fix ==="
mkdir -p "$SRC/sheng-audio-fix-1.0"
cp "$SHENG_SOURCES/audio-fix/audio-fix.c" \
   "$SHENG_SOURCES/audio-fix/audio-fix.service" \
   "$SHENG_SOURCES/audio-fix/51-disable-suspend.lua" \
   "$SRC/sheng-audio-fix-1.0/"
tar -czf "$TOP/SOURCES/sheng-audio-fix-1.0.tar.gz" -C "$SRC" sheng-audio-fix-1.0
build_spec sheng-audio-fix.spec

# 18. sheng-gnome-fix
echo "=== [18/18] Building sheng-gnome-fix ==="
tar -czf "$TOP/SOURCES/sheng-gnome-fix-1.1.tar.gz" -C "$SHENG_SOURCES/sheng-gnome-fix" .
build_spec sheng-gnome-fix.spec

# Copy all built RPMs into output_dir and generate rpm-md metadata
echo "=== Assembling luma-xiaomi-sheng rpm-md repository in $output_dir ==="
mkdir -p "$output_dir/Packages"
find "$TOP/RPMS" -type f -name '*.rpm' -exec cp -v {} "$output_dir/Packages/" \;
createrepo_c "$output_dir"
(
  cd "$output_dir"
  find Packages repodata -type f -exec sha256sum {} + | sort > SHA256SUMS
)

echo "=== Built $(find "$output_dir/Packages" -name '*.rpm' | wc -l) RPM packages in $output_dir ==="

