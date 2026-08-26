#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Justin Tröbinger (bonderaustria)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bonderaustria/proxfy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  python3-yaml \
  openssh-client
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "proxfy" "bonderaustria/proxfy" "tarball"

if [[ -z "${var_pve_host:-}" ]]; then
  read -rp "${TAB3}Address of the Proxmox host Proxfy should verify backups on: " var_pve_host
fi
if [[ -z "${var_pve_host}" ]]; then
  msg_error "No Proxmox host given - Proxfy cannot reach a hypervisor."
  exit 1
fi

msg_info "Creating SSH Key"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
ssh-keygen -t ed25519 -N '' -C "proxfy@$(hostname)" -f /root/.ssh/id_proxfy -q
ssh-keyscan -H "${var_pve_host}" >>/root/.ssh/known_hosts 2>/dev/null
chmod 600 /root/.ssh/known_hosts
msg_ok "Created SSH Key"

# The key has to end up in the hypervisor's authorized_keys. With a password we
# can place it here; without one the user does it afterwards and the public key
# is printed at the end. The password is used once and never stored.
AUTHORIZED=0
if [[ -n "${var_pve_password:-}" ]]; then
  msg_info "Authorizing Key on ${var_pve_host}"
  $STD apt install -y sshpass
  if SSHPASS="${var_pve_password}" sshpass -e ssh-copy-id -i /root/.ssh/id_proxfy.pub \
    -o StrictHostKeyChecking=accept-new "root@${var_pve_host}" >/dev/null 2>&1; then
    AUTHORIZED=1
    msg_ok "Authorized Key on ${var_pve_host}"
  else
    msg_error "Could not authorize the key - the public key is printed at the end."
  fi
  $STD apt purge -y sshpass
fi

# Storages are selectable per run in the interface; these are only the
# preselection. Asking the hypervisor works once the key is authorized.
BACKUP_STORE="PBS"
TARGET_STORE="local-lvm"
if [[ "$AUTHORIZED" = "1" ]]; then
  DETECTED=$(ssh -o BatchMode=yes -i /root/.ssh/id_proxfy "root@${var_pve_host}" \
    "pvesm status --content backup 2>/dev/null | awk 'NR>1 {print \$1; exit}'" 2>/dev/null)
  BACKUP_STORE="${DETECTED:-$BACKUP_STORE}"
  DETECTED=$(ssh -o BatchMode=yes -i /root/.ssh/id_proxfy "root@${var_pve_host}" \
    "pvesm status --content images 2>/dev/null | awk 'NR>1 {print \$1; exit}'" 2>/dev/null)
  TARGET_STORE="${DETECTED:-$TARGET_STORE}"
fi

msg_info "Configuring Proxfy"
cat <<EOF >/opt/proxfy/config.yaml
# Backup source, target storage and cluster node are selectable per run in the
# interface; the values here are only the preselection.
host:
  host: ${var_pve_host}
  user: root
  key_file: /root/.ssh/id_proxfy

restore:
  backup_storage: ${BACKUP_STORE}
  target_storage: ${TARGET_STORE}
  isolated_bridge: vmbr9
  lan_bridge: vmbr0
  boot_timeout: 300
  agent_timeout: 240

auth:
  env_file: /opt/proxfy/auth.env
  port: 8100

# Only enable behind a reverse proxy. Otherwise any caller could invent an
# origin address in a header and walk around the login lockout.
trust_forwarded_for: false

# Only used by the collective run on the command line. Triggers nothing by
# itself - there is no built-in schedule.
targets: []
EOF

umask 077
cat <<EOF >/opt/proxfy/auth.env
BETTER_AUTH_SECRET=$(openssl rand -base64 36 | tr -d '\n')
PROXFY_INTERNAL_SECRET=$(openssl rand -hex 32)
BETTER_AUTH_URL=http://${LOCAL_IP}:8099
PROXFY_BASE_ORIGINS=http://${LOCAL_IP}:8099,http://$(hostname):8099,http://localhost:8099
PROXFY_TRUSTED_ORIGINS=http://${LOCAL_IP}:8099,http://$(hostname):8099,http://localhost:8099
PROXFY_AUTH_DB=/opt/proxfy/auth.db
PROXFY_AUTH_PORT=8100
EOF
chmod 600 /opt/proxfy/auth.env
umask 022
msg_ok "Configured Proxfy"

msg_info "Setting up Login Service"
cd /opt/proxfy/auth
$STD npm install --omit=dev --no-audit --no-fund
set -a
. /opt/proxfy/auth.env
set +a
$STD npx --yes auth@latest migrate --yes
msg_ok "Set up Login Service"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/proxfy-auth.service
[Unit]
Description=Proxfy Login Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/proxfy/auth
EnvironmentFile=/opt/proxfy/auth.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/proxfy.service
[Unit]
Description=Proxfy Restore Verification
After=network-online.target proxfy-auth.service
Wants=network-online.target proxfy-auth.service

[Service]
Type=simple
WorkingDirectory=/opt/proxfy
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 -m proxfy.cli --config /opt/proxfy/config.yaml serve --port 8099 --db /opt/proxfy/proxfy.db
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now proxfy-auth
systemctl enable -q --now proxfy
msg_ok "Created Services"

if [[ "$AUTHORIZED" != "1" ]]; then
  msg_error "Proxfy cannot reach ${var_pve_host} yet. Run this on the Proxmox host:"
  echo -e "\n  echo '$(cat /root/.ssh/id_proxfy.pub)' >> /root/.ssh/authorized_keys\n"
fi

motd_ssh
customize
cleanup_lxc
