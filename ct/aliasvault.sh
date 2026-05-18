#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ProxmoxVED Community
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://aliasvault.net

APP="AliasVault"
var_tags="${var_tags:-security;passwords;privacy}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-30}"
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

  if [[ ! -f /opt/aliasvault/.env ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "aliasvault" "aliasvault/aliasvault"; then
    RELEASE=$(get_latest_github_release "aliasvault/aliasvault")

    msg_info "Stopping Services"
    systemctl stop aliasvault-api aliasvault-admin aliasvault-smtp aliasvault-taskrunner
    msg_ok "Stopped Services"

    msg_info "Backing up Configuration"
    cp /opt/aliasvault/.env /opt/aliasvault_env.bak
    cp -r /opt/aliasvault/certificates /opt/aliasvault_certs.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "aliasvault" "aliasvault/aliasvault" "tarball"

    msg_info "Building Core Libraries (Patience)"
    source "$HOME/.cargo/env"
    $STD rustup target add wasm32-unknown-unknown
    cd /opt/aliasvault/core
    $STD bash build-and-distribute.sh --browser
    msg_ok "Built Core Libraries"

    msg_info "Copying Core Artifacts"
    mkdir -p /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/wasm
    cp /opt/aliasvault/core/rust/dist/wasm/aliasvault_core_bg.wasm \
      /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/wasm/
    cp /opt/aliasvault/core/rust/dist/wasm/aliasvault_core.js \
      /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/wasm/
    mkdir -p /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/{identity-generator,password-generator,vault}
    cp -r /opt/aliasvault/core/typescript/identity-generator/dist/. \
      /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/identity-generator/
    cp -r /opt/aliasvault/core/typescript/password-generator/dist/. \
      /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/password-generator/
    cp -r /opt/aliasvault/core/vault/dist/. \
      /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/vault/
    msg_ok "Copied Core Artifacts"

    msg_info "Building AliasVault Applications (Patience)"
    cd /opt/aliasvault/apps/server
    $STD dotnet workload install wasm-tools
    $STD dotnet restore aliasvault.sln
    $STD dotnet publish AliasVault.Api/AliasVault.Api.csproj -c Release -o /opt/aliasvault/api --no-restore
    $STD dotnet build AliasVault.Client/AliasVault.Client.csproj -c Release --no-restore
    $STD dotnet publish AliasVault.Client/AliasVault.Client.csproj -c Release -o /opt/aliasvault/client --no-restore
    $STD dotnet publish AliasVault.Admin/AliasVault.Admin.csproj -c Release -o /opt/aliasvault/admin --no-restore
    $STD dotnet publish Services/AliasVault.SmtpService/AliasVault.SmtpService.csproj -c Release -o /opt/aliasvault/smtp --no-restore
    $STD dotnet publish Services/AliasVault.TaskRunner/AliasVault.TaskRunner.csproj -c Release -o /opt/aliasvault/taskrunner --no-restore
    msg_ok "Built AliasVault Applications"

    msg_info "Restoring Configuration"
    cp /opt/aliasvault_env.bak /opt/aliasvault/.env
    cp -r /opt/aliasvault_certs.bak/. /opt/aliasvault/certificates/
    rm -f /opt/aliasvault_env.bak
    rm -rf /opt/aliasvault_certs.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Services"
    systemctl start aliasvault-api aliasvault-admin aliasvault-smtp aliasvault-taskrunner
    msg_ok "Started Services"
    msg_ok "Updated successfully to ${RELEASE}!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
echo -e "${INFO}${YW} Admin Panel:${CL} ${TAB}${GATEWAY}${BGN}https://${IP}/admin${CL}"
echo -e "${INFO}${YW} Admin credentials were shown in the installation output above.${CL}"
