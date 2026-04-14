# Orionlinux Archiso Bundle

This repository contains the source bundle used to build a branded `archiso`
image for `Orionlinux`.

`Orionlinux` is a personal Linux distribution based on Arch Linux, named after
my cat.

It does not ship prebuilt ISOs. The intended workflow is:

1. clone this repo inside an Arch Linux `x86_64` build environment
2. optionally stage a local `customrepo/` with `yay-bin`
3. run `./build.sh`
4. collect the ISO from `out/`

## Requirements

- Arch Linux `x86_64`
- `archiso`
- root privileges for `mkarchiso`

Install the builder package:

```bash
sudo pacman -Syu archiso
```

## Quick Start

Build a stock Orionlinux ISO:

```bash
./build.sh
```

Artifacts land in:

```bash
out/
```

## Offline `yay` In The Installed System

If you want the installed Orionlinux system to come up with `yay` already
available and without downloading it during installation, stage a local repo in
this repository before running `build.sh`.

Expected layout:

```text
customrepo/
  x86_64/
    orionlocal.db.tar.gz
    yay-bin-*.pkg.tar.zst
```

Example:

```bash
mkdir -p customrepo/x86_64
cp /path/to/yay-bin-12.5.7-1-x86_64.pkg.tar.zst customrepo/x86_64/
repo-add customrepo/x86_64/orionlocal.db.tar.gz \
  customrepo/x86_64/yay-bin-12.5.7-1-x86_64.pkg.tar.zst
./build.sh
```

When `customrepo/x86_64` is present and contains `yay-bin`, the build:

- prepends an `orionlocal` repo to the temporary `pacman.conf`
- installs `yay-bin` into the live ISO
- embeds the local repo inside the ISO
- configures `archinstall` and `orioninstall` so the installed system also gets
  `git`, `base-devel`, `sudo`, and `yay-bin`
- removes the temporary `orionlocal` stanza from the installed target at the
  end of the post-install step

## What `build.sh` Does

`build.sh` automates the full local workflow:

1. copies `/usr/share/archiso/configs/releng` into `work/orionlinux`
2. optionally stages `customrepo/`
3. applies the Orionlinux branding patch via `prepare-orionlinux-profile.sh`
4. runs `mkarchiso`
5. writes the final ISO to `out/`

The script accepts these environment overrides when needed:

- `RELENG_SOURCE`: alternate source profile instead of
  `/usr/share/archiso/configs/releng`
- `WORKDIR`: alternate temporary build directory
- `OUTDIR`: alternate output directory
- `MKARCHISO_BIN`: alternate `mkarchiso` binary path
- `SUDO_BIN`: alternate privilege escalation command

## What Gets Branded

- ISO metadata in `profiledef.sh`
- live system identity in `airootfs/etc/os-release`
- console banner in `airootfs/etc/issue`
- login message in `airootfs/etc/motd`
- live hostname in `airootfs/etc/hostname`
- boot menu labels in GRUB, systemd-boot, and Syslinux config files when present
- guided installations launched via `archinstall` or `orioninstall`

## Repo Layout

```text
.
├── branding/
├── build.sh
├── prepare-orionlinux-profile.sh
└── tests/
```

## Notes

- This repository is source-only. `*.iso`, `work/`, `out/`, and `customrepo/`
  are ignored.
- Branding of the installed target is wired into `archinstall` and
  `orioninstall`. Manual `pacstrap` installs will not automatically pick up the
  Orionlinux post-install branding.
