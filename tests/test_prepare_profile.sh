#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TARGET_SCRIPT="$REPO_ROOT/prepare-orionlinux-profile.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local needle=$2

  grep -Fq -- "$needle" "$file" || fail "expected '$needle' in $file"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PROFILE="$TMPDIR/releng"
mkdir -p "$PROFILE/airootfs/etc" \
         "$PROFILE/boot/grub" \
         "$PROFILE/boot/syslinux" \
         "$PROFILE/customrepo/x86_64"

cat > "$PROFILE/profiledef.sh" <<'EOF'
iso_name='archlinux'
iso_label='ARCH_202604'
iso_publisher='Arch Linux'
iso_application='Arch Linux live/install medium'
install_dir='arch'
EOF

cat > "$PROFILE/packages.x86_64" <<'EOF'
bash
EOF

cat > "$PROFILE/pacman.conf" <<'EOF'
[options]
Architecture = auto

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

cat > "$PROFILE/boot/grub/grub.cfg" <<'EOF'
menuentry "Arch Linux install medium" {
    echo Arch Linux
}
EOF

touch "$PROFILE/customrepo/x86_64/yay-bin-12.5.7-1-x86_64.pkg.tar.zst"

bash "$TARGET_SCRIPT" "$PROFILE"

assert_file_contains "$PROFILE/profiledef.sh" "iso_name='orionlinux'"
assert_file_contains "$PROFILE/profiledef.sh" "install_dir='orion'"
assert_file_contains "$PROFILE/pacman.conf" "[orionlocal]"
assert_file_contains "$PROFILE/pacman.conf" 'Server = file://'
assert_file_contains "$PROFILE/pacman.conf" 'https://geo.mirror.pkgbuild.com/core/os/$arch'
assert_file_contains "$PROFILE/packages.x86_64" "git"
assert_file_contains "$PROFILE/packages.x86_64" "base-devel"
assert_file_contains "$PROFILE/packages.x86_64" "yay-bin"
assert_file_contains "$PROFILE/airootfs/etc/hostname" "orionlinux"
assert_file_contains "$PROFILE/airootfs/usr/local/share/orionlinux/archinstall-defaults.json" '"name": "orionlocal"'
assert_file_contains "$PROFILE/airootfs/usr/local/share/orionlinux/archinstall-defaults.json" '"yay-bin"'
assert_file_contains "$PROFILE/boot/grub/grub.cfg" "Orionlinux install medium"

[[ -x "$PROFILE/airootfs/usr/local/bin/archinstall" ]] || fail "archinstall wrapper missing"
[[ -x "$PROFILE/airootfs/usr/local/bin/orioninstall" ]] || fail "orioninstall wrapper missing"
[[ -f "$PROFILE/airootfs/usr/local/share/orionlinux/repo/x86_64/yay-bin-12.5.7-1-x86_64.pkg.tar.zst" ]] || fail "embedded repo package missing"

printf 'PASS: prepare-orionlinux-profile smoke test\n'
