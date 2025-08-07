mkdir test_bundle
cd test_bundle

# Dummy rootfs
echo "hello" > rootfs.txt
mksquashfs rootfs.txt rootfs_systemA.squashfs -noappend

# rauc.conf
echo -e '[rauc]\ncompatible=Arch-Linux\nversion=1.0.0' > rauc.conf

# manifest
sha256=$(sha256sum rootfs_systemA.squashfs | awk '{print $1}')
size=$(stat -c %s rootfs_systemA.squashfs)

cat <<EOF > manifest.raucm
[update]
compatible=Arch-Linux
version=1.0.0

[image.rootfs]
filename=rootfs_systemA.squashfs
sha256=$sha256
size=$size
EOF

# Create keys
openssl genpkey -algorithm RSA -out private.key
openssl req -x509 -new -key private.key -out certificate.pem -days 365 -subj "/CN=RAUC Test"

# Sign
openssl cms -sign -binary -nocerts -noattr -in manifest.raucm -signer certificate.pem -inkey private.key -outform DER -out signature.p7s

# Pack
tar -cf test.raucb manifest.raucm rauc.conf rootfs_systemA.squashfs
tar --append -f test.raucb signature.p7s

# Verify
rauc info --keyring=certificate.pem test.raucb
