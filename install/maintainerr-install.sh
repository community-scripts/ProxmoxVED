#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tumeden
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Maintainerr/Maintainerr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  python3
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "maintainerr" "Maintainerr/Maintainerr" "tarball" "latest" "/opt/maintainerr"

NODE_VERSION="24" setup_nodejs
msg_info "Preparing Build Runtime"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable
if [[ -f /opt/maintainerr/package.json ]]; then
  if command -v jq >/dev/null 2>&1; then
    yarn_spec=$(jq -r '.packageManager // empty' /opt/maintainerr/package.json 2>/dev/null || true)
    if [[ -n "$yarn_spec" && "$yarn_spec" == yarn@* ]]; then
      yarn_ver="${yarn_spec#yarn@}"
      yarn_ver="${yarn_ver%%+*}"
      $STD corepack prepare "yarn@${yarn_ver}" --activate || true
    fi
  fi
fi
mkdir -p /opt/data/logs /etc/maintainerr
ln -sfnT /opt/maintainerr /opt/app
msg_ok "Prepared Build Runtime"

msg_info "Building Maintainerr (Patience)"
cd /opt/maintainerr || { msg_error "Failed to change to /opt/maintainerr"; exit 1; }
cat <<'EOF' >/opt/maintainerr/apps/ui/.env
VITE_BASE_PATH=/__PATH_PREFIX__
EOF
export NODE_OPTIONS="--max-old-space-size=4096"
$STD yarn install --immutable --network-timeout 99999999
$STD yarn turbo build
$STD yarn workspaces focus --all --production
mkdir -p /opt/maintainerr/apps/server/dist/ui
cp -a /opt/maintainerr/apps/ui/dist/. /opt/maintainerr/apps/server/dist/ui/
msg_ok "Built Maintainerr"

msg_info "Creating Start Script"
cat <<'EOF' >/opt/maintainerr/start.sh
#!/usr/bin/env bash
set -euo pipefail

BASE_PATH_REPLACE="${BASE_PATH:-}"
UI_DIST_DIR="/opt/maintainerr/apps/server/dist/ui"
BASE_PATH_MARKER="/opt/maintainerr/.base-path-applied"

if [[ ! -d "$UI_DIST_DIR" ]]; then
  echo "Missing UI build directory: $UI_DIST_DIR" >&2
  exit 1
fi

if grep -R -q -- '/__PATH_PREFIX__' "$UI_DIST_DIR"; then
  ESCAPED_BASE_PATH="${BASE_PATH_REPLACE//\\/\\\\}"
  ESCAPED_BASE_PATH="${ESCAPED_BASE_PATH//&/\\&}"
  if ! find "$UI_DIST_DIR" -type f -not -path '*/node_modules/*' -print0 | xargs -0 sed -i "s,/__PATH_PREFIX__,$ESCAPED_BASE_PATH,g"; then
    echo "Failed to rewrite UI base paths under $UI_DIST_DIR" >&2
    exit 1
  fi
  printf '%s' "$BASE_PATH_REPLACE" >"$BASE_PATH_MARKER"
elif [[ -f "$BASE_PATH_MARKER" ]]; then
  APPLIED_BASE_PATH="$(cat "$BASE_PATH_MARKER")"
  if [[ "$APPLIED_BASE_PATH" != "$BASE_PATH_REPLACE" ]]; then
    echo "BASE_PATH changed from '$APPLIED_BASE_PATH' to '$BASE_PATH_REPLACE', but UI assets were already rewritten. Rebuild Maintainerr to apply a new BASE_PATH." >&2
    exit 1
  fi
else
  # Compatibility path for installs created before marker tracking existed.
  printf '%s' "$BASE_PATH_REPLACE" >"$BASE_PATH_MARKER"
fi

exec npm run --prefix /opt/maintainerr/apps/server start
EOF
chmod +x /opt/maintainerr/start.sh
msg_ok "Created Start Script"

msg_info "Configuring Maintainerr"
cat <<'EOF' >/etc/maintainerr/maintainerr.conf
UI_PORT=6246
UI_HOSTNAME=0.0.0.0
VERSION_TAG=stable
DEBUG=false
BASE_PATH=
EOF
msg_ok "Configured Maintainerr"

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/maintainerr.service
[Unit]
Description=Maintainerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/maintainerr/maintainerr.conf
Environment=NODE_ENV=production
Type=simple
Restart=on-failure
RestartSec=5
WorkingDirectory=/opt/maintainerr
ExecStart=/opt/maintainerr/start.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now maintainerr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
