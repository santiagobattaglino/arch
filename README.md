download https://archlinux.org/releng/releases/2025.07.01/torrent/
flash into 64 GB pendrive with balena etcher
boot from drive (pick no speech) (assuming a wired internet connection)

# set spanish keyboard
localectl set-keymap es

# for now, just public scripts to avoid overkill SSH setup
curl -O https://raw.githubusercontent.com/santiagobattaglino/arch/refs/heads/main/install.sh
curl -O https://raw.githubusercontent.com/santiagobattaglino/arch/refs/heads/main/chroot-script.sh

# make scripts executable
chmod +x install.sh chroot-script.sh

# install
./install.sh

# helpful commands

# list partitions
lsblk