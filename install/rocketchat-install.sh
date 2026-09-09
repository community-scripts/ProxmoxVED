#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: william-aqn
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.rocket.chat/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Asked up front, before the ~250 MB download and the native-module build, so an
# interactive run is not left sitting on a prompt minutes in. An unattended run
# sets var_admin_email in the environment and is never asked.
if [[ -z "${var_admin_email:-}" ]]; then
  # `|| true` is load-bearing: an unattended run reaches this over lxc-attach
  # with no tty, so read hits EOF and returns 1, which the error trap would
  # otherwise turn into a failed install before anything is downloaded.
  read -r -p "${TAB3}Admin email address: " var_admin_email || true
fi
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  # Rocket.Chat silently drops an invalid ADMIN_EMAIL and leaves the admin with
  # no address at all, which is harder to notice than this warning.
  msg_warn "Invalid email '${var_admin_email}', falling back to admin@example.com"
  var_admin_email="admin@example.com"
fi

msg_info "Installing Dependencies"
# build-essential and python3 are for node-gyp: the bundle compiles native
# modules on install and @sematext/gc-stats has no prebuilt binary to fall back
# on. graphicsmagick is the image backend named by the official Debian guide.
$STD apt install -y \
  build-essential \
  python3 \
  graphicsmagick \
  jq
msg_ok "Installed Dependencies"

# Rocket.Chat 8.x exits on MongoDB <7.0 and warns below 8.0 (support for <8.0 is
# dropped in Rocket.Chat 9). releases.rocket.chat reports 8.0 as the compatible
# series, so that is what gets installed.
MONGO_VERSION="8.0" setup_mongodb

# The server bundle validates only the Node.js MAJOR line against the version it
# was built with (bundle/.node_version.txt, currently v22.x), so the NodeSource
# 22 line satisfies it.
#
# npm is pinned to 10 because the bundle is built with npm 10 and does not
# install under npm 12: npm 12 refuses the bundle's remote tarball dependency
# (EALLOWREMOTE on source-map-support), and the bundle's own npm-rebuild.js
# calls `npm rebuild --update-binary`, a flag npm 12 rejects outright.
NODE_VERSION="22" NPM_VERSION="10" setup_nodejs

msg_info "Configuring MongoDB Replica Set"
# Rocket.Chat requires a replica set: it dropped oplog tailing in 8.0 and now
# relies on change streams and multi-document transactions, neither of which a
# standalone mongod provides. A single member is enough.
if ! grep -q "^replication:" /etc/mongod.conf; then
  cat <<EOF >>/etc/mongod.conf
replication:
  replSetName: rs0
EOF
fi
systemctl restart mongod
for _ in {1..60}; do
  mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null && break
  sleep 1
done
if ! mongosh --quiet --eval "rs.status().ok" &>/dev/null; then
  $STD mongosh --quiet --eval 'rs.initiate({ _id: "rs0", members: [{ _id: 0, host: "127.0.0.1:27017" }] })'
fi
for _ in {1..60}; do
  [[ "$(mongosh --quiet --eval "db.hello().isWritablePrimary" 2>/dev/null)" == "true" ]] && break
  sleep 1
done
msg_ok "Configured MongoDB Replica Set"

# The prebuilt Meteor bundle is published on releases.rocket.chat, not as a
# GitHub release asset, so fetch_and_deploy_gh_release does not apply.
# /latest/info names the current stable tag; the GitHub API cannot be used here
# because backport releases on older majors are published after newer ones and
# would win a "latest" query. The archive unpacks to a single bundle/ directory,
# which fetch_and_deploy_from_url strips into the target.
RELEASE=$(curl -fsSL https://releases.rocket.chat/latest/info | jq -r '.tag')
fetch_and_deploy_from_url "https://releases.rocket.chat/${RELEASE}/download" "/opt/rocketchat"
echo "${RELEASE}" >~/.rocketchat

msg_info "Building Rocket.Chat ${RELEASE} (Patience)"
cd /opt/rocketchat/programs/server || exit
$STD npm install
msg_ok "Built Rocket.Chat ${RELEASE}"

msg_info "Creating Configuration"
# Kept outside /opt/rocketchat so an update, which replaces the bundle
# wholesale, leaves it untouched.
#
# The admin is seeded from the environment and the setup wizard is marked
# completed on purpose. The wizard's last step ("Awaiting confirmation") mails a
# confirmation code, and a fresh bare-metal install has no MAIL_URL, so the mail
# never leaves the box and the wizard cannot be finished from the UI -- the
# admin created in step 1 is then locked out behind it. insertAdminUserFromEnv()
# only fires while no admin exists, so these stay inert on every later boot.
ADMIN_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-24)
mkdir -p /etc/rocketchat
cat <<EOF >/etc/rocketchat/rocketchat.env
NODE_ENV=production
PORT=3000
ROOT_URL=http://${LOCAL_IP}:3000
MONGO_URL=mongodb://127.0.0.1:27017/rocketchat?replicaSet=rs0
ADMIN_USERNAME=admin
ADMIN_NAME=Administrator
ADMIN_EMAIL=${var_admin_email}
ADMIN_PASS=${ADMIN_PASS}
OVERWRITE_SETTING_Show_Setup_Wizard=completed
EOF
chmod 600 /etc/rocketchat/rocketchat.env
{
  echo "Rocket.Chat Admin"
  echo "Username: admin"
  echo "Password: ${ADMIN_PASS}"
  echo "Email: ${var_admin_email}"
} >~/rocketchat.creds
chmod 600 ~/rocketchat.creds
msg_ok "Created Configuration"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rocketchat.service
[Unit]
Description=Rocket.Chat Server
After=network.target mongod.service
Requires=mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rocketchat
EnvironmentFile=/etc/rocketchat/rocketchat.env
ExecStart=/usr/bin/node /opt/rocketchat/main.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rocketchat
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
