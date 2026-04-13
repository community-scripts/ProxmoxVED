#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: 007hacky007
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://foldingathome.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ARCH=$(dpkg --print-architecture)
case "${ARCH}" in
amd64)
  DEB_URL="https://download.foldingathome.org/releases/public/fah-client/debian-10-64bit/release/latest.deb"
  ;;
arm64)
  DEB_URL="https://download.foldingathome.org/releases/public/fah-client/debian-stable-arm64/release/latest.deb"
  ;;
*)
  msg_error "Unsupported architecture: ${ARCH}"
  exit 1
  ;;
esac

DEB_FILE="/tmp/fah-client_latest_${ARCH}.deb"
GPU_ENABLED="${ENABLE_GPU:-no}"

msg_info "Installing Folding@Home Control Helper"
$STD apt install -y python3-websocket
msg_ok "Installed Folding@Home Control Helper"

msg_info "Downloading Folding@Home"
curl -fsSL "${DEB_URL}" -o "${DEB_FILE}"
msg_ok "Downloaded Folding@Home"

msg_info "Installing Folding@Home"
$STD apt install -y "${DEB_FILE}"
rm -f "${DEB_FILE}"
msg_ok "Installed Folding@Home"

setup_hwaccel

DEFAULT_MACHINE_NAME=$(hostname)
CPU_COUNT=$(nproc)

echo -e "${INFO}${YW} Folding@Home account token (optional):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Log in to Folding@Home Web Control, then open Account Settings to copy your current token:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://v8-5.foldingathome.org/account/settings${CL}"
read -r -p "${TAB3}Enter your Folding@Home account token (press Enter to skip): " ACCOUNT_TOKEN
read -r -p "${TAB3}Enter machine name [${DEFAULT_MACHINE_NAME}] (press Enter to skip): " MACHINE_NAME_INPUT

if [[ -n "${MACHINE_NAME_INPUT}" ]]; then
  MACHINE_NAME="${MACHINE_NAME_INPUT}"
else
  MACHINE_NAME="${DEFAULT_MACHINE_NAME}"
fi

msg_info "Configuring Folding@Home"
install -d -m 0755 /etc/fah-client
CONFIG_FILE="/etc/fah-client/config.xml"
[[ -f "${CONFIG_FILE}" ]] || echo "<config/>" >"${CONFIG_FILE}"

python3 - "${CONFIG_FILE}" "${ACCOUNT_TOKEN}" "${MACHINE_NAME}" "${GPU_ENABLED}" "${CPU_COUNT}" <<'PY'
import sys
import xml.etree.ElementTree as ET

config_file, account_token, machine_name, gpu_enabled, cpu_count = sys.argv[1:6]

try:
    tree = ET.parse(config_file)
    root = tree.getroot()
except ET.ParseError:
    root = ET.Element("config")
    tree = ET.ElementTree(root)

if root.tag != "config":
    new_root = ET.Element("config")
    new_root.append(root)
    root = new_root
    tree = ET.ElementTree(root)

for tag in ("account-token", "machine-name", "gpu", "cpus", "slot"):
    for node in list(root.findall(tag)):
        root.remove(node)

if account_token:
    ET.SubElement(root, "account-token", {"v": account_token})
if machine_name:
    ET.SubElement(root, "machine-name", {"v": machine_name})
ET.SubElement(root, "gpu", {"v": "true" if gpu_enabled == "yes" else "false"})
ET.SubElement(root, "cpus", {"v": cpu_count})
ET.SubElement(root, "slot", {"id": "0", "type": "CPU"})
if gpu_enabled == "yes":
    ET.SubElement(root, "slot", {"id": "1", "type": "GPU"})

ET.indent(tree, space="  ")
tree.write(config_file, encoding="utf-8", xml_declaration=False)
PY
msg_ok "Configured Folding@Home"

msg_info "Starting Folding@Home"
systemctl enable -q --now fah-client
msg_ok "Started Folding@Home"

msg_info "Starting Folding Workload"
if python3 - <<'PY'
import json
import time
from datetime import datetime, timezone

import websocket

payload = {
    "cmd": "state",
    "state": "fold",
    "time": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}

last_error = None
for _ in range(15):
    try:
        ws = websocket.create_connection("ws://127.0.0.1:7396/api/websocket", timeout=5)
        ws.recv()
        ws.send(json.dumps(payload))
        ws.close()
        raise SystemExit(0)
    except Exception as exc:
        last_error = exc
        time.sleep(1)

raise SystemExit(f"Unable to send fold command: {last_error}")
PY
then
  msg_ok "Started Folding Workload"
else
  msg_warn "Unable to start folding automatically; use Web Control or fahctl to issue Fold"
fi

echo -e "${INFO}${YW} Post-Install Notes:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Config file: /etc/fah-client/config.xml${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Web Control: https://v8-5.foldingathome.org/${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Documentation: https://foldingathome.org/guides/v8-5-client-guide/${CL}"

motd_ssh
customize
cleanup_lxc
