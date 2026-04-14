#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RELENG_SOURCE=${RELENG_SOURCE:-/usr/share/archiso/configs/releng}
WORKDIR=${WORKDIR:-"$SCRIPT_DIR/work/orionlinux"}
OUTDIR=${OUTDIR:-"$SCRIPT_DIR/out"}
PREPARE_SCRIPT="$SCRIPT_DIR/prepare-orionlinux-profile.sh"
CUSTOMREPO_SOURCE="$SCRIPT_DIR/customrepo"
MKARCHISO_BIN=${MKARCHISO_BIN:-mkarchiso}
SUDO_BIN=${SUDO_BIN:-sudo}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_dir() {
  local dir=$1
  [[ -d "$dir" ]] || die "missing required directory: $dir"
}

require_file() {
  local file=$1
  [[ -f "$file" ]] || die "missing required file: $file"
}

require_cmd() {
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
}

run_privileged() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
    return
  fi

  require_cmd "$SUDO_BIN"
  "$SUDO_BIN" "$@"
}

validate_customrepo() {
  local repo_dir=$1

  [[ -d "$repo_dir/x86_64" ]] || die "customrepo exists but customrepo/x86_64 is missing"
  compgen -G "$repo_dir/x86_64/yay*.pkg.tar.*" >/dev/null || \
    die "customrepo/x86_64 must contain a yay package"
  [[ -f "$repo_dir/x86_64/orionlocal.db.tar.gz" ]] || \
    die "customrepo/x86_64 must contain orionlocal.db.tar.gz"
}

require_dir "$RELENG_SOURCE"
require_file "$PREPARE_SCRIPT"
require_cmd "$MKARCHISO_BIN"

rm -rf "$WORKDIR"
mkdir -p "$(dirname "$WORKDIR")" "$OUTDIR"
cp -R "$RELENG_SOURCE" "$WORKDIR"

if [[ -d "$CUSTOMREPO_SOURCE" ]]; then
  validate_customrepo "$CUSTOMREPO_SOURCE"
  cp -R "$CUSTOMREPO_SOURCE" "$WORKDIR/customrepo"
fi

bash "$PREPARE_SCRIPT" "$WORKDIR"
run_privileged "$MKARCHISO_BIN" -v -o "$OUTDIR" "$WORKDIR"
