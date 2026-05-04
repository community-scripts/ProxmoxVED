#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://gitea.com/gitea/act_runner

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="GiteaActRunner"

msg_info "Installing Dependencies"
$STD apk add --no-cache curl jq tar bash
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
$STD apk add --no-cache docker docker-cli-compose
$STD rc-update add docker default
$STD rc-service docker start
msg_ok "Installed Docker"

msg_info "Fetching latest act_runner release"
RELEASE=$(curl -fsSL https://gitea.com/api/v1/repos/gitea/act_runner/releases | jq -r '.[0].tag_name')
if [[ -z "${RELEASE}" || "${RELEASE}" == "null" ]]; then
  msg_error "Unable to fetch latest release tag"
  exit 1
fi
VERSION="${RELEASE#v}"

ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  armv7l)  ARCH="armv7" ;;
  *) msg_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac
msg_ok "Latest release: ${RELEASE} (${ARCH})"

msg_info "Installing act_runner ${RELEASE}"
curl -fsSL "https://gitea.com/gitea/act_runner/releases/download/${RELEASE}/act_runner-${VERSION}-linux-${ARCH}" -o /usr/local/bin/act_runner
chmod +x /usr/local/bin/act_runner
ln -sf /usr/local/bin/act_runner /usr/bin/act_runner
msg_ok "Installed act_runner"

msg_info "Creating gitea-runner user"
adduser -S -D -H -h /var/lib/gitea-runner -s /bin/bash -G docker gitea-runner
$STD addgroup gitea-runner docker || true
mkdir -p /var/lib/gitea-runner
chown -R gitea-runner:docker /var/lib/gitea-runner
msg_ok "Created gitea-runner user"

msg_info "Creating OpenRC service"
cat <<'EOF' >/etc/init.d/gitea-runner
#!/sbin/openrc-run

name="Gitea Act Runner"
description="Gitea Actions Runner (act_runner)"
command="/usr/local/bin/act_runner"
command_args="daemon"
command_user="gitea-runner"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
directory="/var/lib/gitea-runner"

depend() {
  need net docker
  after docker
}

start_pre() {
    export PATH="/usr/local/bin:$PATH"
    checkpath --directory --owner gitea-runner:docker --mode 0755 /var/lib/gitea-runner
}
EOF
chmod +x /etc/init.d/gitea-runner
$STD rc-update add gitea-runner default
msg_ok "Created OpenRC service"

echo "${RELEASE}" >/opt/${APP}_version.txt

motd_ssh
customize

msg_info "Cleaning up"
$STD apk cache clean || true
rm -rf /var/cache/apk/*
msg_ok "Cleaned"
