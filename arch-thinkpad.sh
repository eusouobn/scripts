#!/bin/bash

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###RELOGIO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

timedatectl set-ntp true



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARTICIONAMENTO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

fdisk /dev/sda

cfdisk /dev/sda



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###FORMATAR PARTICOES###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 2

mkfs.fat /dev/sda1

mkfs.btrfs /dev/sda2 --force




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MONTAR PARTICOES###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 2

mkdir /mnt/efi

mount /dev/sda1 /mnt/efi

mount /dev/sda2 /mnt


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MIRRORS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 2

pacman -S pacman-contrib

curl -s "https://archlinux.org/mirrorlist/?country=BR&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 5 - | sudo tee /etc/pacman.d/mirrorlist



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARALLEL DOWNLOADS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


cp /etc/pacman.conf /etc/pacman.conf.bak && sed -i '37c\ParallelDownloads = 16' /etc/pacman.conf && pacman -Syyyuuu



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###BASE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 2

pacstrap /mnt base linux-zen linux-firmware




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###FSTAB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

genfstab -U /mnt >> /mnt/etc/fstab




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###SCRIPT PS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

cd /mnt
git clone http://github.com/eusouobn/scripts




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###CHROOT###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

arch-chroot /mnt

