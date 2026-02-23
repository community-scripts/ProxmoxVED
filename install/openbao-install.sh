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

# shellcheck disable=SC2034
APP="openbao"
app="${app:-openbao}"
SSH_ROOT="${SSH_ROOT:-no}"

msg_info "Installing OpenBao"
ARCH="$(dpkg --print-architecture)"
case "${ARCH}" in
amd64)
  ARCH="x86_64"
  OPENBAO_ASSET="bao_*_Linux_x86_64.tar.gz"
  ;;
arm64)
  ARCH="arm64"
  OPENBAO_ASSET="bao_*_Linux_arm64.tar.gz"
  ;;
*)
  msg_error "Unsupported architecture: ${ARCH}"
  exit 1
  ;;
esac

RELEASE="$(curl -fsSL https://api.github.com/repos/openbao/openbao/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
fetch_and_deploy_gh_release "openbao" "openbao/openbao" "prebuild" "latest" "/tmp/openbao" "${OPENBAO_ASSET}"
install -m 755 /tmp/openbao/bao /usr/local/bin/bao
rm -rf /tmp/openbao
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
OPENBAO_BIND_ADDRESS="${OPENBAO_BIND_ADDRESS:-0.0.0.0}"
OPENBAO_PORT="${OPENBAO_PORT:-8200}"
OPENBAO_CLUSTER_BIND_ADDRESS="${OPENBAO_CLUSTER_BIND_ADDRESS:-0.0.0.0}"
OPENBAO_CLUSTER_PORT="${OPENBAO_CLUSTER_PORT:-8201}"
OPENBAO_PUBLIC_ADDR="${OPENBAO_PUBLIC_ADDR:-http://$(hostname -f):${OPENBAO_PORT}}"
OPENBAO_PUBLIC_CLUSTER_ADDR="${OPENBAO_PUBLIC_CLUSTER_ADDR:-http://$(hostname -f):${OPENBAO_CLUSTER_PORT}}"
cat <<EOF >/etc/openbao.d/openbao.hcl
ui = true
disable_mlock = true

listener "tcp" {
  address     = "${OPENBAO_BIND_ADDRESS}:${OPENBAO_PORT}"
  cluster_address = "${OPENBAO_CLUSTER_BIND_ADDRESS}:${OPENBAO_CLUSTER_PORT}"
  tls_disable = "true"
}

storage "raft" {
  path = "/var/lib/openbao"
  node_id = "openbao-1"
}

api_addr = "${OPENBAO_PUBLIC_ADDR}"
cluster_addr = "${OPENBAO_PUBLIC_CLUSTER_ADDR}"
EOF
chown openbao:openbao /etc/openbao.d/openbao.hcl
chmod 640 /etc/openbao.d/openbao.hcl
msg_ok "Created OpenBao Configuration"

msg_warn "OpenBao is configured with HTTP (tls_disable=true) on port ${OPENBAO_PORT}."
msg_warn "Use only trusted internal networks until TLS is configured."
msg_warn "Production requires TLS certificates and hardened listener settings."

cat <<'EOF' >/etc/profile.d/openbao.sh
export BAO_ADDR=__BAO_ADDR__
EOF
sed -i "s|__BAO_ADDR__|http://127.0.0.1:${OPENBAO_PORT}|g" /etc/profile.d/openbao.sh
chmod 644 /etc/profile.d/openbao.sh

cat <<'EOF' >/etc/profile.d/openbao-reminder.sh
#!/usr/bin/env bash

# Show OpenBao initialization/unseal reminders for interactive shells only.
[[ $- != *i* ]] && return

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  return
fi

HEALTH_JSON="$(curl -fsS --max-time 2 __BAO_HEALTH_URL__ 2>/dev/null)"
if [[ $? -ne 0 ]]; then
  HEALTH_JSON=""
fi
[[ -z "${HEALTH_JSON}" ]] && return

INITIALIZED="$(echo "${HEALTH_JSON}" | jq -r '.initialized // "unknown"' 2>/dev/null)"
SEALED="$(echo "${HEALTH_JSON}" | jq -r '.sealed // "unknown"' 2>/dev/null)"

if [[ "${INITIALIZED}" != "true" ]]; then
  echo "[OpenBao] Initialization required."
  echo "[OpenBao] Run: BAO_ADDR=__BAO_ADDR__ bao operator init"
elif [[ "${SEALED}" == "true" ]]; then
  echo "[OpenBao] OpenBao is initialized but sealed."
  echo "[OpenBao] Run: BAO_ADDR=__BAO_ADDR__ bao operator unseal"
fi
EOF
sed -i "s|__BAO_ADDR__|http://127.0.0.1:${OPENBAO_PORT}|g" /etc/profile.d/openbao-reminder.sh
sed -i "s|__BAO_HEALTH_URL__|http://127.0.0.1:${OPENBAO_PORT}/v1/sys/health|g" /etc/profile.d/openbao-reminder.sh
chmod 644 /etc/profile.d/openbao-reminder.sh

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
HEALTH_URL="http://127.0.0.1:${OPENBAO_PORT}/v1/sys/health"
for _ in {1..30}; do
  if ! HEALTH_CODE="$(curl -sS -o /dev/null -w "%{http_code}" "${HEALTH_URL}")"; then
    HEALTH_CODE="000"
  fi
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

msg_warn "Current state is expected: Initialized=false, Sealed=true."
msg_warn "Complete setup manually with 'bao operator init' and 'bao operator unseal'."
msg_warn "If container IP changes, update api_addr/cluster_addr in /etc/openbao.d/openbao.hcl."

{
  echo "OpenBao Access"
  echo "URL: http://${LOCAL_IP}:${OPENBAO_PORT}"
  echo "Service: systemctl status openbao"
  echo "Status: BAO_ADDR=http://127.0.0.1:${OPENBAO_PORT} bao status"
  echo ""
  echo "Manual Initialization (one-time):"
  echo "  export BAO_ADDR=http://127.0.0.1:${OPENBAO_PORT}"
  echo "  bao operator init"
  echo ""
  echo "Manual Unseal (on each restart unless auto-unseal configured):"
  echo "  bao operator unseal"
  echo ""
  echo "Security Notes:"
  echo "  - This script does not store unseal keys or root token."
  echo "  - HTTP is enabled by default (tls_disable=true). Configure TLS before production use."
  echo "  - Release checksum/signature verification is not automated in this helper script."
  echo "  - If IP changes, update api_addr/cluster_addr in /etc/openbao.d/openbao.hcl."
  echo "  - You can customize bind/public addresses by setting OPENBAO_* env vars before reinstall."
  echo "  - Login reminders are enabled via /etc/profile.d/openbao-reminder.sh."
} >~/openbao.creds
chmod 600 ~/openbao.creds

motd_ssh
customize
cleanup_lxc
