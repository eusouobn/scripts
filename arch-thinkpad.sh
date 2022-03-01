#!/bin/bash

echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###RELOGIO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

timedatectl set-ntp true



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###PARTICIONAMENTO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

fdisk /dev/sda

cfdisk /dev/sda



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###FORMATAR PARTICOES###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

mkfs.fat /dev/sda1

mkfs.btrfs /dev/sda2 --force




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MONTAR PARTICOES###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

mkdir /mnt/efi

mount /dev/sda1 /mnt/efi

mount /dev/sda2 /mnt


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###MIRRORS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacman -S reflector

reflector --country Brazil --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###BASE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

pacstrap /mnt base linux-zen linux-firmware




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###FSTAB###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

genfstab -U /mnt >> /mnt/etc/fstab



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###CHROOT###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

arch-chroot /mnt

