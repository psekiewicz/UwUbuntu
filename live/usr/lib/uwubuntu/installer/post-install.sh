#!/bin/sh
# Runs inside the newly installed system (Calamares shellprocess module):
# puts the right GRUB package in place and removes everything live-only.
set -u
export DEBIAN_FRONTEND=noninteractive
DEBS=/var/cache/uwubuntu/bootloader

# grub-pc and grub-efi-amd64 conflict, so the image carries both as .debs and
# we install the one matching how the machine booted the live session.
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
if [ -d /sys/firmware/efi ]; then
    dpkg -i "$DEBS"/grub-efi-amd64_*.deb || echo "post-install: grub-efi-amd64 failed" >&2
else
    dpkg -i "$DEBS"/grub-pc_*.deb || echo "post-install: grub-pc failed" >&2
fi
rm -rf /var/cache/uwubuntu

apt-get -y purge calamares casper || true
apt-get -y autoremove --purge || true
rm -rf /etc/calamares /usr/share/applications/uwubuntu-installer.desktop /usr/lib/uwubuntu/installer
exit 0
