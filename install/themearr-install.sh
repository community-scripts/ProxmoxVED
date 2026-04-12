#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Themearr
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Themearr/themearr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# =============================================================================
# DEPENDENCIES
# =============================================================================

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  ffmpeg \
  python3
msg_ok "Installed Dependencies"

# =============================================================================
# .NET 9 RUNTIME
# =============================================================================

msg_info "Installing .NET 9 Runtime"
$STD bash -c "curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0 --runtime aspnetcore --install-dir /usr/share/dotnet"
ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
msg_ok "Installed .NET 9 Runtime"

# =============================================================================
# YT-DLP
# =============================================================================

msg_info "Installing yt-dlp"
$STD curl -sSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
  -o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp
msg_ok "Installed yt-dlp"

# =============================================================================
# DOWNLOAD & DEPLOY APPLICATION
# =============================================================================

get_lxc_ip

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_SUFFIX="linux-x64" ;;
  aarch64) ARCH_SUFFIX="linux-arm64" ;;
  *)       msg_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac
fetch_and_deploy_gh_release "themearr" "Themearr/themearr" "prebuild" "latest" "/opt/themearr" "themearr-${ARCH_SUFFIX}.tar.gz"

msg_info "Setting up Application"
mkdir -p /opt/themearr/data
msg_ok "Set up Application"

# =============================================================================
# CREATE SYSTEMD SERVICE
# =============================================================================

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/themearr.service
[Unit]
Description=Themearr Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/themearr
Environment="HOME=/opt/themearr/data"
Environment="XDG_CACHE_HOME=/opt/themearr/data/.cache"
Environment="DB_PATH=/opt/themearr/data/themearr.db"
Environment="THEMEARR_VERSION_FILE=/opt/themearr/VERSION"
Environment="ASPNETCORE_URLS=http://0.0.0.0:8080"
ExecStart=/usr/local/bin/dotnet /opt/themearr/Themearr.API.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now themearr
msg_ok "Created Service"

# =============================================================================
# CLEANUP & FINALIZATION
# =============================================================================

motd_ssh
customize
cleanup_lxc
