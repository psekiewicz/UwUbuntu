#!/bin/sh
# Runs inside the newly installed system (Calamares shellprocess module):
# puts the right GRUB package in place and removes everything live-only.
set -u
export DEBIAN_FRONTEND=noninteractive
DEBS=/var/cache/uwubuntu/bootloader

# grub-pc and grub-efi-amd64 conflict, so the image carries both (each with
# its dependencies) and we install the one matching how the machine booted
# the live session. Without it GRUB isn't reinstalled when it gets updates.
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
if [ -d /sys/firmware/efi ]; then
    dpkg -i "$DEBS"/efi/*.deb || echo "post-install: grub-efi-amd64 failed" >&2
else
    dpkg -i "$DEBS"/bios/*.deb || echo "post-install: grub-pc failed" >&2
fi
rm -rf /var/cache/uwubuntu

apt-get -y purge calamares casper || true
apt-get -y autoremove --purge || true
rm -rf /etc/calamares /usr/share/applications/uwubuntu-installer.desktop /usr/lib/uwubuntu/installer
rm -f /etc/xdg/autostart/uwubuntu-live-noblank.desktop
exit 0
