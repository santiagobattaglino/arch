localectl set-keymap en

# Install reflector if you don't have it (this should be run inside chroot)
pacman -S reflector --noconfirm

# Generate a new mirrorlist for Argentina (or closest/fastest)
# --age 12: mirrors updated in last 12 hours
# --protocol https: prefer secure connections
# --sort rate: sort by download speed
# --save: write to the default mirrorlist file
reflector --country "Argentina" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# If Argentina mirrors are still slow or don't work, try other regions or worldwide fast mirrors:
# reflector --country "Chile" --country "Brazil" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
# OR (for general fastest mirrors globally, might include distant ones)
# reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

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

echo ">>> (Chroot) Script finished. Exiting chroot."

# Clean up the script
rm /mnt/root/chroot-script.sh

echo ">>> [8/8] Cloning System A to System B and finalizing GRUB..."
umount -R /mnt
# Close the LUKS container before cloning
cryptsetup close home

dd if=${SYS_A_PART} of=${SYS_B_PART} bs=4M status=progress

# Remount to update GRUB for both slots
mount ${SYS_A_PART} /mnt
mount ${EFI_PART} /mnt/boot
mkdir /mnt/tmp_b
mount ${SYS_B_PART} /mnt/tmp_b

# Enable os-prober and regenerate GRUB config to see both slots
echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
