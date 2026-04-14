#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TARGET_SCRIPT="$REPO_ROOT/build.sh"

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

RELENG_SOURCE="$TMPDIR/releng-source"
BIN_DIR="$TMPDIR/bin"
mkdir -p "$RELENG_SOURCE/airootfs/etc" \
         "$RELENG_SOURCE/boot/grub" \
         "$BIN_DIR"

cat > "$RELENG_SOURCE/profiledef.sh" <<'EOF'
iso_name='archlinux'
EOF

cat > "$RELENG_SOURCE/packages.x86_64" <<'EOF'
bash
EOF

cat > "$RELENG_SOURCE/pacman.conf" <<'EOF'
[options]
Architecture = auto

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

cat > "$RELENG_SOURCE/boot/grub/grub.cfg" <<'EOF'
menuentry "Arch Linux install medium" {
    echo Arch Linux
}
EOF

cat > "$BIN_DIR/mkarchiso" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_LOG"
mkdir -p "$TEST_OUT"
touch "$TEST_OUT/fake.iso"
EOF

cat > "$BIN_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$@"
EOF

chmod 0755 "$BIN_DIR/mkarchiso" "$BIN_DIR/sudo"

mkdir -p "$REPO_ROOT/customrepo/x86_64"
trap 'rm -rf "$TMPDIR"; rm -rf "$REPO_ROOT/customrepo" "$REPO_ROOT/work" "$REPO_ROOT/out"' EXIT
touch "$REPO_ROOT/customrepo/x86_64/yay-bin-12.5.7-1-x86_64.pkg.tar.zst"
touch "$REPO_ROOT/customrepo/x86_64/orionlocal.db.tar.gz"

TEST_LOG="$TMPDIR/mkarchiso.log"
TEST_OUT="$REPO_ROOT/out"
export TEST_LOG TEST_OUT

PATH="$BIN_DIR:$PATH" RELENG_SOURCE="$RELENG_SOURCE" MKARCHISO_BIN="$BIN_DIR/mkarchiso" SUDO_BIN="$BIN_DIR/sudo" \
  bash "$TARGET_SCRIPT"

[[ -d "$REPO_ROOT/work/orionlinux" ]] || fail "workdir missing"
[[ -f "$REPO_ROOT/out/fake.iso" ]] || fail "fake iso output missing"
[[ -f "$REPO_ROOT/work/orionlinux/customrepo/x86_64/yay-bin-12.5.7-1-x86_64.pkg.tar.zst" ]] || fail "customrepo not staged"

assert_file_contains "$TEST_LOG" "-v -o $REPO_ROOT/out $REPO_ROOT/work/orionlinux"
assert_file_contains "$REPO_ROOT/work/orionlinux/profiledef.sh" "iso_name='orionlinux'"
assert_file_contains "$REPO_ROOT/work/orionlinux/airootfs/etc/hostname" "orionlinux"

printf 'PASS: build.sh smoke test\n'
