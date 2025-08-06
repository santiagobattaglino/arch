#!/bin/bash

set -e

# === CONFIG ===
BUILD_DIR=~/rauc_bundle_workspace
BUNDLE_NAME="systemA_bundle_v1.0.0.raucb"
SRC_PARTITION="/dev/sda2"
MNT_POINT="/mnt/source_systemA"
KEY="private.key"
CERT="certificate.pem"
RECIPE="bundle.raucb"
SQUASHFS="rootfs_systemA.squashfs"

# === CLEANUP ===
echo "🔄 Cleaning previous workspace..."
sudo umount "$MNT_POINT" 2>/dev/null || true
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$MNT_POINT"

# === MOUNT SYSTEM A ROOT (read-only) ===
echo "🗂️ Mounting $SRC_PARTITION to $MNT_POINT..."
sudo mount -o ro "$SRC_PARTITION" "$MNT_POINT"

# === CREATE SQUASHFS IMAGE ===
echo "📦 Creating squashfs image from System A..."
mksquashfs "$MNT_POINT" "$BUILD_DIR/$SQUASHFS" -comp xz

# === UNMOUNT CLEANLY ===
echo "🚪 Unmounting $SRC_PARTITION..."
sudo umount "$MNT_POINT"

# === COPY CERT/KEY ===
echo "🔐 Copying signing cert and key..."
cp "$KEY" "$CERT" "$BUILD_DIR/"

# === CREATE BUNDLE RECIPE ===
echo "📝 Generating RAUC bundle recipe..."
cat > "$BUILD_DIR/$RECIPE" <<EOF
[bundle]
version=1.0.0
compatible=Arch-Linux
cert=$CERT
key=$KEY
output=$BUNDLE_NAME

[image.rootfs]
filename=$SQUASHFS
EOF

# === BUILD THE BUNDLE ===
cd "$BUILD_DIR"
echo "🛠️ Building RAUC bundle using 'rauc bundle'..."
rauc bundle "$RECIPE"

# === VERIFY THE BUNDLE ===
echo "🔍 Verifying generated bundle with 'rauc info'..."
rauc info --keyring="$CERT" "$BUNDLE_NAME"

# === DONE ===
echo ""
echo "✅ RAUC bundle created and verified successfully!"
echo "   → $BUILD_DIR/$BUNDLE_NAME"
