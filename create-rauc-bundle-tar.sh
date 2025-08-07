#!/bin/bash
set -e

# === CONFIG ===
WORK_DIR=~/rauc_bundle_workspace
MOUNT_POINT=/mnt/source_systemA
SQUASHFS_IMG=$WORK_DIR/rootfs_systemA.squashfs
BUNDLE_NAME=systemA_bundle_v1.0.0.raucb

# === CREATE WORKDIR ===
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# === Step 1: Mount systemA rootfs if not mounted ===
if ! mountpoint -q "$MOUNT_POINT"; then
    mkdir -p "$MOUNT_POINT"
    mount -o ro /dev/sda2 "$MOUNT_POINT"
fi

# === Step 2: Create squashfs if it doesn't exist ===
if [[ -s "$SQUASHFS_IMG" ]]; then
    echo "✅ SquashFS image already exists. Skipping creation."
else
    echo "🌀 Creating SquashFS image..."
    mksquashfs "$MOUNT_POINT" "$SQUASHFS_IMG" -comp xz -noappend
fi

# === Step 3: Create keys (if needed) ===
if [[ ! -f private.key || ! -f certificate.pem ]]; then
    echo "🔐 Generating keys..."
    openssl genpkey -algorithm RSA -out private.key
    openssl req -x509 -new -key private.key -out certificate.pem -days 365 -subj "/CN=RAUC Test"
fi

# === Step 4: Generate manifest.raucm ===
SHA256=$(sha256sum "$SQUASHFS_IMG" | awk '{print $1}')
SIZE=$(stat -c%s "$SQUASHFS_IMG")

cat > manifest.raucm <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$(basename "$SQUASHFS_IMG")
sha256=$SHA256
size=$SIZE
EOF

# === Step 5: Create bundle contents directory ===
rm -rf bundle_contents
mkdir bundle_contents

cp rauc.conf manifest.raucm "$SQUASHFS_IMG" bundle_contents/
openssl cms -sign -in manifest.raucm -signer certificate.pem -inkey private.key -nodetach -outform DER -out bundle_contents/signature.p7s

# === Step 6: Package the bundle ===
tar -cvf "$BUNDLE_NAME" -C bundle_contents .

# === Step 7: Verify ===
rauc info --keyring=certificate.pem "$BUNDLE_NAME"

echo "✅ RAUC bundle created successfully: $BUNDLE_NAME"
