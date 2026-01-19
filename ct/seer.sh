#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://docs.seerr.dev/

APP="Seer"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/seer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "seer" "seerr-team/seerr"; then
    msg_info "Stopping Service"
    systemctl stop seer
    msg_ok "Stopped Service"

    pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seer/package.json)
    NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "seer" "seerr-team/seerr" "tarball" "latest"

    cd /opt/seer
    export CYPRESS_INSTALL_BINARY=0
    $STD pnpm install --frozen-lockfile
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm build

    cat <<EOF >/etc/systemd/system/seer.service
[Unit]
Description=Seer Service
After=network.target

[Service]
EnvironmentFile=/etc/seer/seer.conf
Environment=NODE_ENV=production
Type=exec
WorkingDirectory=/opt/seer
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl start seer
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5055${CL}"
