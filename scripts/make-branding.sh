#!/usr/bin/env bash
# Render the artwork and build the UwUbuntu .debs (uwubuntu-branding and
# uwubuntu-apps), plus the live-only files (installer config) that build.sh
# copies into the chroot.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ART="$ROOT/art"
PKG="$STAGE/uwubuntu-branding"
APPS="$STAGE/uwubuntu-apps"
LIVE="$STAGE/live"

log "Rendering packages $PKG_VERSION"
rm -rf "$PKG" "$APPS" "$LIVE" "$STAGE"/uwubuntu-*_all.deb
mkdir -p "$STAGE"
cp -a "$ROOT/branding/uwubuntu-branding" "$PKG"
cp -a "$ROOT/branding/uwubuntu-apps" "$APPS"
cp -a "$ROOT/live" "$LIVE"
render_templates "$PKG"
render_templates "$APPS"
render_templates "$LIVE"

log "Rendering artwork"
# Desktop + lock screen
wallpaper2png "$ART/wallpaper-day.webp"   "$PKG/usr/share/backgrounds/uwubuntu/uwubuntu-day.png"
wallpaper2png "$ART/wallpaper-night.webp" "$PKG/usr/share/backgrounds/uwubuntu/uwubuntu-night.png"
# Logo / icon (LOGO= in os-release, GNOME "About", installer)
for size in 48 64 128 256; do
  img2png "$ART/logo.png" $size $size "$PKG/usr/share/icons/hicolor/${size}x${size}/apps/uwubuntu-logo.png"
done
img2png "$ART/logo.png" 256 256 "$PKG/usr/share/pixmaps/uwubuntu-logo.png"
# Boot splash
img2png "$ART/logo.png" 200 200 "$PKG/usr/share/plymouth/themes/uwubuntu/logo.png"
img2png "$ART/paw.svg"   36  36 "$PKG/usr/share/plymouth/themes/uwubuntu/paw.png"
# GRUB (installed system + ISO). Plain background: the wallpapers have the
# logo in the middle, right where the boot menu goes.
img2png "$ART/grub-background.svg" 1920 1080 "$PKG/usr/share/grub/themes/uwubuntu/background.png"
img2png "$ART/logo.png" 128 128 "$PKG/usr/share/grub/themes/uwubuntu/logo.png"
img2png "$ART/grub-select.svg" 16 34 "$PKG/usr/share/grub/themes/uwubuntu/select_c.png"
# Installer
CAL="$LIVE/etc/calamares/branding/uwubuntu"
img2png "$ART/logo.png" 128 128 "$CAL/logo.png"
img2png "$ART/logo.png" 360 360 "$CAL/welcome.png"
img2png "$ART/paw.svg"  96  96  "$CAL/paw.png"
# App icons: art/icons/<name>.{svg,png} -> org.uwubuntu.<AppId>
declare -A APP_ICONS=([welcome]=Welcome [settings]=Settings [paw-updater]=PawUpdater)
for name in "${!APP_ICONS[@]}"; do
  src="$(ls "$ART/icons/$name".* | head -n1)"
  id="org.uwubuntu.${APP_ICONS[$name]}"
  if [[ "$src" == *.svg ]]; then
    install -Dm644 "$src" "$APPS/usr/share/icons/hicolor/scalable/apps/$id.svg"
  fi
  for size in 48 128 256; do
    img2png "$src" $size $size "$APPS/usr/share/icons/hicolor/${size}x${size}/apps/$id.png"
  done
done

log "Building .debs"
# Sources may come from a Windows/WSL mount where everything is 0777.
find "$PKG" "$APPS" "$LIVE" -type d -exec chmod 0755 {} +
find "$PKG" "$APPS" "$LIVE" -type f -exec chmod 0644 {} +
chmod 0755 "$PKG"/DEBIAN/{preinst,postinst,prerm,postrm} "$PKG"/usr/bin/* "$PKG"/etc/update-motd.d/*
chmod 0755 "$APPS"/usr/bin/* "$APPS"/usr/lib/uwubuntu/paw-updater-helper
chmod 0755 "$LIVE"/usr/lib/uwubuntu/installer/*
for dir in "$PKG" "$APPS"; do
  echo "Installed-Size: $(du -sk --exclude=DEBIAN "$dir" | cut -f1)" >> "$dir/DEBIAN/control"
  name="$(basename "$dir")"
  dpkg-deb --root-owner-group --build "$dir" "$STAGE/${name}_${PKG_VERSION}_all.deb"
  log "Built $STAGE/${name}_${PKG_VERSION}_all.deb"
done
