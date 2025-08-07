#!/bin/bash
set -euo pipefail

# === Configuration ===
BUILD_DIR="/root/rauc_bundle_workspace"
SRC_PARTITION="/dev/sda2"
MNT_POINT="/mnt/source_systemA"
SQUASHFS="rootfs_systemA.squashfs"
CERT="certificate.pem"
KEY="private.key"
RECIPE="bundle.raucb"
BUNDLE_NAME="systemA_bundle_v1.0.0.raucb"

SQUASHFS_PATH="$BUILD_DIR/$SQUASHFS"
CERT_PATH="$BUILD_DIR/$CERT"
KEY_PATH="$BUILD_DIR/$KEY"
RECIPE_PATH="$BUILD_DIR/$RECIPE"
BUNDLE_PATH="$BUILD_DIR/$BUNDLE_NAME"

# === Prepare workspace ===
echo "🔧 Preparing workspace..."
mkdir -p "$BUILD_DIR"
mkdir -p "$MNT_POINT"

# === Validate that required files exist ===
for FILE in "$CERT" "$KEY"; do
    if [[ ! -f "$FILE" ]]; then
        echo "❌ Missing required file: $FILE"
        exit 1
    fi
done

# === Create squashfs only if not present ===
if [[ -s "$SQUASHFS_PATH" ]]; then
    echo "✅ SquashFS already exists at $SQUASHFS_PATH"
else
    echo "📦 Creating SquashFS from $SRC_PARTITION..."
    mount -o ro "$SRC_PARTITION" "$MNT_POINT"
    mksquashfs "$MNT_POINT" "$SQUASHFS_PATH" -comp xz
    umount "$MNT_POINT"
fi

# === Copy certs and key to build dir ===
cp "$CERT" "$CERT_PATH"
cp "$KEY" "$KEY_PATH"

# === Clean up old bundle if exists ===
if [[ -f "$BUNDLE_PATH" ]]; then
    echo "🗑️ Removing existing bundle: $BUNDLE_PATH"
    rm -f "$BUNDLE_PATH"
fi

# === Create bundle recipe ===
echo "📝 Writing bundle recipe to $RECIPE_PATH..."
cat > "$RECIPE_PATH" <<EOF
[bundle]
version=1.0.0
compatible=Arch-Linux
cert=$CERT
key=$KEY
output=$BUNDLE_PATH

[image.rootfs]
filename=$SQUASHFS
EOF

# === Build the RAUC bundle ===
echo "🔨 Building RAUC bundle..."
cd "$BUILD_DIR"
rauc bundle "$RECIPE"

# === Verify bundle was created ===
if [[ ! -f "$BUNDLE_PATH" ]]; then
    echo "❌ ERROR: Bundle was not created."
    exit 1
fi

# === Verify bundle contents ===
echo "🔍 Verifying RAUC bundle..."
rauc info --keyring="$CERT_PATH" "$BUNDLE_NAME"

echo ""
echo "✅ Success! Bundle created and verified:"
echo "   → $BUNDLE_PATH"
