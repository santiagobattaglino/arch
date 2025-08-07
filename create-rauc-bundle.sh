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
WORKDIR="$BUILD_DIR/.rauc-workdir"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$WORKDIR"

# === Step 1: Mount System A source if not mounted ===
if ! mountpoint -q "$SRC_MOUNT"; then
    echo "🔗 Mounting /dev/sda2 to $SRC_MOUNT..."
    mkdir -p "$SRC_MOUNT"
    mount -o ro /dev/sda2 "$SRC_MOUNT"
fi

# === Step 2: Create squashfs only if it doesn't exist ===
if [[ -s "$SQUASHFS" ]]; then
    echo "✅ SquashFS already exists, skipping creation: $SQUASHFS"
else
    echo "📦 Creating squashfs image deterministically..."
    mksquashfs "$SRC_MOUNT" "$SQUASHFS" \
        -comp xz \
        -all-root \
        -no-exports \
        -no-xattrs \
        -no-fragments \
        -mkfs-time 0 \
        -sort /dev/null \
        -quiet
fi

# === Step 3: Validate squashfs exists ===
if [[ ! -f "$SQUASHFS" || ! -s "$SQUASHFS" ]]; then
    echo "❌ squashfs missing or empty!"
    exit 1
fi

cd "$BUILD_DIR"

# === Step 4: Compute digest and size ===
SHA256=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
SIZE=$(stat -c %s "$(basename "$SQUASHFS")")

# === Step 5: Generate manifest.raucm ===
echo "📄 Creating manifest.raucm..."
cat > manifest.raucm <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$(basename "$SQUASHFS")
sha256=$SHA256
size=$SIZE
EOF

# === Step 6: Validate manifest digest ===
ACTUAL_HASH=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
EXPECTED_HASH=$(grep sha256 manifest.raucm | cut -d= -f2 | tr -d ' ')
if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
    echo "❌ Digest mismatch! squashfs and manifest differ."
    exit 1
fi

# === Step 7: Create rauc.conf ===
echo "📄 Creating rauc.conf..."
cat > rauc.conf <<EOF
[rauc]
compatible=Arch-Linux
version=1.0.0
EOF

# === Step 8: Clean any old bundle first ===
rm -f "$BUNDLE"

# === Step 9.5: Deep pre-bundle debug digest check ===
echo "🔬 DEBUG: manifest + squashfs pre-bundle consistency check..."
echo "--- manifest.raucm ---"
cat manifest.raucm

echo "--- sha256sum squashfs ---"
sha256sum "$SQUASHFS"

echo "--- stat squashfs ---"
stat "$SQUASHFS"

echo "--- hexdump squashfs head ---"
hexdump -C "$SQUASHFS" | head -n 8

# === Step 10: Create signed bundle with workdir ===
echo "🔐 Building signed bundle..."
RAUC_LOG_LEVEL=debug rauc bundle \
    --cert="$CERT" \
    --key="$KEY" \
    --workdir="$WORKDIR" \
    "$BUILD_DIR" "$BUNDLE"

# === Step 11: Verify signed bundle ===
echo "✅ Verifying signed bundle..."
rauc info --keyring="$CERT" "$BUNDLE"

echo "🎉 Signed bundle successfully created at: $BUNDLE"
