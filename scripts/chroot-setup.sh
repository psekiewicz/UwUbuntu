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

log "Checking UwUbuntu packages for file clashes"
# dpkg stops at the first file another package owns; list them all at once.
# The diverted files are expected (the branding preinst diverts them).
DIVERTED=' /usr/lib/os-release /etc/issue /etc/issue.net '
clashes=""
for deb in "$IN"/uwubuntu-*_all.deb; do
  while IFS= read -r path; do
    [[ "$DIVERTED" == *" $path "* ]] && continue
    owner="$(dpkg-query -S "$path" 2>/dev/null | cut -d: -f1 || true)"
    [[ -n "$owner" ]] && clashes+="  $path (already in $owner)"$'\n'
  done < <(dpkg-deb --fsys-tarfile "$deb" | tar -t | sed -n 's#^\./#/#p' | grep -v '/$')
done
if [[ -n "$clashes" ]]; then
  printf '\e[1;31m[chroot] error:\e[0m these files clash with installed packages:\n%s' "$clashes" >&2
  exit 1
fi

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

log "UwUbuntu desktop metapackage"
# Ubuntu's ubuntu-desktop-minimal depends on update-manager and friends, so it
# goes when they do, and then nothing pulls new desktop packages in on upgrade.
# Like Linux Mint, replace it with our own copy of its dependency list, minus
# everything the removals below would take with them (including the cascade,
# e.g. ubuntu-release-upgrader-gtk needs update-manager), plus our extras.
# These must survive the removals; ubuntu-desktop-minimal may go, since
# uwubuntu-desktop replaces it.
PROTECTED=(ubuntu-minimal ubuntu-standard uwubuntu-desktop uwubuntu-branding uwubuntu-apps
           gnome-shell gdm3)
mapfile -t unwanted < <(read_list "$IN/packages-remove.list")
installed_unwanted=()
for pkg in "${unwanted[@]}"; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then installed_unwanted+=("$pkg"); fi
done
# apt's simulation prints "Remv pkg [ver]" for removals and "Purg pkg [ver]"
# for purges. Captured first: piping straight into grep can SIGPIPE apt.
simulation="$(apt-get -s purge "${installed_unwanted[@]}" 2>/dev/null || true)"
sed -nE 's/^(Remv|Purg) ([^ :]+).*/\2/p' <<<"$simulation" | sort -u \
  | { grep -vxF -f <(printf '%s\n' "${PROTECTED[@]}") || true; } > "$IN/going-away.list"
log "  removing Canonical's tools also takes: $(tr '\n' ' ' < "$IN/going-away.list")"

mkdir -p "$IN/desktop/DEBIAN"
python3 - "$PKG_VERSION" "$IN/going-away.list" "$IN/packages-remove.list" "$IN/packages.list" \
  > "$IN/desktop/DEBIAN/control" <<'PY'
import re, subprocess, sys

version, going_away, remove_list, extras_list = sys.argv[1:5]

def names(path):
    with open(path, encoding="utf-8") as f:
        return [l.split("#", 1)[0].strip() for l in f if l.split("#", 1)[0].strip()]

excluded = set(names(going_away)) | set(names(remove_list))
show = subprocess.run(["apt-cache", "show", "--no-all-versions", "ubuntu-desktop-minimal"],
                      capture_output=True, text=True, check=True).stdout
fields = dict(re.findall(r"^(Depends|Recommends): (.*)$", show, re.M))

def keep(field):
    kept = []
    for dep in fields.get(field, "").split(","):
        alts = [a.strip() for a in dep.split("|") if a.strip()]
        alts = [a for a in alts if re.split(r"[ (:]", a)[0] not in excluded]
        if alts:
            kept.append(" | ".join(alts))
    return kept

installed = set(subprocess.run(["dpkg-query", "-W", "-f=${Package}\n"],
                               capture_output=True, text=True).stdout.split())
depends = keep("Depends") + ["uwubuntu-branding", "uwubuntu-apps"]
recommends = keep("Recommends") + [p for p in names(extras_list)
                                   if p in installed and p not in excluded]
print("Package: uwubuntu-desktop")
print(f"Version: {version}")
print("Architecture: all")
print("Maintainer: UwUbuntu Developers <uwubuntu@example.org>")
print("Section: metapackages")
print("Priority: optional")
print("Depends: " + ", ".join(depends))
if recommends:
    print("Recommends: " + ", ".join(recommends))
print("Description: UwUbuntu desktop system")
print(" Everything Ubuntu's desktop metapackage pulls in, minus Canonical's own")
print(" tools, plus UwUbuntu's extras, so upgrades keep the desktop complete.")
PY
dpkg-deb --root-owner-group --build "$IN/desktop" "$IN/uwubuntu-desktop_${PKG_VERSION}_all.deb"
"${APT[@]}" install "$IN/uwubuntu-desktop_${PKG_VERSION}_all.deb"

log "Removing unwanted packages"
# Hold what keeps the desktop together (PROTECTED, above): apt then refuses,
# and we skip, any removal that would take one of these with it.
apt-mark hold "${PROTECTED[@]}"
for pkg in "${installed_unwanted[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || continue   # already gone with an earlier one
  if ! "${APT[@]}" purge "$pkg"; then
    warn "keeping '$pkg': removing it would also remove the desktop"
  fi
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
apt-mark unhold "${PROTECTED[@]}"   # held packages would never get upgrades
apt-get clean
rm -rf /var/lib/apt/lists/* /var/tmp/* /root/.bash_history
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id /usr/sbin/policy-rc.d
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
log "Chroot done (=^·ω·^=)"
