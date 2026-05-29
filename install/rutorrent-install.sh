#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trawis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Novik/ruTorrent

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Passed in from ct script via build.func environment
RUTORRENT_USER="${RUTORRENT_USER:-rutorrent}"
RUTORRENT_PASS="${RUTORRENT_PASS:-}"
RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS:-}"
RUTORRENT_ENABLE_RPC2="${RUTORRENT_ENABLE_RPC2:-no}"
RUTORRENT_ENABLE_REAL_IP="${RUTORRENT_ENABLE_REAL_IP:-no}"
RUTORRENT_MAX_UPLOAD_MB="${RUTORRENT_MAX_UPLOAD_MB:-32}"
RUTORRENT_SERVICE_USER="${RUTORRENT_SERVICE_USER:-torrent}"

msg_info "Installing Dependencies"
$STD apt install -y \
  screen \
  rtorrent \
  nginx \
  openssl \
  apache2-utils \
  curl \
  unrar-free \
  mediainfo \
  ffmpeg \
  python3 \
  python3-cloudscraper \
  python-is-python3 \
  sox
msg_ok "Installed Dependencies"

PHP_FPM="YES" setup_php
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

msg_info "Creating ${RUTORRENT_SERVICE_USER} user"
useradd -r -s /bin/false -d /var/lib/rtorrent -m "${RUTORRENT_SERVICE_USER}" 2>/dev/null || true
usermod -aG "${RUTORRENT_SERVICE_USER}" www-data 2>/dev/null || true
msg_ok "Created ${RUTORRENT_SERVICE_USER} user"

msg_info "Setting up directories"
mkdir -p /var/lib/rtorrent/{downloads,session,.watch}
chown -R "${RUTORRENT_SERVICE_USER}:${RUTORRENT_SERVICE_USER}" /var/lib/rtorrent
chmod 750 /var/lib/rtorrent
for i in "" 2 3 4 5 6 7 8; do
  mp="/data${i}"
  if [[ -d "${mp}" ]]; then
    chown "${RUTORRENT_SERVICE_USER}:${RUTORRENT_SERVICE_USER}" "${mp}" 2>/dev/null || true
    chmod 750 "${mp}" 2>/dev/null || true
  fi
done
msg_ok "Set up directories"

fetch_and_deploy_gh_release "rutorrent" "Novik/ruTorrent" "tarball" "latest" "/var/www/rutorrent"
chown -R www-data:www-data /var/www/rutorrent

msg_info "Patching filedrop upload limit"
FILEDROP_CONF=/var/www/rutorrent/plugins/filedrop/conf.php
if [[ -f "${FILEDROP_CONF}" ]]; then
  UPLOAD_BYTES=$(( RUTORRENT_MAX_UPLOAD_MB * 1024 * 1024 ))
  FILEDROP_PAT='\(\$maxFileSize\s*=\s*\)'
  sed -i "s/${FILEDROP_PAT}[0-9]*/\1${UPLOAD_BYTES}/" "${FILEDROP_CONF}"
fi
msg_ok "Patched filedrop (${RUTORRENT_MAX_UPLOAD_MB} MiB)"

msg_info "Generating plugins.ini"
PLUGINS_DIR=/var/www/rutorrent/plugins
PLUGINS_INI="/var/www/rutorrent/conf/plugins.ini"

declare -A _ENABLED=()
IFS=',' read -ra _SEL <<<"${RUTORRENT_PLUGINS}"
for slug in "${_SEL[@]}"; do
  [[ -n "${slug}" ]] && _ENABLED["${slug}"]=1
done

for plugin_dir in "${PLUGINS_DIR}"/_*/; do
  slug=$(basename "${plugin_dir}")
  [[ -f "${plugin_dir}/init.js" ]] && _ENABLED["${slug}"]=1
done

: >"${PLUGINS_INI}"
for plugin_dir in "${PLUGINS_DIR}"/*/; do
  slug=$(basename "${plugin_dir}")
  [[ -f "${plugin_dir}/init.js" ]] || continue
  if [[ "${_ENABLED[${slug}]+_}" ]]; then
    printf '[%s]\nenabled = yes\n\n' "${slug}" >>"${PLUGINS_INI}"
  else
    printf '[%s]\nenabled = no\n\n' "${slug}" >>"${PLUGINS_INI}"
  fi
done
chown www-data:www-data "${PLUGINS_INI}"
msg_ok "Generated plugins.ini"

msg_info "Configuring rTorrent"
RTORRENT_RC=/var/lib/rtorrent/.rtorrent.rc
cat <<EOF >"${RTORRENT_RC}"
directory.default.set = /var/lib/rtorrent/downloads
session.path.set = /var/lib/rtorrent/session
network.scgi.open_local = /run/rtorrent/rtorrent.sock
network.port_range.set = 6881-6881
network.port_random.set = no
pieces.hash.on_completion.set = no
schedule2 = watch_directory,5,5,load.start=/var/lib/rtorrent/.watch/*.torrent
execute.nothrow = chmod,770,/run/rtorrent/rtorrent.sock
EOF
chown "${RUTORRENT_SERVICE_USER}:${RUTORRENT_SERVICE_USER}" "${RTORRENT_RC}"

cat <<EOF >/etc/systemd/system/rtorrent.service
[Unit]
Description=rTorrent via screen
After=network.target

[Service]
User=${RUTORRENT_SERVICE_USER}
Group=${RUTORRENT_SERVICE_USER}
Type=forking
KillMode=none
RuntimeDirectory=rtorrent
RuntimeDirectoryMode=0750
ExecStart=/usr/bin/screen -d -m -S rtorrent /usr/bin/rtorrent
ExecStop=/usr/bin/bash -c 'screen -S rtorrent -X quit || true'
WorkingDirectory=/var/lib/rtorrent
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Configured rTorrent"

msg_info "Configuring ruTorrent"
cat <<'EOF' >/var/www/rutorrent/conf/config.php
<?php
$topDirectory = '/var/lib/rtorrent/downloads';
$scgi_port = 0;
$scgi_host = "unix:///run/rtorrent/rtorrent.sock";
$XMLRPCMountPoint = "/RPC2";
$pathToExternals = array(
    "php"   => "",
    "curl"  => "",
    "gzip"  => "",
    "id"    => "",
    "stat"  => "",
);
$localhosts = array("127.0.0.1", "localhost");
$tempDirectory = null;
$canUseXSendFile = false;
$locale = "UTF-8";
EOF
chown www-data:www-data /var/www/rutorrent/conf/config.php
msg_ok "Configured ruTorrent"

msg_info "Setting up HTTP basic auth"
[[ -z "${RUTORRENT_PASS}" ]] && RUTORRENT_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
htpasswd -bc /etc/nginx/.rutorrent_htpasswd "${RUTORRENT_USER}" "${RUTORRENT_PASS}"
chmod 640 /etc/nginx/.rutorrent_htpasswd
chown root:www-data /etc/nginx/.rutorrent_htpasswd
msg_ok "Configured HTTP basic auth"

msg_info "Configuring PHP-FPM pool"
PHP_POOL_DIR="/etc/php/${PHP_VER}/fpm/pool.d"
cat <<EOF >"${PHP_POOL_DIR}/rutorrent.conf"
[rutorrent]
user = www-data
group = www-data
listen = /run/php/rutorrent-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
php_admin_value[error_reporting] = E_ERROR
EOF
rm -f "${PHP_POOL_DIR}/www.conf"
msg_ok "Configured PHP-FPM pool"

msg_info "Configuring PHP upload limit"
PHP_CONF_D="/etc/php/${PHP_VER}/fpm/conf.d"
cat <<EOF >"${PHP_CONF_D}/99-rutorrent-upload.ini"
upload_max_filesize = ${RUTORRENT_MAX_UPLOAD_MB}M
post_max_size = ${RUTORRENT_MAX_UPLOAD_MB}M
EOF
msg_ok "Configured PHP upload limit (${RUTORRENT_MAX_UPLOAD_MB} MiB)"

msg_info "Configuring nginx"
if [[ "${RUTORRENT_ENABLE_RPC2}" == "yes" ]]; then
  RPC2_LOCATION="
    location /RPC2 {
        include scgi_params;
        scgi_pass unix:///run/rtorrent/rtorrent.sock;
    }
"
else
  RPC2_LOCATION=""
fi

if [[ "${RUTORRENT_ENABLE_REAL_IP}" == "yes" ]]; then
  REAL_IP_BLOCK="
    set_real_ip_from 127.0.0.1;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
"
else
  REAL_IP_BLOCK=""
fi

cat <<EOF >/etc/nginx/sites-available/rutorrent
server {
    listen 80;
    server_name _;

    root /var/www/rutorrent;
    index index.html index.php;

    client_max_body_size ${RUTORRENT_MAX_UPLOAD_MB}M;

    auth_basic "ruTorrent";
    auth_basic_user_file /etc/nginx/.rutorrent_htpasswd;
${REAL_IP_BLOCK}${RPC2_LOCATION}
    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/rutorrent-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
ln -sf /etc/nginx/sites-available/rutorrent /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
msg_ok "Configured nginx"

msg_info "Starting services"
systemctl enable -q --now rtorrent

for i in {1..15}; do
  [[ -S /run/rtorrent/rtorrent.sock ]] && break
  sleep 1
done
[[ -S /run/rtorrent/rtorrent.sock ]] \
  || msg_warn "rTorrent socket not found after 15 s — check 'systemctl status rtorrent'"

systemctl restart "php${PHP_VER}-fpm"
systemctl enable -q nginx
systemctl restart nginx
msg_ok "Started services"

msg_info "Writing credentials"
{
  echo "ruTorrent Credentials"
  echo "====================="
  echo "URL:      http://$(hostname -I | awk '{print $1}')/"
  echo "Username: ${RUTORRENT_USER}"
  echo "Password: ${RUTORRENT_PASS}"
} >~/rutorrent.creds
chmod 600 ~/rutorrent.creds
msg_ok "Credentials written to ~/rutorrent.creds"

motd_ssh
customize
cleanup_lxc
