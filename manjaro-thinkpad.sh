#!/bin/bash

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###YAY###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S yay --noconfirm

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Softwares Padrão###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S simplescreenrecorder ffmpeg psensor gimp gnome-disk-utility frei0r-plugins ntfs-3g exfat-utils gsmartcontrol obs-studio uget qbittorrent papirus-icon-theme telegram-desktop gamemode fatsort mpv audacious inkscape audacity kdenlive libreoffice-fresh-pt-br pulseaudio pulseaudio-alsa pavucontrol alsa-firmware alsa-utils a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore gstreamer gst-plugins-base gst-plugins-base-libs gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb git go fuse2 base-devel movit --noconfirm

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Chrome###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

yay -S google-chrome --noconfirm

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Limitar Logs###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo journalctl --vacuum-time=2d

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Descompactadores XFCE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S xarchiver file-roller tar gzip bzip2 zip unzip unrar p7zip thunar-archive-plugin --noconfirm

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Utilitários Básicos XFCE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S galculator xfce4-screenshooter ristretto mousepad hardinfo audacious --noconfirm

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Bluetooth###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S bluez blueman bluez-utils pulseaudio-bluetooth --noconfirm

sudo modprobe btusb
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

sudo cp /etc/pulse/default.pa /etc/pulse/default.pa.bak

echo -e '\nload-module module-switch-on-connect' | sudo tee -a /etc/pulse/default.pa

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Impressão###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S cups gtk3-print-backends system-config-printer hplip xsane python-pyqt5 --noconfirm && sudo systemctl enable cups && sudo systemctl start cups

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Tearing e Pacotes de Video Intel###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

echo -e 'Section "Device"\n Identifier "Intel Graphics"\n Driver "intel"\n Option "TearFree" "true"\nEndSection' | sudo tee /etc/X11/xorg.conf.d/20-intel.conf

sudo pacman -Syy vulkan-intel vulkan-icd-loader vulkan-mesa-layers libva-intel-driver lib32-mesa lib32-vulkan-intel  lib32-vulkan-icd-loader lib32-libva-intel-driver lib32-vulkan-mesa-layers mesa-demos xorg-xdpyinfo intel-ucode --noconfirm

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Atalhos ZSH###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

echo "alias att='sudo pacman -Syyuu -y'" >>  ~/.zshrc

echo "alias update-grub='sudo grub-mkconfig -o /boot/grub/grub.cfg'" >>  ~/.zshrc

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Desativar NetworkManager-wait-online.service###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo systemctl disable NetworkManager-wait-online.service

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Apps QT em Interfaces GTK###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S qt5ct --noconfirm

echo -e '\nQT_QPA_PLATFORMTHEME=qt5ct\nQT_AUTO_SCREEN_SCALE_FACTOR=0' | sudo tee -a /etc/environment

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###ZRAM###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

echo -e 'zram' | sudo tee /etc/modules-load.d/zram.conf && echo -e 'options zram num_devices=4' | sudo tee /etc/modprobe.d/zram.conf && echo -e 'KERNEL=="zram0", ATTR{disksize}="1G" RUN="/usr/bin/mkswap /dev/zram0", TAG+="systemd"\nKERNEL=="zram1", ATTR{disksize}="1G" RUN="/usr/bin/mkswap /dev/zram1", TAG+="systemd"\nKERNEL=="zram2", ATTR{disksize}="1G" RUN="/usr/bin/mkswap /dev/zram2", TAG+="systemd"\nKERNEL=="zram3", ATTR{disksize}="1G" RUN="/usr/bin/mkswap /dev/zram3", TAG+="systemd"' | sudo tee /etc/udev/rules.d/99-zram.rules && echo -e '/dev/zram0 none swap defaults 0 0\n/dev/zram1 none swap defaults 0 0\n/dev/zram2 none swap defaults 0 0\n/dev/zram3 none swap defaults 0 0\n' | sudo tee -a /etc/fstab

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###ZSH###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S zsh git wget

sh -c "$(wget https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Problemas com Wi-Fi###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

echo -e '\n[device]\nwifi.scan-rand-mac-address=no' | sudo tee -a /etc/NetworkManager/NetworkManager.conf

echo -e 'blacklist i2c_i801 wmi' | sudo tee -a /etc/modprobe.d/blacklist.conf

#
#
#
#
#

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Fontes###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji  ttf-roboto ttf-roboto-mono ttf-opensans

sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d
echo -e '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n<fontconfig>\n<match target="font">\n<edit name="antialias" mode="assign">\n<bool>true</bool>\n</edit>\n<edit name="hinting" mode="assign">\n<bool>true</bool>\n</edit>\n<edit mode="assign" name="rgba\n<const>rgb</const>\n</edit>\n<edit mode="assign" name="hintstyle"\n<const>hintslight</const>\n</edit>\n<edit mode="assign" name="lcdfilter"\n<const>lcddefault</const>\n</edit>\n</match>\n</fontconfig>' | sudo tee /etc/fonts/local.conf
echo -e '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n<fontconfig>\n<match target="font">\n<edit name="embeddedbitmap" mode="assign">\n<bool>false</bool>\n</edit>\n</match\n</fontconfig>' | sudo tee /etc/fonts/conf.d/20-no-embedded.conf

