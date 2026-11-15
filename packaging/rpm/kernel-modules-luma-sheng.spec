%global debug_package %{nil}
%global _build_id_links none
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%global __brp_strip_static_archive %{nil}
%global __os_install_post %{nil}

%if %{undefined kver}
%global kver 7.2.0-sm8550
%endif
%if %{undefined rpmver}
%global rpmver %(echo "%{kver}" | tr '-' '_')
%endif

Name:           kernel-modules-luma-sheng
Version:        %{rpmver}
Release:        1%{?dist}
Summary:        Luma SM8550 kernel modules for Xiaomi Pad 6S Pro 12.4 (sheng)
License:        GPL-2.0-only
URL:            https://github.com/SimplyLuma/luma

Source0:        %{name}-%{version}.tar.gz

ExclusiveArch:  aarch64
AutoReqProv:    no

Provides:       kernel-modules-luma-sm8550 = %{version}-%{release}
Provides:       kernel-modules-for-luma = %{kver}

%description
Loadable kernel modules built from the Luma SM8550 kernel tree (linux-sheng)
for the Xiaomi Pad 6S Pro 12.4 (xiaomi,sheng). The kernel image and device tree
themselves boot from the Android boot partition; this package provides the
matching /usr/lib/modules/%{kver} tree inside the OSTree deployment and optional
A/B boot image payload under /usr/lib/luma/device-boot/xiaomi-sheng for
luma-device-boot.service.

%prep
%autosetup

%build
# Pre-built modules and depmod metadata from the kernel build stage.

%install
install -d %{buildroot}/usr/lib/modules/%{kver}
cp -a modules/%{kver}/. %{buildroot}/usr/lib/modules/%{kver}/
rm -f %{buildroot}/usr/lib/modules/%{kver}/build \
      %{buildroot}/usr/lib/modules/%{kver}/source

if [ -d device-boot/xiaomi-sheng ]; then
    install -d %{buildroot}/usr/lib/luma/device-boot/xiaomi-sheng
    cp -a device-boot/xiaomi-sheng/. %{buildroot}/usr/lib/luma/device-boot/xiaomi-sheng/
fi

%files
/usr/lib/modules/%{kver}
/usr/lib/luma/device-boot/xiaomi-sheng

%changelog
* Sun Nov 15 2026 Luma OS Contributors <releng@simplyluma.com> - %{version}-1
- Luma SM8550 kernel modules and device-boot payload for Xiaomi Pad 6S Pro (sheng)

