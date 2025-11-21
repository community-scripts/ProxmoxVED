#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: gpt-5-codex
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/openbao/openbao

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors

if [[ -z "${OPENBAO_PARENT_INITIALIZED:-}" ]]; then
    setting_up_container
    network_check
    update_os
fi

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    sudo \
    mc \
    libcap2-bin \
    openssl
msg_ok "Installed Dependencies"

msg_info "Creating OpenBao user and directories"
if ! id -u openbao >/dev/null 2>&1; then
    useradd --system --home /var/lib/openbao --shell /usr/sbin/nologin openbao
fi
install -d -m 0750 -o openbao -g openbao /var/lib/openbao/data
install -d -m 0750 -o openbao -g openbao /etc/openbao
install -d -m 0750 -o openbao -g openbao /var/log/openbao
msg_ok "Prepared OpenBao user and directories"

msg_info "Downloading and installing OpenBao"

# Get latest version from HTML (avoids API rate limit)
RELEASE=$(curl -fsSL https://github.com/openbao/openbao/releases/latest 2>&1 | grep -oP 'openbao/openbao/releases/tag/v\K[0-9.]+' | head -1)

if [[ -z "$RELEASE" ]]; then
    # Fallback: use a known stable version
    RELEASE="2.4.3"
    msg_info "Could not determine latest version, using v${RELEASE}"
fi

msg_info "Installing OpenBao v${RELEASE}"

# Download .deb package directly (no API needed)
DEB_URL="https://github.com/openbao/openbao/releases/download/v${RELEASE}/bao_${RELEASE}_linux_amd64.deb"
TMP_DEB="/tmp/openbao.deb"

if ! curl -fsSL "$DEB_URL" -o "$TMP_DEB"; then
    msg_error "Failed to download from ${DEB_URL}"
    exit 1
fi

# Install the package
if ! $STD apt install -y "$TMP_DEB"; then
    if ! $STD dpkg -i "$TMP_DEB"; then
        msg_error "Failed to install OpenBao package"
        rm -f "$TMP_DEB"
        exit 1
    fi
fi

rm -f "$TMP_DEB"

# Create symlink for consistency
if [[ -f /usr/bin/bao ]]; then
    ln -sf /usr/bin/bao /usr/local/bin/openbao
    msg_ok "Installed OpenBao ${RELEASE}"
else
    msg_error "OpenBao binary not found after installation"
    exit 1
fi

echo "${RELEASE}" >/opt/openbao_version.txt

msg_info "Configuring OpenBao"
cat >/etc/openbao/config.hcl <<'EOF_CONF'
storage "file" {
  path = "/var/lib/openbao/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

cluster_addr = "http://127.0.0.1:8201"
api_addr     = "http://0.0.0.0:8200"
ui           = true

log_level      = "info"
EOF_CONF
chown openbao:openbao /etc/openbao/config.hcl
chmod 640 /etc/openbao/config.hcl
msg_ok "Configured OpenBao"

create_service() {
    local service_name="$1"
    local service_content="$2"
    printf '%s' "$service_content" >/etc/systemd/system/"${service_name}".service
}

msg_info "Creating systemd service"

create_service "openbao" "[Unit]
Description=OpenBao Secrets Management Server
After=network-online.target
Wants=network-online.target
Documentation=https://openbao.org/docs

[Service]
User=openbao
Group=openbao
ExecStart=/usr/local/bin/openbao server -config=/etc/openbao/config.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
CapabilityBoundingSet=CAP_IPC_LOCK
AmbientCapabilities=CAP_IPC_LOCK
LimitMEMLOCK=infinity
Restart=on-failure
RestartSec=5s
StartLimitInterval=60
StartLimitBurst=3
LogsDirectory=openbao
StandardOutput=journal
StandardError=inherit

[Install]
WantedBy=multi-user.target
"

msg_ok "Systemd service created"

msg_info "Enabling service"
systemctl daemon-reload
if ! systemctl enable -q --now openbao.service; then
    msg_error "Failed to enable service. Checking logs..."
    echo "=== Status for openbao ==="
    systemctl status openbao --no-pager || true
    echo "=== Journal for openbao ==="
    journalctl -u openbao -n 50 --no-pager || true
    exit 1
fi
msg_ok "Service enabled"

msg_info "Initializing OpenBao"

# Wait for OpenBao to be ready
for i in {1..30}; do
    if curl -fsS http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Verify OpenBao is actually listening
if ! ss -tlnp | grep -q ':8200'; then
    msg_error "OpenBao is running but not listening on port 8200"
    ss -tlnp | grep openbao || true
    journalctl -u openbao -n 50 --no-pager || true
    exit 1
fi

export VAULT_ADDR="http://127.0.0.1:8200"

if ! openbao operator init -status >/dev/null 2>&1; then
    INIT_OUTPUT=$(openbao operator init -key-shares=1 -key-threshold=1)
    UNSEAL_KEY=$(echo "$INIT_OUTPUT" | awk '/Unseal Key 1/ {print $4}')
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | awk '/Initial Root Token/ {print $4}')

    openbao operator unseal "$UNSEAL_KEY"

    msg_info "Storing administrator credentials"
    {
        echo "OpenBao Administrator"
        echo "Root Token: ${ROOT_TOKEN}"
        echo "Unseal Key: ${UNSEAL_KEY}"
        echo ""
        echo "Full initialization output:"
        echo "$INIT_OUTPUT"
    } >~/openbao.creds
    chmod 600 ~/openbao.creds
    msg_ok "Administrator credentials stored in ~/openbao.creds"
else
    msg_ok "OpenBao already initialized"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned"
