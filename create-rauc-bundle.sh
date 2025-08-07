#!/bin/bash
set -euo pipefail

# === Config ===
BUILD_DIR="/root/rauc_bundle_workspace"
SRC_PARTITION="/dev/sda2"
MNT_POINT="/mnt/source_systemA"
SQUASHFS="rootfs_systemA.squashfs"
CERT="certificate.pem"
KEY="private.key"
RECIPE="bundle.raucb"
BUNDLE_NAME="systemA_bundle_v1.0.0.raucb"

cd "$BUILD_DIR"

# === Validate required files ===
for FILE in "$CERT" "$KEY"; do
    if [[ ! -f "$FILE" ]]; then
        echo "❌ Required file missing: $FILE"
        exit 1
    fi
done

# === Create squashfs if missing ===
if [[ -s "$SQUASHFS" ]]; then
    echo "✅ Found existing squashfs: $SQUASHFS"
else
    echo "📦 Creating squashfs from $SRC_PARTITION..."
    mkdir -p "$MNT_POINT"
    mount -o ro "$SRC_PARTITION" "$MNT_POINT"
    mksquashfs "$MNT_POINT" "$SQUASHFS" -comp xz
    umount "$MNT_POINT"
    echo "✅ squashfs created: $SQUASHFS"
fi

# === Delete old bundle if it exists ===
if [[ -f "$BUNDLE_NAME" ]]; then
    echo "🗑️ Removing previous bundle: $BUNDLE_NAME"
    rm -f "$BUNDLE_NAME"
fi

# === Generate bundle.raucb recipe ===
echo "📝 Writing recipe: $RECIPE"
cat > "$RECIPE" <<EOF
[bundle]
version=1.0.0
compatible=Arch-Linux
cert=$CERT
key=$KEY
output=$BUNDLE_NAME

[image.rootfs]
filename=$SQUASHFS
EOF

# Optional: strip carriage returns just in case
sed -i 's/\r$//' "$RECIPE"

# === Build bundle ===
echo "🔨 Running rauc bundle..."
rauc bundle "$RECIPE"

# === Verify bundle ===
echo "🔍 Verifying bundle..."
rauc info --keyring="$CERT" "$BUNDLE_NAME"

echo ""
echo "✅ Bundle created and verified successfully:"
echo "   → $BUILD_DIR/$BUNDLE_NAME"
