#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: renizmy
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/safebucket/safebucket

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

msg_info "Installing MinIO"
curl -fsSL https://dl.min.io/server/minio/release/linux-${ARCH}/minio -o /usr/local/bin/minio
chmod +x /usr/local/bin/minio
mkdir -p /opt/minio/data
MINIO_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
cat <<EOF >/etc/default/minio
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_PASS}
MINIO_VOLUMES=/opt/minio/data
MINIO_OPTS="--address :9000 --console-address :9001"
EOF
cat <<EOF >/etc/systemd/system/minio.service
[Unit]
Description=MinIO Object Storage
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server \$MINIO_VOLUMES \$MINIO_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now minio
msg_ok "Installed MinIO"

msg_info "Configuring MinIO"
curl -fsSL https://dl.min.io/client/mc/release/linux-${ARCH}/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc
for i in $(seq 1 30); do
  /usr/local/bin/mc alias set local http://localhost:9000 minioadmin "${MINIO_PASS}" &>/dev/null && break
  sleep 1
done
if ! /usr/local/bin/mc alias set local http://localhost:9000 minioadmin "${MINIO_PASS}" &>/dev/null; then
  msg_error "Failed to connect to MinIO after 30 seconds"
  exit 1
fi
$STD /usr/local/bin/mc mb local/safebucket --ignore-existing
msg_ok "Configured MinIO"

msg_info "Installing Safebucket"
fetch_and_deploy_gh_release "safebucket" "safebucket/safebucket" "singlefile" "latest" "/opt/safebucket" "safebucket-linux-${ARCH}"
chmod +x /opt/safebucket/safebucket
msg_ok "Installed Safebucket"

msg_info "Configuring Safebucket"
mkdir -p /opt/safebucket/data/{notifications,activity}
JWT_SECRET=$(openssl rand -base64 32)
MFA_KEY=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
get_lxc_ip
cat <<EOF >/opt/safebucket/config.yaml
app:
  log_level: info
  api_url: http://${LOCAL_IP}:8080
  web_url: http://${LOCAL_IP}:8080
  allowed_origins:
    - http://${LOCAL_IP}:8080
  port: 8080
  jwt_secret: "${JWT_SECRET}"
  mfa_encryption_key: "${MFA_KEY}"
  mfa_required: false
  admin_email: admin@safebucket.io
  admin_password: ChangeMePlease
  trash_retention_days: 7
  max_upload_size: 53687091200
  trusted_proxies:
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 127.0.0.0/8
    - ::1/128
    - fc00::/7
  static_files:
    enabled: true

database:
  type: sqlite
  sqlite:
    path: /opt/safebucket/data/safebucket.db

cache:
  type: memory

storage:
  type: minio
  minio:
    bucket_name: safebucket
    endpoint: localhost:9000
    external_endpoint: http://${LOCAL_IP}:9000
    client_id: minioadmin
    client_secret: ${MINIO_PASS}

events:
  type: memory
  queues:
    notifications:
      name: safebucket-notifications
    object_deletion:
      name: safebucket-object-deletion
    bucket_events:
      name: safebucket-bucket-events

notifier:
  type: filesystem
  filesystem:
    directory: /opt/safebucket/data/notifications

activity:
  type: filesystem
  filesystem:
    directory: /opt/safebucket/data/activity

auth:
  providers:
    local:
      type: local
      sharing:
        allowed: true
        domains: []
EOF
msg_ok "Configured Safebucket"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/safebucket.service
[Unit]
Description=Safebucket File Sharing Platform
After=network-online.target minio.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/safebucket
ExecStart=/opt/safebucket/safebucket
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now safebucket
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
