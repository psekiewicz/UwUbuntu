#!/usr/bin/env bash
# Build the UwUbuntu live + install ISO.
#
# Run as root on Ubuntu 26.04 (bare metal, VM, WSL2 or a --privileged container):
#   sudo bash build.sh            # everything
#   sudo bash build.sh <stage>    # one stage: deps branding bootstrap customize iso clean
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

HOST_DEPS=(debootstrap squashfs-tools xorriso grub-common grub-pc-bin grub-efi-amd64-bin
           mtools dosfstools librsvg2-bin imagemagick webp dpkg-dev ubuntu-keyring)

stage_deps() {
  log "Installing host build dependencies"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${HOST_DEPS[@]}"
}

stage_branding() {
  bash "$ROOT/scripts/make-branding.sh"
}

stage_bootstrap() {
  if [[ -e "$WORK/.bootstrapped" ]]; then
    log "Base system already bootstrapped (delete $WORK to start over)"
    return
  fi
  log "Bootstrapping Ubuntu '$UBUNTU_SUITE' into $CHROOT"
  rm -rf "$CHROOT"
  mkdir -p "$CHROOT"
  # Older debootstrap releases don't know brand-new suites yet; every Ubuntu
  # suite since 7.10 uses the same script.
  local script=()
  if [[ ! -e "/usr/share/debootstrap/scripts/$UBUNTU_SUITE" ]]; then
    warn "host debootstrap doesn't know '$UBUNTU_SUITE', using the generic Ubuntu script"
    script=(/usr/share/debootstrap/scripts/gutsy)
  fi
  debootstrap --arch="$ARCH" --variant=minbase --components=main,restricted,universe,multiverse \
    "$UBUNTU_SUITE" "$CHROOT" "$UBUNTU_MIRROR" "${script[@]}"
  touch "$WORK/.bootstrapped"
}

mount_chroot() {
  mountpoint -q "$CHROOT/dev"     || mount --bind /dev "$CHROOT/dev"
  mountpoint -q "$CHROOT/dev/pts" || mount --bind /dev/pts "$CHROOT/dev/pts"
  mountpoint -q "$CHROOT/proc"    || mount -t proc proc "$CHROOT/proc"
  mountpoint -q "$CHROOT/sys"     || mount -t sysfs sysfs "$CHROOT/sys"
  mountpoint -q "$CHROOT/run"     || mount -t tmpfs tmpfs "$CHROOT/run"
}

umount_chroot() {
  local d
  for d in run sys proc dev/pts dev; do
    if mountpoint -q "$CHROOT/$d"; then
      umount "$CHROOT/$d" 2>/dev/null || umount -l "$CHROOT/$d"
    fi
  done
}

stage_customize() {
  [[ -e "$WORK/.bootstrapped" ]] || die "run the bootstrap stage first"
  ls "$STAGE"/uwubuntu-{branding,apps}_*.deb >/dev/null 2>&1 || die "run the branding stage first"

  log "Customizing the chroot"
  trap umount_chroot EXIT
  mount_chroot

  rm -rf "$CHROOT/tmp/uwubuntu"
  mkdir -p "$CHROOT/tmp/uwubuntu"
  cp "$ROOT/scripts/chroot-setup.sh" "$ROOT"/config/*.list "$STAGE"/uwubuntu-*_all.deb \
     "$CHROOT/tmp/uwubuntu/"
  cp -a "$STAGE/live" "$CHROOT/tmp/uwubuntu/live"
  cp -L /etc/resolv.conf "$CHROOT/tmp/uwubuntu/host-resolv.conf"

  local var envs=(HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin)
  for var in "${TEMPLATE_VARS[@]}" UBUNTU_MIRROR UBUNTU_SECURITY_MIRROR; do
    envs+=("$var=${!var}")
  done
  chroot "$CHROOT" /usr/bin/env -i "${envs[@]}" bash /tmp/uwubuntu/chroot-setup.sh

  rm -rf "$CHROOT/tmp/uwubuntu"
  umount_chroot
  trap - EXIT
}

stage_iso() {
  [[ -e "$CHROOT/boot/vmlinuz" ]] || die "no kernel in the chroot; run the customize stage first"
  umount_chroot

  local iso="$OUT/${DISTRO_ID}-${DISTRO_VERSION}-desktop-${ARCH}.iso"
  log "Assembling ISO tree"
  rm -rf "$IMAGE"
  mkdir -p "$IMAGE"/{casper,.disk,boot/grub/themes} "$OUT"

  local kver
  kver="$(basename "$(ls -1 "$CHROOT"/boot/vmlinuz-* | sort -V | tail -n1)")"
  kver="${kver#vmlinuz-}"
  log "Using kernel $kver"
  cp "$CHROOT/boot/vmlinuz-$kver" "$IMAGE/casper/vmlinuz"
  cp "$CHROOT/boot/initrd.img-$kver" "$IMAGE/casper/initrd"
  chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$IMAGE/casper/filesystem.manifest"
  du -sx --block-size=1 "$CHROOT" | cut -f1 > "$IMAGE/casper/filesystem.size"
  printf '%s %s%s "%s" - %s (%s)\n' "$DISTRO_NAME" "$DISTRO_VERSION" "$DISTRO_VERSION_SUFFIX" \
    "$DISTRO_CODENAME_PRETTY" "$ARCH" "$(date -u +%Y%m%d)" > "$IMAGE/.disk/info"

  cp "$ROOT/iso/grub.cfg.in" "$IMAGE/boot/grub/"
  render_templates "$IMAGE/boot/grub"
  cp -a "$STAGE/uwubuntu-branding/usr/share/grub/themes/uwubuntu" "$IMAGE/boot/grub/themes/"

  log "Compressing root filesystem ($SQUASHFS_COMP), this takes a while"
  mksquashfs "$CHROOT" "$IMAGE/casper/filesystem.squashfs" -noappend -comp "$SQUASHFS_COMP" -b 1M

  log "Writing hybrid BIOS/UEFI ISO"
  grub-mkrescue --output="$iso" "$IMAGE" -- -volid "$ISO_VOLUME_ID"
  (cd "$OUT" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
  log "Done! $iso ($(du -h "$iso" | cut -f1))  (=^·ω·^=)"
}

stage_clean() {
  umount_chroot
  log "Removing $WORK"
  rm -rf "$WORK"
}

main() {
  [[ $EUID -eq 0 ]] || die "run me as root (sudo bash build.sh)"
  local stage="${1:-all}"
  case "$stage" in
    all)
      command -v apt-get >/dev/null && stage_deps
      stage_branding; stage_bootstrap; stage_customize; stage_iso ;;
    deps|branding|bootstrap|customize|iso|clean) "stage_$stage" ;;
    *) die "unknown stage '$stage' (all deps branding bootstrap customize iso clean)" ;;
  esac
}

main "$@"
