#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Andreas Schmidt (schmidtandreas)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://minecraft.net

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

function get_mc_br_url() {
    download_url="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"
    index=0
    while type="$(curl -s "${download_url}" | jq -r ".result.links[${index}].downloadType")"; do
        if [[ "${type}" == "serverBedrockLinux" ]]; then
            curl -s "${download_url}" | jq -r ".result.links[${index}].downloadUrl"
            return
        fi
        index=$((index + 1))
    done
    msg_error "Couldn't find download URL!"
}

function get_mc_br_version() {
    get_mc_br_url | sed -e "s|.*bedrock-server-\(.*\)\.zip|\1|"
}

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y unzip
msg_ok "Installed Dependencies"

APP="MineCraft-Bedrock"
MCBR_SERVER_DIRECTORY="/minecraft"
MCBR_SERVER_VERSION_FILE="${MCBR_SERVER_DIRECTORY}/server_version.txt"
MCBR_VERSION="$(get_mc_br_version)"
MCBR_SERVER_URL="$(get_mc_br_url)"
MCBR_SERVER_ARCHIVE="bedrock-server-${MCBR_VERSION}.zip"
MCBR_SYSTEMD_SERVICE="/lib/systemd/system/minecraft.service"

msg_info "Installing ${APP}"

if [ -f "${MCBR_SYSTEMD_SERVICE}" ]; then
    systemctl stop minecraft
else
    cat << EOF > "${MCBR_SYSTEMD_SERVICE}"
[Unit]
Description=MineCraft Bedrock Server

[Service]
WorkingDirectory=${MCBR_SERVER_DIRECTORY}
Environment="LD_LIBRARY_PATH=${MCBR_SERVER_DIRECTORY}"
ExecStart=${MCBR_SERVER_DIRECTORY}/bedrock_server

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now minecraft
fi
curl -s -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "${MCBR_SERVER_URL}" -o "${MCBR_SERVER_ARCHIVE}"
[ ! -d "${MCBR_SERVER_DIRECTORY}" ] && mkdir "${MCBR_SERVER_DIRECTORY}"
unzip -d "${MCBR_SERVER_DIRECTORY}" "${MCBR_SERVER_ARCHIVE}"
echo "${MCBR_VERSION}" > "${MCBR_SERVER_VERSION_FILE}"
systemctl start minecraft
msg_ok "Installed ${APP}"

motd_ssh
customize

msg_info "Cleaning up"
rm "${MCBR_SERVER_ARCHIVE}"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
