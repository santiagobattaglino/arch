#!/bin/bash

# This script is run inside the chroot environment

# Stop on any error
set -e

# ---ARGUMENTS FROM MAIN SCRIPT---
NEW_USER="$1"
USER_PASS="$2"
TIMEZONE="$3"
DATA_UUID="$4" # UUID for the encrypted partition
# ---END ARGUMENTS---

echo ">>> (Chroot) Setting Timezone..."
ln -sf /usr/share/zoneinfo/"${TIMEZONE}" /etc/localtime
hwclock --systohc

echo ">>> (Chroot) Configuring Locale..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo ">>> (Chroot) Setting Hostname..."
echo "arch-hypr" > /etc/hostname

echo ">>> (Chroot) Setting root and user passwords..."
echo "root:${USER_PASS}" | chpasswd
useradd -m "${NEW_USER}"
echo "${NEW_USER}:${USER_PASS}" | chpasswd
usermod -aG wheel "${NEW_USER}"

# Grant sudo access to the 'wheel' group automatically
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

echo ">>> (Chroot) Configuring crypttab for boot..."
# This tells the system how to unlock the encrypted partition
# It will use the UUID to find the partition and prompt for a password
echo "home UUID=${DATA_UUID} none" >> /etc/crypttab

echo ">>> (Chroot) Configuring mkinitcpio for encryption..."
# Add the 'encrypt' hook so the boot process knows how to handle LUKS
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
# Regenerate the initramfs image with the new hooks
mkinitcpio -P

# Install reflector
pacman -S reflector --noconfirm

# Generate a new mirrorlist
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Synchronize pacman databases with the new mirror list (crucial!)
pacman -Syy

echo ">>> (Chroot) Installing Hyprland and essentials..."
# --noconfirm avoids any interactive prompts
pacman -S --noconfirm hyprland kitty waybar wofi pipewire wireplumber polkit-kde-agent \
           xdg-desktop-portal-hyprland qt5-wayland qt6-wayland grim slurp \
           noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd

echo ">>> (Chroot) Enabling NetworkManager..."
systemctl enable NetworkManager

echo ">>> (Chroot) Installing GRUB for the first time..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo ">>> (Chroot) Script finished. Exiting chroot script."
