#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CORE="${CORE:-$ROOT/.core/pve/vm-core.func}"
VM_DIR="${VM_DIR:-$ROOT/vm}"
export CORE VM_DIR

fail() { echo "FAIL: $*" >&2; exit 1; }

if [[ "${1:-}" == "--case" ]]; then
  script="$2" mode="$3"
  COMMUNITY_SCRIPTS_CORE_DIR="$(cd -- "$(dirname -- "$CORE")/.." && pwd)"
  export COMMUNITY_SCRIPTS_CORE_DIR
  pveversion() { :; }
  source "$CORE"
  color
  formatting
  icons
  default_vars
  get_valid_nextid() { echo 100; }
  pct() { return 1; }
  qm() { return 1; }
  ip() {
    if [[ "$*" == *"-o link"* ]]; then
      printf '1: vmbr0: <UP>\n2: vmbr1: <UP>\n'
    fi
  }
  msg_warn() { echo "WARN: $*" >&2; }
  msg_error() { echo "ERROR: $*" >&2; }
  header_info() { :; }
  exit_script() { echo "Wizard cancelled" >&2; exit 130; }
  whiptail() {
    [[ "$mode" != cancel ]] || return 1
    local args=("$@") i
    for ((i = 0; i < ${#args[@]}; i++)); do
      case "${args[i]}" in
      --inputbox)
        printf '%s' "${args[i + 4]:-}" >&2
        return 0
        ;;
      --yesno) return 0 ;;
      --radiolist)
        for ((i = i + 1; i < ${#args[@]}; i++)); do
          if [[ "${args[i]}" == ON ]]; then
            printf '%s' "${args[i - 2]}" >&2
            return 0
          fi
        done
        return 2
        ;;
      esac
    done
    fail "Unexpected dialog: $*"
  }
  APP="$(basename "$script" .sh)"
  GEN_MAC="02:00:00:00:00:01" GEN_MAC_LAN="02:00:00:00:00:02"
  STABLE="16.0" BETA="16.1" DEV="17.0.dev1"
  USE_CLOUD_INIT="no" VM_UNATTENDED=0
  _CS_VM_PREFLIGHT_DONE=1
  OS_TYPE="" OS_VERSION="" OS_CODENAME="" OS_DISPLAY=""
  var_version="26.04" CLOUDINIT_REQUIRED=0
  while IFS= read -r fn; do
    definition="$(awk -v name="$fn" '
      $0 == "function " name "() {" {keep=1}
      keep {print}
      keep && /^}$/ {exit}
    ' "$script")"
    [[ -n "$definition" ]] || fail "Missing function $fn"
    eval "$definition"
  done < <(sed -n 's/^function \([a-z_]*\)() {.*/\1/p' "$script")
  declare -f default_settings >/dev/null || fail "$script lacks default_settings"
  declare -f advanced_settings >/dev/null || fail "$script lacks advanced_settings"
  if [[ "$script" == *pimox* ]]; then
    VM_ARCH=arm64
  else
    VM_ARCH=amd64
  fi
  case "$mode" in
  default) default_settings ;;
  advanced | cancel) advanced_settings ;;
  unattended)
    VM_UNATTENDED=1 VM_START=no VM_DISK_SIZE=96G
    vm_start_script "test"
    [[ "$START_VM:$DISK_SIZE" == no:96G ]] || fail "Unattended overrides lost"
    ;;
  *) fail "Unknown mode $mode" ;;
  esac
  for v in VMID DISK_SIZE HN CORE_COUNT RAM_SIZE BRG MAC START_VM METHOD; do
    [[ -n "${!v:-}" ]] || fail "$script $mode leaves $v unset"
  done
  [[ "$VMID" == 100 ]] || fail "VMID changed"
  [[ "$DISK_SIZE" =~ ^[1-9][0-9]*G$ ]] || fail "Invalid disk size"
  [[ "$START_VM" == yes || "$START_VM" == no ]] || fail "Invalid start setting"
  exit 0
fi

[[ -r "$CORE" ]] || fail "Core checkout missing: $CORE"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
checked=0
for script in "$VM_DIR"/*.sh; do
  [[ -f "$script" ]] || fail "No VM scripts found"
  for mode in default advanced unattended; do
    if bash "$0" --case "$script" "$mode" >"$TEST_DIR/output" 2>&1; then
      echo "PASS $(basename "$script") $mode"
    else
      cat "$TEST_DIR/output" >&2
      fail "$(basename "$script") $mode"
    fi
  done
  rc=0
  bash "$0" --case "$script" cancel >"$TEST_DIR/output" 2>&1 || rc=$?
  [[ "$rc" == 130 ]] || {
    cat "$TEST_DIR/output" >&2
    fail "$(basename "$script") cancellation returned $rc, expected 130"
  }
  grep -q 'vm_mark_created' "$script" || fail "$script lacks post-create protection"
  grep -Eq '^set -[A-Za-z]*E[A-Za-z]*' "$script" || fail "$script lacks ERR inheritance"
  echo "PASS $(basename "$script") cancellation and lifecycle guards"
  checked=$((checked + 1))
done
echo "All $checked VM scripts: default, advanced, unattended and cancellation checked."
