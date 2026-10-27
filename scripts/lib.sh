# Shared helpers for the UwUbuntu build scripts. Source this, don't run it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/uwubuntu.conf
source "$ROOT/config/uwubuntu.conf"

WORK="${WORK:-$ROOT/work}"
OUT="${OUT:-$ROOT/out}"
STAGE="$WORK/stage"     # rendered branding package + live-only files
CHROOT="$WORK/chroot"   # the future root filesystem
IMAGE="$WORK/image"     # the ISO tree
PKG_VERSION="${PKG_VERSION:-${DISTRO_VERSION}.$(date -u +%Y%m%d)}"

# Every @NAME@ placeholder in a *.in file is replaced with the value of $NAME.
TEMPLATE_VARS=(
  DISTRO_NAME DISTRO_ID DISTRO_VERSION DISTRO_VERSION_SUFFIX DISTRO_CODENAME_PRETTY
  DISTRO_HOME_URL DISTRO_SUPPORT_URL DISTRO_BUG_URL
  UBUNTU_SUITE PKG_VERSION LIVE_USERNAME LIVE_FULLNAME LIVE_HOSTNAME
)

log()  { printf '\e[1;35m[uwu]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[uwu] warning:\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m[uwu] error:\e[0m %s\n' "$*" >&2; exit 1; }

# Render every *.in file below $1 in place (foo.conf.in -> foo.conf).
render_templates() {
  local args=() var val file
  for var in "${TEMPLATE_VARS[@]}"; do
    val="${!var}"
    val="${val//\\/\\\\}"; val="${val//|/\\|}"; val="${val//&/\\&}"
    args+=(-e "s|@${var}@|${val}|g")
  done
  while IFS= read -r -d '' file; do
    sed "${args[@]}" "$file" > "${file%.in}"
    chmod --reference="$file" "${file%.in}"
    rm "$file"
  done < <(find "$1" -type f -name '*.in' -print0)
}

imagemagick() { if command -v magick >/dev/null; then magick "$@"; else convert "$@"; fi; }

# Decode .webp to a temporary .png (ImageMagick's own WebP support varies);
# prints the path to use.
decode_webp() {
  local tmp
  if [[ "$1" == *.webp ]]; then
    tmp="$(mktemp --suffix=.png)"
    dwebp -quiet "$1" -o "$tmp"
    echo "$tmp"
  else
    echo "$1"
  fi
}

# img2png SRC WIDTH HEIGHT DEST: fit SVG/PNG/WebP into a transparent
# WIDTHxHEIGHT box. Always writes 8-bit non-interlaced PNG (GRUB is picky).
img2png() {
  local src
  mkdir -p "$(dirname "$4")"
  if [[ "$1" == *.svg ]]; then
    rsvg-convert --width "$2" --height "$3" --keep-aspect-ratio --output "$4" "$1"
    return
  fi
  src="$(decode_webp "$1")"
  imagemagick "$src" -resize "${2}x${3}" -background none -gravity center \
    -extent "${2}x${3}" -depth 8 -interlace none "PNG32:$4"
  [[ "$src" == "$1" ]] || rm -f "$src"
}

# wallpaper2png SRC DEST: flatten to an opaque PNG at native resolution.
wallpaper2png() {
  local src
  mkdir -p "$(dirname "$2")"
  src="$(decode_webp "$1")"
  imagemagick "$src" -background black -alpha remove -alpha off -depth 8 -interlace none "PNG24:$2"
  [[ "$src" == "$1" ]] || rm -f "$src"
}
