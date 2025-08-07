#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
BUILD_DIR="/root/rauc_bundle_workspace"
OUTPUT_DIR="/root/rauc_output"
SRC_MOUNT="/mnt/source_systemA"
SQUASHFS="$BUILD_DIR/rootfs_systemA.squashfs"
BUNDLE="$OUTPUT_DIR/systemA_bundle_v1.0.0.raucb"
CERT="$BUILD_DIR/certificate.pem"
KEY="$BUILD_DIR/private.key"
RECIPE="$BUILD_DIR/bundle.raucb"

mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# === Step 1: Mount System A if not already ===
if ! mountpoint -q "$SRC_MOUNT"; then
    echo "🔗 Mounting /dev/sda2 to $SRC_MOUNT..."
    mkdir -p "$SRC_MOUNT"
    mount -o ro /dev/sda2 "$SRC_MOUNT"
fi

# === Step 2: Create squashfs only if not present ===
if [[ -s "$SQUASHFS" ]]; then
    echo "✅ SquashFS already exists, skipping creation: $SQUASHFS"
else
    echo "📦 Creating squashfs image from $SRC_MOUNT..."
    mksquashfs "$SRC_MOUNT" "$SQUASHFS" -comp xz -noappend -all-root -no-xattrs -noatime
    sync
fi

# === Step 3: Verify squashfs exists ===
if [[ ! -f "$SQUASHFS" || ! -s "$SQUASHFS" ]]; then
    echo "❌ Error: squashfs not found or empty at $SQUASHFS"
    exit 1
fi

# === Step 4: Recalculate hash and size ===
cd "$BUILD_DIR"
SHA256=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
SIZE=$(stat -c %s "$(basename "$SQUASHFS")")

# === Step 5: Write manifest.raucm ===
echo "📄 Generating manifest.raucm..."
cat > manifest.raucm <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$(basename "$SQUASHFS")
sha256=$SHA256
size=$SIZE
EOF

# === Step 6: Sanity check on manifest digest ===
echo "🧪 Verifying manifest digest..."
ACTUAL_HASH=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
EXPECTED_HASH=$(grep sha256 manifest.raucm | cut -d= -f2)

if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
    echo "❌ SHA mismatch! squashfs has changed after manifest generation."
    exit 1
fi

# === Step 7: Create rauc.conf ===
echo "📄 Creating rauc.conf..."
cat > rauc.conf <<EOF
[rauc]
compatible=Arch-Linux
version=1.0.0
EOF

# === Step 8: Create the bundle using rauc ===
echo "🔐 Creating bundle with rauc..."
rauc bundle --cert="$CERT" --key="$KEY" "$BUILD_DIR" "$BUNDLE"

# === Step 9: Verify created bundle ===
echo "✅ Verifying created bundle..."
rauc info --keyring="$CERT" "$BUNDLE"

echo "🎉 Bundle successfully created: $BUNDLE"
