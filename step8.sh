# Assign partition variables
EFI_PART="${SSD_DRIVE}1"
SYS_A_PART="${SSD_DRIVE}2"
SYS_B_PART="${SSD_DRIVE}3"

# Clean up the script
rm /mnt/root/chroot-script.sh

echo ">>> [8/8] Cloning System A to System B and finalizing GRUB..."
umount -R /mnt
# Close the LUKS container before cloning
cryptsetup close home

dd if="${SYS_A_PART}" of="${SYS_B_PART}" bs=4M status=progress

# Remount to update GRUB for both slots
mount "${SYS_A_PART}" /mnt
mount "${EFI_PART}" /mnt/boot
mkdir /mnt/tmp_b
mount "${SYS_B_PART}" /mnt/tmp_b

# Enable os-prober and regenerate GRUB config to see both slots
echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Cleanup
umount -R /mnt

echo "✅ Installation Complete! You can now reboot."
echo "On boot, you will be prompted for your LUKS password to unlock your home directory."
