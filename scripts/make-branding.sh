#!/usr/bin/env bash
# Render the artwork and build the uwubuntu-branding .deb, plus the live-only
# files (installer config) that build.sh copies into the chroot.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ART="$ROOT/art"
PKG="$STAGE/uwubuntu-branding"
LIVE="$STAGE/live"

log "Rendering branding package $PKG_VERSION"
rm -rf "$PKG" "$LIVE" "$STAGE"/uwubuntu-branding_*.deb
mkdir -p "$STAGE"
cp -a "$ROOT/branding/uwubuntu-branding" "$PKG"
cp -a "$ROOT/live" "$LIVE"
render_templates "$PKG"
render_templates "$LIVE"

log "Rendering artwork"
# Desktop + lock screen
svg2png "$ART/wallpaper-day.svg"   3840 2160 "$PKG/usr/share/backgrounds/uwubuntu/uwubuntu-day.png"
svg2png "$ART/wallpaper-night.svg" 3840 2160 "$PKG/usr/share/backgrounds/uwubuntu/uwubuntu-night.png"
# Logo / icon (LOGO= in os-release, GNOME "About", installer)
install -Dm644 "$ART/logo.svg" "$PKG/usr/share/icons/hicolor/scalable/apps/uwubuntu-logo.svg"
for size in 48 128 256; do
  svg2png "$ART/logo.svg" $size $size "$PKG/usr/share/icons/hicolor/${size}x${size}/apps/uwubuntu-logo.png"
done
svg2png "$ART/logo.svg" 256 256 "$PKG/usr/share/pixmaps/uwubuntu-logo.png"
# Boot splash
svg2png "$ART/logo.svg" 200 200 "$PKG/usr/share/plymouth/themes/uwubuntu/logo.png"
svg2png "$ART/paw.svg"   36  36 "$PKG/usr/share/plymouth/themes/uwubuntu/paw.png"
# GRUB (installed system + ISO)
svg2png "$ART/wallpaper-night.svg" 1920 1080 "$PKG/usr/share/grub/themes/uwubuntu/background.png"
svg2png "$ART/logo.svg" 128 128 "$PKG/usr/share/grub/themes/uwubuntu/logo.png"
svg2png "$ART/grub-select.svg" 16 34 "$PKG/usr/share/grub/themes/uwubuntu/select_c.png"
# Installer
CAL="$LIVE/etc/calamares/branding/uwubuntu"
svg2png "$ART/logo.svg" 128 128 "$CAL/logo.png"
svg2png "$ART/logo.svg" 360 360 "$CAL/welcome.png"
svg2png "$ART/paw.svg"  96  96  "$CAL/paw.png"

log "Building .deb"
# Sources may come from a Windows/WSL mount where everything is 0777.
find "$PKG" "$LIVE" -type d -exec chmod 0755 {} +
find "$PKG" "$LIVE" -type f -exec chmod 0644 {} +
chmod 0755 "$PKG"/DEBIAN/{preinst,postinst,prerm,postrm} "$PKG"/usr/bin/* "$PKG"/etc/update-motd.d/*
chmod 0755 "$LIVE"/usr/lib/uwubuntu/installer/*
echo "Installed-Size: $(du -sk --exclude=DEBIAN "$PKG" | cut -f1)" >> "$PKG/DEBIAN/control"
dpkg-deb --root-owner-group --build "$PKG" "$STAGE/uwubuntu-branding_${PKG_VERSION}_all.deb"
log "Built $STAGE/uwubuntu-branding_${PKG_VERSION}_all.deb"
