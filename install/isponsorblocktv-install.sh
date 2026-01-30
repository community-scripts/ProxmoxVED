#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Matthew Stern (sternma)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/dmunozv04/iSponsorBlockTV

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

INSTALL_DIR="/opt/isponsorblocktv"
DATA_DIR="/var/lib/isponsorblocktv"

msg_info "Installing Dependencies"
$STD apt install -y \
  python3 \
  python3-venv \
  python3-pip
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "isponsorblocktv" "dmunozv04/iSponsorBlockTV"

msg_info "Setting up iSponsorBlockTV"
$STD python3 -m venv "$INSTALL_DIR/venv"
$STD "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
$STD "$INSTALL_DIR/venv/bin/pip" install "$INSTALL_DIR"
msg_ok "Set up iSponsorBlockTV"

msg_info "Creating data directory"
install -d "$DATA_DIR"
msg_ok "Created data directory"

msg_info "Creating Service"
cat <<EOT >/etc/systemd/system/isponsorblocktv.service
[Unit]
Description=iSponsorBlockTV
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=iSPBTV_data_dir=$DATA_DIR
ExecStart=$INSTALL_DIR/venv/bin/iSponsorBlockTV
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
systemctl enable -q --now isponsorblocktv
msg_ok "Created Service"

msg_info "Creating CLI wrapper"
install -d /usr/local/bin
cat <<'EOT' >/usr/local/bin/iSponsorBlockTV
#!/usr/bin/env bash
export iSPBTV_data_dir="/var/lib/isponsorblocktv"

set +e
/opt/isponsorblocktv/venv/bin/iSponsorBlockTV "$@"
status=$?
set -e

case "${1:-}" in
  setup|setup-cli)
    systemctl restart isponsorblocktv >/dev/null 2>&1 || true
    ;;
esac

exit $status
EOT
chmod +x /usr/local/bin/iSponsorBlockTV
ln -sf /usr/local/bin/iSponsorBlockTV /usr/bin/iSponsorBlockTV
msg_ok "Created CLI wrapper"

msg_info "Setting default data dir for shells"
cat <<'EOT' >/etc/profile.d/isponsorblocktv.sh
export iSPBTV_data_dir="/var/lib/isponsorblocktv"
EOT
if ! grep -q '^iSPBTV_data_dir=' /etc/environment 2>/dev/null; then
  cat <<'EOT' >>/etc/environment
iSPBTV_data_dir=/var/lib/isponsorblocktv
EOT
fi
msg_ok "Set default data dir for shells"

motd_ssh
customize
cleanup_lxc
