# These commands are to be executed from a **NEW, separate Arch Linux Live USB environment**.
# You are logged in as root, so 'sudo' is not needed unless explicitly stated for specific commands.

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    echo "Exiting script."
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 0: Initial Setup (in Live USB environment)
echo "Verifying internet connection..."
ping -c 3 archlinux.org || { echo "ERROR: No internet connection. Please connect to the internet."; exit 1; }
echo "Setting console keyboard layout to Spanish (es)..."
loadkeys es # Set to 'es' for Spanish keyboard layout.

# Install sgdisk if not present (part of gptfdisk package)
if ! command_exists sgdisk; then
    echo "sgdisk not found. Installing gptfdisk..."
    pacman -Sy --noconfirm gptfdisk || error_exit "Failed to install gptfdisk (sgdisk)."
fi

# Step 1: Partition /dev/sdb for UEFI using sgdisk (unattended).
# This will create two partitions:
# /dev/sdb1: EFI System Partition (ESP) - ~512MB, FAT32
# /dev/sdb2: Root partition for Arch Linux - remaining space, Ext4
echo "Starting unattended partitioning of /dev/sdb. ALL DATA ON /dev/sdb WILL BE ERASED!"
echo "Wiping existing partition table on /dev/sdb..."
sgdisk -Z /dev/sdb || error_exit "Failed to wipe partition table on /dev/sdb."

echo "Creating EFI System Partition (/dev/sdb1)..."
sgdisk -n 1:0:+512MiB -t 1:ef00 -c 1:"EFI System Partition" /dev/sdb || error_exit "Failed to create ESP."

echo "Creating Arch Linux Root Partition (/dev/sdb2)..."
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Arch Linux Root" /dev/sdb || error_exit "Failed to create root partition."

echo "Partitioning complete. Verifying new partition table:"
sgdisk -p /dev/sdb

# Step 2: Format the new partitions.
echo "Formatting /dev/sdb1 (ESP) as FAT32..."
mkfs.fat -F32 /dev/sdb1 || { echo "ERROR: Failed to format /dev/sdb1."; exit 1; }
echo "Formatting /dev/sdb2 (Root) as Ext4..."
mkfs.ext4 /dev/sdb2 || { echo "ERROR: Failed to format /dev/sdb2."; exit 1; }

# Step 3: Mount the new partitions.
echo "Mounting /dev/sdb2 (Root) to /mnt..."
mkdir -p /mnt
mount /dev/sdb2 /mnt || { echo "ERROR: Failed to mount /dev/sdb2."; exit 1; }
echo "Mounting /dev/sdb1 (ESP) to /mnt/boot/efi..."
mkdir -p /mnt/boot/efi
mount /dev/sdb1 /mnt/boot/efi || { echo "ERROR: Failed to mount /dev/sdb1 to /mnt/boot/efi."; exit 1; }

# Step 4: Install the base system and essential RAUC tools.
echo "Installing base system and RAUC tools onto /dev/sdb2 (this may take a while)..."
pacstrap /mnt base linux linux-firmware grub efibootmgr openssl rauc squashfs-tools || { echo "ERROR: pacstrap failed."; exit 1; }

# Step 5: Generate fstab for the new system.
echo "Generating fstab for the new system..."
genfstab -U /mnt >> /mnt/etc/fstab || { echo "ERROR: genfstab failed."; exit 1; }

# Step 6: Chroot into the new system to configure it.
echo "Chrooting into the new system..."
arch-chroot /mnt || { echo "ERROR: arch-chroot failed."; exit 1; }

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

# Step 8: Unmount partitions and reboot.
echo "Unmounting all partitions..."
umount -R /mnt || { echo "ERROR: Failed to unmount partitions. Try 'umount -lfR /mnt'."; }
echo "Installation complete. Rebooting into your new RAUC build server on /dev/sdb..."
reboot
