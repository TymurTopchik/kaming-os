#!/usr/bin/env bash
# Kaming OS - сборщик ISO (Debian 13 "trixie" + XFCE в стиле macOS)
# Запускать на Debian 12/13 или Ubuntu 24.04 (можно в WSL2). Нужно ~20 ГБ места и интернет.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then exec sudo bash "$0" "$@"; fi

echo "==> Установка инструментов сборки"
apt-get update
apt-get install -y live-build debootstrap xorriso squashfs-tools mtools dosfstools \
  grub-pc-bin grub-efi-amd64-bin imagemagick curl ca-certificates

WORK="$(pwd)/kaming-build"
mkdir -p "$WORK"
cd "$WORK"
lb clean --purge >/dev/null 2>&1 || true

echo "==> Конфигурация live-build"
lb config \
  --distribution trixie \
  --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none \
  --iso-application "Kaming OS" \
  --iso-publisher "Kaming" \
  --iso-volume "KAMING_OS" \
  --bootappend-live "boot=live components quiet splash username=kaming hostname=kaming-os" \
  --memtest none

mkdir -p config/package-lists config/hooks/live \
         config/includes.chroot/etc/lightdm/lightdm.conf.d \
         config/includes.chroot/etc/skel/.config/autostart \
         config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml \
         config/includes.chroot/usr/share/backgrounds/kaming \
         config/includes.chroot/etc/skel/Desktop

echo "==> Список пакетов"
cat > config/package-lists/kaming.list.chroot <<'PKG'
# Система и рабочий стол
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
plank
network-manager
network-manager-gnome
pulseaudio
pavucontrol
fonts-inter
fonts-noto
fonts-noto-color-emoji
gnome-themes-extra
sassc
libglib2.0-dev-bin
git
imagemagick
dbus-x11
sudo
# Программы
firefox-esr
galculator
mousepad
thunar
thunar-archive-plugin
xarchiver
xfce4-terminal
ristretto
evince
vlc
file-roller
# Запуск .exe
wine
wine64
winetricks
# Работа в виртуалках (VirtualBox, VMware, QEMU/KVM)
open-vm-tools
open-vm-tools-desktop
spice-vdagent
qemu-guest-agent
# Установка на реальный компьютер
calamares
calamares-settings-debian
# Драйверы и прошивки
firmware-linux
firmware-misc-nonfree
firmware-iwlwifi
firmware-realtek
firmware-atheros
PKG

echo "==> Автовход и брендинг"
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-kaming.conf <<'LDM'
[Seat:*]
autologin-user=kaming
autologin-user-timeout=0
user-session=xfce
LDM

cat > config/includes.chroot/etc/os-release <<'OSR'
PRETTY_NAME="Kaming OS 1.0"
NAME="Kaming OS"
VERSION="1.0"
ID=kamingos
ID_LIKE=debian
HOME_URL="https://example.com"
OSR

# Док Plank при старте
cat > config/includes.chroot/etc/skel/.config/autostart/plank.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Dock
Exec=plank
X-GNOME-Autostart-enabled=true
DESK

# Тема, иконки и шрифт
cat > config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'XS'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="WhiteSur-Light"/>
    <property name="IconThemeName" type="string" value="WhiteSur"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Inter 10"/>
    <property name="CursorThemeName" type="string" value="WhiteSur-cursors"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
XS

cat > config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'XW'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="WhiteSur-Light"/>
    <property name="button_layout" type="string" value="CHM|"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="show_frame_shadow" type="bool" value="false"/>
  </property>
</channel>
XW

# Обои
cat > config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<'XD'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/kaming/wallpaper.png"/>
        </property>
      </property>
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/kaming/wallpaper.png"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XD

echo "==> Хук сборки (тема WhiteSur, обои, права)"
cat > config/hooks/live/0100-kaming.hook.chroot <<'HOOK'
#!/bin/bash
set -x
cd /tmp

# Тема и иконки в стиле macOS (открытые, проект WhiteSur)
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git || true
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme.git || true
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors.git || true
( cd WhiteSur-gtk-theme  && ./install.sh -d /usr/share/themes -c Light ) || true
( cd WhiteSur-icon-theme && ./install.sh -d /usr/share/icons ) || true
( cd WhiteSur-cursors    && ./install.sh ) || true
rm -rf /tmp/WhiteSur-*

# Обои с градиентом
convert -size 1920x1080 gradient:'#4facfe-#8e44ad' \
  /usr/share/backgrounds/kaming/wallpaper.png || true

# Виндовые программы: открывать .exe двойным кликом через Wine
cat > /usr/share/applications/wine-exe.desktop <<'EXE'
[Desktop Entry]
Type=Application
Name=Windows Program (Wine)
Exec=wine start /unix %f
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;
NoDisplay=true
EXE
update-desktop-database /usr/share/applications || true

# Пользователь kaming: пароль live, права администратора
if ! id kaming >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev kaming
fi
echo "kaming:live" | chpasswd

# Копируем настройки в профиль пользователя
mkdir -p /home/kaming
cp -rT /etc/skel /home/kaming
chown -R kaming:kaming /home/kaming
HOOK
chmod +x config/hooks/live/0100-kaming.hook.chroot

echo "==> Ярлыки на рабочем столе"
for app in firefox-esr galculator mousepad calamares; do
  src="/usr/share/applications/${app}.desktop"
  echo "$src" > /dev/null
done
cat > config/includes.chroot/etc/skel/Desktop/install-kaming-os.desktop <<'INST'
[Desktop Entry]
Type=Application
Name=Install Kaming OS
Exec=sudo -E calamares
Icon=system-software-install
Terminal=false
INST
chmod +x config/includes.chroot/etc/skel/Desktop/install-kaming-os.desktop

echo "==> Сборка ISO (это долго, 20-60 минут)"
lb build 2>&1 | tee build.log

ISO="$(ls -1 *.iso | head -n1)"
mv "$ISO" ../kaming-os.iso
echo
echo "Готово: $(cd .. && pwd)/kaming-os.iso"
echo "Вход: пользователь kaming, пароль live"
