#!/bin/bash

# === Configuration ===
BUILD_DIR="/root/rauc_bundle_workspace"
SOURCE_PARTITION="/dev/sda2"
SOURCE_MOUNT="/mnt/source_systemA"
CERT="$BUILD_DIR/certificate.pem"
KEY="$BUILD_DIR/private.key"
BUNDLE_NAME="systemA_bundle_v1.0.0.raucb"
OUTPUT_BUNDLE="/root/$BUNDLE_NAME"
SQUASHFS="rootfs_systemA.squashfs"

# === Utility function ===
error_exit() {
    echo "❌ ERROR: $1"
    exit 1
}

echo "🚀 Starting RAUC bundle creation..."

# === Step 1: Prepare build directory ===
mkdir -p "$BUILD_DIR" || error_exit "Failed to create build directory."
cd "$BUILD_DIR" || error_exit "Cannot change to build directory."

# === Step 2: Mount System A read-only if not already mounted ===
if ! mountpoint -q "$SOURCE_MOUNT"; then
    mkdir -p "$SOURCE_MOUNT"
    mount -o ro "$SOURCE_PARTITION" "$SOURCE_MOUNT" || error_exit "Failed to mount $SOURCE_PARTITION"
fi

# === Step 3: Create squashfs if not already present ===
if [[ -f "$SQUASHFS" && -s "$SQUASHFS" ]]; then
    echo "📦 SquashFS image already exists. Skipping mksquashfs."
else
    echo "📦 Creating squashfs image from $SOURCE_PARTITION..."
    mksquashfs "$SOURCE_MOUNT" "$SQUASHFS" -comp xz || error_exit "mksquashfs failed"
fi

# === Step 4: Generate cert and key if missing ===
if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
    echo "🔐 Generating new certificate and key..."
    openssl genpkey -algorithm RSA -out "$KEY" || error_exit "Failed to generate private key"
    openssl req -x509 -new -key "$KEY" -out "$CERT" -days 365 -subj "/CN=RAUC Test Certificate" || error_exit "Failed to generate certificate"
else
    echo "🔐 Existing certificate and key found. Reusing."
fi

# === Step 5: Create rauc.conf ===
cat > "$BUILD_DIR/rauc.conf" <<EOF
[system]
compatible=Arch-Linux
version=1.0.0
EOF

# === Step 6: Create manifest.raucm ===
SHA256=$(sha256sum "$SQUASHFS" | awk '{print $1}')
SIZE=$(stat -c %s "$SQUASHFS")

cat > "$BUILD_DIR/manifest.raucm" <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$SQUASHFS
sha256=$SHA256
size=$SIZE
EOF

echo "🔍 Verifying squashfs hash and manifest match..."
ACTUAL_HASH=$(sha256sum "$SQUASHFS" | awk '{print $1}')
MANIFEST_HASH=$(grep sha256 manifest.raucm | cut -d= -f2)

if [[ "$ACTUAL_HASH" != "$MANIFEST_HASH" ]]; then
    error_exit "Mismatch between actual squashfs hash and manifest! Aborting."
fi

# === Step 7: Build RAUC bundle ===
echo "🔨 Creating RAUC bundle..."
rm -f "$OUTPUT_BUNDLE"  # Clean previous bundle if it exists
rauc bundle --cert="$CERT" --key="$KEY" "$BUILD_DIR" "$OUTPUT_BUNDLE" || error_exit "RAUC bundle creation failed"

# === Step 8: Verify bundle ===
echo "🔍 Verifying created RAUC bundle..."
rauc info --keyring="$CERT" "$OUTPUT_BUNDLE" || error_exit "RAUC bundle verification failed"

# === Cleanup mount ===
if mountpoint -q "$SOURCE_MOUNT"; then
    umount "$SOURCE_MOUNT"
fi

echo "✅ RAUC bundle created and verified: $OUTPUT_BUNDLE"
