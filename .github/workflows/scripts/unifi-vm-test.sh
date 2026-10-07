#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${SCRIPT:-$ROOT/vm/unifi-os-server-vm.sh}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
EVENTS="$TEST_DIR/events"
TEMP_DIR="$TEST_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
expect() { [[ "$1" == *"$2"* ]] || fail "Missing: $2"; }
reject() { [[ "$1" != *"$2"* ]] || fail "Unexpected: $2"; }
extract_function() {
  awk -v name="$1" '$0 == "function " name "() {" {keep=1} keep {print} keep && /^}$/ {exit}' "$SCRIPT"
}
for fn in select_os default_settings; do
  definition="$(extract_function "$fn")"
  [[ -n "$definition" ]] || fail "Function $fn not found"
  eval "$definition"
done

msg_info() { echo "INFO $*"; }
msg_ok() { echo "OK $*"; }
msg_warn() { echo "WARN $*"; }
msg_error() { echo "ERROR $*"; }
vm_apply_machine_type() { :; }
get_valid_nextid() { echo 104; }
vm_echo_default_settings() { :; }
whiptail() { fail "Defaults must not show custom OS/password/key dialogs"; }
exit_script() { fail "Defaults entered a custom dialog"; }
GEN_MAC="02:11:22:33:44:55"
default_settings
[[ "$OS_TYPE:$DISK_SIZE:$CORE_COUNT:$RAM_SIZE" == debian:32G:2:6144 ]] || fail "Changed VM defaults"
VM_OS_VERSION=ubuntu2404 default_settings
[[ "$OS_TYPE:$OS_VERSION" == ubuntu:24.04 ]] || fail "Ubuntu selection"
if (select_os unsupported) >"$TEST_DIR/output" 2>&1; then
  fail "Unsupported OS accepted"
fi
expect "$(cat "$TEST_DIR/output")" "Unsupported OS"
echo "PASS default settings and OS compatibility (3 cases)"

prompt="$(awk '/^vm_preflight$/ {keep=1; next} /^vm_start_script / {exit} keep {print}' "$SCRIPT")"
[[ -n "$prompt" ]] || fail "Shared Cloud-Init prompt block not found"
vm_prompt_cloud_init() {
  [[ "$1" == root ]] || fail "Default Cloud-Init user"
  USE_CLOUD_INIT="${TEST_CI:-yes}"
}
setup_cloud_init() { :; }
_ci_ssh_extract_keys_from_file() { grep -E '^(ssh-|ecdsa-sha2-)' "$1" || true; }
VM_UNATTENDED=1 VM_ROOT_PASSWORD="test-only-password"
eval "$prompt"
[[ "$CLOUDINIT_PASSWORD" == "$VM_ROOT_PASSWORD" ]] || fail "Legacy unattended password lost"
CLOUDINIT_PASSWORD="standard-setting-wins"
eval "$prompt"
[[ "$CLOUDINIT_PASSWORD" == standard-setting-wins ]] || fail "Standard password overwritten"
unset CLOUDINIT_PASSWORD VM_ROOT_PASSWORD
eval "$prompt"
[[ -z "$CLOUDINIT_PASSWORD" ]] || fail "Blank password must reach shared generation"
if (
  TEST_CI=no
  eval "$prompt"
) >"$TEST_DIR/output" 2>&1; then
  fail "Cloud-Init disabled despite being required"
fi
expect "$(cat "$TEST_DIR/output")" "requires Cloud-Init"
if (
  unset -f setup_cloud_init
  eval "$prompt"
) >"$TEST_DIR/output" 2>&1; then
  fail "Missing required helper accepted"
fi
expect "$(cat "$TEST_DIR/output")" "helpers are unavailable"
ssh-keygen -q -t ed25519 -N "" -f "$TEST_DIR/test-key"
for key in "$TEST_DIR/test-key.pub" "$(cat "$TEST_DIR/test-key.pub")"; do
  unset CLOUDINIT_SSH_KEYS
  VM_SSH_KEYS="$key"
  eval "$prompt"
  cmp "$CLOUDINIT_SSH_KEYS" "$TEST_DIR/test-key.pub" || fail "Legacy SSH keys changed"
done
if (
  unset CLOUDINIT_SSH_KEYS
  VM_SSH_KEYS="not-a-public-key"
  eval "$prompt"
) >"$TEST_DIR/output" 2>&1; then
  fail "Invalid SSH key accepted"
fi
expect "$(cat "$TEST_DIR/output")" "valid SSH public keys"
unset VM_SSH_KEYS CLOUDINIT_SSH_KEYS
echo "PASS shared Cloud-Init and unattended compatibility (8 cases)"

firstboot="$(awk "/^cat >.*<<'FBEOF'$/ {keep=1; next} /^FBEOF$/ {exit} keep {print}" "$SCRIPT")"
unit="$(awk "/^cat >.*<<'SVCEOF'$/ {keep=1; next} /^SVCEOF$/ {exit} keep {print}" "$SCRIPT")"
expect "$unit" "After=network-online.target cloud-final.service qemu-guest-agent.service"
expect "$unit" "Wants=network-online.target cloud-final.service qemu-guest-agent.service"
expect "$unit" "WantedBy=cloud-init.target"
reject "$unit" "WantedBy=multi-user.target"
reject "$firstboot" "echo y |"
expect "$firstboot" "set -euo pipefail"
pre_packages="$(awk '/^# Setup swap / {exit} {print}' <<<"$firstboot" |
  sed '/^LOG=/d; /^exec > /d')"
[[ -n "$pre_packages" ]] || fail "First-boot package block not found"
systemctl() {
  echo "$*" >>"$EVENTS"
  [[ "$*" != "start qemu-guest-agent" || "${APT_MODE:-ok}" != agent-recovery ]]
}
timedatectl() { [[ "$1" != show ]] || echo yes; }
sleep() { :; }
apt-get() {
  echo "apt $*" >>"$EVENTS"
  if [[ "$1" == update && "${APT_MODE:-ok}" == update-fails ]]; then
    return 1
  fi
  if [[ "$1" == install && "${APT_MODE:-ok}" == install-fails ]]; then
    return 1
  fi
}
for APT_MODE in ok agent-recovery update-fails install-fails; do
  : >"$EVENTS"
  rc=0
  (
    set -e
    eval "$pre_packages"
  ) >"$TEST_DIR/output" 2>&1 || rc=$?
  [[ "$(head -n 1 "$EVENTS")" == "start qemu-guest-agent" ]] || fail "Agent starts after package work"
  if [[ "$APT_MODE" == ok || "$APT_MODE" == agent-recovery ]]; then
    [[ "$rc" == 0 ]] || fail "Successful package setup failed"
    if [[ "$APT_MODE" == agent-recovery ]]; then
      expect "$(cat "$TEST_DIR/output")" "Preinstalled guest agent could not start"
      expect "$(cat "$EVENTS")" "enable --now qemu-guest-agent"
    fi
  else
    [[ "$rc" != 0 ]] || fail "Failed package setup reported success"
    expect "$(cat "$TEST_DIR/output")" "failed after 3 attempts"
    [[ "$(grep -c "^apt ${APT_MODE%-fails}" "$EVENTS")" == 3 ]] || fail "Retry count must be 3"
    if [[ "$APT_MODE" == update-fails ]]; then
      ! grep -q "^apt install" "$EVENTS" || fail "Continued after update failure"
    fi
  fi
done
echo "PASS first-boot ordering, agent recovery and package failure reporting (4 cases)"

script_text="$(cat "$SCRIPT")"
reject "$script_text" "virt-resize"
reject "$script_text" "virt-filesystems"
reject "$script_text" "expanded.qcow2"
expect "$script_text" 'vm_resize_disk'
expect "$script_text" 'vm_prepare_cloud_image "$FILE" "$HN"'
[[ "$(grep -c '^virt-customize ' "$SCRIPT")" == 1 ]] || fail "Additional application staging appliance"
provision="$(awk '/^vm_mark_created$/ {keep=1} /^set_description$/ {exit} keep {print}' "$SCRIPT")"
expect "$provision" $'vm_mark_created\nvm_provision "$VMID"'
expect "$provision" 'qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"'
reject "$provision" "--cipassword"
echo "PASS no offline expansion, one staging appliance, shared provisioning"

vm_mark_created() { echo "VM marked created"; }
vm_provision() { :; }
qm() { return 13; }
export -f vm_mark_created vm_provision qm
rc=0
output="$(VMID="$VMID" CLOUDINIT_SSH_KEYS="$TEST_DIR/test-key.pub" bash -c 'set -Eeuo pipefail; eval "$1"; echo UNEXPECTED_SUCCESS' -- "$provision" 2>&1)" || rc=$?
[[ "$rc" == 13 ]] || fail "SSH-key write error was suppressed"
expect "$output" "VM marked created"
reject "$output" "UNEXPECTED_SUCCESS"
echo "PASS SSH-key write failure stops provisioning"

completion="$(awk '/^VM_IP=""$/ {keep=1} keep {print}' "$SCRIPT")"
[[ -n "$completion" ]] || fail "Completion block not found"
STD="" TAB="" INFO="" GATEWAY="" BOLD="" GN="" CL="" YW="" HOLD=""
VMID=104 MAC="$GEN_MAC" CLOUDINIT_USER=admin CLOUDINIT_CRED_FILE="/tmp/test-credentials"
get_vm_ip() {
  echo "ip $*" >>"$EVENTS"
  [[ "$IP_MODE" != timeout ]] || return 1
  echo "172.17.0.1"
}
qm() {
  echo "qm $*" >>"$EVENTS"
  if [[ "$1" == guest ]]; then
    if [[ "$IP_MODE" == timeout ]]; then
      echo "QEMU guest agent is not running" >&2
      return 1
    fi
    local address=192.168.1.104
    [[ "$IP_MODE" != linklocal ]] || address=169.254.1.2
    [[ "$IP_MODE" != malformed ]] || {
      echo '{'
      return
    }
    printf '[{"hardware-address":"aa:bb:cc:dd:ee:ff","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"172.17.0.1"}]},{"hardware-address":"%s","ip-addresses":[{"ip-address-type":"ipv6","ip-address":"::1"},{"ip-address-type":"ipv4","ip-address":"%s"}]}]\n' "$MAC" "$address"
  fi
}
curl() {
  echo "curl $*" >>"$EVENTS"
  [[ "$*" == *"-fsSk"* ]] || fail "Readiness must reject HTTP errors"
  [[ "$READY_MODE" == ready ]]
}
post_update_to_api() { echo "telemetry $*" >>"$EVENTS"; }
for scenario in ready pending timeout linklocal malformed stopped; do
  START_VM=yes IP_MODE=address READY_MODE=ready
  case "$scenario" in
  pending) READY_MODE=pending ;;
  timeout | linklocal | malformed) IP_MODE="$scenario" ;;
  stopped) START_VM=no ;;
  esac
  : >"$EVENTS"
  output="$(
    set -e
    eval "$completion"
  )"
  expect "$output" "Console login: admin"
  expect "$output" "Cloud-Init credentials: /tmp/test-credentials"
  [[ "$(grep -c '^telemetry done none$' "$EVENTS")" == 1 ]] || fail "Completion telemetry count"
  if [[ "$scenario" == ready || "$scenario" == pending ]]; then
    expect "$output" "VM IP: 192.168.1.104"
    reject "$output" "VM IP: 172.17.0.1"
    if [[ "$scenario" == ready ]]; then
      expect "$output" "OK UniFi OS is up"
    else
      expect "$output" "WARN UniFi OS is not ready"
      reject "$output" "OK UniFi OS is up"
      [[ "$(grep -c '^curl ' "$EVENTS")" == 60 ]] || fail "Readiness poll count"
    fi
  elif [[ "$scenario" == stopped ]]; then
    expect "$output" "Start VM 104"
    ! grep -q '^qm\|^ip\|^curl' "$EVENTS" || fail "Stopped VM was queried"
  else
    expect "$output" "WARN"
    reject "$output" "OK Guest agent responding"
    ! grep -q '^curl ' "$EVENTS" || fail "Readiness queried without usable IP"
    expect "$output" "journalctl -u cloud-final -u unifi-os-firstboot.service"
  fi
done
echo "PASS management IP selection, readiness warnings and stopped VM (6 cases)"

jq -e '.interface_port == 11443 and .install_methods[0].resources.ram == 6144 and (.notes | length) > 0' \
  "$ROOT/json/unifi-os-server-vm.json" >/dev/null
echo "PASS UniFi catalog matches provisioning defaults"
