# --- Inside the chroot environment (commands below run automatically) ---
echo "Configuring timezone, locale, and hostname inside chroot..."
ln -sf /usr/share/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime # Adjust timezone as needed
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "rauc-build-server" > /etc/hostname # Set a clear hostname for your build system

# Set root password (you will be prompted to type this)
echo "Setting root password for the new system..."
passwd

# Install and enable NetworkManager for easy network setup after boot
# NetworkManager handles wired connections automatically via DHCP.
echo "Installing and enabling NetworkManager for automatic wired networking..."
pacman -S --noconfirm networkmanager || { echo "WARNING: NetworkManager installation failed. Manual network setup may be required."; }
systemctl enable NetworkManager

# Step 7: Install and configure GRUB for UEFI.
echo "Installing GRUB for UEFI to /dev/sdb..."
# --efi-directory points to where the ESP is mounted *inside the chroot* (/boot/efi).
# --bootloader-id is the name that will appear in your UEFI boot menu.
# --removable is good for external drives, making it more portable.
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RAUCBuildServer --removable /dev/sdb || { echo "ERROR: GRUB installation failed. Check UEFI settings."; exit 1; }

echo "Generating GRUB configuration for /dev/sdb (will detect /dev/sda systems)..."
grub-mkconfig -o /boot/grub/grub.cfg || { echo "ERROR: grub-mkconfig failed."; exit 1; }

# --- End of chroot environment (commands below run automatically) ---
echo "Exiting chroot environment..."
exit

# Executing final step and reboot"
# ./rauc-build-server-final.sh
