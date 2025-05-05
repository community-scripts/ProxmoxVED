#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/CrazyWolf13/streamlink-webui

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22"
NODE_MODULE="npm@latest,yarn@latest,@vue/cli-service@latest,@vue/cli-plugin-babel@latest"
install_node_and_modules
setup_uv

msg_info "Setup ${APPLICATION}"
fetch_and_deploy_gh_release "CrazyWolf13/streamlink-webui"
$STD uv venv /opt/"${APPLICATION}"/backend/src/.venv
source /opt/"${APPLICATION}"/backend/src/.venv/bin/activate
$STD uv pip install -r /opt/streamlink-webui/backend/src/requirements.txt --python=/opt/"${APPLICATION}"/backend/src/.venv
cd /opt/"${APPLICATION}"/frontend/src
$STD yarn build
msg_ok "Setup ${APPLICATION}"

msg_info "Creating Service"
cat <<'EOF' >/opt/"${APPLICATION}".env
CLIENT_ID='your_client_id'
CLIENT_SECRET='your_client_secret'
DOWNLOAD_PATH=/opt/streamlink-webui-download'
# BASE_URL='https://sub.domain.com' \
# REVERSE_PROXY=True \
EOF

cat <<EOF >/etc/systemd/system/"${APPLICATION}".service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
EnvironmentFile=/opt/${APPLICATION}.env
WorkingDirectory=/opt/${APPLICATION}
ExecStart=start.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "${APPLICATION}"
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "${RELEASE}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
