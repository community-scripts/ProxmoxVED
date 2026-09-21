#!/usr/bin/env bash
#dev_mode=logs
#dev_mode=net,timing,trace,pause,keep,breakpoint,motd,logs
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

APP="Apache-Artemis"
var_tags="${var_tags:-message}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk=${var_disk:-3}
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
  run_os_update
  exit
}

start
build_container
description
msg_ok "Completed successfully!\n"

#echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the web console using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8161${CL}"
#echo -e "${INFO}${YW}Set the password for user "
echo -e "${TAB}${DEFAULT}${BGN}"
