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
SQUASHFS_PATH="$BUILD_DIR/$SQUASHFS"

# === CLEANUP (WITHOUT TOUCHING SQUASHFS) ===
echo "🔄 Preparing workspace..."
umount "$MNT_POINT" 2>/dev/null || true
mkdir -p "$BUILD_DIR"
mkdir -p "$MNT_POINT"

# === CREATE SQUASHFS ONLY IF MISSING ===
if [[ -s "$SQUASHFS_PATH" ]]; then
    echo "✅ Existing SquashFS found: $SQUASHFS_PATH"
    echo "⏩ Skipping mksquashfs."
else
    echo "📦 Creating squashfs image from $SRC_PARTITION..."
    mount -o ro "$SRC_PARTITION" "$MNT_POINT"
    mksquashfs "$MNT_POINT" "$SQUASHFS_PATH" -comp xz
    umount "$MNT_POINT"
fi

# === COPY CERT/KEY TO WORKSPACE ===
echo "🔐 Copying certificate and key..."
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
