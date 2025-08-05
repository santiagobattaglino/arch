# These commands are to be executed from your Arch Linux Live (Recovery) environment.
# You are logged in as root, so 'sudo' is not needed.

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    echo "Exiting script."
    # Attempt to unmount if mounted
    if mountpoint -q "/mnt/home_workspace/rauc_bundle_creation"; then umount "/mnt/home_workspace/rauc_bundle_creation"; fi
    if mountpoint -q "/mnt/home_workspace"; then umount "/mnt/home_workspace"; fi
    if mountpoint -q "/mnt/system_a_root"; then umount "/mnt/system_a_root"; fi
    if [[ -n "$LUKS_MAPPER_NAME" && -b "/dev/mapper/$LUKS_MAPPER_NAME" ]]; then cryptsetup luksClose "$LUKS_MAPPER_NAME"; fi
    exit 1
}

# Step 0: Unlock and Mount your /home partition (/dev/sda5).
# This is crucial for using it as your workspace.
# You will be prompted for your LUKS password for /dev/sda5.
echo "Unlocking and mounting /home partition for workspace..."
LUKS_MAPPER_NAME="home_workspace" # Using 'home_workspace' as the mapper name
cryptsetup luksOpen /dev/sda5 "$LUKS_MAPPER_NAME" || error_exit "Failed to unlock /dev/sda5."
mkdir -p /mnt/home_workspace || error_exit "Failed to create /mnt/home_workspace."
mount /dev/mapper/"$LUKS_MAPPER_NAME" /mnt/home_workspace || error_exit "Failed to mount /dev/mapper/$LUKS_MAPPER_NAME."

# Step 1: Create a temporary working directory for the bundle creation within your /home partition.
# All RAUC-related files will be created here.
mkdir -p /mnt/home_workspace/rauc_bundle_creation || error_exit "Failed to create rauc_bundle_creation directory."
cd /mnt/home_workspace/rauc_bundle_creation || error_exit "Failed to change to rauc_bundle_creation directory."

# Step 2: Mount System A's root filesystem.
# You need to access the files of System A (/dev/sda2) to create its image.
# We'll mount it to a temporary location.
# Ensure /mnt/system_a_root is empty or doesn't exist before mounting.
mkdir -p /mnt/system_a_root || error_exit "Failed to create mount point /mnt/system_a_root."
mount /dev/sda2 /mnt/system_a_root || error_exit "Failed to mount /dev/sda2."

# Step 3: Create the SquashFS image of System A's root filesystem.
# This will create a compressed, read-only image of your System A.
# This might take some time depending on the size of your root filesystem.
# The output filename will be `rootfs_systemA.squashfs`.
mksquashfs /mnt/system_a_root rootfs_systemA.squashfs -comp xz || error_exit "Failed to create SquashFS image."

# --- NEW STEP: Copy the SquashFS file to a permanent location ---
# This ensures the file is saved outside the temporary workspace before cleanup.
echo "Copying SquashFS image to permanent location on /home..."
# We'll put it directly in the root of your /home partition for easy access.
cp rootfs_systemA.squashfs /mnt/home_workspace/rootfs_systemA.squashfs || error_exit "Failed to copy SquashFS image."
echo "SquashFS image successfully copied to /mnt/home_workspace/rootfs_systemA.squashfs"

# Step 4: Unmount System A's root filesystem.
# It's good practice to unmount it once the image is created.
umount /mnt/system_a_root || error_exit "Failed to unmount /mnt/system_a_root."
rmdir /mnt/system_a_root || error_exit "Failed to remove /mnt/system_a_root directory."

# Step 5: Unmount the /home workspace and close the LUKS device.
# This is crucial before rebooting back into System A.
echo "Unmounting /home workspace and closing LUKS device..."
umount /mnt/home_workspace || error_exit "Failed to unmount /mnt/home_workspace."
rmdir /mnt/home_workspace || error_exit "Failed to remove /mnt/home_workspace directory."
cryptsetup luksClose "$LUKS_MAPPER_NAME" || error_exit "Failed to close LUKS device."

echo "SquashFS image created and saved successfully on your /home partition."
echo "You can now reboot into System A to complete the RAUC bundle creation."
