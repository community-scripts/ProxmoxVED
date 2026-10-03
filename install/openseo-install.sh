#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Brandon Visca (visbran)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/every-app/open-seo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "openseo" "every-app/open-seo" "tarball"

PNPM_VERSION=$(sed -n 's/.*"packageManager": "pnpm@\([^"+]*\).*/\1/p' /opt/openseo/package.json)
NODE_VERSION="22" NODE_MODULE="pnpm@${PNPM_VERSION:-10.30.1}" setup_nodejs

if [[ -z "${var_dataforseo_api_key:-}" ]]; then
  var_dataforseo_api_key=$(prompt_input "DataForSEO API key (base64 of login:password, leave empty to set later):" "" 120)
fi

msg_info "Configuring OpenSEO"
cat <<EOF >/opt/openseo/.env
AUTH_MODE=local_noauth
CLOUDFLARE_INCLUDE_PROCESS_ENV=true
PORT=3001
ALLOWED_HOST=
DATAFORSEO_API_KEY=${var_dataforseo_api_key:-}
OPENROUTER_API_KEY=
OPENROUTER_MODEL=
OPENSEO_TELEMETRY_DISABLED=
VITE_SHOW_DEVTOOLS=false
EOF
msg_ok "Configured OpenSEO"

msg_info "Building OpenSEO"
cd /opt/openseo
$STD pnpm install --frozen-lockfile
# The Cloudflare vite plugin serializes the whole process env into .dev.vars; run with a clean env so it only sees /opt/openseo/.env
$STD env -i PATH="$PATH" HOME=/root pnpm run db:migrate:local
$STD env -i PATH="$PATH" HOME=/root pnpm run build
msg_ok "Built OpenSEO"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/openseo.service
[Unit]
Description=OpenSEO
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/openseo
EnvironmentFile=/opt/openseo/.env
ExecStart=/usr/bin/pnpm exec vite preview --host 0.0.0.0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now openseo
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
