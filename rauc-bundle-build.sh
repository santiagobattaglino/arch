#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
WORKDIR=~/rauc_bundle_build
IMAGEDIR="$WORKDIR/images"
BUNDLEDIR="$WORKDIR/bundle_input"
BUNDLE_NAME=systemA_bundle_v1.0.0.raucb
CERT=cert.pem
KEY=key.pem
DEVICE=/dev/sda2
IMG_NAME=rootfs_systemA.ext4
BUNDLE_OUTPUT="$WORKDIR/$BUNDLE_NAME"
COPY_SIZE=25G

# === SETUP ===
echo "📁 Creating workspace..."
rm -rf "$WORKDIR"
mkdir -p "$IMAGEDIR" "$BUNDLEDIR"

# === CREATE ROOTFS IMAGE ===
echo "💽 Creating raw ext4 image from $DEVICE (size: $COPY_SIZE)..."
IMG_PATH="$IMAGEDIR/$IMG_NAME"
dd if="$DEVICE" of="$IMG_PATH" bs=1M count=$((25*1024)) status=progress conv=sparse

# === GENERATE rauc.conf ===
echo "⚙️  Creating rauc.conf..."
cat > "$BUNDLEDIR/rauc.conf" <<EOF
[system]
compatible=Arch-Linux
version=1.0.0
EOF

# === GENERATE manifest.raucm ===
echo "📝 Generating manifest.raucm..."
SHA256=$(sha256sum "$IMG_PATH" | awk '{print $1}')
SIZE=$(stat -c%s "$IMG_PATH")

cat > "$BUNDLEDIR/manifest.raucm" <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$IMG_NAME
sha256=$SHA256
size=$SIZE
EOF

# === COPY IMAGE ===
cp "$IMG_PATH" "$BUNDLEDIR/"

# === KEY + CERT ===
if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
    echo "🔐 Creating signing key and certificate..."
    openssl req -x509 -newkey rsa:4096 -keyout "$KEY" -out "$CERT" -days 365 -nodes -subj "/CN=RAUC Test Certificate"
else
    echo "✅ Using existing certificate and key."
fi

# === CREATE BUNDLE ===
echo "📦 Creating RAUC bundle..."
rauc bundle "$BUNDLEDIR" "$BUNDLE_OUTPUT" \
    --cert="$CERT" \
    --key="$KEY"

# === VERIFY BUNDLE ===
echo "🔍 Verifying RAUC bundle..."
rauc info --keyring="$CERT" "$BUNDLE_OUTPUT"

echo "✅ Done: Bundle created at $BUNDLE_OUTPUT"
