#!/bin/bash


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MIRRORS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"



sudo pacman -S pacman-contrib --noconfirm && sudo cp cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak && curl -s "https://archlinux.org/mirrorlist/?country=BR&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 5 - | sudo tee /etc/pacman.d/mirrorlist



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARALLEL DOWNLOADS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1


sudo cp /etc/pacman.conf /etc/pacman.conf.bak && sudo sed -i '37c\ParallelDownloads = 16' /etc/pacman.conf && sudo pacman -Syyyuuu



sudo pacman -S base-devel


git clone https://aur.archlinux.org/yay.git


cd yay


makepkg -si --noconfirm


yay -S fontconfig-ubuntu ttf-ms-fonts ttf-ubuntu-font-family

wget https://raw.githubusercontent.com/eusouobn/scripts/main/fonts.conf


mkdir ~/.config/fontconfig/ 


mv fonts.conf ~/.config/fontconfig/fonts.conf


wget https://raw.githubusercontent.com/eusouobn/scripts/main/fonts.conf


sudo sed -i 12d /etc/profile.d/freetype2.sh && echo -e 'export FREETYPE_PROPERTIES="truetype:interpreter-version=40"' | sudo tee -a /etc/profile.d/freetype2.sh



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###INTERFACE GRAFICA###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S xdg-user-dirs xorg-server xorg-xinit xterm xf86-video-intel xfce4 lightdm lightdm-gtk-greeter networkmanager xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin pavucontrol --noconfirm

sudo systemctl enable lightdm NetworkManager

sudo localectl set-x11-keymap br abnt2 thinkpad



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###SOFTWARES PADRAO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


sudo pacman -S simplescreenrecorder ffmpeg psensor gimp gnome-disk-utility frei0r-plugins ntfs-3g exfatprogs gsmartcontrol obs-studio uget qbittorrent papirus-icon-theme telegram-desktop gamemode fatsort mpv audacious inkscape audacity kdenlive libreoffice-fresh-pt-br alsa-firmware alsa-utils a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore gstreamer gst-plugins-base gst-plugins-base-libs gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb git go fuse2 base-devel movit --noconfirm

sudo pacman -S pipewire-pulse --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###LIMITAR LOGS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo journalctl --vacuum-time=2d




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MULTILIB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


sudo cp /etc/pacman.conf /etc/pacman.conf.bak && sudo sed -i '92c\[multilib]' /etc/pacman.conf && sudo sed -i '93c\Include = /etc/pacman.d/mirrorlist' /etc/pacman.conf && sudo pacman -Syyyuu



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###DESCOMPACTADORES###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S xarchiver file-roller tar gzip bzip2 zip unzip unrar p7zip --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###UTILITARIOS BASICOS XFCE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S galculator xfce4-screenshooter ristretto mousepad hardinfo audacious --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###BLUETOOTH###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S bluez bluez-utils --noconfirm

sudo modprobe btusb

sudo systemctl enable bluetooth

sudo systemctl start bluetooth




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###WINE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S wine-staging wine-mono wine-gecko giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls mpg123 lib32-mpg123 openal lib32-openal v4l-utils lib32-v4l-utils libpulse lib32-libpulse libgpg-error lib32-libgpg-error alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite libxcomposite lib32-libxcomposite libxinerama lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses opencl-icd-loader lib32-opencl-icd-loader libxslt lib32-libxslt libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader vkd3d lib32-vkd3d lib32-gnutls winetricks --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Impressão###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo pacman -S cups gtk3-print-backends system-config-printer hplip xsane python-pyqt5 --noconfirm && sudo systemctl enable cups && sudo systemctl start cups


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Tearing e Pacotes de Video Intel###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1


echo -e 'Section "Device"\n Identifier "Intel Graphics"\n Driver "intel"\n Option "TearFree" "true"\nEndSection' | sudo tee /etc/X11/xorg.conf.d/20-intel.conf

sudo pacman -Syy vulkan-intel vulkan-icd-loader vulkan-mesa-layers libva-intel-driver lib32-mesa lib32-vulkan-intel lib32-vulkan-icd-loader lib32-libva-intel-driver lib32-vulkan-mesa-layers mesa-demos xorg-xdpyinfo intel-ucode --noconfirm



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###Desativar NetworkManager-wait-online.service###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo systemctl disable NetworkManager-wait-online.service

sudo systemctl enable NetwotkManager lightdm


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARAMETROS GRUB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

sudo cp /etc/default/grub /etc/default/grub.bak && sudo sed -i '4c\GRUB_TIMEOUT=1' /etc/default/grub && sudo sed -i '6c\GRUB_CMDLINE_LINUX_DEFAULT="mitigations=off"' /etc/default/grub && sudo grub-mkconfig -o /boot/grub/grub.cfg


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###AUTOLOGIN LIGHTDM###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


sudo cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.bak && sudo sed -i '120c\autologin-user=bn' /etc/lightdm/lightdm.conf
