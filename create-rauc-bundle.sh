# These commands are to be executed from your new dedicated RAUC build server (booted from /dev/sdb).
# You are logged in as root.

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    echo "Exiting script."
    # Attempt to unmount if mounted, and close LUKS if open, for a clean exit
    if mountpoint -q "/mnt/source_systemA"; then umount "/mnt/source_systemA"; fi
    if mountpoint -q "/mnt/system_a_home"; then umount "/mnt/system_a_home"; fi
    if [[ -n "$LUKS_MAPPER_NAME" && -b "/dev/mapper/$LUKS_MAPPER_NAME" ]]; then cryptsetup luksClose "$LUKS_MAPPER_NAME"; fi
    exit 1
}

# Step 1: Create a temporary working directory for the bundle creation.
# This will be on your build server's root filesystem.
echo "Creating bundle creation directory..."
mkdir -p ~/rauc_bundle_workspace || error_exit "Failed to create ~/rauc_bundle_workspace."
cd ~/rauc_bundle_workspace || error_exit "Failed to change to workspace directory: ~/rauc_bundle_workspace. Check permissions or if directory exists."
echo "Current working directory: $(pwd)" # Diagnostic: Show current directory

# Step 2: Mount System A's root filesystem (read-only).
# This is your source for the SquashFS image.
echo "Mounting System A (/dev/sda2) as read-only source..."
mkdir -p /mnt/source_systemA || error_exit "Failed to create /mnt/source_systemA mount point."
mount -o ro /dev/sda2 /mnt/source_systemA || error_exit "Failed to mount /dev/sda2 to /mnt/source_systemA. Ensure /dev/sda2 exists and is not already mounted."

# Step 3: Create the SquashFS image of System A's root filesystem.
# This will be a clean, consistent image.
echo "Checking for existing rootfs_systemA.squashfs..."
if [[ -f "rootfs_systemA.squashfs" && -s "rootfs_systemA.squashfs" ]]; then
    echo "rootfs_systemA.squashfs already exists and is not empty. Skipping mksquashfs."
else
    echo "Creating SquashFS image of System A (this may take a while)..."
    mksquashfs /mnt/source_systemA rootfs_systemA.squashfs -comp xz || error_exit "Failed to create SquashFS image. Check mksquashfs output above for details."
fi

# --- Diagnostic: Verify SquashFS file creation ---
echo "Verifying creation of rootfs_systemA.squashfs..."
if [[ ! -f "rootfs_systemA.squashfs" ]]; then
    error_exit "rootfs_systemA.squashfs was NOT created. Check mksquashfs output for errors."
fi
if [[ ! -s "rootfs_systemA.squashfs" ]]; then
    error_exit "rootfs_systemA.squashfs was created but is EMPTY. Check mksquashfs output for errors."
fi
echo "rootfs_systemA.squashfs created successfully and is not empty."
echo "Files in current directory after mksquashfs:" # Diagnostic: List files after mksquashfs
ls -l
# --- End Diagnostic ---

# Step 4: Generate a signing key and certificate.
# These keys will be used to sign your RAUC bundles.
echo "Generating signing keys and certificate..."
openssl genpkey -algorithm RSA -out private.key || error_exit "Failed to generate private key."
openssl req -x509 -new -key private.key -out certificate.pem -days 365 -subj "/CN=RAUC Test Certificate" || error_exit "Failed to generate certificate."

# Step 5: Recalculate SHA256 and Size for the SquashFS file.
echo "Recalculating SHA256 sum and size for rootfs_systemA.squashfs..."
SQUASHFS_SHA256=$(sha256sum rootfs_systemA.squashfs | awk '{print $1}') || error_exit "Failed to calculate SHA256 sum."
SQUASHFS_SIZE=$(stat -c %s rootfs_systemA.squashfs) || error_exit "Failed to get file size."

echo "Calculated SHA256: $SQUASHFS_SHA256"
echo "Calculated Size: $SQUASHFS_SIZE"

# Step 6: Create the RAUC bundle configuration file (`rauc.conf`).
printf '[rauc]\ncompatible=Arch-Linux\nversion=1.0.0\n' > rauc.conf || error_exit "Failed to create rauc.conf."

# Step 7: Create the RAUC manifest file (`manifest.raucm`).
printf '[update]\ncompatible=Arch-Linux\nversion=1.0.0\n\n[image.rootfs]\nfilename=rootfs_systemA.squashfs\nsha256=%s\nsize=%s\n' "$SQUASHFS_SHA256" "$SQUASHFS_SIZE" > manifest.raucm || error_exit "Failed to create manifest.raucm."

echo "Manifest created. Verifying its content:"
cat manifest.raucm

# --- Diagnostic Block: Verify actual file properties vs. manifest ---
echo "--- Diagnostic: Verifying actual SquashFS file properties and manifest content before bundling ---"
echo "Actual SHA256 of rootfs_systemA.squashfs:"
sha256sum rootfs_systemA.squashfs
echo "Actual Size of rootfs_systemA.squashfs:"
stat -c %s rootfs_systemA.squashfs
echo "Content of manifest.raucm:"
cat manifest.raucm
echo "--- End Diagnostic ---"
# --- End Diagnostic Block ---

# Step 8: Build the RAUC bundle.
echo "Attempting to build RAUC bundle..."
# Explicitly passing manifest and image file to rauc bundle
rauc bundle --key=private.key --cert=certificate.pem \
 --manifest=manifest.raucm \
 --output=systemA_bundle_v1.0.0.raucb \
 rootfs_systemA.squashfs || error_exit "Failed to build RAUC bundle. Check RAUC output above for details."

# Step 9: Verify the created bundle.
echo "Verifying the created bundle..."
rauc info systemA_bundle_v1.0.0.raucb || error_exit "Failed to verify RAUC bundle."

# Step 10: Move the completed bundle to System A's /home directory.
# This makes it accessible from your main system for installation.
echo "Moving completed bundle to System A's /home directory..."
# Assuming /home is on /dev/sda5 (your LUKS partition) and it's currently unmounted.
LUKS_MAPPER_NAME="home_partition_on_sda" # Choose a unique mapper name
cryptsetup luksOpen /dev/sda5 "$LUKS_MAPPER_NAME" || error_exit "Failed to unlock /dev/sda5. Please provide LUKS password."
mkdir -p /mnt/system_a_home || error_exit "Failed to create mount point /mnt/system_a_home."
mount /dev/mapper/"$LUKS_MAPPER_NAME" /mnt/system_a_home || error_exit "Failed to mount /dev/mapper/$LUKS_MAPPER_NAME."

# Move the bundle
mv systemA_bundle_v1.0.0.raucb /mnt/system_a_home/systemA_bundle_v1.0.0.raucb || error_exit "Failed to move bundle to System A's home."
echo "Bundle moved to /mnt/system_a_home/systemA_bundle_v1.0.0.raucb"

# Unmount System A's /home and close LUKS
umount /mnt/system_a_home || echo "WARNING: Failed to unmount /mnt/system_a_home. Manual unmount may be needed."
rmdir /mnt/system_a_home || echo "WARNING: Failed to remove /mnt/system_a_home directory. Manual cleanup may be needed."
cryptsetup luksClose "$LUKS_MAPPER_NAME" || echo "WARNING: Failed to close LUKS device. Manual close may be needed."

# Step 11: Clean up the temporary directory on the build server.
echo "Cleaning up temporary directory on build server..."
cd ~
rm -rf ~/rauc_bundle_workspace || echo "WARNING: Failed to remove ~/rauc_bundle_workspace. Manual cleanup may be needed."
echo "RAUC bundle creation process complete!"
echo "You can now reboot into System A and install the bundle onto System B."
