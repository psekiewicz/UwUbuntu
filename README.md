# UwUbuntu
I vibecoded ubuntu.

Made with claude, this is better than Ubntu: furry edition.\
I hope ts works.\
Propably not.

Wait,

I forgot my dad follows me on Github\
I might be dead rn

---

A Ubuntu remix built on **Ubuntu 26.04 LTS "Resolute Raccoon"**, with
five years of upstream updates.

| | |
|---|---|
| Base | Ubuntu 26.04 LTS (switch to 26.10 "Stonking Stingray" in `config/uwubuntu.conf`) |
| Desktop | GNOME: dock at the bottom, dark mode + orange accent, wobbly windows, magic-lamp minimise, Burn My Windows effects, Blur My Shell |
| Terminal | kitty with the "Ember" colour theme and a cursor trail |
| Our own apps | **UwU Welcome** (first-run tour + Flathub app picker), **UwU Settings** (look, animations, terminal, startup), **Paw Updater** (system + Flatpak updates) |
| No Canonical extras | No snap, Ubuntu Pro, Update Manager, Apport or telemetry |
| Installer | Calamares, with a custom slideshow and branding |
| Apps | GNOME Software + Flathub, Firefox `.deb` straight from Mozilla, Krita, Inkscape, GIMP, VLC |
| Boot | Themed GRUB menu and an animated "walking paws" Plymouth splash (with LUKS prompt) |
| Toys | `uwufetch`, `uwuify`, a furry MOTD, `cowsay`, `lolcat`, `sl` |

## Layout

```
config/            what to build: names, versions, mirrors, package and
                   GNOME extension lists
art/               source artwork (SVG/PNG/WebP), rendered at build time
branding/          the two .debs: uwubuntu-branding (os-release, wallpapers,
                   plymouth, grub, GNOME/kitty defaults, terminal
                   toys) and uwubuntu-apps (Welcome, Settings, Paw Updater)
live/              files that only exist on the live ISO (Calamares installer)
iso/               boot menu of the ISO
scripts/           build stages (chroot-setup.sh runs inside the new system)
build.sh           entry point
```

Files ending in `.in` are templates: every `@DISTRO_NAME@`-style placeholder is
filled in from `config/uwubuntu.conf`, so renaming the distro is one edit.

## Building

The build needs **Linux running as root**, about **25 GB** of free disk and an
internet connection. It takes 30–90 minutes.

### Option A: GitHub Actions (easiest from Windows)

Push this folder to a GitHub repo, then go to **Actions → Build ISO → Run
workflow**. The ISO is uploaded as a build artifact. Free artifact storage is
very limited on private repos, so use a public repo or a self-hosted runner.

### Option B: WSL2 on Windows

```powershell
wsl --install -d Ubuntu-26.04
```

Build from inside WSL's own filesystem. Building on `/mnt/p` (NTFS) breaks the chroot:

```bash
sudo WORK=/var/tmp/uwubuntu OUT=/mnt/p/UwUbuntu/out bash /mnt/p/UwUbuntu/build.sh
```

### Option C: any Ubuntu 26.04 machine or VM

```bash
sudo bash build.sh
```

### Option D: Docker (Linux host)

```bash
sudo docker run --rm --privileged -v "$PWD:/src" -w /src ubuntu:26.04 bash build.sh
```

### Stages

`build.sh` with no argument runs everything. You can also run one stage at a
time, which is handy while iterating on the art or the branding:

| Stage | Does |
|---|---|
| `deps` | installs host tools (debootstrap, squashfs-tools, xorriso, grub, rsvg) |
| `branding` | renders the art and builds `uwubuntu-branding_*.deb` |
| `bootstrap` | debootstraps a minimal Ubuntu into `work/chroot` (cached) |
| `customize` | installs the desktop, apps, installer and branding in the chroot |
| `iso` | squashes the chroot and writes `out/uwubuntu-26.04-desktop-amd64.iso` |
| `clean` | deletes `work/` |

Set `SQUASHFS_COMP="zstd"` in the config for much faster test builds.

## Testing

Boot the ISO in a VM before using real hardware:

```bash
qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cdrom out/uwubuntu-26.04-desktop-amd64.iso \
  -bios /usr/share/ovmf/OVMF.fd
```

VirtualBox and GNOME Boxes work too. Turn on EFI in the VM settings to test the UEFI path.

## Known limitations

- The **live ISO's** GRUB is unsigned, so turn off Secure Boot to boot it. The
  **installed** system uses Ubuntu's signed shim + GRUB and works with Secure Boot on.
- BIOS (legacy) installs are best-effort. UEFI is the main target.
- "Ubuntu" is a Canonical trademark. A private build is fine, but before
  publishing ISOs, read Canonical's [IP rights policy](https://ubuntu.com/legal/intellectual-property-policy)
  on remixes, or consider a name without "Ubuntu" in it.

## Artwork

Everything is in `art/` and gets resized and converted at build time (SVG, PNG and
WebP all work; the paths are in `scripts/make-branding.sh`):

- `logo.png`: the kitty-eared logo (app icon, boot splash, GRUB, installer)
- `wallpaper-day.webp`, `wallpaper-night.webp`: desktop wallpapers for light and dark mode
- `paw.svg`: single paw print used in the boot animation and slideshow
- `grub-background.svg`: **placeholder** boot menu background, to be replaced.
  Keep the middle clear (roughly 25–75% across, 36–78% down), since that's
  where the menu is drawn and the logo sits just above it
- `icons/welcome.png`, `icons/settings.png`, `icons/paw-updater.png`: icons for
  UwU Welcome, UwU Settings and Paw Updater (square, 256 px or bigger; `.svg` works too)
- Wishlist, not wired up yet: a paw cursor theme, a mascot character for the
  installer slideshow, login/notification sounds, extra wallpapers, and 4K
  versions of the wallpapers (the current ones are 1920×1080)

The logo is based on Ubuntu's Circle of Friends, which is a Canonical trademark.
Fine for a fan project, but check the policy linked above before distributing widely.

Open `art/preview.html` through the `art-preview` launch config to see them all at once.
