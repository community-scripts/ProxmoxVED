#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: geedoes
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

APP="ioquake3"
var_tags="${var_tags:-game;server}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    # Check if installation is present | -f for file, -d for folder
    if [[ ! -d /opt/ioquake3 ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_ok "No update required. ${APP} does not currently support auto-updates."
    exit
}

start
build_container
description

msg_info "Running internal Quake 3 installation..."
pct exec $CTID -- bash -c "$(curl -s https://raw.githubusercontent.com/geedoes/ProxmoxVED/refs/heads/main/install/ioquake3-install.sh)"
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} IMPORTANT: Manual File Deployment Required${CL}"
echo -e "${TAB}${BGN}1.${CL} Upload your 'pak0.pk3' to Proxmox ISO storage, renamed as ${BL}pak0.iso${CL}"
echo -e "${TAB}${BGN}2.${CL} Run the following command on your Proxmox Host to deploy it:"
echo -e "${TAB}${TAB}${GN}pct push $CTID /var/lib/vz/template/iso/pak0.iso /opt/ioquake3/baseq3/pak0.pk3${CL}"
echo -e "${TAB}${BGN}3.${CL} Fix permissions and restart:"
echo -e "${TAB}${TAB}${GN}pct exec $CTID -- bash -c \"chown -R quake3:quake3 /opt/ioquake3/ && systemctl restart ioquake3\"${CL}"
