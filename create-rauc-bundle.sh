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
echo "🔄 Cleaning workspace..."
umount "$MNT_POINT" 2>/dev/null || true
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$MNT_POINT"

# === MOUNT SYSTEM A ROOT (READ-ONLY) ===
echo "🗂️ Mounting $SRC_PARTITION as read-only..."
mount -o ro "$SRC_PARTITION" "$MNT_POINT"

# === CHECK IF SQUASHFS ALREADY EXISTS ===
if [[ -s "$BUILD_DIR/$SQUASHFS" ]]; then
    echo "✅ Existing SquashFS found: $BUILD_DIR/$SQUASHFS"
    echo "⏩ Skipping mksquashfs step."
else
    echo "📦 Creating squashfs image..."
    mksquashfs "$MNT_POINT" "$BUILD_DIR/$SQUASHFS" -comp xz
fi

# === UNMOUNT SYSTEM A ===
echo "🚪 Unmounting $SRC_PARTITION..."
umount "$MNT_POINT"

# === COPY CERT/KEY TO WORKSPACE ===
echo "🔐 Copying certificate and key to workspace..."
cp "$KEY" "$CERT" "$BUILD_DIR/"

# === CREATE BUNDLE RECIPE ===
echo "📝 Writing RAUC bundle recipe..."
cat > "$BUILD_DIR/$RECIPE" <<EOF
[bundle]
version=1.0.0
compatible=Arch-Linux
cert=$CERT
key=$KEY
output=$(realpath "$BUILD_DIR/$BUNDLE_NAME")

[image.rootfs]
filename=$SQUASHFS
EOF

# === BUILD THE BUNDLE ===
echo "🛠️ Building RAUC bundle..."
cd "$BUILD_DIR"
rauc bundle "$RECIPE"

# === VERIFY THE BUNDLE ===
echo "🔍 Verifying RAUC bundle..."
rauc info --keyring="$CERT" "$BUNDLE_NAME"

# === DONE ===
echo ""
echo "✅ RAUC bundle created and verified successfully!"
echo "   → Location: $BUILD_DIR/$BUNDLE_NAME"
