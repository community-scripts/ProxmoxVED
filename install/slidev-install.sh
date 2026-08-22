#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Filan-glitch
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://sli.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Creating slidev user"
useradd -m -s /bin/bash slidev
SLIDEV_SSH_PASS=""
if [[ -s /root/.ssh/authorized_keys ]]; then
  mkdir -p /home/slidev/.ssh
  cp /root/.ssh/authorized_keys /home/slidev/.ssh/authorized_keys
  chmod 700 /home/slidev/.ssh
  chmod 600 /home/slidev/.ssh/authorized_keys
  chown -R slidev:slidev /home/slidev/.ssh
else
  # No key to inherit — fall back to a password, otherwise the account is
  # unreachable over SSH and the MCP entrypoint has no way in.
  SLIDEV_SSH_PASS="$(openssl rand -base64 18)"
  echo "slidev:${SLIDEV_SSH_PASS}" | chpasswd
fi
msg_ok "Created slidev user"

msg_info "Scaffolding Slidev project"
su - slidev -c "CI=1 npx --yes create-slidev@latest my-slides --template=default --theme=default -y" </dev/null
msg_ok "Scaffolded Slidev project"

msg_info "Installing npm dependencies"
su - slidev -c "cd my-slides && npm install" </dev/null
msg_ok "Installed npm dependencies"

msg_info "Creating service"
cat <<EOF >/etc/systemd/system/slidev.service
[Unit]
Description=Slidev Presentation Server
After=network.target

[Service]
Type=simple
User=slidev
WorkingDirectory=/home/slidev/my-slides
ExecStart=/usr/bin/npm run dev -- --remote --port 3030
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now slidev
msg_ok "Created service"

msg_info "Installing Slidev MCP server helper"
su - slidev -c "cd my-slides && npm install -D @slidev/cli@latest" </dev/null
cat <<'EOF' >/home/slidev/mcp-start.sh
#!/usr/bin/env bash
cd /home/slidev/my-slides
exec npx slidev mcp --entry slides.md
EOF
chmod +x /home/slidev/mcp-start.sh
chown slidev:slidev /home/slidev/mcp-start.sh
msg_ok "Installed Slidev MCP server helper"

motd_ssh
customize

if [[ -n "$SLIDEV_SSH_PASS" ]]; then
  msg_ok "SSH login for slidev user: slidev / ${SLIDEV_SSH_PASS}"
else
  msg_ok "SSH login for slidev user: key-based (root's authorized_keys)"
fi
cleanup_lxc
