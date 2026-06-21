#!/usr/bin/env bash
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://etcd.io/

APP="etcd"
var_tags="${var_tags:-database;key-value}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export ETCD_NAME="${ETCD_NAME:-}"
export ETCD_LISTEN_CLIENT_URLS="${ETCD_LISTEN_CLIENT_URLS:-}"
export ETCD_ADVERTISE_CLIENT_URLS="${ETCD_ADVERTISE_CLIENT_URLS:-}"
export ETCD_LISTEN_PEER_URLS="${ETCD_LISTEN_PEER_URLS:-}"
export ETCD_INITIAL_ADVERTISE_PEER_URLS="${ETCD_INITIAL_ADVERTISE_PEER_URLS:-}"
export ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER:-}"
export ETCD_INITIAL_CLUSTER_STATE="${ETCD_INITIAL_CLUSTER_STATE:-}"
export ETCD_INITIAL_CLUSTER_TOKEN="${ETCD_INITIAL_CLUSTER_TOKEN:-}"
export ETCDCTL_ENDPOINTS="${ETCDCTL_ENDPOINTS:-}"

header_info "$APP"
variables
color
catch_errors

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

  if [[ ! -x /usr/local/bin/etcd ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "etcd" "etcd-io/etcd"; then
    msg_info "Stopping Service"
    systemctl stop etcd
    msg_ok "Stopped Service"

    msg_info "Updating etcd"
    local arch
    arch="$(etcd_release_arch)"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "etcd" "etcd-io/etcd" "prebuild" "latest" "/opt/etcd" "etcd-v*-linux-${arch}.tar.gz"
    ln -sf /opt/etcd/etcd /usr/local/bin/etcd
    ln -sf /opt/etcd/etcdctl /usr/local/bin/etcdctl
    ln -sf /opt/etcd/etcdutl /usr/local/bin/etcdutl
    chown -R root:root /opt/etcd
    msg_ok "Updated etcd"

    msg_info "Starting Service"
    systemctl start etcd
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
echo -e "${INFO}${YW}etcd client endpoint:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:2379${CL}"
echo -e "${INFO}${YW}For optional multi-node bootstrap, set ETCD_* variables before running this script.${CL}"
