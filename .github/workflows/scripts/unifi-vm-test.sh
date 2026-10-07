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

for fn in select_os get_image_url default_settings; do
  definition="$(extract_function "$fn")"
  [[ -n "$definition" ]] || fail "Function $fn not found"
  eval "$definition"
done

msg_info() { echo "INFO $*"; }
msg_ok() { echo "OK $*"; }
msg_warn() { echo "WARN $*"; }
msg_error() { echo "ERROR $*"; }
vm_apply_machine_type() { :; }
vm_arch_resolve() { echo "$1"; }
get_valid_nextid() { echo 104; }
vm_echo_default_settings() { :; }
vm_dialog() {
  [[ "$1:$2" == "radiolist:SELECT OS" ]] || fail "Unexpected dialog: $*"
  VM_DIALOG_RESULT=debian13
}
exit_script() { fail "Defaults entered a custom dialog"; }
GEN_MAC="02:11:22:33:44:55"
default_settings
[[ "$OS_TYPE:$var_os:$var_version:$DISK_SIZE:$CORE_COUNT:$RAM_SIZE" == debian:debian:13:32G:2:6144 ]] || fail "Changed VM defaults"
VM_OS_VERSION=ubuntu2404 default_settings
[[ "$OS_TYPE:$OS_VERSION:$var_os:$var_version" == ubuntu:24.04:ubuntu:24.04 ]] || fail "Ubuntu selection"
unset VM_OS_VERSION
select_os
[[ "$OS_TYPE:$OS_VERSION" == debian:13 ]] || fail "Interactive OS selection failed"
if (select_os unsupported) >"$TEST_DIR/output" 2>&1; then
  fail "Unsupported OS accepted"
fi
expect "$(cat "$TEST_DIR/output")" "Unsupported OS"
echo "PASS default settings and OS compatibility (4 cases)"

script_text="$(cat "$SCRIPT")"
expect "$script_text" "vm_require_tools curl jq virt-customize"
reject "$script_text" "apt-get install -y jq"
reject "$script_text" "qm importdisk"
reject "$script_text" "network-get-interfaces"
reject "$script_text" "post_update_to_api \"done\""
echo "PASS host-side helper contract checks"

prompt="$(awk '/^vm_start_script / {keep=1; next} /^post_to_api_vm$/ {exit} keep {print}' "$SCRIPT")"
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
setup_cloud_init() { :; }
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
firstboot_unit="$(awk '/^vm_firstboot_unit / {keep=1} keep {print} keep && /--cloud-init yes/ {exit}' "$SCRIPT")"
[[ -n "$firstboot" ]] || fail "First-boot installer script not found"
[[ -n "$firstboot_unit" ]] || fail "vm_firstboot_unit call not found"
expect "$firstboot" "#!/usr/bin/env bash"
expect "$firstboot" "set -Eeuo pipefail"
reject "$firstboot" "systemctl disable unifi-os-firstboot.service"
reject "$firstboot" "echo y |"
expect "$firstboot_unit" 'vm_firstboot_unit "$FILE" "unifi-os-firstboot" "$FIRSTBOOT_SCRIPT"'
expect "$firstboot_unit" "--after qemu-guest-agent.service"
expect "$firstboot_unit" "--requires-path /opt/unifi-os-server.bin"
expect "$firstboot_unit" "--cloud-init yes"

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
  [[ "$(head -n 1 "$EVENTS")" == "start qemu-guest-agent" ]] || fail "Agent starts before package work"
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
echo "PASS first-boot staging, agent recovery and package failure reporting (4 cases)"

expect "$script_text" 'vm_prepare_cloud_image "$FILE" "$HN"'
expect "$script_text" 'vm_customize "UniFi OS installer" "$FILE"'
expect "$script_text" 'vm_firstboot_unit "$FILE" "unifi-os-firstboot" "$FIRSTBOOT_SCRIPT"'
reject "$script_text" "virt-resize"
reject "$script_text" "virt-filesystems"
reject "$script_text" "expanded.qcow2"
reject "$script_text" "virt-customize -a"
expect "$script_text" 'vm_resize_disk'
creation="$(awk '/^qm create / {keep=1} /^vm_provision / {exit} keep {print}' "$SCRIPT")"
expect "$creation" $'vm_mark_created\nvm_import_disk "$VMID" "$FILE" "$STORAGE" "$DISK_IMPORT_FORMAT"'
expect "$creation" '${VM_IMPORTED_DISK}'
provision="$(awk '/^vm_provision / {keep=1} /^set_description$/ {print; exit} keep {print}' "$SCRIPT")"
expect "$provision" 'vm_provision "$VMID"'
expect "$provision" 'qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"'
reject "$provision" "--cipassword"
echo "PASS shared image customization, import, and provisioning"

qm() { return 13; }
vm_provision() { :; }
set_description() { :; }
export -f qm vm_provision set_description
rc=0
output="$(VMID=104 CLOUDINIT_SSH_KEYS="$TEST_DIR/test-key.pub" bash -c 'set -Eeuo pipefail; eval "$1"; echo UNEXPECTED_SUCCESS' -- "$provision" 2>&1)" || rc=$?
[[ "$rc" == 13 ]] || fail "SSH-key write error was suppressed"
reject "$output" "UNEXPECTED_SUCCESS"
echo "PASS SSH-key write failure stops provisioning"

completion="$(awk '/^VM_IP=""$/ {keep=1} keep {print}' "$SCRIPT")"
[[ -n "$completion" ]] || fail "Completion block not found"
STD="" TAB="" INFO="" GATEWAY="" BOLD="" GN="" CL="" YW="" HOLD=""
VMID=104 MAC="$GEN_MAC" CLOUDINIT_USER=admin CLOUDINIT_CRED_FILE="/tmp/test-credentials"
UOS_VERSION=5.1.42 OS_DISPLAY="Debian 13 (Trixie)" DISK_SIZE=32G CORE_COUNT=2 RAM_SIZE=6144 HN=unifi-server-os
VM_FIRSTBOOT_MARKER="/var/lib/community-scripts/unifi-os-firstboot.done"
vm_start_vm() { echo "start $*" >>"$EVENTS"; }
vm_wait_for_ip() {
  echo "ip $*" >>"$EVENTS"
  [[ "$IP_MODE" != noip ]] || return 1
  VM_IP=192.168.1.104
}
vm_guest_exec() {
  echo "guest $*" >>"$EVENTS"
  [[ "$MARKER_MODE" == done ]]
}
vm_wait_http() {
  echo "http $*" >>"$EVENTS"
  [[ "$*" == *"https://192.168.1.104:11443 300 --insecure"* ]] || fail "Readiness URL/options changed"
  [[ "$READY_MODE" == ready ]]
}
vm_print_summary() {
  echo "summary"
  for item in "$@"; do echo "summary $item"; done
}
vm_next_steps() {
  echo "next"
  for step in "$@"; do echo "step $step"; done
}
vm_finish() { echo "finish ${1:-}"; }
for scenario in ready pending marker-only noip stopped; do
  START_VM=yes IP_MODE=address MARKER_MODE=done READY_MODE=ready
  case "$scenario" in
  pending) MARKER_MODE=pending READY_MODE=pending ;;
  marker-only) READY_MODE=pending ;;
  noip) IP_MODE=noip MARKER_MODE=pending READY_MODE=pending ;;
  stopped) START_VM=no MARKER_MODE=pending READY_MODE=pending ;;
  esac
  : >"$EVENTS"
  output="$(
    set -e
    eval "$completion"
  )"
  expect "$output" "summary Console Login=admin"
  expect "$output" "summary Cloud-Init Credentials=/tmp/test-credentials"
  expect "$output" "summary Web Interface=https://"
  if [[ "$scenario" == ready ]]; then
    expect "$output" "OK UniFi OS is up"
    expect "$output" "finish UniFi OS Server VM is ready."
  elif [[ "$scenario" == marker-only ]]; then
    expect "$output" "web readiness was not confirmed yet"
    expect "$output" "journalctl -u unifi-os-firstboot.service"
  elif [[ "$scenario" == stopped ]]; then
    expect "$output" "Start VM 104"
    expect "$output" "installation continues in the VM on first boot"
    ! grep -q '^start \|^ip \|^guest \|^http ' "$EVENTS" || fail "Stopped VM was queried"
  else
    expect "$output" "WARN UniFi OS"
    expect "$output" "installation continues in the VM on first boot"
    if [[ "$scenario" == noip ]]; then
      ! grep -q '^http ' "$EVENTS" || fail "Readiness queried without usable IP"
    fi
  fi
done
echo "PASS management IP, marker, HTTP readiness and completion messaging (5 cases)"

jq -e '.interface_port == 11443 and .install_methods[0].resources.ram == 6144 and (.notes | length) > 0' \
  "$ROOT/json/unifi-os-server-vm.json" >/dev/null
jq -e '.install_methods[0].resources.cpu == 2 and .install_methods[0].resources.ram == 2048 and .install_methods[0].resources.hdd == 7' \
  "$ROOT/json/ubuntu-vm.json" >/dev/null
echo "PASS VM catalogs match provisioning defaults"
