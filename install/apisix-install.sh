#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://apisix.apache.org/

# shellcheck disable=SC1091
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APISIX_VERSION="3.16.0-0"

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

apisix_etcd_hosts_yaml() {
  local host
  local hosts="${APISIX_ETCD_HOSTS:-http://127.0.0.1:2379}"
  local IFS=,

  for host in $hosts; do
    host="${host//[[:space:]]/}"
    if [[ -n "$host" ]]; then
      printf '      - "%s"\n' "$host"
    fi
  done
}

if [[ -z "${APISIX_ETCD_HOSTS:-}" ]]; then
  APISIX_ETCD_HOSTS="http://127.0.0.1:2379"

  fetch_and_deploy_gh_release "etcd" "etcd-io/etcd" "prebuild" "latest" "/opt/etcd" "etcd-v*-linux-$(etcd_release_arch).tar.gz"

  msg_info "Installing etcd Binaries"
  ln -sf /opt/etcd/etcd /usr/local/bin/etcd
  ln -sf /opt/etcd/etcdctl /usr/local/bin/etcdctl
  ln -sf /opt/etcd/etcdutl /usr/local/bin/etcdutl
  mkdir -p /var/lib/etcd /etc/etcd
  chown -R root:root /opt/etcd /var/lib/etcd
  chmod 700 /var/lib/etcd
  msg_ok "Installed etcd Binaries"

  msg_info "Configuring etcd"
  cat <<EOF >/etc/default/etcd
ETCD_NAME="apisix"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_CLIENT_URLS="http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://127.0.0.1:2379"
ETCD_LISTEN_PEER_URLS="http://127.0.0.1:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://127.0.0.1:2380"
ETCD_INITIAL_CLUSTER="apisix=http://127.0.0.1:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="apisix-etcd"
EOF
  chmod 0644 /etc/default/etcd
  msg_ok "Configured etcd"

  msg_info "Creating etcd Service"
  cat <<EOF >/etc/systemd/system/etcd.service
[Unit]
Description=etcd key-value store for Apache APISIX
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/etcd
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now etcd
  msg_ok "Created etcd Service"

  msg_info "Checking etcd"
  sleep 3
  ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints="http://127.0.0.1:2379" endpoint health >/dev/null
  msg_ok "etcd Healthy"
else
  msg_info "Using External etcd"
  msg_ok "Using External etcd"
fi

setup_deb822_repo "apisix" \
  "http://repos.apiseven.com/pubkey.gpg" \
  "$(apisix_repo_url)" \
  "bullseye" \
  "main"

msg_info "Installing APISIX"
$STD apt install -y apisix="${APISIX_VERSION}"
msg_ok "Installed APISIX"

msg_info "Configuring APISIX"
APISIX_ADMIN_KEY="${APISIX_ADMIN_KEY:-$(openssl rand -hex 32)}"
APISIX_ETCD_PREFIX="${APISIX_ETCD_PREFIX:-/apisix}"
APISIX_ETCD_TIMEOUT="${APISIX_ETCD_TIMEOUT:-30}"
APISIX_ETCD_HOSTS_YAML="$(apisix_etcd_hosts_yaml)"
cat <<EOF >/usr/local/apisix/conf/config.yaml
apisix:
  node_listen: 9080
  enable_ipv6: false

  enable_control: true
  control:
    ip: "0.0.0.0"
    port: 9092

deployment:
  admin:
    allow_admin:
      - 0.0.0.0/0
    admin_key:
      - name: "admin"
        key: "${APISIX_ADMIN_KEY}"
        role: admin
  etcd:
    host:
${APISIX_ETCD_HOSTS_YAML}
    prefix: "${APISIX_ETCD_PREFIX}"
    timeout: ${APISIX_ETCD_TIMEOUT}

plugin_attr:
  prometheus:
    export_addr:
      ip: "0.0.0.0"
      port: 9091
EOF
chmod 600 /usr/local/apisix/conf/config.yaml
msg_ok "Configured APISIX"

msg_info "Initializing APISIX"
$STD apisix init
msg_ok "Initialized APISIX"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/apisix.service
[Unit]
Description=Apache APISIX API Gateway
After=network.target
Wants=network.target

[Service]
Type=forking
PIDFile=/usr/local/apisix/logs/nginx.pid
ExecStart=/usr/bin/apisix start
ExecReload=/usr/bin/apisix reload
ExecStop=/usr/bin/apisix stop
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now apisix
msg_ok "Created Service"

msg_info "Checking APISIX"
sleep 3
systemctl is-active --quiet apisix
msg_ok "APISIX Running"

motd_ssh
customize
cleanup_lxc
