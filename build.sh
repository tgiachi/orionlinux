#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RELENG_SOURCE=${RELENG_SOURCE:-/usr/share/archiso/configs/releng}
WORKDIR=${WORKDIR:-"$SCRIPT_DIR/work/orionlinux"}
OUTDIR=${OUTDIR:-"$SCRIPT_DIR/out"}
ARCHISO_CACHE_DIR=${ARCHISO_CACHE_DIR:-"$SCRIPT_DIR/cache/archlinux"}
PREPARE_SCRIPT="$SCRIPT_DIR/prepare-orionlinux-profile.sh"
CUSTOMREPO_SOURCE="$SCRIPT_DIR/customrepo"
MKARCHISO_BIN=${MKARCHISO_BIN:-mkarchiso}
SUDO_BIN=${SUDO_BIN:-sudo}
CURL_BIN=${CURL_BIN:-curl}
SHA256_BIN=${SHA256_BIN:-sha256sum}
ARCH_DOWNLOAD_PAGE_URL=${ARCH_DOWNLOAD_PAGE_URL:-https://archlinux.org/download/}
ARCH_DOWNLOAD_MIRROR_BASE_URL=${ARCH_DOWNLOAD_MIRROR_BASE_URL:-https://geo.mirror.pkgbuild.com/iso}

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

fetch_text() {
  "$CURL_BIN" -f -s -S -L "$1"
}

download_file() {
  local url=$1
  local output=$2

  "$CURL_BIN" -f -L --retry 3 --retry-delay 2 -o "$output" "$url"
}

file_sha256() {
  "$SHA256_BIN" "$1" | awk '{print $1}'
}

resolve_current_release() {
  local page=$1
  local release

  release=$(printf '%s\n' "$page" | sed -n 's#.*Current Release:</strong>[[:space:]]*\([0-9.][0-9.]*\).*#\1#p' | head -n 1)
  [[ -n "$release" ]] || die "could not resolve current Arch release from $ARCH_DOWNLOAD_PAGE_URL"
  printf '%s\n' "$release"
}

resolve_iso_checksum() {
  local release=$1
  local iso_name=$2
  local checksums
  local checksum

  checksums=$(fetch_text "https://archlinux.org/iso/$release/sha256sums.txt")
  checksum=$(printf '%s\n' "$checksums" | awk -v iso_name="$iso_name" '$2 == iso_name { print $1; exit }')
  [[ -n "$checksum" ]] || die "could not resolve checksum for $iso_name"
  printf '%s\n' "$checksum"
}

ensure_latest_archiso_cached() {
  local release_page
  local release
  local iso_name
  local iso_url
  local expected_sha
  local cached_iso
  local tmp_iso
  local actual_sha

  require_cmd "$CURL_BIN"
  require_cmd "$SHA256_BIN"

  release_page=$(fetch_text "$ARCH_DOWNLOAD_PAGE_URL")
  release=$(resolve_current_release "$release_page")
  iso_name="archlinux-${release}-x86_64.iso"
  iso_url="$ARCH_DOWNLOAD_MIRROR_BASE_URL/$release/$iso_name"
  expected_sha=$(resolve_iso_checksum "$release" "$iso_name")

  mkdir -p "$ARCHISO_CACHE_DIR"
  cached_iso="$ARCHISO_CACHE_DIR/$iso_name"

  if [[ -f "$cached_iso" ]]; then
    actual_sha=$(file_sha256 "$cached_iso")
    if [[ "$actual_sha" == "$expected_sha" ]]; then
      printf 'Using cached official Arch ISO: %s\n' "$cached_iso"
      return
    fi

    printf 'Checksum mismatch for cached Arch ISO, re-downloading: %s\n' "$cached_iso" >&2
    rm -f "$cached_iso"
  fi

  tmp_iso="$cached_iso.part"
  rm -f "$tmp_iso"
  printf 'Downloading latest official Arch ISO: %s\n' "$iso_url"
  download_file "$iso_url" "$tmp_iso"
  actual_sha=$(file_sha256 "$tmp_iso")
  [[ "$actual_sha" == "$expected_sha" ]] || die "checksum mismatch for downloaded Arch ISO: $iso_name"
  mv "$tmp_iso" "$cached_iso"
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
ensure_latest_archiso_cached

rm -rf "$WORKDIR"
mkdir -p "$(dirname "$WORKDIR")" "$OUTDIR"
cp -R "$RELENG_SOURCE" "$WORKDIR"

if [[ -d "$CUSTOMREPO_SOURCE" ]]; then
  validate_customrepo "$CUSTOMREPO_SOURCE"
  cp -R "$CUSTOMREPO_SOURCE" "$WORKDIR/customrepo"
fi

bash "$PREPARE_SCRIPT" "$WORKDIR"
run_privileged "$MKARCHISO_BIN" -v -o "$OUTDIR" "$WORKDIR"
