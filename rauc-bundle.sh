# These commands are to be executed from your running Arch Linux System A.

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    echo "Exiting script."
    exit 1
}

# Step 1: Create a NEW temporary working directory for the bundle components.
# This is where the manifest, keys, and the final bundle will be created.
# The SquashFS file itself will be referenced from your home directory.
mkdir -p ~/rauc_bundle_temp || error_exit "Failed to create rauc_bundle_temp directory."
cd ~/rauc_bundle_temp || error_exit "Failed to change to rauc_bundle_temp directory."

# Step 2: Generate a signing key and certificate (if you don't have them).
# RAUC bundles must be signed. If you already have a key.pem and cert.pem
# from a previous attempt that you want to reuse, skip this step.
# Otherwise, generate new ones:
openssl genpkey -algorithm RSA -out private.key || error_exit "Failed to generate private key."
openssl req -x509 -new -key private.key -out certificate.pem -days 365 -subj "/CN=RAUC Test Certificate" || error_exit "Failed to generate certificate."

# Step 3: Create the RAUC bundle configuration file (`rauc.conf`).
# This file defines general bundle properties.
echo '
[rauc]
compatible=Arch-Linux
version=1.0.0
' > rauc.conf || error_exit "Failed to create rauc.conf."

# Step 4: Create the RAUC manifest file (`manifest.raucm`).
# This file describes the contents of your bundle.
# IMPORTANT: You MUST replace the SHA256 sum and size with the actual values
# for your `rootfs_systemA.squashfs` file.
# You can get these values using:
# sha256sum ~/rootfs_systemA.squashfs
# stat -c %s ~/rootfs_systemA.squashfs

# Example content (REPLACE SHA256 and SIZE):
echo '
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=rootfs_systemA.squashfs
sha256=<REPLACE_WITH_ACTUAL_SHA256_SUM>
size=<REPLACE_WITH_ACTUAL_SIZE_IN_BYTES>
' > manifest.raucm || error_exit "Failed to create manifest.raucm."

# Step 5: Build the RAUC bundle.
# This command combines all the pieces into your final .raucb file.
# We explicitly tell RAUC where to find the SquashFS file using its full path.
# The output bundle will be named `systemA_bundle_v1.0.0.raucb`.
rauc bundle --conf=rauc.conf --key=private.key --cert=certificate.pem \
 --output=systemA_bundle_v1.0.0.raucb manifest.raucm ~/rootfs_systemA.squashfs || error_exit "Failed to build RAUC bundle."

# Step 6: Verify the created bundle (optional but recommended).
# This checks the bundle's integrity and displays its contents.
rauc info systemA_bundle_v1.0.0.raucb || error_exit "Failed to verify RAUC bundle."

# Step 7: Clean up the temporary directory (optional).
# After you have copied the `systemA_bundle_v1.0.0.raucb` file to a safe location
# (e.g., a USB drive, or uploaded to Hawkbit), you can remove this directory.
# cd ..
# rm -rf ~/rauc_bundle_temp