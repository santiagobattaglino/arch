#!/bin/bash

set -e

# === CONFIG ===
BUNDLE_NAME="systemA_bundle_v1.0.0.raucb"
WORK_DIR=~/rauc_bundle_workspace
SRC_PARTITION="/dev/sda2"  # System A root
MNT_SRC="/mnt/source_systemA"
KEY="private.key"
CERT="certificate.pem"

# === CLEAN SETUP ===
echo "Preparing workspace..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$MNT_SRC"

# === MOUNT SYSTEM A PARTITION ===
echo "Mounting System A root..."
mount -o ro "$SRC_PARTITION" "$MNT_SRC"

# === CREATE SQUASHFS IMAGE ===
echo "Creating SquashFS image..."
mksquashfs "$MNT_SRC" "$WORK_DIR/rootfs_systemA.squashfs" -comp xz

# === UNMOUNT CLEANLY ===
umount "$MNT_SRC"
rmdir "$MNT_SRC"

# === GENERATE CONFIG AND MANIFEST ===
cd "$WORK_DIR"

echo "Generating rauc.conf..."
cat > rauc.conf <<EOF
[rauc]
compatible=Arch-Linux
version=1.0.0
EOF

echo "Calculating SHA256 and size..."
SHA256=$(sha256sum rootfs_systemA.squashfs | awk '{print $1}')
SIZE=$(stat -c %s rootfs_systemA.squashfs)

echo "Generating manifest.raucm..."
cat > manifest.raucm <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=rootfs_systemA.squashfs
sha256=$SHA256
size=$SIZE
EOF

# === SIGN MANIFEST ===
echo "Signing manifest..."
openssl cms -sign \
    -in manifest.raucm \
    -signer "$CERT" \
    -inkey "$KEY" \
    -nodetach -outform DER \
    -out signature.p7s

# === FINAL PACKAGING ===
echo "Packaging bundle into flat .raucb archive..."
tar -cvf "$BUNDLE_NAME" rauc.conf manifest.raucm rootfs_systemA.squashfs signature.p7s

# === DONE ===
echo "RAUC bundle created at: $WORK_DIR/$BUNDLE_NAME"
