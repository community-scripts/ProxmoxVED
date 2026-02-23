#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yamon
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.openbao.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="openbao"
app="${app:-openbao}"
SSH_ROOT="${SSH_ROOT:-no}"

msg_info "Installing Dependencies"
$STD apt install -y curl jq ca-certificates tar
msg_ok "Installed Dependencies"

msg_info "Installing OpenBao"
ARCH="$(dpkg --print-architecture)"
case "${ARCH}" in
amd64) ARCH="x86_64" ;;
arm64) ARCH="arm64" ;;
*)
  msg_error "Unsupported architecture: ${ARCH}"
  exit 1
  ;;
esac

RELEASE="$(curl -fsSL https://api.github.com/repos/openbao/openbao/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
TMP_DIR="$(mktemp -d)"
$STD curl -fsSL "https://github.com/openbao/openbao/releases/download/v${RELEASE}/bao_${RELEASE}_Linux_${ARCH}.tar.gz" -o "${TMP_DIR}/openbao.tar.gz"
$STD tar -xzf "${TMP_DIR}/openbao.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/bao" /usr/local/bin/bao
rm -rf "${TMP_DIR}"
msg_ok "Installed OpenBao v${RELEASE}"

msg_info "Creating OpenBao User and Directories"
if ! id -u openbao >/dev/null 2>&1; then
  useradd --system --home /var/lib/openbao --shell /usr/sbin/nologin openbao
fi
mkdir -p /etc/openbao.d /var/lib/openbao /var/log/openbao /opt/openbao
touch /var/log/openbao/openbao.log
chown -R openbao:openbao /etc/openbao.d /var/lib/openbao /var/log/openbao
chmod 750 /etc/openbao.d /var/lib/openbao /var/log/openbao
echo "${RELEASE}" >/opt/openbao/VERSION
msg_ok "Created OpenBao User and Directories"

msg_info "Creating OpenBao Configuration"
get_lxc_ip
LOCAL_IP="${LOCAL_IP:-$IP}"
cat <<EOF >/etc/openbao.d/openbao.hcl
ui = true
disable_mlock = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = "true"
}

storage "raft" {
  path = "/var/lib/openbao"
  node_id = "openbao-1"
}

api_addr = "http://${LOCAL_IP}:8200"
cluster_addr = "http://${LOCAL_IP}:8201"
EOF
chown openbao:openbao /etc/openbao.d/openbao.hcl
chmod 640 /etc/openbao.d/openbao.hcl
msg_ok "Created OpenBao Configuration"

cat <<'EOF' >/etc/profile.d/openbao.sh
export BAO_ADDR=http://127.0.0.1:8200
EOF
chmod 644 /etc/profile.d/openbao.sh

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/openbao.service
[Unit]
Description=OpenBao Secret Management Service
Documentation=https://openbao.org/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openbao
Group=openbao
ExecStart=/usr/local/bin/bao server -config=/etc/openbao.d/openbao.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=/var/lib/openbao /var/log/openbao

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now openbao
msg_ok "Created Service"

msg_info "Running Health Check"
for _ in {1..30}; do
  HEALTH_CODE="$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8200/v1/sys/health || true)"
  case "${HEALTH_CODE}" in
  200 | 429 | 472 | 473 | 501)
    break
    ;;
  esac
  sleep 2
done

case "${HEALTH_CODE}" in
200 | 429 | 472 | 473 | 501) msg_ok "Health check passed (HTTP ${HEALTH_CODE})" ;;
*)
  msg_error "OpenBao health check failed (HTTP ${HEALTH_CODE:-000})"
  exit 1
  ;;
esac

{
  echo "OpenBao Access"
  echo "URL: http://${LOCAL_IP}:8200"
  echo "Service: systemctl status openbao"
  echo "Status: BAO_ADDR=http://127.0.0.1:8200 bao status"
  echo ""
  echo "Manual Initialization (one-time):"
  echo "  export BAO_ADDR=http://127.0.0.1:8200"
  echo "  bao operator init"
  echo ""
  echo "Manual Unseal (on each restart unless auto-unseal configured):"
  echo "  bao operator unseal"
  echo ""
  echo "Security Note: This script does not store unseal keys or root token."
} >~/openbao.creds
chmod 600 ~/openbao.creds

motd_ssh
customize
cleanup_lxc
