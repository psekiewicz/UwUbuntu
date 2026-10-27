#!/bin/sh
# Runs inside the newly installed system (Calamares shellprocess module):
# puts the right GRUB package in place and removes everything live-only.
set -u
export DEBIAN_FRONTEND=noninteractive
DEBS=/var/cache/uwubuntu/bootloader

# The image ships grub-pc (BIOS). On UEFI machines swap in grub-efi-amd64,
# bundled with its dependencies; apt (unlike dpkg -i) removes the conflicting
# grub-pc for us, offline. Without it GRUB isn't refreshed on updates.
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
if [ -d /sys/firmware/efi ]; then
    apt-get install -y --no-download -o Dpkg::Options::=--force-confold "$DEBS"/efi/*.deb \
        || echo "post-install: grub-efi-amd64 failed" >&2
fi
rm -rf /var/cache/uwubuntu

apt-get -y purge calamares casper || true
apt-get -y autoremove --purge || true
rm -rf /etc/calamares /usr/share/applications/uwubuntu-installer.desktop /usr/lib/uwubuntu/installer
rm -f /etc/xdg/autostart/uwubuntu-live-noblank.desktop
exit 0
