# 1) Backup the current broken hook and recreate the minimal RAUC hook
cp -a /etc/grub.d/09_rauc_boot_order /etc/grub.d/09_rauc_boot_order.bak.$(date +%F-%H%M)

cat >/etc/grub.d/09_rauc_boot_order <<'EOF'
#!/bin/sh
# Delegate menu generation to RAUC’s hook
exec rauc grub-mkconfig-hook "$@"
EOF

chmod +x /etc/grub.d/09_rauc_boot_order

# 2) Keep 40_custom non-executable so it cannot override A/B entries
chmod -x /etc/grub.d/40_custom 2>/dev/null || true

# 3) Make sure GRUB respects saved/next entry
if [ -f /etc/default/grub ]; then
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
  if grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
    sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
  else
    echo 'GRUB_SAVEDEFAULT=true' >> /etc/default/grub
  fi
fi

# 4) Regenerate grub.cfg cleanly
grub-mkconfig -o /boot/grub/grub.cfg

# 5) (Optional) sanity-check entries and UUIDs
grep -n "menuentry '" /boot/grub/grub.cfg | sed -n '1,200p'
grep -n "root=UUID=" /boot/grub/grub.cfg | sed -n '1,200p'
