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
HN=zimaos CL="" BL=""
MINIMUM_SIZE=$((1024 * 1024 * 1024))
SHA256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
msg_info() { echo "INFO $*"; }
msg_ok() { echo "OK $*"; }
msg_warn() { echo "WARN $*"; }
msg_error() { echo "ERROR $*"; }
vm_release_asset() {
  [[ "$1" == github && "$2" == IceWhaleTech/ZimaOS && "$3" == 'zimaos-x86_64-.*_installer\.iso$' ]] || {
    echo "Wrong release lookup arguments: $*" >&2
    exit 1
  }
  [[ $# -eq 3 ]] || {
    echo "ZimaOS should use the latest release lookup without an explicit tag" >&2
    exit 1
  }
  case "$MODE" in
  beta | stable)
    local asset="zimaos-x86_64-${VERSION}_installer.iso"
    [[ "$asset" =~ $3 ]] || {
      echo "Release regex does not match $asset" >&2
      exit 1
    }
    VM_RELEASE_TAG="$VERSION"
    VM_RELEASE_VERSION="$VERSION"
    VM_RELEASE_ASSET="$asset"
    VM_RELEASE_URL="https://github.com/IceWhaleTech/ZimaOS/releases/download/${VERSION}/${asset}"
    VM_RELEASE_SHA256="$SHA256"
    ;;
  release-error)
    msg_error "Could not read the latest release of IceWhaleTech/ZimaOS"
    return 1
    ;;
  no-asset)
    msg_error "IceWhaleTech/ZimaOS ${VERSION} has no asset matching $3"
    return 1
    ;;
  *)
    echo "Unknown scenario: $MODE" >&2
    exit 1
    ;;
  esac
}
vm_select_iso_storage() {
  printf 'selected %s\n' "$1" >>"$EVENTS"
  ISO_PATH="$TEST_DIR/$1"
}
vm_fetch_image() {
  local url="$1"
  [[ "$url" == "https://github.com/IceWhaleTech/ZimaOS/releases/download/${VERSION}/zimaos-x86_64-${VERSION}_installer.iso" && "$2" == "$ISO_PATH" ]] || {
    echo "Wrong ISO URL/path" >&2
    exit 1
  }
  shift 2
  local cache=0 min_bytes="" sha256=""
  while (($#)); do
    case "$1" in
    --cache)
      cache=1
      shift
      ;;
    --min-bytes)
      min_bytes="$2"
      shift 2
      ;;
    --sha256)
      sha256="$2"
      shift 2
      ;;
    *)
      echo "Unexpected vm_fetch_image argument: $1" >&2
      exit 1
      ;;
    esac
  done
  ((cache == 1)) || {
    echo "Missing --cache" >&2
    exit 1
  }
  [[ "$min_bytes" == "$MINIMUM_SIZE" ]] || {
    echo "Wrong min-bytes threshold: $min_bytes" >&2
    exit 1
  }
  [[ "$sha256" == "$SHA256" ]] || {
    echo "Wrong sha256 argument: $sha256" >&2
    exit 1
  }
  printf 'downloaded %s\n' "$url" >>"$EVENTS"
}
curl() {
  echo "The harmonized ZimaOS release block should not call curl directly: $*" >&2
  exit 1
}
for scenario in beta stable release-error no-asset; do
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
