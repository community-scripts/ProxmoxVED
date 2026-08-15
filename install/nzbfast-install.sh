#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: nzbfast (nzbfast)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nzbfast/nzbfast

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# No dependency block: nzbfast is one statically linked binary. RAR
# extraction, PAR2 verify and Reed-Solomon repair are all native, so there is
# no unrar, par2 or 7z to install.

fetch_and_deploy_gh_release "nzbfast" "nzbfast/nzbfast" "prebuild" "latest" "/opt/nzbfast" "nzbfast-*-linux-$(arch_resolve x64 arm64).tar.gz"

msg_info "Setting up nzbfast"
# The tarball wraps its payload in a versioned directory, and releases up to
# 1.1.2 also carry macOS AppleDouble siblings (._name). Those extra top-level
# entries stop the deploy helper collapsing the wrapper, so the binary lands a
# level down. Flatten it and drop the resource forks; both are no-ops on a
# tarball that does not have the problem.
find /opt/nzbfast -name '._*' -delete
if [[ ! -f /opt/nzbfast/nzbfast ]]; then
  nzbfast_wrapper="$(find /opt/nzbfast -mindepth 1 -maxdepth 1 -type d -name 'nzbfast-*' -print -quit)"
  if [[ -n "$nzbfast_wrapper" ]]; then
    mv "$nzbfast_wrapper"/* /opt/nzbfast/
    rmdir "$nzbfast_wrapper"
  fi
fi
chmod +x /opt/nzbfast/nzbfast
msg_ok "Set up nzbfast"

msg_info "Creating Service"
mkdir -p /opt/nzbfast_data/{downloads,watch}
cat <<EOF >/etc/systemd/system/nzbfast.service
[Unit]
Description=nzbfast Usenet downloader
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nzbfast_data
# This install is managed by the community script, which owns the update
# (see update_script in ct/nzbfast.sh). Marking it bundled stops nzbfast
# self-swapping its own binary underneath that; it still reports when a
# newer release is out.
Environment=NZBFAST_BUNDLED=1
ExecStart=/opt/nzbfast/nzbfast serve \\
    --config /opt/nzbfast_data/config.json \\
    --port 6789 \\
    --out /opt/nzbfast_data/downloads \\
    --watch /opt/nzbfast_data/watch \\
    --index-db /opt/nzbfast_data/index.db
Restart=on-failure
RestartSec=5
# config.json holds the Usenet provider password and the sibling apikey file
# is the credential every *arr authenticates with, so nothing the daemon
# creates should inherit a world-readable 0022.
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nzbfast
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
