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



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###FUSO HORARIO###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

hwclock --systohc




echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###LOCALE###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

mv /etc/locale.gen /etc/locale.gen.bak

echo -e 'pt_BR.UTF-8 UTF-8' | tee /etc/locale.gen

locale-gen

echo -e 'LANG=pt_BR.UTF-8' | tee /etc/locale.conf



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###HOSTNAME###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

echo -e 'thinkpad-arch' | tee /etc/hostname



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###INITRAMFS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1 

mkinitcpio -P



echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###ROOT###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"

sleep 1

#ROOT PASSWORD {{{
root_password() {
	print_title "ROOT PASSWORD"
	print_warning "Enter your new root password"
	arch_chroot "passwd"
	pause_function
}


echo -e "\n#\n#\n#\n#\n#\n#\n#\n#\n#\n###USUARIOS###\n#\n#\n#\n#\n#\n#\n#\n#\n#\n"


