#!/bin/bash
set -e

# === CONFIG ===
BUILD_DIR="/root/rauc_bundle_workspace"
ROOTFS_SOURCE="/mnt/systemA"  # adjust if different
SQUASHFS="$BUILD_DIR/rootfs_systemA.squashfs"
CERT="$BUILD_DIR/certificate.pem"
KEY="$BUILD_DIR/private.key"
BUNDLE="$BUILD_DIR/systemA_bundle_v1.0.0.raucb"

# === Step 1: Go to workspace ===
cd "$BUILD_DIR"

# === Step 2: Create squashfs if not already present ===
if [ -f "$SQUASHFS" ]; then
    echo "🟡 SquashFS already exists, skipping creation: $SQUASHFS"
else
    echo "🟢 Creating SquashFS image..."
    mksquashfs "$ROOTFS_SOURCE" "$SQUASHFS"
fi

# === Step 3: Compute digest and size ===
echo "🔢 Calculating hash and size..."
SHA256=$(sha256sum "$(basename "$SQUASHFS")" | awk '{print $1}')
SIZE=$(stat -c %s "$(basename "$SQUASHFS")")

# === Step 4: Generate manifest.raucm ===
echo "📄 Writing manifest.raucm..."
cat > manifest.raucm <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$(basename "$SQUASHFS")
sha256=$SHA256
size=$SIZE
EOF

# === Step 5: Create rauc.conf ===
echo "📄 Creating rauc.conf..."
cat > rauc.conf <<EOF
[system]
compatible=Arch-Linux
EOF

# === Step 6: Sign manifest ===
echo "🔏 Signing manifest..."
openssl cms -sign -in manifest.raucm -outform DER -nosmimecap -nodetach -nocerts \
    -noattr -binary -signer "$CERT" -inkey "$KEY" -out signature.p7s

# === Step 7: Build the .raucb bundle ===
echo "📦 Creating bundle: $(basename "$BUNDLE")"
tar -cf "$BUNDLE" \
    "$(basename "$SQUASHFS")" \
    manifest.raucm \
    rauc.conf \
    signature.p7s

# === Step 8: Verify with RAUC ===
echo "🔍 Verifying with rauc..."
rauc info --keyring="$CERT" "$BUNDLE"
