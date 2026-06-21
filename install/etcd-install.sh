#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://etcd.io/

# shellcheck disable=SC1091
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

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

msg_info "Creating etcd User"
if ! getent group etcd >/dev/null 2>&1; then
  groupadd --system etcd
fi
if ! id -u etcd >/dev/null 2>&1; then
  useradd --system --gid etcd --home-dir /var/lib/etcd --shell /usr/sbin/nologin etcd
fi
mkdir -p /opt/etcd /var/lib/etcd /etc/etcd
chown -R etcd:etcd /var/lib/etcd
chmod 700 /var/lib/etcd
msg_ok "Created etcd User"

msg_info "Installing etcd"
ETCD_ARCH="$(etcd_release_arch)"
fetch_and_deploy_gh_release "etcd" "etcd-io/etcd" "prebuild" "latest" "/opt/etcd" "etcd-v*-linux-${ETCD_ARCH}.tar.gz"
ln -sf /opt/etcd/etcd /usr/local/bin/etcd
ln -sf /opt/etcd/etcdctl /usr/local/bin/etcdctl
ln -sf /opt/etcd/etcdutl /usr/local/bin/etcdutl
chown -R root:root /opt/etcd
msg_ok "Installed etcd"

msg_info "Configuring etcd"
get_lxc_ip
LOCAL_IP="${LOCAL_IP:-$(hostname -I | awk '{print $1}')}"
LOCAL_IP="${LOCAL_IP:-127.0.0.1}"

ETCD_NODE_NAME="${ETCD_NAME:-$(hostname -s)}"
ETCD_CLIENT_LISTEN_URLS="${ETCD_LISTEN_CLIENT_URLS:-http://0.0.0.0:2379}"
ETCD_CLIENT_ADVERTISE_URLS="${ETCD_ADVERTISE_CLIENT_URLS:-http://${LOCAL_IP}:2379}"
ETCD_PEER_LISTEN_URLS="${ETCD_LISTEN_PEER_URLS:-http://0.0.0.0:2380}"
ETCD_PEER_ADVERTISE_URLS="${ETCD_INITIAL_ADVERTISE_PEER_URLS:-http://${LOCAL_IP}:2380}"
ETCD_CLUSTER="${ETCD_INITIAL_CLUSTER:-${ETCD_NODE_NAME}=http://${LOCAL_IP}:2380}"
ETCD_CLUSTER_STATE="${ETCD_INITIAL_CLUSTER_STATE:-new}"
ETCD_CLUSTER_TOKEN="${ETCD_INITIAL_CLUSTER_TOKEN:-etcd-cluster}"
ETCD_HEALTH_ENDPOINTS="${ETCDCTL_ENDPOINTS:-http://127.0.0.1:2379}"

cat <<EOF >/etc/default/etcd
ETCD_NAME="${ETCD_NODE_NAME}"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_CLIENT_URLS="${ETCD_CLIENT_LISTEN_URLS}"
ETCD_ADVERTISE_CLIENT_URLS="${ETCD_CLIENT_ADVERTISE_URLS}"
ETCD_LISTEN_PEER_URLS="${ETCD_PEER_LISTEN_URLS}"
ETCD_INITIAL_ADVERTISE_PEER_URLS="${ETCD_PEER_ADVERTISE_URLS}"
ETCD_INITIAL_CLUSTER="${ETCD_CLUSTER}"
ETCD_INITIAL_CLUSTER_STATE="${ETCD_CLUSTER_STATE}"
ETCD_INITIAL_CLUSTER_TOKEN="${ETCD_CLUSTER_TOKEN}"
EOF

chmod 0644 /etc/default/etcd
msg_ok "Configured etcd"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/etcd.service
[Unit]
Description=etcd key-value store
Documentation=https://etcd.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=etcd
Group=etcd
EnvironmentFile=-/etc/default/etcd
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now etcd
msg_ok "Created Service"

if [[ "${ETCD_CLUSTER}" != *,* ]]; then
  msg_info "Checking Service"
  sleep 3
  ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints="${ETCD_HEALTH_ENDPOINTS}" endpoint health >/dev/null
  msg_ok "Service Healthy"
else
  msg_info "Checking Service"
  systemctl is-active --quiet etcd
  msg_ok "Service Started"
fi

motd_ssh
customize
cleanup_lxc
