#!/usr/bin/env bash
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://apisix.apache.org/

APP="Apache APISIX"
var_tags="${var_tags:-gateway;proxy;api}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export APISIX_ETCD_HOSTS="${APISIX_ETCD_HOSTS:-}"
export APISIX_ETCD_PREFIX="${APISIX_ETCD_PREFIX:-}"
export APISIX_ETCD_TIMEOUT="${APISIX_ETCD_TIMEOUT:-}"
export APISIX_ADMIN_KEY="${APISIX_ADMIN_KEY:-}"

header_info "$APP"
variables
color
catch_errors

apisix_repo_url() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
  amd64 | x86_64)
    echo "http://repos.apiseven.com/packages/debian"
    ;;
  arm64 | aarch64)
    echo "http://repos.apiseven.com/packages/arm64/debian"
    ;;
  *)
    msg_error "Unsupported architecture: ${arch}"
    exit 65
    ;;
  esac
}

etcd_release_arch() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
  amd64 | x86_64)
    echo "amd64"
    ;;
  arm64 | aarch64)
    echo "arm64"
    ;;
  *)
    msg_error "Unsupported architecture: ${arch}"
    exit 65
    ;;
  esac
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/bin/apisix ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_deb822_repo "apisix" \
    "http://repos.apiseven.com/pubkey.gpg" \
    "$(apisix_repo_url)" \
    "bullseye" \
    "main"

  msg_info "Stopping APISIX"
  systemctl stop apisix
  msg_ok "Stopped APISIX"

  msg_info "Updating APISIX"
  $STD apt install -y apisix
  msg_ok "Updated APISIX"

  if systemctl is-enabled --quiet etcd 2>/dev/null && check_for_gh_release "etcd" "etcd-io/etcd"; then
    msg_info "Stopping etcd"
    systemctl stop etcd
    msg_ok "Stopped etcd"

    local arch
    arch="$(etcd_release_arch)"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "etcd" "etcd-io/etcd" "prebuild" "latest" "/opt/etcd" "etcd-v*-linux-${arch}.tar.gz"

    msg_info "Installing etcd Binaries"
    ln -sf /opt/etcd/etcd /usr/local/bin/etcd
    ln -sf /opt/etcd/etcdctl /usr/local/bin/etcdctl
    ln -sf /opt/etcd/etcdutl /usr/local/bin/etcdutl
    chown -R root:root /opt/etcd
    msg_ok "Installed etcd Binaries"

    msg_info "Starting etcd"
    systemctl start etcd
    msg_ok "Started etcd"
  fi

  msg_info "Initializing APISIX"
  $STD apisix init
  msg_ok "Initialized APISIX"

  msg_info "Starting APISIX"
  systemctl start apisix
  msg_ok "Started APISIX"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Gateway endpoint:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9080${CL}"
echo -e "${INFO}${YW} Admin API endpoint:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9180${CL}"
echo -e "${INFO}${YW} Configuration:${CL}"
echo -e "${TAB}${BGN}/usr/local/apisix/conf/config.yaml${CL}"
