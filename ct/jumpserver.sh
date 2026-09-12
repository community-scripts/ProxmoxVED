#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.jumpserver.org/ | Github: https://github.com/jumpserver/jumpserver

APP="JumpServer"
var_tags="${var_tags:-bastion-host;pam}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; koko/lion ship arm64 binaries and guacd builds fine on arm64, but the combined stack has not actually been run on arm64

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/jumpserver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "jumpserver" "jumpserver/jumpserver" "" "" "v4."; then
    msg_info "Stopping Services"
    systemctl stop jumpserver koko lion
    msg_ok "Stopped Services"

    create_backup /opt/jumpserver/config.yml /opt/jumpserver/data/media /opt/koko/config.yml /opt/lion/config.yml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jumpserver" "jumpserver/jumpserver" "tarball" "latest" "" "" "v4."
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "koko" "jumpserver/koko" "prebuild" "latest" "/opt/koko" "koko-v4.*-linux-$(arch_resolve amd64 arm64).tar.gz" "v4."
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lion" "jumpserver/lion-release" "prebuild" "latest" "/opt/lion" "lion-v*-linux-$(arch_resolve amd64 arm64).tar.gz"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lina" "jumpserver/lina" "prebuild" "latest" "/opt/lina" "lina-v4.*.tar.gz" "v4."
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "luna" "jumpserver/luna" "prebuild" "latest" "/opt/luna" "luna-v4.*.tar.gz" "v4."

    restore_backup

    msg_info "Updating Python Environment"
    cd /opt/jumpserver
    $STD bash requirements/static_files.sh
    $STD uv venv --python 3.14
    $STD uv pip install -r pyproject.toml
    JMS_GALAXY_RETRIES=3
    until ANSIBLE_COLLECTIONS_PATHS="/opt/jumpserver/.venv/lib/python3.14/site-packages/ansible_collections" $STD .venv/bin/ansible-galaxy collection install -r requirements/collections.yml --force --ignore-certs; do
      JMS_GALAXY_RETRIES=$((JMS_GALAXY_RETRIES - 1))
      if ((JMS_GALAXY_RETRIES <= 0)); then
        msg_error "ansible-galaxy collection install failed after 3 attempts (Ansible Galaxy may be unreachable)"
        exit 1
      fi
      sleep 15
    done
    msg_ok "Updated Python Environment"

    msg_info "Starting Services"
    systemctl start jumpserver koko lion
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW}SSH bastion (character protocols): ${CL}${BGN}ssh -p 2222 <user>@${IP}${CL}"
echo -e "${INFO}${YW}Login credentials: ~/jumpserver.creds (inside the container)${CL}"
