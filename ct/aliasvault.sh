#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ProxmoxVED Community
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://aliasvault.net

APP="AliasVault"
var_tags="${var_tags:-security;passwords;privacy}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-24}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
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

    create_backup /opt/aliasvault/.env /opt/aliasvault/certificates

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "aliasvault" "aliasvault/aliasvault" "tarball"

    msg_info "Building Core Libraries (Patience)"
    source "$HOME/.cargo/env"
    $STD rustup target add wasm32-unknown-unknown
    cd /opt/aliasvault/core
    $STD bash build-and-distribute.sh --browser
    msg_ok "Built Core Libraries"

    msg_info "Building AliasVault Applications (Patience)"
    cd /opt/aliasvault/apps/server
    $STD dotnet workload install wasm-tools
    $STD dotnet restore aliasvault.sln
    $STD dotnet publish AliasVault.Api/AliasVault.Api.csproj -c Release -o /opt/aliasvault/api --no-restore
    $STD dotnet build AliasVault.Client/AliasVault.Client.csproj -c Release --no-restore
    $STD dotnet publish AliasVault.Client/AliasVault.Client.csproj -c Release -o /opt/aliasvault/client --no-restore
    python3 -c "
import json, pathlib
p = pathlib.Path('/opt/aliasvault/client/wwwroot/appsettings.json')
c = json.loads(p.read_text()); c['ApiUrl'] = ''; p.write_text(json.dumps(c, indent=2))
for ext in ['.gz', '.br']:
    q = pathlib.Path(str(p) + ext)
    if q.exists(): q.unlink()
"
    mkdir -p /opt/certificates/app
    $STD dotnet publish AliasVault.Admin/AliasVault.Admin.csproj -c Release -o /opt/aliasvault/admin --no-restore
    $STD dotnet publish Services/AliasVault.SmtpService/AliasVault.SmtpService.csproj -c Release -o /opt/aliasvault/smtp --no-restore
    $STD dotnet publish Services/AliasVault.TaskRunner/AliasVault.TaskRunner.csproj -c Release -o /opt/aliasvault/taskrunner --no-restore
    msg_ok "Built AliasVault Applications"

    restore_backup

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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
echo -e "${INFO}${YW} Admin Panel:${CL} ${GATEWAY}${BGN}https://${IP}/admin${CL}"
echo -e "${INFO}${YW} Admin credentials were shown in the installation output above.${CL}"
