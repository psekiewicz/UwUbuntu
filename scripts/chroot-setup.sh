#!/usr/bin/env bash
# Runs INSIDE the chroot (started by build.sh). Turns a minbase debootstrap
# into the UwUbuntu desktop. Everything it needs is in /tmp/uwubuntu.
set -euo pipefail
: "${UBUNTU_SUITE:?}" "${UBUNTU_MIRROR:?}" "${DISTRO_NAME:?}" "${LIVE_USERNAME:?}"

export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
IN=/tmp/uwubuntu
APT=(apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

log()  { printf '\e[1;36m[chroot]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[chroot] warning:\e[0m %s\n' "$*" >&2; }

# Packages may swap /etc/resolv.conf for a systemd-resolved symlink that leads
# nowhere inside a chroot; put the host's resolver back before network work.
fix_dns() { rm -f /etc/resolv.conf; cp "$IN/host-resolv.conf" /etc/resolv.conf; }

# Print the package names in a list file, skipping comments and blank lines.
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' || true; }

# Install only the packages from a list that this suite actually has.
install_available() {
  local pkg available=()
  for pkg in "$@"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
      available+=("$pkg")
    else
      warn "skipping '$pkg' (not in $UBUNTU_SUITE)"
    fi
  done
  (( ${#available[@]} )) && "${APT[@]}" install "${available[@]}"
  return 0
}

log "Basic system setup"
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d   # don't start services in here
chmod 755 /usr/sbin/policy-rc.d
echo "$LIVE_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $LIVE_HOSTNAME
::1       localhost ip6-localhost ip6-loopback
EOF

rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: $UBUNTU_MIRROR
Suites: $UBUNTU_SUITE $UBUNTU_SUITE-updates $UBUNTU_SUITE-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $UBUNTU_SECURITY_MIRROR
Suites: $UBUNTU_SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

fix_dns
apt-get update
"${APT[@]}" install systemd-sysv dbus ca-certificates curl gpg
dbus-uuidgen > /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

log "Kernel, live boot and bootloader tools"
fix_dns
"${APT[@]}" install linux-generic casper laptop-detect os-prober network-manager locales \
  grub-common grub2-common grub-gfxpayload-lists grub-pc-bin grub-efi-amd64-bin \
  grub-efi-amd64-signed shim-signed efibootmgr mtools dosfstools

log "Firefox straight from Mozilla (Ubuntu's 'firefox' is a snap wrapper)"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc
cat > /etc/apt/sources.list.d/mozilla.sources <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
cat > /etc/apt/preferences.d/mozilla <<EOF
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
apt-get update

log "GNOME desktop"
fix_dns
"${APT[@]}" install ubuntu-desktop-minimal firefox

log "Extra packages"
fix_dns
mapfile -t extras < <(read_list "$IN/packages.list")
install_available "${extras[@]}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
  || warn "couldn't add Flathub; users can add it later"
if [[ -x /usr/bin/kitty ]]; then
  update-alternatives --set x-terminal-emulator /usr/bin/kitty \
    || warn "couldn't make kitty the x-terminal-emulator"
fi

log "Animation extensions from extensions.gnome.org"
shell_major="$(dpkg-query -W -f='${Version}' gnome-shell | cut -d. -f1)"
mapfile -t extensions < <(read_list "$IN/gnome-extensions.list")
for uuid in "${extensions[@]}"; do
  info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell_major")" || {
    warn "skipping extension '$uuid' (nothing compatible with GNOME $shell_major)"; continue; }
  url="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["download_url"])' <<<"$info")"
  dest="/usr/share/gnome-shell/extensions/$uuid"
  rm -rf "$dest"
  mkdir -p "$dest"
  curl -fsSL "https://extensions.gnome.org$url" -o /tmp/extension.zip
  unzip -q -o /tmp/extension.zip -d "$dest"
  rm -f /tmp/extension.zip
  # system-wide extensions need their settings schemas in the global dir
  if compgen -G "$dest/schemas/*.gschema.xml" >/dev/null; then
    cp "$dest"/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
  fi
  chmod -R u=rwX,go=rX "$dest"
  log "  installed $uuid"
done
glib-compile-schemas /usr/share/glib-2.0/schemas

log "Installer + UwUbuntu branding and apps"
fix_dns
"${APT[@]}" install calamares "$IN"/uwubuntu-*_all.deb
# Fail the build (rather than ship broken apps) if GTK/libadwaita won't load
python3 -c 'import sys; sys.path.insert(0, "/usr/lib/uwubuntu"); import uwubuntu_ui' \
  && python3 -m py_compile /usr/bin/uwu-welcome /usr/bin/uwu-settings /usr/bin/paw-updater
# The installed system needs exactly one of these, depending on BIOS vs UEFI;
# post-install.sh picks the right one offline.
mkdir -p /var/cache/uwubuntu/bootloader
(cd /var/cache/uwubuntu/bootloader && apt-get download grub-efi-amd64 grub-pc)
cp -r "$IN/live/." /   # plain -r: never touch ownership/modes of existing dirs

log "Live session (casper)"
cat > /etc/casper.conf <<EOF
export USERNAME="$LIVE_USERNAME"
export USERFULLNAME="$LIVE_FULLNAME"
export HOST="$LIVE_HOSTNAME"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="$DISTRO_NAME"
EOF

log "Locale"
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/default/locale

log "Removing unwanted packages"
# Never let a removal drag these out with it (they pull in the whole desktop,
# and losing them would make autoremove delete everything they brought in).
PROTECTED='^Remv (ubuntu-minimal|ubuntu-standard|ubuntu-desktop-minimal|ubuntu-desktop|gnome-shell|gdm3|uwubuntu-[a-z]+) '
mapfile -t unwanted < <(read_list "$IN/packages-remove.list")
for pkg in "${unwanted[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || continue
  if apt-get -s purge "$pkg" | grep -qE "$PROTECTED"; then
    warn "keeping '$pkg': removing it would also remove the desktop"
    continue
  fi
  "${APT[@]}" purge "$pkg"
done
# Keep snap from sneaking back in through a dependency (same as Linux Mint).
if ! dpkg -s snapd >/dev/null 2>&1; then
  rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
  printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' > /etc/apt/preferences.d/no-snap
fi

log "Regenerating initramfs (casper + boot splash)"
update-initramfs -u -k all

log "Cleaning up"
"${APT[@]}" autoremove --purge
apt-get clean
rm -rf /var/lib/apt/lists/* /var/tmp/* /root/.bash_history
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id /usr/sbin/policy-rc.d
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
log "Chroot done (=^·ω·^=)"
