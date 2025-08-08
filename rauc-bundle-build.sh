#!/usr/bin/env bash
set -euo pipefail

# ===========================
#  CONFIGURATION (edit me)
# ===========================
SOURCE_DEVICE=/dev/sda2                   # System A rootfs device (read-only source)
SOURCE_MOUNT=/mnt/source_systemA
IMAGE_MOUNT=/mnt/ext4_image

WORKDIR=~/rauc_bundle_build
IMAGEDIR="$WORKDIR/images"
BUNDLEDIR="$WORKDIR/bundle_input"

BUNDLE_NAME=systemA_bundle_v1.0.0.raucb   # Final bundle filename (will be overwritten)
IMG_NAME=rootfs_systemA.ext4
IMG_SIZE_MB=12288                         # Size of ext4 image in MB (e.g., 12288 = 12 GiB)

CERT=cert.pem                             # Signing cert (PEM)
KEY=key.pem                               # Signing private key (PEM)

# Encrypted /home (LUKS on sda5) copy target
HOME_LUKS_DEV=/dev/sda5
HOME_MAPPER_NAME=home_crypt
HOME_MOUNT=/mnt/home_luks
TARGET_DIR="$HOME_MOUNT/rauc"

# ===========================
#  PRECHECKS
# ===========================
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1"; exit 1; }; }
for bin in rauc rsync cryptsetup openssl dd mkfs.ext4 mount umount; do need "$bin"; done

echo "📁 Setting up directories..."
mkdir -p "$SOURCE_MOUNT" "$IMAGE_MOUNT" "$IMAGEDIR" "$BUNDLEDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ===========================
#  CLEANUP TRAP
# ===========================
cleanup() {
  set +e
  mountpoint -q "$IMAGE_MOUNT"  && umount "$IMAGE_MOUNT"
  mountpoint -q "$SOURCE_MOUNT" && umount "$SOURCE_MOUNT"
  mountpoint -q "$HOME_MOUNT"   && umount "$HOME_MOUNT"
  if [[ -e "/dev/mapper/$HOME_MAPPER_NAME" ]]; then
    cryptsetup close "$HOME_MAPPER_NAME"
  fi
}
trap cleanup EXIT

# ===========================
#  MOUNT SOURCE (READ-ONLY)
# ===========================
if ! mountpoint -q "$SOURCE_MOUNT"; then
  echo "🌀 Mounting $SOURCE_DEVICE → $SOURCE_MOUNT (read-only)…"
  mount -o ro "$SOURCE_DEVICE" "$SOURCE_MOUNT"
else
  echo "✅ $SOURCE_MOUNT already mounted."
fi

# ===========================
#  CREATE EXT4 IMAGE
# ===========================
IMG_PATH="$IMAGEDIR/$IMG_NAME"
echo "💽 Creating empty ext4 image ($IMG_SIZE_MB MB) at $IMG_PATH…"
rm -f "$IMG_PATH"
dd if=/dev/zero of="$IMG_PATH" bs=1M count="$IMG_SIZE_MB" status=progress
mkfs.ext4 -q "$IMG_PATH"

echo "🔄 Mounting ext4 image…"
mount -o loop "$IMG_PATH" "$IMAGE_MOUNT"

echo "📥 Rsyncing System A → image (this can take a while)…"
# Notes:
#  - -aHAX for attrs/ACLs/xattrs/hardlinks
#  - -x stay on one FS (don’t cross into other mounts)
#  - --numeric-ids preserves numeric UID/GID
rsync -aHAXx --numeric-ids --info=progress2 \
  --exclude={"/boot/*","/dev/*","/proc/*","/sys/*","/run/*","/tmp/*","/mnt/*","/media/*","/lost+found"} \
  "$SOURCE_MOUNT"/ "$IMAGE_MOUNT"/

echo "🔽 Unmounting image…"
umount "$IMAGE_MOUNT"

# ===========================
#  PREPARE BUNDLE INPUT
# ===========================
echo "📦 Preparing RAUC bundle input…"
cp -f "$IMG_PATH" "$BUNDLEDIR/$IMG_NAME"

# Optional rauc.conf: can be useful for metadata, but not required by RAUC
cat > "$BUNDLEDIR/rauc.conf" <<'EOF'
[system]
compatible=Arch-Linux
version=1.0.0
EOF

# Manifest: RAUC will compute sha256/size for the image
cat > "$BUNDLEDIR/manifest.raucm" <<EOF
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=$IMG_NAME
EOF

# ===========================
#  KEYS (generate if missing)
# ===========================
if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
  echo "🔐 Generating signing key & cert (self-signed, test)…"
  openssl req -x509 -newkey rsa:4096 -keyout "$KEY" -out "$CERT" -days 365 -nodes -subj "/CN=RAUC Test"
else
  echo "✅ Using existing key & cert."
fi
chmod 600 "$KEY" 2>/dev/null || true

# ===========================
#  CREATE (OVERWRITE) BUNDLE
# ===========================
BUNDLE_PATH="$WORKDIR/$BUNDLE_NAME"
echo "🛠️ Creating bundle (overwrite) → $BUNDLE_PATH"
rm -f "$BUNDLE_PATH"

rauc bundle "$BUNDLEDIR" "$BUNDLE_PATH" \
  --cert="$CERT" \
  --key="$KEY"

# ===========================
#  VERIFY BUNDLE
# ===========================
echo "🔍 Verifying bundle…"
rauc info --keyring="$CERT" "$BUNDLE_PATH"

echo "✅ DONE! Bundle at: $BUNDLE_PATH"

# ===========================
#  COPY TO ENCRYPTED /home
# ===========================
echo "🔐 Opening LUKS container $HOME_LUKS_DEV → $HOME_MAPPER_NAME…"
mkdir -p "$HOME_MOUNT"
if [[ ! -e "/dev/mapper/$HOME_MAPPER_NAME" ]]; then
  cryptsetup open "$HOME_LUKS_DEV" "$HOME_MAPPER_NAME"
fi

echo "📂 Mounting /dev/mapper/$HOME_MAPPER_NAME → $HOME_MOUNT…"
mount "/dev/mapper/$HOME_MAPPER_NAME" "$HOME_MOUNT"

echo "📤 Copying bundle + cert into $TARGET_DIR…"
mkdir -p "$TARGET_DIR"
cp -f "$BUNDLE_PATH" "$TARGET_DIR/"
cp -f "$CERT" "$TARGET_DIR/"

echo "📋 Contents of $TARGET_DIR:"
ls -lh "$TARGET_DIR" | sed -n '1,50p'

echo "🎉 All done."
