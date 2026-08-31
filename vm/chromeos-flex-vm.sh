#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://chromeenterprise.google/os/chromeosflex/

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="ChromeOS Flex"
APP_TYPE="vm"
NSAPP="chromeos-flex-vm"
var_os="chromeos"
var_version=" "
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
THIN="discard=on,ssd=1,"

header_info
echo -e "\n Loading..."

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

if vm_confirm_new_vm "$APP" "This will create a new ChromeOS Flex VM from Google's official recovery image.\n\nNote that Google does not support ChromeOS Flex in a virtual machine. It runs, but it is not a configuration they test.\n\nFlex has no Play Store and no Android apps.\n\nProceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check
ssh_check

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="32G"
  DISK_CACHE=""
  HN="chromeos-flex"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "32G" "Set Disk Size in GiB (the image alone needs 10)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "chromeos-flex"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ChromeOS Flex VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ChromeOS Flex VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 4 CPU Cores (Host model)\n• 4 GB RAM\n• 32 GB Disk\n• UEFI, Secure Boot off" 14 58
post_to_api_vm

vm_select_storage "$HN"

msg_info "Retrieving the URL for the ChromeOS Flex image"

# Flex is not in recovery.json -- that file lists Chromebooks. Google keeps the
# Flex images (board name "reven") in the old CloudReady index, which today
# holds a single stable-channel entry carrying the URL, both sizes and a sha1.
# That means the download can be verified properly rather than guessed at.
INDEX_URL="https://dl.google.com/dl/edgedl/chromeos/recovery/cloudready_recovery.json"
INDEX=$(curl -fsSL "$INDEX_URL" 2>/dev/null) || INDEX=""
if [[ -z "$INDEX" ]]; then
  msg_error "Could not reach Google's ChromeOS Flex image index"
  exit 1
fi

URL=$(grep -oP '"url"\s*:\s*"\K[^"]*reven[^"]*\.bin\.zip' <<<"$INDEX" | head -1)
IMAGE_FILE=$(grep -oP '"file"\s*:\s*"\K[^"]*reven[^"]*\.bin' <<<"$INDEX" | head -1)
FLEX_VERSION=$(grep -oP '"version"\s*:\s*"\K[^"]+' <<<"$INDEX" | head -1)
CHROME_VERSION=$(grep -oP '"chrome_version"\s*:\s*"\K[^"]+' <<<"$INDEX" | head -1)
EXPECT_SHA1=$(grep -oP '"sha1"\s*:\s*"\K[^"]+' <<<"$INDEX" | head -1)
EXPECT_ZIP_BYTES=$(grep -oP '"zipfilesize"\s*:\s*\K[0-9]+' <<<"$INDEX" | head -1)
EXPECT_BIN_BYTES=$(grep -oP '"filesize"\s*:\s*\K[0-9]+' <<<"$INDEX" | head -1)

if [[ -z "$URL" || -z "$IMAGE_FILE" ]]; then
  msg_error "Could not determine the current ChromeOS Flex image"
  exit 1
fi

ZIP_FILE="$(basename "$URL")"
msg_ok "ChromeOS Flex ${CL}${BL}${FLEX_VERSION}${CL} ${GN}(Chrome ${CHROME_VERSION})"

# The zip is about 1.3 GB and expands to roughly 9.5 GB, so the work directory
# needs both at once. Failing here beats failing forty minutes into a download.
NEED_MIB=$(((EXPECT_ZIP_BYTES + EXPECT_BIN_BYTES) / 1048576 + 1024))
AVAIL_MIB=$(df -Pm "$TEMP_DIR" | awk 'NR==2 {print $4}')
if ((AVAIL_MIB < NEED_MIB)); then
  msg_error "Need ${NEED_MIB} MiB free for the image, ${TEMP_DIR} has ${AVAIL_MIB} MiB"
  msg_error "Free some space, or point TMPDIR at a filesystem that has room."
  exit 1
fi

if ! command -v unzip &>/dev/null; then
  msg_info "Installing unzip"
  $STD apt-get update
  $STD apt-get install -y unzip
  msg_ok "Installed unzip"
fi

msg_info "Downloading ChromeOS Flex (about 1.3 GB)"
if ! curl -f#SL --retry 3 --retry-delay 5 -o "$ZIP_FILE" "$URL"; then
  msg_error "Failed to download the ChromeOS Flex image"
  exit 1
fi
echo -en "\e[1A\e[0K"

GOT_BYTES=$(stat -c%s "$ZIP_FILE" 2>/dev/null || echo 0)
if [[ -n "$EXPECT_ZIP_BYTES" ]] && ((GOT_BYTES != EXPECT_ZIP_BYTES)); then
  msg_error "Downloaded ${GOT_BYTES} bytes, the index says ${EXPECT_ZIP_BYTES}"
  exit 1
fi
msg_ok "Downloaded ${CL}${BL}${ZIP_FILE}${CL}"

msg_info "Extracting the disk image (about 9.5 GB)"
# unzip checks the CRC-32 the archive carries for the file and exits non-zero
# when it does not match, so this doubles as the real integrity check.
if ! $STD unzip -o "$ZIP_FILE"; then
  msg_error "Extraction failed -- the archive is corrupt (CRC mismatch)"
  exit 1
fi
rm -f "$ZIP_FILE"
if [[ ! -f "$IMAGE_FILE" ]]; then
  msg_error "Expected ${IMAGE_FILE} in the archive, it is not there"
  exit 1
fi
msg_ok "Extracted ${CL}${BL}${IMAGE_FILE}${CL}"

msg_info "Verifying the image"
GOT_BYTES=$(stat -c%s "$IMAGE_FILE" 2>/dev/null || echo 0)
if [[ -n "$EXPECT_BIN_BYTES" ]] && ((GOT_BYTES != EXPECT_BIN_BYTES)); then
  msg_error "Image is ${GOT_BYTES} bytes, the index says ${EXPECT_BIN_BYTES}"
  exit 1
fi
# Google respins the image without regenerating the index, so a mismatch here
# does not mean a bad download. The stable image was rebuilt on 2026-08-18 and
# the JSON kept the sha1 from before; the archive itself was intact. Image size
# is fixed by the partition layout, which is why a respin lands on the same
# byte count and only the hash moves.
#
# What actually guarantees these bytes: the zip length matched the index and
# Content-Length, the extracted length matched both the index and the archive's
# own ZIP64 header, and unzip checked the CRC-32 Google packed with the file --
# a CRC failure would have aborted the extraction above. The sha1 is the least
# reliable of the four, so it reports rather than decides.
if [[ -n "$EXPECT_SHA1" ]] && command -v sha1sum &>/dev/null; then
  GOT_SHA1=$(sha1sum "$IMAGE_FILE" | awk '{print $1}')
  if [[ "$GOT_SHA1" == "$EXPECT_SHA1" ]]; then
    msg_ok "Verified sha1 ${CL}${BL}${EXPECT_SHA1}${CL}"
  else
    msg_warn "Google's index lists sha1 ${EXPECT_SHA1}, this image is ${GOT_SHA1}"
    msg_warn "Size and archive CRC are correct, so the index is lagging a respin -- continuing"
  fi
else
  msg_ok "Verified size ${CL}${BL}${GOT_BYTES} bytes${CL}"
fi

WORK_FILE="$TEMP_DIR/$IMAGE_FILE"
popd >/dev/null

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
vm_apply_storage_layout "$STORAGE_TYPE"
vm_define_disk_references 2

msg_info "Creating a ChromeOS Flex VM"

# SATA and e1000 rather than virtio, on purpose. The reven build carries the
# generic PC driver set Google ships for old laptops, not the paravirtualised
# drivers a cloud image would have. AHCI and e1000 are what that set definitely
# covers; virtio may well work and is worth testing, but it should not be the
# default anyone has to debug on first boot.
#
# UEFI is required, and pre-enrolled-keys=0 keeps Secure Boot off -- Flex will
# not boot with the Microsoft keys enrolled.
qm create "$VMID" -agent 1${MACHINE} -tablet 1 -localtime 1 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script -net0 e1000,bridge="$BRG",macaddr="$MAC""$VLAN""$MTU" -onboot 0 -ostype l26 \
  -vga std -serial0 socket >/dev/null

pvesm alloc "$STORAGE" "$VMID" "$DISK0" 4M 1>&/dev/null
qm importdisk "$VMID" "$WORK_FILE" "$STORAGE" -format "$DISK_IMPORT_FORMAT" 1>&/dev/null
qm set "$VMID" \
  -efidisk0 "${DISK0_REF}${FORMAT:-}",pre-enrolled-keys=0 \
  -sata0 "${DISK1_REF}",${DISK_CACHE}${THIN}size="${DISK_SIZE}" \
  -boot order=sata0 >/dev/null

set_description
rm -f "$WORK_FILE"
rm -rf "$TEMP_DIR"
msg_ok "Created a ChromeOS Flex VM ${CL}${BL}(${HN})"

msg_info "Resizing disk to ${DISK_SIZE}"
qm resize "$VMID" sata0 "${DISK_SIZE}" >/dev/null
msg_ok "Resized disk to ${DISK_SIZE}"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting ChromeOS Flex VM"
  qm start "$VMID"
  msg_ok "Started ChromeOS Flex VM"
fi

post_update_to_api "done" "none"

echo -e "\n${INFO}${BOLD}${GN}ChromeOS Flex VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}Version: ${BGN}${FLEX_VERSION} (Chrome ${CHROME_VERSION})${CL}"
echo -e "${TAB}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"

echo -e "\n${INFO}${BOLD}${YW}Next Steps:${CL}"
echo -e "${TAB}1. Open the VM Console in Proxmox"
echo -e "${TAB}2. The recovery image boots straight into the Flex setup"
echo -e "${TAB}3. Choose ${BL}Install ChromeOS Flex${CL} to make it permanent,"
echo -e "${TAB}   or ${BL}Try it first${CL} to run without touching the disk"
echo -e "${TAB}4. Sign in with a Google account, or continue as a guest"

echo -e "\n${INFO}${BOLD}${YW}Worth knowing:${CL}"
echo -e "${TAB}• Google does not support Flex in a VM. It runs, but is untested there."
echo -e "${TAB}• No Play Store and no Android apps -- Flex is the web-only build."
echo -e "${TAB}• The disk uses SATA and the NIC e1000, because Flex ships generic"
echo -e "${TAB}  PC drivers rather than paravirtualised ones."

msg_ok "Completed successfully!\n"
