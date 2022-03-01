#!/bin/bash

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###FUSO HORARIO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

hwclock --systohc




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###LOCALE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

mv /etc/locale.gen /etc/locale.gen.bak

echo -e 'pt_BR.UTF-8 UTF-8' | tee /etc/locale.gen

locale-gen

localectl set-locale LANG=pt_BR.UTF-8

unset LANG

source /etc/profile.d/locale.sh



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###HOSTNAME###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

echo -e 'thinkpad-arch' | tee /etc/hostname



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###INITRAMFS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1 

mkinitcpio -P




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARALLEL DOWNLOADS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


cp /etc/pacman.conf /etc/pacman.conf.bak && sed -i '37c\ParallelDownloads = 16' /etc/pacman.conf && pacman -Syyyuuu




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###GRUB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

mount /dev/sda1 /boot/efi/

pacman -S grub efibootmgr

grub-install --target=x86_64-efi --efi-directory=boot/efi --bootloader-id=Arch

grub-mkconfig -o /boot/grub/grub.cfg


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###ROOT###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

passwd



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###USUARIOS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

useradd -m bn

passwd bn

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###INTERFACE GRAFICA###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S xdg-user-dirs xorg-server xorg-xinit xterm xf86-video-intel xfce4 lightdm lightdm-gtk-greeter

systemctl enable lightdm NetworkManager

localectl set-x11-keymap br abnt2 thinkpad



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###SOFTWARES PADRAO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


pacman -S simplescreenrecorder ffmpeg psensor gimp gnome-disk-utility frei0r-plugins ntfs-3g exfat-utils gsmartcontrol obs-studio uget qbittorrent papirus-icon-theme telegram-desktop gamemode fatsort mpv audacious inkscape audacity kdenlive libreoffice-fresh-pt-br alsa-firmware alsa-utils a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore gstreamer gst-plugins-base gst-plugins-base-libs gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb git go fuse2 base-devel movit --noconfirm

pacman -S pipewire-pulse



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###LIMITAR LOGS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

journalctl --vacuum-time=2d




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MULTILIB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


cp /etc/pacman.conf /etc/pacman.conf.bak && sed -i '92c\[multilib]' /etc/pacman.conf && sed -i '93c\Include = /etc/pacman.d/mirrorlist' /etc/pacman.conf && pacman -Syyyuu



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###DESCOMPACTADORES###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S ark file-roller tar gzip bzip2 zip unzip unrar p7zip --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###UTILITARIOS BASICOS XFCE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S galculator xfce4-screenshooter ristretto mousepad hardinfo audacious --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###BLUETOOTH###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S bluez bluez-utils --noconfirm

modprobe btusb

systemctl enable bluetooth

systemctl start bluetooth



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARAMETROS GRUB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo cp /etc/default/grub /etc/default/grub.bak && sed -i '4c\GRUB_TIMEOUT=1' /etc/default/grub && sed -i '6c\GRUB_CMDLINE_LINUX_DEFAULT="mitigations=off"' /etc/default/grub && grub-mkconfig -o /boot/grub/grub.cfg




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###WINE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S wine-staging wine-mono wine-gecko giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls mpg123 lib32-mpg123 openal lib32-openal v4l-utils lib32-v4l-utils libpulse lib32-libpulse libgpg-error lib32-libgpg-error alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite libxcomposite lib32-libxcomposite libxinerama lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses opencl-icd-loader lib32-opencl-icd-loader libxslt lib32-libxslt libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader vkd3d lib32-vkd3d lib32-gnutls winetricks --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Impressão###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S cups gtk3-print-backends system-config-printer hplip xsane python-pyqt5 --noconfirm && systemctl enable cups && systemctl start cups


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Tearing e Pacotes de Video Intel###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1


echo -e 'Section "Device"\n Identifier "Intel Graphics"\n Driver "intel"\n Option "TearFree" "true"\nEndSection' | tee /etc/X11/xorg.conf.d/20-intel.conf

pacman -Syy vulkan-intel vulkan-icd-loader vulkan-mesa-layers libva-intel-driver lib32-mesa lib32-vulkan-intel lib32-vulkan-icd-loader lib32-libva-intel-driver lib32-vulkan-mesa-layers mesa-demos xorg-xdpyinfo intel-ucode --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Desativar NetworkManager-wait-online.service###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo systemctl disable NetworkManager-wait-online.service
