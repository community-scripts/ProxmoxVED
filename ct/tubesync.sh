#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/meeb/tubesync

APP="TubeSync"
var_tags="${var_tags:-media;youtube}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
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

  if [[ ! -d /opt/tubesync ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "tubesync" "meeb/tubesync"; then
    msg_info "Stopping Services"
    systemctl stop tubesync tubesync-worker@database tubesync-worker@network tubesync-worker@limited tubesync-worker@filesystem
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "tubesync" "meeb/tubesync" "tarball"

    msg_info "Installing Python Dependencies"
    $STD uv venv /opt/tubesync/.venv
    # Resolve deps from the upstream Pipfile (skip mysqlclient; add libsass for compilescss).
    sed -n '/^\[packages\]/,/^\[/{/=/p}' /opt/tubesync/Pipfile | grep -v '^mysqlclient' |
      sed -E 's/ = \{.*extras = \[([^]]*)\].*/[\1]/; s/ = "\*"//; s/ = "([^"]*)"/\1/; s/[" ]//g' >/opt/tubesync/requirements.txt
    $STD uv pip install --python /opt/tubesync/.venv/bin/python -r /opt/tubesync/requirements.txt
    $STD uv pip install --python /opt/tubesync/.venv/bin/python libsass
    # Re-apply the yt_dlp/hat patches on top of the freshly installed packages.
    SITE_PACKAGES=$(/opt/tubesync/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
    cp -rf /opt/tubesync/patches/hat/. "$SITE_PACKAGES/hat/"
    cp -rf /opt/tubesync/patches/yt_dlp/. "$SITE_PACKAGES/yt_dlp/"
    msg_ok "Installed Python Dependencies"

    msg_info "Updating TubeSync"
    cp /opt/tubesync/tubesync/tubesync/local_settings.py.container /opt/tubesync/tubesync/tubesync/local_settings.py
    sed -i "s|CONFIG_BASE_DIR = ROOT_DIR / 'config'|CONFIG_BASE_DIR = Path('/opt/tubesync-config')|" /opt/tubesync/tubesync/tubesync/local_settings.py
    sed -i "s|DOWNLOADS_BASE_DIR = ROOT_DIR / 'downloads'|DOWNLOADS_BASE_DIR = Path('/opt/tubesync-downloads')|" /opt/tubesync/tubesync/tubesync/local_settings.py

    set -a
    source /opt/tubesync.env
    set +a
    cd /opt/tubesync/tubesync
    $STD /opt/tubesync/.venv/bin/python manage.py migrate --no-input
    $STD /opt/tubesync/.venv/bin/python manage.py compilescss
    $STD /opt/tubesync/.venv/bin/python manage.py collectstatic --no-input
    msg_ok "Updated TubeSync"

    msg_info "Starting Services"
    systemctl start tubesync tubesync-worker@database tubesync-worker@network tubesync-worker@limited tubesync-worker@filesystem
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4848${CL}"
