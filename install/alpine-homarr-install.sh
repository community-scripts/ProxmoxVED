#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/homarr-labs/homarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add --no-cache \
  redis \
  nginx \
  ca-certificates \
  openssl \
  jq \
  make \
  g++ \
  gettext \
  libstdc++ \
  libgcc \
  python3 \
  py3-pip
msg_ok "Installed Dependencies"

NODE_VERSION=$(curl -s https://raw.githubusercontent.com/homarr-labs/homarr/dev/package.json | jq -r '.engines.node | split(">=")[1] | split(".")[0]')
NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/homarr-labs/homarr/dev/package.json | jq -r '.packageManager | split("@")[1]')"
install_node_and_modules
fetch_and_deploy_gh_release "homarr-labs/homarr"

msg_info "Installing Homarr"
mkdir -p /opt/homarr_db
touch /opt/homarr_db/db.sqlite
SECRET_ENCRYPTION_KEY="$(openssl rand -hex 32)"
cd /opt/homarr
cat <<EOF >/opt/homarr/.env
DB_DRIVER='better-sqlite3'
DB_DIALECT='sqlite'
SECRET_ENCRYPTION_KEY='${SECRET_ENCRYPTION_KEY}'
DB_URL='/opt/homarr_db/db.sqlite'
TURBO_TELEMETRY_DISABLED=1
AUTH_PROVIDERS='credentials'
NODE_ENV='production'
EOF

$STD pnpm install
$STD pnpm build
msg_ok "Installed Homarr"

msg_info "Copying build and config files"
cp /opt/homarr/apps/nextjs/next.config.ts .
cp /opt/homarr/apps/nextjs/package.json .
cp -r /opt/homarr/packages/db/migrations /opt/homarr_db/migrations
cp -r /opt/homarr/apps/nextjs/.next/standalone/* /opt/homarr
mkdir -p /appdata/redis
cp /opt/homarr/packages/redis/redis.conf /opt/homarr/redis.conf
mkdir -p /etc/nginx/templates
cp /opt/homarr/nginx.conf /etc/nginx/templates/nginx.conf
mkdir -p /opt/homarr/apps/cli
cp /opt/homarr/packages/cli/cli.cjs /opt/homarr/apps/cli/cli.cjs
echo -e '#!/bin/sh\ncd /opt/homarr/apps/cli && node ./cli.cjs "$@"' >/usr/bin/homarr
chmod +x /usr/bin/homarr
mkdir -p /opt/homarr/build
cp ./node_modules/better-sqlite3/build/Release/better_sqlite3.node ./build/better_sqlite3.node
echo "${RELEASE}" >"/opt/${APPLICATION}_version.txt"
msg_ok "Finished copying"

msg_info "Creating run script"
cat <<'EOF' >/opt/run_homarr.sh
#!/bin/sh
set -a
. /opt/homarr/.env
set +a
export DB_DIALECT='sqlite'
export AUTH_SECRET=$(openssl rand -base64 32)
node /opt/homarr_db/migrations/$DB_DIALECT/migrate.cjs /opt/homarr_db/migrations/$DB_DIALECT
for dir in $(find /opt/homarr_db/migrations/migrations -mindepth 1 -maxdepth 1 -type d); do
  dirname=$(basename "$dir")
  mkdir -p "/opt/homarr_db/migrations/$dirname"
  cp -r "$dir"/* "/opt/homarr_db/migrations/$dirname/" 2>/dev/null || true
done
export HOSTNAME=$(ip route get 1.1.1.1 | awk '/src/ { print $7 }')
envsubst '${HOSTNAME}' < /etc/nginx/templates/nginx.conf > /etc/nginx/nginx.conf
nginx -g 'daemon off;' &
redis-server /opt/homarr/redis.conf &
node apps/tasks/tasks.cjs &
node apps/websocket/wssServer.cjs &
node apps/nextjs/server.js & PID=$!
wait $PID
EOF
chmod +x /opt/run_homarr.sh
msg_ok "Created run script"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/v${RELEASE}.zip
msg_ok "Cleaned"
