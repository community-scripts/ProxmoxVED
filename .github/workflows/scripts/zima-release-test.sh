#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${SCRIPT:-$ROOT/vm/zimaos-vm.sh}"
selection="$(awk '/^msg_info "Retrieving the URL for the ZimaOS installer"$/ {keep=1} /^msg_info "Creating a ZimaOS VM"$/ {exit} keep {print}' "$SCRIPT")"
[[ -n "$selection" ]] || {
  echo "ZimaOS release block not found" >&2
  exit 1
}
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
EVENTS="$TEST_DIR/events"
HN=zimaos CL="" BL="" MINIMUM_SIZE=$((1024 * 1024 * 1024))
ISO_SIZE=1739614208
msg_info() { echo "INFO $*"; }
msg_ok() { echo "OK $*"; }
msg_warn() { echo "WARN $*"; }
msg_error() { echo "ERROR $*"; }
vm_select_iso_storage() {
  printf 'selected %s\n' "$1" >>"$EVENTS"
  ISO_PATH="$TEST_DIR/$1"
}
vm_fetch_image() {
  [[ "$1" == *"/zimaos-x86_64-${VERSION}_installer.iso" && "$2" == "$ISO_PATH" ]] ||
    {
      echo "Wrong ISO URL/path" >&2
      exit 1
    }
  [[ "$3:$4" == "--cache:--min-bytes" ]] || exit 1
  ((MINIMUM_SIZE <= $5 && $5 <= ISO_SIZE)) || {
    echo "Valid official ISO rejected by size threshold" >&2
    exit 1
  }
  printf 'downloaded %s\n' "$1" >>"$EVENTS"
}
curl() {
  [[ "$*" == *"https://api.github.com/repos/IceWhaleTech/ZimaOS/releases/latest"* ]] || exit 1
  [[ "$MODE" != api-error ]] || return 22
  local tag="$VERSION" iso="zimaos-x86_64-${VERSION}_installer.iso"
  [[ "$MODE" != no-tag ]] || tag=""
  [[ "$MODE" != no-iso ]] || iso="not-an-installer.txt"
  printf '{"tag_name":"%s","prerelease":false,"assets":[{"browser_download_url":"https://github.com/IceWhaleTech/ZimaOS/releases/download/%s/zimaos-x86_64-%s.raucb"},{"browser_download_url":"https://github.com/IceWhaleTech/ZimaOS/releases/download/%s/zimaos-x86_64-%s_installer.img"},{"browser_download_url":"https://github.com/IceWhaleTech/ZimaOS/releases/download/%s/%s"}]}\n' \
    "$tag" "$VERSION" "$VERSION" "$VERSION" "$VERSION" "$VERSION" "$iso"
}
for scenario in beta stable api-error no-tag no-iso; do
  VERSION=1.8.0-beta2 MODE="$scenario"
  [[ "$scenario" != stable ]] || VERSION=1.7.1
  : >"$EVENTS"
  rc=0
  output="$(
    set -e
    eval "$selection"
  )" || rc=$?
  if [[ "$scenario" == beta || "$scenario" == stable ]]; then
    [[ "$rc" == 0 && "$output" == *"ZimaOS $VERSION"* ]] ||
      {
        printf '%s\n' "$output" >&2
        exit 1
      }
    [[ "$(grep -c '^downloaded ' "$EVENTS")" == 1 ]] || exit 1
    [[ "$(grep -c '^selected ' "$EVENTS")" == 1 ]] || exit 1
  else
    [[ "$rc" != 0 && "$output" == *"ERROR"* ]] ||
      {
        echo "Missing release data reported success" >&2
        exit 1
      }
    ! grep -q '^downloaded\|^selected' "$EVENTS" || exit 1
  fi
  printf 'PASS ZimaOS release selection: %s\n' "$scenario"
done
