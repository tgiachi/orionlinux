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
WORKDIR="$TMPDIR/work/orionlinux"
OUTDIR="$TMPDIR/out"
CACHE_DIR="$TMPDIR/cache/archlinux"
DOWNLOAD_PAGE="$TMPDIR/download.html"
CHECKSUMS_FILE="$TMPDIR/sha256sums.txt"
FAKE_ISO_SOURCE="$TMPDIR/archlinux-2026.04.01-x86_64.iso"
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

cat > "$DOWNLOAD_PAGE" <<'EOF'
<ul>
  <li><strong>Current Release:</strong> 2026.04.01</li>
</ul>
EOF

printf 'fake iso payload\n' > "$FAKE_ISO_SOURCE"
FAKE_SHA=$(/usr/bin/shasum -a 256 "$FAKE_ISO_SOURCE" | awk '{print $1}')
cat > "$CHECKSUMS_FILE" <<EOF
$FAKE_SHA  archlinux-2026.04.01-x86_64.iso
EOF

cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=''
url=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    -f|-s|-S|-L|--retry|--retry-delay)
      if [[ "$1" == "--retry" || "$1" == "--retry-delay" ]]; then
        shift 2
      else
        shift
      fi
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

case "$url" in
  https://archlinux.org/download/)
    cat "$TEST_DOWNLOAD_PAGE"
    ;;
  https://archlinux.org/iso/2026.04.01/sha256sums.txt)
    cat "$TEST_SHA256SUMS"
    ;;
  https://geo.mirror.pkgbuild.com/iso/2026.04.01/archlinux-2026.04.01-x86_64.iso)
    cp "$TEST_FAKE_ISO_SOURCE" "$output"
    ;;
  *)
    printf 'unexpected url: %s\n' "$url" >&2
    exit 1
    ;;
esac
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

cat > "$BIN_DIR/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/bin/shasum -a 256 "$@"
EOF

chmod 0755 "$BIN_DIR/curl" "$BIN_DIR/mkarchiso" "$BIN_DIR/sudo" "$BIN_DIR/sha256sum"

TEST_DOWNLOAD_PAGE="$DOWNLOAD_PAGE"
TEST_SHA256SUMS="$CHECKSUMS_FILE"
TEST_FAKE_ISO_SOURCE="$FAKE_ISO_SOURCE"
TEST_LOG="$TMPDIR/mkarchiso.log"
TEST_OUT="$OUTDIR"
export TEST_DOWNLOAD_PAGE TEST_SHA256SUMS TEST_FAKE_ISO_SOURCE TEST_LOG TEST_OUT

PATH="$BIN_DIR:$PATH" \
  RELENG_SOURCE="$RELENG_SOURCE" \
  WORKDIR="$WORKDIR" \
  OUTDIR="$OUTDIR" \
  ARCHISO_CACHE_DIR="$CACHE_DIR" \
  MKARCHISO_BIN="$BIN_DIR/mkarchiso" \
  SUDO_BIN="$BIN_DIR/sudo" \
  CURL_BIN="$BIN_DIR/curl" \
  SHA256_BIN="$BIN_DIR/sha256sum" \
  bash "$TARGET_SCRIPT"

[[ -f "$CACHE_DIR/archlinux-2026.04.01-x86_64.iso" ]] || fail "arch iso not downloaded"
assert_file_contains "$TEST_LOG" "-v -o $OUTDIR $WORKDIR"

printf 'PASS: download official Arch ISO before build\n'
