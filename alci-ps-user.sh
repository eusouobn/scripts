#!/bin/bash

sudo pacman -S base-devel


git clone https://aur.archlinux.org/yay.git


cd yay


makepkg -si --noconfirm


yay -S fontconfig-ubuntu ttf-ms-fonts ttf-ubuntu-font-family


mkdir ~/.config/fontconfig/ 


cd ~/.config/fontconfig/


wget https://raw.githubusercontent.com/eusouobn/scripts/main/fonts.conf


sudo sed -i 12d /etc/profile.d/freetype2.sh && echo -e 'export FREETYPE_PROPERTIES="truetype:interpreter-version=40"' | sudo tee -a /etc/profile.d/freetype2.sh
