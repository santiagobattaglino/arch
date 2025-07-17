sudo umount -R /mnt 2>/dev/null || true # Unmounts everything under /mnt
sudo mount /dev/sdb2 /mnt # Assuming System A is p2 on your SSD_DRIVE
sudo mkdir -p /mnt/boot # Create /mnt/boot if it doesn't exist
sudo mount /dev/sdb1 /mnt/boot # Assuming EFI is p1
sudo mkdir -p /mnt/samples # Create /mnt/samples if it doesn't exist
sudo mount /dev/sdb4 /mnt/samples # Assuming Samples is p4
# IMPORTANT: Replace "YOUR_LUKS_PASSWORD_HERE" with the actual password string
echo -n "password" | sudo cryptsetup open /dev/sdb5 home - # Assuming Data is p5
sudo mkdir -p /mnt/home # Create /mnt/home if it doesn't exist
sudo mount /dev/mapper/home /mnt/home
