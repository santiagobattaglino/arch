# Step 8: Unmount partitions and reboot.
echo "Unmounting all partitions..."
umount -R /mnt || { echo "ERROR: Failed to unmount partitions. Try 'umount -lfR /mnt'."; }
echo "Installation complete. Rebooting into your new RAUC build server on /dev/sdb..."
reboot
