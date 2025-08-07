#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
WORK_DIR=~/rauc_bundle_workspace
SOURCE_MOUNT=/mnt/source_systemA
SOURCE_DEVICE=/dev/sda2
SQUASHFS_IMG=rootfs_systemA.squashfs
BUNDLE_NAME=systemA_bundle_v1.0.0.raucb
KEY=private.key
CERT=certificate.pem

# === PREPARE WORKDIR ===
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "🧼 Cleaning up previous build artifacts..."
rm -rf bundle_contents "$BUNDLE_NAME"
mkdir -p bundle_contents

# === MOUNT SYSTEM A (READ-ONLY) ===
if ! mountpoint -q "$SOURCE_MOUNT"; then
    echo "🌀 Mounting $SOURCE_DEVICE to $SOURCE_MOUNT (read-only)..."
    mkdir -p "$SOURCE_MOUNT"
    mount -o ro "$SOURCE_DEVICE" "$SOURCE_MOUNT"
else
    echo "✅ $SOURCE_MOUNT is already mounted."
fi

# === SQUASHFS IMAGE ===
if [[ -s "$SQUASHFS_IMG" ]]; then
    echo "✅ $SQUASHFS_IMG already exists and is non-empty. Skipping mksquashfs."
else
    echo "🌀 Creating SquashFS image..."
    mksquashfs "$SOURCE_MOUNT" "$SQUASHFS_IMG" -comp xz -noappend
fi

# === KEY AND CERT ===
if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
    echo "🔐 Generating private key and certificate..."
    openssl genpkey -algorithm RSA -out "$KEY"
    openssl req -x509 -new -key "$KEY" -out "$CERT" -days 365 -subj "/CN=RAUC Test Certificate"
else
    echo "✅ Reusing existing key and certificate."
fi

# === rauc.conf ===
cat > rauc.conf <<EOF
[rauc]
compatible=Arch-Linux
version=1.0.0
EOF

# === Generate manifest.raucm ===
SHA256=$(sha256sum "$SQUASHFS_IMG" | awk '{print $1}')
SIZE=$(stat -c%s "$SQUASHFS_IMG")

cat > manifest.raucm <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$SQUASHFS_IMG
sha256=$SHA256
size=$SIZE
EOF

# === Sign the manifest ===
echo "🔏 Signing manifest.raucm..."
openssl cms -sign \
    -in manifest.raucm \
    -signer "$CERT" \
    -inkey "$KEY" \
    -outform DER \
    -nosmimecap -nodetach -nocerts -noattr \
    -out signature.p7s

# Check that signature is valid
if [[ ! -s signature.p7s ]]; then
    echo "❌ ERROR: signature.p7s is empty! Aborting."
    exit 1
fi

# === Package the RAUC bundle ===
echo "📦 Creating RAUC bundle..."
cp rauc.conf manifest.raucm "$SQUASHFS_IMG" signature.p7s bundle_contents/
tar -cf systemA_bundle_v1.0.0.raucb rauc.conf manifest.raucm rootfs_systemA.squashfs
tar -rf systemA_bundle_v1.0.0.raucb signature.p7s

# === Final check ===
echo "🔍 Verifying bundle with rauc info..."
rauc info --keyring="$CERT" "$BUNDLE_NAME"

echo "✅ DONE: Bundle created at $WORK_DIR/$BUNDLE_NAME"
