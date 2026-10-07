#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
customization="$(awk '
  /^msg_info "Customizing / {keep=1}
  keep && /^STORAGE_TYPE=/ {exit}
  keep {print}
' "$ROOT/vm/fedora-vm.sh")"
[[ -n "$customization" ]] || {
  echo "Fedora customization block not found" >&2
  exit 1
}

msg_info() { :; }
msg_ok() { successes=$((successes + 1)); }
msg_warn() { warnings=$((warnings + 1)); }
_vm_customize() {
  calls=$((calls + 1))
  if [[ "$1" == "Fedora serial console" ]]; then
    [[ "$2" == image.qcow2 && "$3" == --run-command &&
      "$4" == "systemctl enable serial-getty@ttyS0.service" ]] || exit 1
  elif [[ "$1" == "Fedora SELinux relabel" ]]; then
    [[ "$2" == image.qcow2 && "$3" == --selinux-relabel ]] || exit 1
  else
    echo "Unexpected customization step: $1" >&2
    exit 1
  fi
  if [[ "$mode" == both || "$mode" == "$1" ]]; then
    _VM_PREPARE_FAILED+=("$1")
    msg_warn "$1"
  fi
}

for mode in none "Fedora serial console" "Fedora SELinux relabel" both; do
  FILE=Fedora.qcow2 WORK_FILE=image.qcow2
  calls=0 successes=0 warnings=0
  _VM_PREPARE_FAILED=("earlier preparation warning")
  eval "$customization"
  [[ "$calls" == 2 ]] || exit 1
  if [[ "$mode" == none ]]; then
    [[ "$successes" == 1 && "$warnings" == 0 ]] || exit 1
  else
    [[ "$successes" == 0 && "$warnings" -ge 2 ]] || exit 1
  fi
  printf 'PASS Fedora customization: %s\n' "$mode"
done
