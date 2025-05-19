#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.kasmweb.com/docs/1.10.0/install/single_server_install.html

APP="Kasm"
var_tags="kasm;workspaces;docker"
var_cpu="2"
var_ram="4096"
var_disk="50"
var_os="debian"
var_version="12"
var_unprivileged="0"
var_fuse="yes"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/kasm ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP} LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated ${APP} LXC"
    exit
}

start
build_container

CT_CONF="/etc/pve/lxc/${CTID}.conf"

msg_info "Configuring TUN/TAP support"
cat <<EOF >>"$CT_CONF"
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
msg_ok "Configured TUN/TAP support"

msg_info "Rebooting container to apply configuration"
pct reboot "$CTID"

msg_info "Waiting for container to be back online"
MAX_ATTEMPTS=60
ATTEMPT=1
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    STATUS=$(pct status "$CTID" | grep -o "running")
    if [ "$STATUS" = "running" ] && pct exec "$CTID" -- true >/dev/null 2>&1; then
        msg_ok "Container is back online"
        break
    fi
    echo -n "."
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
    msg_error "Container failed to come back online within $MAX_ATTEMPTS attempts"
    exit 1
fi

msg_ok "Running Kasm installer"
pct exec "$CTID" -- bash -c "
chmod +x /opt/kasm_release/install.sh
printf 'y\ny\ny\n4\n' | bash /opt/kasm_release/install.sh | tee ~/kasm-install.output
sed -n '/Kasm UI Login Credentials/,\$p' ~/kasm-install.output > ~/kasm.creds
"

msg_ok "Installed Kasm Workspaces"

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:443${CL}"
