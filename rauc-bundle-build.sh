#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
SOURCE_DEVICE=/dev/sda2
SOURCE_MOUNT=/mnt/source_systemA
IMAGE_MOUNT=/mnt/ext4_image
WORKDIR=~/rauc_bundle_build
IMAGEDIR="$WORKDIR/images"
BUNDLEDIR="$WORKDIR/bundle_input"
BUNDLE_NAME=systemA_bundle_v1.0.0.raucb
IMG_NAME=rootfs_systemA.ext4
IMG_SIZE_MB=12288        # Adjust if needed (4GB here)
CERT=cert.pem
KEY=key.pem

echo "📁 Setting up directories..."
mkdir -p "$SOURCE_MOUNT" "$IMAGE_MOUNT" "$IMAGEDIR" "$BUNDLEDIR"
cd "$WORKDIR"

# === MOUNT SOURCE SYSTEM (READ-ONLY) ===
if ! mountpoint -q "$SOURCE_MOUNT"; then
    echo "🌀 Mounting $SOURCE_DEVICE to $SOURCE_MOUNT (read-only)..."
    mount -o ro "$SOURCE_DEVICE" "$SOURCE_MOUNT"
else
    echo "✅ $SOURCE_MOUNT is already mounted."
fi

# === CREATE CLEAN EXT4 IMAGE ===
IMG_PATH="$IMAGEDIR/$IMG_NAME"

echo "💽 Creating empty ext4 image ($IMG_SIZE_MB MB)..."
dd if=/dev/zero of="$IMG_PATH" bs=1M count=$IMG_SIZE_MB status=progress
mkfs.ext4 -q "$IMG_PATH"

echo "🔄 Mounting ext4 image to copy contents..."
mount -o loop "$IMG_PATH" "$IMAGE_MOUNT"

echo "📥 Copying files from System A into ext4 image using rsync..."
rsync -aHAXx --numeric-ids "$SOURCE_MOUNT"/ "$IMAGE_MOUNT"/

echo "🔽 Unmounting ext4 image..."
umount "$IMAGE_MOUNT"

# === PREPARE BUNDLE INPUT DIR ===
echo "📦 Preparing RAUC bundle input..."
cp "$IMG_PATH" "$BUNDLEDIR/$IMG_NAME"

# rauc.conf
cat > "$BUNDLEDIR/rauc.conf" <<EOF
[system]
compatible=Arch-Linux
version=1.0.0
EOF

# manifest.raucm (let rauc generate sha256 and size)
cat > "$BUNDLEDIR/manifest.raucm" <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$IMG_NAME
EOF

# === KEY/CERT HANDLING ===
if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
    echo "🔐 Generating signing key and certificate..."
    openssl req -x509 -newkey rsa:4096 -keyout "$KEY" -out "$CERT" -days 365 -nodes -subj "/CN=RAUC Test"
else
    echo "✅ Using existing key and cert."
fi

# === CREATE BUNDLE ===
echo "🛠️ Creating bundle..."
rauc bundle "$BUNDLEDIR" "$WORKDIR/$BUNDLE_NAME" \
    --cert="$CERT" \
    --key="$KEY"

# === VERIFY BUNDLE ===
echo "🔍 Verifying bundle..."
rauc info --keyring="$CERT" "$WORKDIR/$BUNDLE_NAME"

echo "✅ DONE! Bundle created at: $WORKDIR/$BUNDLE_NAME"
