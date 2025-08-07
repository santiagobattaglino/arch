cat > bundle.raucb << 'EOF'
[bundle]
version=1.0.0
compatible=Arch-Linux
cert=certificate.pem
key=private.key
output=systemA_bundle_v1.0.0.raucb

[image.rootfs]
filename=rootfs_systemA.squashfs
EOF
