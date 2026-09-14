#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yusuf Gundogdu (yusuf-gundogdu)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://libredb.org

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# The .deb ships the standalone server with its own bundled Node runtime under
# /usr/lib/libredb-studio/node/bin/node, so setup_nodejs is not needed.
#
# The release carries two .deb files per architecture: the server package and
# libredb-studio-desktop. The asset pattern below keeps them apart. Resolve the
# architecture first and fail on an unknown one: an empty value would widen the
# pattern, and the engine would then fall back to the first .deb it finds, which
# is the desktop package.
ARCH="$(arch_resolve)" || {
  msg_error "Could not resolve the container architecture"
  exit 1
}
fetch_and_deploy_gh_release "libredb-studio" "libredb/libredb-studio" \
  "binary" "latest" "" "libredb-studio_*_${ARCH}.deb"
if [[ ! -x /usr/bin/libredb-studio ]] || [[ ! -f /usr/lib/systemd/system/libredb-studio.service ]]; then
  msg_error "The installed package is not the server build"
  exit 1
fi

msg_info "Configuring ${APPLICATION}"
JWT_SECRET="$(openssl rand -hex 32)"
ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)"
if [[ -z "$JWT_SECRET" ]] || [[ -z "$ADMIN_PASSWORD" ]]; then
  msg_error "Secret generation failed"
  exit 1
fi
mkdir -p /etc/libredb-studio
# /etc/libredb-studio/env is a dpkg conffile. Writing it in place would leave a
# half-written file behind on an interrupt, and dpkg would then keep that broken
# copy through every later upgrade. Write a temporary file and move it into
# place instead, so the file is either the old one or the complete new one.
(
  umask 077
  cat <<EOF >/etc/libredb-studio/env.tmp
# The packaged unit binds to loopback by default. An LXC is reached over the
# network, so bind to every interface here.
HOSTNAME=0.0.0.0
PORT=3000
# Plain HTTP on a LAN address. In production the app marks the auth cookie
# Secure for any non-loopback host, the browser then drops it, and the login
# page returns after every successful login with nothing written to the log.
AUTH_COOKIE_SECURE=false
# Explicit credentials instead of the zero-config first run, which generates a
# password and prints it to the journal once.
AUTH_BOOTSTRAP=off
JWT_SECRET=${JWT_SECRET}
ADMIN_EMAIL=admin@libredb.org
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF
)
mv /etc/libredb-studio/env.tmp /etc/libredb-studio/env
msg_ok "Configured ${APPLICATION}"

msg_info "Starting Service"
systemctl enable -q --now libredb-studio
msg_ok "Started Service"

motd_ssh
customize
cleanup_lxc
