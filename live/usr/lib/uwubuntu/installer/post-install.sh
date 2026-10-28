#!/bin/sh
# Runs inside the newly installed system (Calamares shellprocess module):
# puts the right GRUB package in place and removes everything live-only.
set -u
export DEBIAN_FRONTEND=noninteractive
DEBS=/var/cache/uwubuntu/bootloader

# The image ships grub-efi-amd64 (UEFI). On BIOS machines swap in grub-pc,
# bundled with its dependencies; apt removes grub-efi-amd64 for us, offline.
# Booting doesn't depend on this (grub-install uses grub-pc-bin either way);
# it keeps GRUB refreshed on updates.
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
if [ ! -d /sys/firmware/efi ]; then
    apt-get install -y --no-download -o Dpkg::Options::=--force-confold "$DEBS"/bios/*.deb \
        || echo "post-install: grub-pc failed" >&2
fi
# Whatever happened above, leave apt consistent so the cleanup below works.
apt-get install -y -f --no-download || true
rm -rf /var/cache/uwubuntu

apt-get -y purge calamares casper || true
apt-get -y autoremove --purge || true
rm -rf /etc/calamares /usr/share/applications/uwubuntu-installer.desktop /usr/lib/uwubuntu/installer
rm -f /usr/share/glib-2.0/schemas/95_uwubuntu-live.gschema.override
glib-compile-schemas /usr/share/glib-2.0/schemas || true
# Run triggers the purges above left queued (menus, udev rules, dbus)
dpkg --configure --pending || true
exit 0
