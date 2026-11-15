Name:           luma-sheng-platform
Version:        0.1.0
Release:        1%{?dist}
Summary:        Xiaomi Pad 6S Pro 12.4 (sheng) platform integration for Luma OS
License:        Apache-2.0
URL:            https://github.com/SimplyLuma/luma

Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch

Requires:       NetworkManager
Requires:       qbootctl
Requires:       systemd
Requires:       util-linux-core
Suggests:       luma-sheng-firmware
Suggests:       kernel-modules-luma-sheng
Suggests:       xiaomi-sheng-thp
Suggests:       libssc
Suggests:       fastrpc
Suggests:       sheng-devauth
Suggests:       xiaomi-mipps-auth
Suggests:       xiaomi-charger-mode
Suggests:       xiaomi-sheng-keyboard-helper
Suggests:       xiaomi-sheng-keyboard-backlight
Suggests:       xiaomi-pen-status
Suggests:       xiaomi-sheng-fingerprint
Suggests:       sheng-sensors
Suggests:       alsa-xiaomi-sheng
Suggests:       sheng-audio-fix
Suggests:       sheng-gnome-fix

%description
Xiaomi Pad 6S Pro 12.4 (sheng / Qualcomm SM8550) platform units and
configuration for Luma OS: tablet device class marker, device update stream
channel (/etc/luma/update.conf), handheld/tablet shell environment defaults,
WCN7850 Wi-Fi power-save workaround, /boot automount for LumaBoot, A/B slot
boot-success confirmation service (qbootctl -m), and persistent wall-clock
save/restore across reboots when the PMIC RTC is read-only.

%prep
%autosetup

%build
# Shipped configuration and systemd units only.

%install
cp -a root/. %{buildroot}/
install -d %{buildroot}%{_unitdir}/multi-user.target.wants
ln -s ../boot.automount \
    %{buildroot}%{_unitdir}/multi-user.target.wants/boot.automount
ln -s ../luma-sheng-boot-success.service \
    %{buildroot}%{_unitdir}/multi-user.target.wants/luma-sheng-boot-success.service
ln -s ../luma-clock-restore.service \
    %{buildroot}%{_unitdir}/multi-user.target.wants/luma-clock-restore.service
ln -s ../luma-clock-save.service \
    %{buildroot}%{_unitdir}/multi-user.target.wants/luma-clock-save.service
ln -s ../luma-clock-save.timer \
    %{buildroot}%{_unitdir}/multi-user.target.wants/luma-clock-save.timer

%post
%systemd_post boot.automount luma-sheng-boot-success.service luma-clock-restore.service luma-clock-save.service luma-clock-save.timer

%preun
%systemd_preun boot.automount luma-sheng-boot-success.service luma-clock-restore.service luma-clock-save.service luma-clock-save.timer

%postun
%systemd_postun_with_restart luma-clock-save.timer

%files
%license LICENSE
%doc README.md
%config(noreplace) %{_sysconfdir}/luma-device-class
%dir %{_sysconfdir}/luma
%config(noreplace) %{_sysconfdir}/luma/update.conf
%{_prefix}/lib/environment.d/90-luma-handheld.conf
%{_prefix}/lib/NetworkManager/conf.d/50-luma-sheng-wifi.conf
%{_unitdir}/boot.automount
%{_unitdir}/luma-sheng-boot-success.service
%{_unitdir}/luma-clock-restore.service
%{_unitdir}/luma-clock-save.service
%{_unitdir}/luma-clock-save.timer
%{_unitdir}/multi-user.target.wants/boot.automount
%{_unitdir}/multi-user.target.wants/luma-sheng-boot-success.service
%{_unitdir}/multi-user.target.wants/luma-clock-restore.service
%{_unitdir}/multi-user.target.wants/luma-clock-save.service
%{_unitdir}/multi-user.target.wants/luma-clock-save.timer
%{_tmpfilesdir}/luma-sheng-clock.conf
%{_presetdir}/60-luma-sheng-platform.preset

%changelog
* Sun Nov 15 2026 Luma OS Contributors <releng@simplyluma.com> - 0.1.0-1
- Initial Xiaomi Pad 6S Pro 12.4 (sheng) platform package for Luma OS

