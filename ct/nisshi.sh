#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Josua Blejeru (josuablejeru)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nisshi-io/nisshi

APP="Nisshi"
var_tags="${var_tags:-kafka;messaging}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_nisshi_storage="${var_nisshi_storage:-}"
export var_nisshi_postgres_url="${var_nisshi_postgres_url:-}"
export var_nisshi_s3_bucket="${var_nisshi_s3_bucket:-}"
export var_nisshi_s3_endpoint="${var_nisshi_s3_endpoint:-}"
export var_nisshi_s3_region="${var_nisshi_s3_region:-}"
export var_nisshi_s3_access_key="${var_nisshi_s3_access_key:-}"
export var_nisshi_s3_secret_key="${var_nisshi_s3_secret_key:-}"
export var_nisshi_iceberg_catalog="${var_nisshi_iceberg_catalog:-}"
export var_nisshi_iceberg_warehouse="${var_nisshi_iceberg_warehouse:-}"
export var_nisshi_lake_location="${var_nisshi_lake_location:-}"
export var_nisshi_otlp_endpoint="${var_nisshi_otlp_endpoint:-}"
export var_nisshi_otlp_headers="${var_nisshi_otlp_headers:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/nisshi/bin/nisshi ]]; then
    msg_error "No Nisshi Installation Found!"
    exit
  fi

  if check_for_gh_release "nisshi" "nisshi-io/nisshi"; then
    msg_info "Stopping Nisshi"
    systemctl stop nisshi
    msg_ok "Stopped Nisshi"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nisshi" "nisshi-io/nisshi" "prebuild" "latest" "/opt/nisshi" "nisshi-$(arch_resolve "x86_64" "aarch64")-unknown-linux-*.tar.gz"

    msg_info "Starting Nisshi"
    systemctl start nisshi
    msg_ok "Started Nisshi"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Point your Kafka clients at this bootstrap server:${CL}"
echo -e "${GATEWAY}${BGN}${IP}:9092${CL}"
