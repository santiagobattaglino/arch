#!/bin/bash

set -e

# === CONFIGURATION ===
BUILD_DIR="/root/rauc_bundle_workspace"
OUTPUT_DIR="/root/rauc_output"
SRC_MOUNT="/mnt/source_systemA"
SQUASHFS="$BUILD_DIR/rootfs_systemA.squashfs"
BUNDLE="$OUTPUT_DIR/systemA_bundle_v1.0.0.raucb"
CERT="$BUILD_DIR/certificate.pem"
KEY="$BUILD_DIR/private.key"

mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# === Step 1: Mount System A source if not mounted ===
if ! mountpoint -q "$SRC_MOUNT"; then
    echo "🔗 Mounting /dev/sda2 to $SRC_MOUNT..."
    mkdir -p "$SRC_MOUNT"
    mount -o ro /dev/sda2 "$SRC_MOUNT"
fi

# === Step 2: Generate squashfs only if not present ===
if [[ -s "$SQUASHFS" ]]; then
    echo "✅ SquashFS already exists, skipping creation: $SQUASHFS"
else
    echo "📦 Creating squashfs image from $SRC_MOUNT..."
    mksquashfs "$SRC_MOUNT" "$SQUASHFS" -comp xz
fi

# === Step 3: Verify squashfs file ===
if [[ ! -f "$SQUASHFS" || ! -s "$SQUASHFS" ]]; then
    echo "❌ Error: squashfs not found or empty at $SQUASHFS"
    exit 1
fi

# === Step 4: Generate manifest.raucm ===
cd "$BUILD_DIR"
SHA256=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
SIZE=$(stat -c %s "$(basename "$SQUASHFS")")

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

# === Step 5: Verify manifest hash matches squashfs ===
echo "🧪 Verifying manifest against squashfs..."
ACTUAL_HASH=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
EXPECTED_HASH=$(grep sha256 manifest.raucm | cut -d= -f2)

if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
    echo "❌ SHA mismatch! squashfs has changed after manifest generation."
    exit 1
fi

# === Step 6: Generate rauc.conf (required) ===
echo "📄 Creating rauc.conf..."
cat > rauc.conf <<EOF
[rauc]
compatible=Arch-Linux
version=1.0.0
EOF

# === Step 7: Bundle creation ===
echo "🔐 Signing and bundling..."
rauc bundle --cert="$CERT" --key="$KEY" "$BUILD_DIR" "$BUNDLE"

# === Step 8: Verify final bundle ===
echo "✅ Verifying created bundle..."
rauc info --keyring="$CERT" "$BUNDLE"

echo "🎉 RAUC bundle created successfully: $BUNDLE"
