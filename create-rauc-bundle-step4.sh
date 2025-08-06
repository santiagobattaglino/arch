# Step 4: Generate a signing key and certificate.
# These keys will be used to sign your RAUC bundles.
echo "Generating signing keys and certificate..."
openssl genpkey -algorithm RSA -out private.key || { echo "ERROR: Failed to generate private key."; exit 1; }
openssl req -x509 -new -key private.key -out certificate.pem -days 365 -subj "/CN=RAUC Test Certificate" || { echo "ERROR: Failed to generate certificate."; exit 1; }

# Step 5: Recalculate SHA256 and Size for the SquashFS file.
echo "Recalculating SHA256 sum and size for rootfs_systemA.squashfs..."
SQUASHFS_SHA256=$(sha256sum rootfs_systemA.squashfs | awk '{print $1}')
SQUASHFS_SIZE=$(stat -c %s rootfs_systemA.squashfs)

echo "Calculated SHA256: $SQUASHFS_SHA256"
echo "Calculated Size: $SQUASHFS_SIZE"

# Step 6: Create the RAUC bundle configuration file (`rauc.conf`).
printf '[rauc]\ncompatible=Arch-Linux\nversion=1.0.0\n' > rauc.conf || { echo "ERROR: Failed to create rauc.conf."; exit 1; }

# Step 7: Create the RAUC manifest file (`manifest.raucm`).
printf '[update]\ncompatible=Arch-Linux\nversion=1.0.0\n\n[image.rootfs]\nfilename=rootfs_systemA.squashfs\nsha256=%s\nsize=%s\n' "$SQUASHFS_SHA256" "$SQUASHFS_SIZE" > manifest.raucm || { echo "ERROR: Failed to create manifest.raucm."; exit 1; }

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
rauc bundle --key=private.key --cert=certificate.pem \
 . systemA_bundle_v1.0.0.raucb || { echo "ERROR: Failed to build RAUC bundle."; exit 1; }

# Step 9: Verify the created bundle.
echo "Verifying the created bundle..."
rauc info systemA_bundle_v1.0.0.raucb || { echo "ERROR: Failed to verify RAUC bundle."; exit 1; }

# Step 10: Move the completed bundle to System A's /home directory.
# This makes it accessible from your main system for installation.
echo "Moving completed bundle to System A's /home directory..."
# First, mount System A's /home partition if it's separate, or its root if /home is on root.
# Assuming /home is on /dev/sda5 (your LUKS partition) and it's currently unmounted.
LUKS_MAPPER_NAME="home_partition_on_sda" # Choose a unique mapper name
cryptsetup luksOpen /dev/sda5 "$LUKS_MAPPER_NAME" || { echo "ERROR: Failed to unlock /dev/sda5."; exit 1; }
mkdir -p /mnt/system_a_home || { echo "ERROR: Failed to create mount point."; exit 1; }
mount /dev/mapper/"$LUKS_MAPPER_NAME" /mnt/system_a_home || { echo "ERROR: Failed to mount /dev/sda5."; exit 1; }

# Move the bundle
mv systemA_bundle_v1.0.0.raucb /mnt/system_a_home/systemA_bundle_v1.0.0.raucb || { echo "ERROR: Failed to move bundle to System A's home."; exit 1; }
echo "Bundle moved to /mnt/system_a_home/systemA_bundle_v1.0.0.raucb"

# Unmount System A's /home and close LUKS
umount /mnt/system_a_home || { echo "ERROR: Failed to unmount /mnt/system_a_home."; }
rmdir /mnt/system_a_home || { echo "ERROR: Failed to remove /mnt/system_a_home directory."; }
cryptsetup luksClose "$LUKS_MAPPER_NAME" || { echo "ERROR: Failed to close LUKS device."; }

# Step 11: Clean up the temporary directory on the build server.
echo "Cleaning up temporary directory on build server..."
cd ~
rm -rf ~/rauc_bundle_workspace
echo "RAUC bundle creation process complete!"
echo "You can now reboot into System A and install the bundle onto System B."
