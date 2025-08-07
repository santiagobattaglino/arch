#!/bin/bash
set -euo pipefail

# === Configuration ===
VERSION="1.0.0"
COMPATIBLE="Arch-Linux"
IMAGE="rootfs_systemA.squashfs"
MANIFEST="manifest.raucm"
SIGNATURE="signature.p7s"
CERT="certificate.pem"
KEY="private.key"
BUNDLE="systemA_bundle_v${VERSION}.raucb"

echo "=== RAUC Bundle Creation Script ==="
echo "Version: $VERSION"
echo "Compatible: $COMPATIBLE"
echo "Bundle: $BUNDLE"

# === Step 1: Create squashfs (only if not present) ===
if [ ! -f "$IMAGE" ]; then
    echo "Creating squashfs image..."
    mksquashfs rootfs "$IMAGE" -noappend
else
    echo "Squashfs already exists, skipping creation: $IMAGE"
fi

# === Step 2: Compute digest and size ===
echo "Computing hash and size..."
SHA256=$(sha256sum "$IMAGE" | awk '{print $1}')
SIZE=$(stat -c %s "$IMAGE")

# === Step 3: Create manifest.raucm ===
echo "Creating manifest..."
cat > "$MANIFEST" <<EOF
[update]
compatible=$COMPATIBLE
version=$VERSION

[image.rootfs]
filename=$IMAGE
sha256=$SHA256
size=$SIZE
EOF

# === Step 4: Sign the manifest (includes cert) ===
echo "Signing manifest..."
openssl cms -sign \
    -binary \
    -noattr \
    -in "$MANIFEST" \
    -signer "$CERT" \
    -inkey "$KEY" \
    -outform DER \
    -out "$SIGNATURE"

# === Step 5: Verify the signature ===
echo "Verifying signature..."
openssl cms -verify \
    -in "$SIGNATURE" \
    -inform DER \
    -content "$MANIFEST" \
    -CAfile "$CERT" \
    -no_attr_verify \
    -no_content_verify

# === Step 6: Create rauc.conf ===
echo "Creating rauc.conf..."
cat > rauc.conf <<EOF
[system]
compatible=$COMPATIBLE
EOF

# === Step 7: Package the bundle ===
echo "Packing bundle..."
tar --format=ustar -cf "$BUNDLE" \
    rauc.conf \
    "$MANIFEST" \
    "$IMAGE" \
    "$SIGNATURE"

echo "✅ Bundle created: $BUNDLE"
