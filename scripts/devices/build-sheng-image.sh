#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build Luma OS images and device kit for the Xiaomi Pad 6S Pro 12.4 (xiaomi/sheng):
#
#   Mode A (--layout linux or both):
#     Pulls the generic Luma ARM OSTree commit (luma/1/aarch64/<channel> from
#     https://dl.simplyluma.com/os/repo), layers the xiaomi/sheng rpm-md
#     device repository offline using scripts/devices/rpm-ostree-offline.sh,
#     and builds a flashable ext4 image (luma-sheng-<channel>-<build>-aarch64-linux.img)
#     for PARTLABEL=linux dual-boot (Slot B).
#
#   Mode B (--layout userdata or both):
#     Runs scripts/devices/build-device-kit.py --device devices/xiaomi/sheng
#     to produce the standard Luma Device Kit (luma-sheng-<version>-kit.sparse,
#     luma-sheng-<version>-boot.img, dtbo-blank.img, FLASH.txt, SHA256SUMS)
#     that layers on top of the generic Luma ARM userdata image on first boot.
#
# Usage:
#   scripts/devices/build-sheng-image.sh \
#     --device-repo build/sheng-repo \
#     --boot-dir build/sheng-boot \
#     [--layout both|linux|userdata] \
#     [--ostree-url https://dl.simplyluma.com/os/repo] \
#     [--ostree-ref luma/1/aarch64/nightly] \
#     [--version 0.1.0] \
#     [--root-size-mib 14336] \
#     --output-dir build/sheng-images

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
device_repo=""
boot_dir=""
layout="both"
ostree_url="https://dl.simplyluma.com/os/repo"
ostree_ref="luma/1/aarch64/nightly"
version="0.1.0"
root_size_mib=14336
output_dir="$repo_root/build/sheng-images"

while [ $# -gt 0 ]; do
  case "$1" in
    --device-repo) device_repo=$(realpath -e "$2"); shift 2 ;;
    --boot-dir) boot_dir=$(realpath -e "$2"); shift 2 ;;
    --layout) layout="$2"; shift 2 ;;
    --ostree-url) ostree_url="$2"; shift 2 ;;
    --ostree-ref) ostree_ref="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --root-size-mib) root_size_mib="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,29p' "$0"
      exit 0
      ;;
    *)
      printf 'build-sheng-image: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

[ -n "$device_repo" ] || { printf 'build-sheng-image: --device-repo DIR is required\n' >&2; exit 2; }
[ -f "$device_repo/repodata/repomd.xml" ] || {
  printf 'build-sheng-image: %s has no repodata/repomd.xml (run build-sheng-rpms.sh first)\n' "$device_repo" >&2
  exit 1
}
[ -n "$boot_dir" ] || { printf 'build-sheng-image: --boot-dir DIR is required\n' >&2; exit 2; }

mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")

# ---------------------------------------------------------------------------
# Mode B: Standard Luma Device Kit for single-boot on userdata
# ---------------------------------------------------------------------------
if [ "$layout" = "userdata" ] || [ "$layout" = "both" ]; then
  echo "=== Building Mode B: Standard Luma Device Kit (userdata) ==="
  boot_img="$boot_dir/luma-sheng-$version-boot.img"
  dtbo_img="$boot_dir/dtbo-blank.img"
  [ -f "$boot_img" ] || { printf 'build-sheng-image: missing %s\n' "$boot_img" >&2; exit 1; }
  [ -f "$dtbo_img" ] || { printf 'build-sheng-image: missing %s\n' "$dtbo_img" >&2; exit 1; }

  kit_out="$output_dir/kit"
  mkdir -p "$kit_out"
  python3 "$repo_root/scripts/devices/build-device-kit.py" \
    --device "$repo_root/devices/xiaomi/sheng" \
    --version "$version" \
    --boot-image "$boot_img" \
    --dtbo-image "$dtbo_img" \
    --repo "$device_repo" \
    --unsigned \
    --output-dir "$kit_out"
  echo "=== Mode B Device Kit ready in $kit_out ==="
fi

# ---------------------------------------------------------------------------
# Mode A: Pre-layered PARTLABEL=linux ext4 image for Dual-Boot (Slot B)
# ---------------------------------------------------------------------------
if [ "$layout" = "linux" ] || [ "$layout" = "both" ]; then
  echo "=== Building Mode A: Pre-layered PARTLABEL=linux image (Dual-Boot Slot B) ==="
  for tool in ostree mkfs.ext4 e2fsck resize2fs; do
    command -v "$tool" >/dev/null 2>&1 || {
      printf 'build-sheng-image: missing required tool for Mode A image: %s\n' "$tool" >&2
      exit 1
    }
  done

  work=$(mktemp -d "$output_dir/work-linux.XXXXXX")
  trap 'rm -rf "$work"' EXIT INT TERM

  ostree_repo="$work/ostree-repo"
  ostree --repo="$ostree_repo" init --mode=archive
  ostree --repo="$ostree_repo" remote add --no-gpg-verify luma-origin "$ostree_url"
  echo ">>> Pulling $ostree_ref from $ostree_url ..."
  ostree --repo="$ostree_repo" pull --depth=1 luma-origin "$ostree_ref"
  base_commit=$(ostree --repo="$ostree_repo" rev-parse "luma-origin:$ostree_ref")
  ostree --repo="$ostree_repo" refs --create="$ostree_ref" "$base_commit"

  # Read replace & install package lists from devices/xiaomi/sheng/device.toml
  mapfile -t compose_args < <(python3 - "$repo_root/devices/xiaomi/sheng/device.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    d = tomllib.load(f)
repo = d["device_repo"]
for pkg in repo.get("replace", []):
    print("--replace")
    print(pkg)
for pkg in repo.get("install", []):
    print("--install")
    print(pkg)
PY
  )

  layered_ref="luma/1/aarch64/xiaomi-sheng/nightly"
  echo ">>> Layering luma-xiaomi-sheng packages onto $base_commit ..."
  "$repo_root/scripts/devices/rpm-ostree-offline.sh" \
    --ostree-repo "$ostree_repo" \
    --base-ref "$ostree_ref" \
    --target-ref "$layered_ref" \
    --rpm-repo "luma-xiaomi-sheng=$device_repo" \
    "${compose_args[@]}"

  layered_commit=$(ostree --repo="$ostree_repo" rev-parse "$layered_ref")
  echo ">>> Layered commit: $layered_commit"

  sysroot="$work/sysroot"
  mkdir -p "$sysroot"
  ostree admin init-fs --modern "$sysroot"
  ostree admin os-init luma --sysroot="$sysroot"
  ostree --repo="$sysroot/ostree/repo" pull-local "$ostree_repo" "$layered_commit"
  ostree --repo="$sysroot/ostree/repo" refs --create="luma:$layered_ref" "$layered_commit"

  KERNEL_ARGS=(
    "root=PARTLABEL=linux"
    "rw"
    "console=tty0"
    "earlycon"
    "clk_ignore_unused"
    "pd_ignore_unused"
    "quiet"
    "splash"
    "loglevel=4"
    "systemd.show_status=auto"
    "udmabuf.size_limit_mb=256"
    "enforcing=1"
  )
  karg_flags=()
  for karg in "${KERNEL_ARGS[@]}"; do
    karg_flags+=("--karg-append=$karg")
  done

  OSTREE_BOOT_PARTITION="/boot" ostree admin deploy "luma:$layered_ref" \
    --sysroot="$sysroot" \
    --os=luma \
    "${karg_flags[@]}"

  deploy_dir=$(find "$sysroot/ostree/deploy/luma/deploy" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  cat > "$deploy_dir/etc/fstab" <<'EOF'
PARTLABEL=linux  /  ext4  defaults,noatime  0 1
EOF

  # Mark device layer as already applied in Mode A pre-layered image
  mkdir -p "$sysroot/ostree/deploy/luma/var/lib/luma-device-layer"
  printf '%s\n' "$layered_commit" > "$sysroot/ostree/deploy/luma/var/lib/luma-device-layer/layered"

  # Relabel with deployment's SELinux policy if setfiles is available
  policy_file=$(find "$deploy_dir/etc/selinux/targeted/policy" -maxdepth 1 -type f -name 'policy.*' | sort -V | tail -n 1 || true)
  fc_file="$deploy_dir/etc/selinux/targeted/contexts/files/file_contexts"
  if command -v setfiles >/dev/null 2>&1 && [ -n "$policy_file" ] && [ -f "$fc_file" ]; then
    setfiles -F -r "$deploy_dir" -c "$policy_file" "$fc_file" "$deploy_dir" || true
    setfiles -F -r "$sysroot/ostree/deploy/luma" -c "$policy_file" "$fc_file" "$sysroot/ostree/deploy/luma/var" || true
  fi

  linux_img="$output_dir/luma-sheng-nightly-$version-aarch64-linux.img"
  rm -f "$linux_img"
  truncate -s "${root_size_mib}M" "$linux_img"
  mkfs.ext4 -F -b 4096 -L LumaRoot -U 03797c05-cf87-4eda-adc4-6ce111baf2d3 \
    -O metadata_csum,64bit,extents,dir_index,filetype \
    -d "$sysroot" "$linux_img"
  e2fsck -fy "$linux_img" || true

  if [ -f "$boot_dir/luma-sheng-$version-boot-linux.img" ]; then
    cp -f "$boot_dir/luma-sheng-$version-boot-linux.img" "$output_dir/"
  fi
  if [ -f "$boot_dir/dtbo-blank.img" ]; then
    cp -f "$boot_dir/dtbo-blank.img" "$output_dir/"
  fi
  (
    cd "$output_dir"
    find . -maxdepth 1 -type f -name '*.img' -exec sha256sum {} + | sort > SHA256SUMS-linux
  )
  echo "=== Mode A PARTLABEL=linux image ready: $linux_img ==="
fi

