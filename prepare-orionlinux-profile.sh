#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/archiso-profile" >&2
  exit 1
fi

TARGET=$(cd "$1" && pwd)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

require_file() {
  local file=$1
  if [[ ! -f "$file" ]]; then
    echo "Missing required file: $file" >&2
    exit 1
  fi
}

copy_tree() {
  local src=$1
  local dst=$2

  mkdir -p "$dst"
  cp -R "$src"/. "$dst"/
}

sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

set_profile_var() {
  local file=$1
  local key=$2
  local value=$3

  if grep -q "^${key}=" "$file"; then
    sed_in_place "s#^${key}=.*#${key}='${value}'#" "$file"
  else
    printf "%s='%s'\n" "$key" "$value" >> "$file"
  fi
}

TARGET_PROFILE="$TARGET/profiledef.sh"
TARGET_ETC="$TARGET/airootfs/etc"
TARGET_ROOT_HOME="$TARGET/airootfs/root"
TARGET_PACKAGES="$TARGET/packages.x86_64"
TARGET_PACMAN_CONF="$TARGET/pacman.conf"
TARGET_LOCAL_BIN="$TARGET/airootfs/usr/local/bin"
TARGET_SHARE_DIR="$TARGET/airootfs/usr/local/share/orionlinux"
TARGET_REPO_DIR="$TARGET_SHARE_DIR/repo"
TARGET_ARCHINSTALL_DEFAULTS="$TARGET_SHARE_DIR/archinstall-defaults.json"
TARGET_CUSTOMIZE="$TARGET_ROOT_HOME/customize_airootfs.sh"

append_package_once() {
  local pkg=$1

  if ! grep -qx "$pkg" "$TARGET_PACKAGES"; then
    printf "%s\n" "$pkg" >> "$TARGET_PACKAGES"
  fi
}

set_repo_server() {
  local repo=$1
  local url=$2

  perl -0pi -e "s#\\[$repo\\]\\nInclude = /etc/pacman\\.d/mirrorlist#[$repo]\\nServer = $url#g" "$TARGET_PACMAN_CONF"
}

require_file "$TARGET_PROFILE"
require_file "$TARGET_PACKAGES"
require_file "$TARGET_PACMAN_CONF"
mkdir -p "$TARGET_ETC"
mkdir -p "$TARGET_ROOT_HOME"
mkdir -p "$TARGET_LOCAL_BIN"
mkdir -p "$TARGET_SHARE_DIR"
mkdir -p "$TARGET_REPO_DIR"

install -m 0644 "$SCRIPT_DIR/branding/issue" "$TARGET_ETC/issue"
install -m 0644 "$SCRIPT_DIR/branding/motd" "$TARGET_ETC/motd"
install -m 0644 "$SCRIPT_DIR/branding/os-release" "$TARGET_SHARE_DIR/live-os-release"
install -m 0644 "$SCRIPT_DIR/branding/issue" "$TARGET_SHARE_DIR/live-issue"
install -m 0644 "$SCRIPT_DIR/branding/motd" "$TARGET_SHARE_DIR/live-motd"
printf "orionlinux\n" > "$TARGET_ETC/hostname"

cat > "$TARGET_CUSTOMIZE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

install -m 0644 /usr/local/share/orionlinux/live-os-release /usr/lib/os-release
ln -sf ../usr/lib/os-release /etc/os-release
install -m 0644 /usr/local/share/orionlinux/live-issue /etc/issue
install -m 0644 /usr/local/share/orionlinux/live-motd /etc/motd
printf "orionlinux\n" > /etc/hostname
EOF
chmod 0755 "$TARGET_CUSTOMIZE"

set_profile_var "$TARGET_PROFILE" "iso_name" "orionlinux"
set_profile_var "$TARGET_PROFILE" "iso_label" "ORIONLINUX"
set_profile_var "$TARGET_PROFILE" "iso_publisher" "Orionlinux <https://arch.anaconda.net-freaks.com>"
set_profile_var "$TARGET_PROFILE" "iso_application" "Orionlinux"
set_profile_var "$TARGET_PROFILE" "install_dir" "orion"

if compgen -G "$TARGET/customrepo/x86_64/yay*.pkg.tar.*" > /dev/null; then
  if ! grep -q '^\[orionlocal\]$' "$TARGET_PACMAN_CONF"; then
    cp "$TARGET_PACMAN_CONF" "$TARGET_PACMAN_CONF.orig"
    {
      printf "[orionlocal]\n"
      printf "SigLevel = Optional TrustAll\n"
      printf 'Server = file://%s/customrepo/$arch\n\n' "$TARGET"
      cat "$TARGET_PACMAN_CONF.orig"
    } > "$TARGET_PACMAN_CONF"
    rm -f "$TARGET_PACMAN_CONF.orig"
  fi

  append_package_once "git"
  append_package_once "base-devel"
  append_package_once "yay-bin"

  rm -rf "$TARGET_REPO_DIR"
  mkdir -p "$TARGET_REPO_DIR"
  copy_tree "$TARGET/customrepo" "$TARGET_REPO_DIR"
fi

set_repo_server "core" "https://geo.mirror.pkgbuild.com/core/os/\\\$arch"
set_repo_server "extra" "https://geo.mirror.pkgbuild.com/extra/os/\\\$arch"

cat > "$TARGET_ARCHINSTALL_DEFAULTS" <<'EOF'
{
  "mirror_config": {
    "custom_repositories": [
      {
        "name": "orionlocal",
        "url": "file:///usr/local/share/orionlinux/repo/$arch",
        "sign_check": "Optional",
        "sign_option": "TrustAll"
      }
    ]
  },
  "packages": [
    "git",
    "base-devel",
    "sudo",
    "yay-bin"
  ],
  "custom_commands": [
    "bash -lc 'cat > /usr/lib/os-release <<\"EOT\"\nNAME=\"Orionlinux\"\nPRETTY_NAME=\"Orionlinux\"\nID=orionlinux\nID_LIKE=arch\nBUILD_ID=rolling\nANSI_COLOR=\"38;2;23;147;209\"\nHOME_URL=\"https://arch.anaconda.net-freaks.com/\"\nDOCUMENTATION_URL=\"https://wiki.archlinux.org/\"\nSUPPORT_URL=\"https://arch.anaconda.net-freaks.com/\"\nBUG_REPORT_URL=\"https://arch.anaconda.net-freaks.com/\"\nLOGO=orionlinux\nEOT'",
    "ln -sf ../usr/lib/os-release /etc/os-release",
    "bash -lc 'cat > /etc/issue <<\"EOT\"\nWelcome To Orionlinux \\\\r (\\\\l)\nEOT'",
    "bash -lc 'cat > /etc/motd <<\"EOT\"\nWelcome To Orionlinux\nThis system is not affiliated with the Arch Linux project.\nEOT'",
    "bash -lc 'python3 - <<\"PY\"\nfrom pathlib import Path\npath = Path(\"/etc/pacman.conf\")\nlines = path.read_text().splitlines()\nout = []\nskip = False\nfor line in lines:\n    stripped = line.strip()\n    if stripped == \"[orionlocal]\":\n        skip = True\n        continue\n    if skip and stripped.startswith(\"[\") and stripped.endswith(\"]\"):\n        skip = False\n    if not skip:\n        out.append(line)\npath.write_text(\"\\n\".join(out).rstrip() + \"\\n\")\nPY'"
  ]
}
EOF

cat > "$TARGET_LOCAL_BIN/archinstall" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

defaults=/usr/local/share/orionlinux/archinstall-defaults.json
use_defaults=1
prev_is_config=0

for arg in "$@"; do
  if [[ $prev_is_config -eq 1 ]]; then
    use_defaults=0
    prev_is_config=0
    continue
  fi

  case "$arg" in
    --config|--config-url)
      use_defaults=0
      prev_is_config=1
      ;;
    --config=*|--config-url=*)
      use_defaults=0
      ;;
  esac
done

if [[ $use_defaults -eq 1 ]]; then
  exec /usr/bin/archinstall --config "$defaults" "$@"
fi

exec /usr/bin/archinstall "$@"
EOF
chmod 0755 "$TARGET_LOCAL_BIN/archinstall"

cat > "$TARGET_LOCAL_BIN/orioninstall" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/archinstall "$@"
EOF
chmod 0755 "$TARGET_LOCAL_BIN/orioninstall"

while IFS= read -r -d '' file; do
  sed_in_place \
    -e 's/Arch Linux install medium/Orionlinux install medium/g' \
    -e 's/Arch Linux/Orionlinux/g' \
    -e 's/archlinux\.org\/download/arch.anaconda.net-freaks.com/g' \
    "$file"
done < <(
  find "$TARGET" -type f \
    \( -path "*/grub/grub.cfg" \
    -o -path "*/grub/loopback.cfg" \
    -o -path "*/syslinux/*.cfg" \
    -o -path "*/efiboot/loader/entries/*.conf" \) \
    -print0
)

echo "Orionlinux profile prepared in: $TARGET"
