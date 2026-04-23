#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tobias Salzmann (Eun)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/cinnyapp/cinny

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add --no-cache \
  nginx
msg_ok "Installed Dependencies"

msg_info "Installing Cinny"
RELEASE=$(curl -fsSL https://api.github.com/repos/cinnyapp/cinny/releases/latest | grep '"tag_name":' | cut -d '"' -f4)
temp_file=$(mktemp)
curl -fsSL "https://github.com/cinnyapp/cinny/releases/download/${RELEASE}/cinny-${RELEASE}.tar.gz" -o "$temp_file"
mkdir -p /usr/share/nginx/html
tar -xzf "$temp_file" --strip-components=1 -C /usr/share/nginx/html
rm -f "$temp_file"
cat <<'EOF' >/etc/nginx/http.d/default.conf
server {
  listen 8080;
  server_name localhost;

  location / {
        root /usr/share/nginx/html/;

        rewrite ^/config.json$ /config.json break;
        rewrite ^/manifest.json$ /manifest.json break;

        rewrite ^/sw.js$ /sw.js break;
        rewrite ^/pdf.worker.min.js$ /pdf.worker.min.js break;

        rewrite ^/public/(.*)$ /public/$1 break;
        rewrite ^/assets/(.*)$ /assets/$1 break;

        rewrite ^(.+)$ /index.html break;
    }
}
EOF
$STD rc-update add nginx default
$STD rc-service nginx start
echo "${RELEASE}" >/opt/"${APPLICATION}"_version.txt
msg_ok "Installed Cinny"

motd_ssh
customize

msg_info "Cleaning up"
$STD apk cache clean
msg_ok "Cleaned"
