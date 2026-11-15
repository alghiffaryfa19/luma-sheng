%global debug_package %{nil}
%global _build_id_links none
# Binary firmware blobs for Qualcomm Hexagon DSP, Adreno GPU, WCN7850, and Cirrus Logic CS35L41.
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%global __brp_strip_static_archive %{nil}
%global __os_install_post %{nil}

Name:           luma-sheng-firmware
Version:        20260417
Release:        1%{?dist}
Summary:        Xiaomi Pad 6S Pro 12.4 (sheng) vendor firmware for Luma OS
License:        Redistributable, no modification permitted
URL:            https://github.com/ianchb/sheng-firmware

# Assembled from the device firmware tree verified against devices/xiaomi/sheng/firmware.manifest.
# Unlike fedora-sheng's firmware-xiaomi-sheng, this package only installs files that do not
# collide with Fedora's base linux-firmware package, or overrides via /usr/lib/firmware/updates
# where needed, so rpm-ostree can layer it cleanly without Conflicts: linux-firmware.
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
Provides:       firmware-xiaomi-sheng = %{version}-%{release}

%description
Board-specific Qualcomm SM8550, Adreno 740, FastCV, WCN7850 Wi-Fi/Bluetooth,
focaltech touch, and Cirrus Logic CS35L41 Quad-Speaker DSP firmware files for
the Xiaomi Pad 6S Pro 12.4 (xiaomi,sheng).

Installed under /usr/lib/firmware/updates (and /usr/lib/firmware/qcom/sm8550/xiaomi/sheng)
so the kernel firmware loader prefers device-specific board data while coexisting
cleanly with linux-firmware in an OSTree base image.

%prep
%autosetup

%build
# Binary firmware only.

%install
install -d %{buildroot}/usr/lib/firmware
cp -a firmware/. %{buildroot}/usr/lib/firmware/

%files
/usr/lib/firmware/*

%changelog
* Sun Nov 15 2026 Luma OS Contributors <releng@simplyluma.com> - 20260417-1
- Xiaomi Pad 6S Pro 12.4 (sheng) firmware package for Luma OS
