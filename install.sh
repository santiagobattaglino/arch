#!/bin/bash

# A SCRIPT TO AUTOMATE THE ARCH LINUX A/B PARTITION INSTALL
# WITH A DEDICATED SAMPLE LIBRARY AND ENCRYPTED HOME PARTITION.
# WARNING: THIS WILL WIPE THE SPECIFIED DRIVE.

# ---CONFIGURATION---
# ⚠️ EDIT THESE VARIABLES BEFORE RUNNING!
SSD_DRIVE="/dev/sdb"     # The target SSD (e.g., /dev/sda or /dev/vda)
NEW_USER="user"    # Your desired username
USER_PASS="user"   # Your desired password for the user and root
LUKS_PASS="password" # The password for your encrypted data partition
TIMEZONE="America/Argentina/Buenos_Aires"
# ---END CONFIGURATION---

# Stop on any error
set -e

# Set console keyboard layout to spanish (optional)
localectl set-keymap es

echo ">>> [1/8] Partitioning the drive: ${SSD_DRIVE}"
# New layout: EFI, System A, System B, Samples, Data
parted ${SSD_DRIVE} --script -- mklabel gpt \
  mkpart "EFI" fat32 1MiB 513MiB \
  set 1 esp on \
  mkpart "SystemA" ext4 513MiB 25.5GiB \
  mkpart "SystemB" ext4 25.5GiB 50.5GiB \
  mkpart "SampleLibrary" ext4 50.5GiB 80.5GiB \
  mkpart "UserData" ext4 80.5GiB 100%

# Short pause to let the kernel recognize new partitions
sleep 2

# Assign partition variables
EFI_PART="${SSD_DRIVE}1"
SYS_A_PART="${SSD_DRIVE}2"
SYS_B_PART="${SSD_DRIVE}3"
SAMPLES_PART="${SSD_DRIVE}4"
DATA_PART="${SSD_DRIVE}5"

echo ">>> [2/8] Formatting partitions..."
mkfs.fat -F32 ${EFI_PART}
mkfs.ext4 ${SYS_A_PART}
mkfs.ext4 ${SYS_B_PART}
mkfs.ext4 ${SAMPLES_PART}

echo ">>> [3/8] Setting up LUKS encryption for User Data..."
# Use the password from the variable to format the LUKS partition non-interactively
echo -n "${LUKS_PASS}" | cryptsetup luksFormat ${DATA_PART} -
# Open the LUKS container
echo -n "${LUKS_PASS}" | cryptsetup open ${DATA_PART} home -
# Format the opened container
mkfs.ext4 /dev/mapper/home

echo ">>> [4/8] Mounting filesystems for Slot A..."
mount ${SYS_A_PART} /mnt
mkdir -p /mnt/boot
mkdir -p /mnt/samples
mkdir -p /mnt/home
mount ${EFI_PART} /mnt/boot
mount ${SAMPLES_PART} /mnt/samples
mount /dev/mapper/home /mnt/home

echo ">>> [5/8] Installing base system and packages with pacstrap..."
# Added cryptsetup to the list of packages
pacstrap -K /mnt base linux linux-firmware nano networkmanager grub efibootmgr os-prober cryptsetup

echo ">>> [6/8] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> [7/8] Chrooting into new system to run setup..."
# Copy the chroot script into the new system
cp chroot-script.sh /mnt/root/
chmod +x /mnt/root/chroot-script.sh

# Get the UUID of the physical data partition for crypttab
DATA_UUID=$(blkid -s UUID -o value ${DATA_PART})

# Run the chroot script, passing variables to it
arch-chroot /mnt /root/chroot-script.sh "${NEW_USER}" "${USER_PASS}" "${TIMEZONE}" "${DATA_UUID}"

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

# Cleanup
umount -R /mnt

echo "✅ Installation Complete! You can now reboot."
echo "On boot, you will be prompted for your LUKS password to unlock your home directory."
