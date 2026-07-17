#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://castopod.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  caddy \
  expect
msg_ok "Installed Dependencies"

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULES="curl,exif,gd,intl,mbstring,mysql,xml,zip" setup_php
setup_ffmpeg
setup_mariadb
MARIADB_DB_NAME="castopod" MARIADB_DB_USER="castopod" setup_mariadb_db

GITLAB_URL="https://code.castopod.org" fetch_and_deploy_gl_release \
  "castopod" \
  "adaures/castopod" \
  "prebuild" \
  "latest" \
  "/opt/castopod" \
  "castopod-*.tar.gz"

cd /
msg_info "Configuring Castopod"

mkdir -p \
  /opt/castopod/public/media \
  /opt/castopod/writable

CASTOPOD_SALT="$(openssl rand -hex 32)"

cat <<EOF >/opt/castopod/.env
app.baseURL="http://${LOCAL_IP}/"
media.baseURL="http://${LOCAL_IP}/media/"
admin.gateway="cp-admin"
auth.gateway="cp-auth"
analytics.salt="${CASTOPOD_SALT}"

database.default.hostname="127.0.0.1"
database.default.database="${MARIADB_DB_NAME}"
database.default.username="${MARIADB_DB_USER}"
database.default.password="${MARIADB_DB_PASS}"
database.default.DBPrefix="cp_"

cache.handler="file"
EOF

chown root:www-data /opt/castopod/.env
chmod 640 /opt/castopod/.env

chown -R www-data:www-data \
  /opt/castopod/public/media \
  /opt/castopod/writable

msg_ok "Configured Castopod"

msg_info "Initializing Castopod Database"

cd /opt/castopod
$STD runuser -u www-data -- php spark install:init-database

cd /
msg_ok "Initialized Castopod Database"

msg_info "Creating Castopod Superadmin"

CASTOPOD_ADMIN_USERNAME="admin"
CASTOPOD_ADMIN_EMAIL="admin@castopod.local"
CASTOPOD_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"

export CASTOPOD_ADMIN_USERNAME
export CASTOPOD_ADMIN_EMAIL
export CASTOPOD_ADMIN_PASSWORD

cat >/tmp/create-castopod-superadmin.exp <<'EOF'
#!/usr/bin/expect -f

set timeout 120

set username $env(CASTOPOD_ADMIN_USERNAME)
set email    $env(CASTOPOD_ADMIN_EMAIL)
set password $env(CASTOPOD_ADMIN_PASSWORD)

spawn runuser -u www-data -- php /opt/castopod/spark install:create-superadmin

expect {
    -re "(?i)user(name)?.*:" {
        send -- "$username\r"
        exp_continue
    }
    -re "(?i)e-?mail.*:" {
        send -- "$email\r"
        exp_continue
    }
    -re "(?i)(confirm|repeat|again|confirmation).*password.*:" {
        send -- "$password\r"
        exp_continue
    }
    -re "(?i)password.*:" {
        send -- "$password\r"
        exp_continue
    }
    -re "(?i)(yes/no|y/n).*:" {
        send -- "yes\r"
        exp_continue
    }
    eof
}

catch wait result
set exit_code [lindex $result 3]
exit $exit_code
EOF

chmod 700 /tmp/create-castopod-superadmin.exp
$STD /usr/bin/expect /tmp/create-castopod-superadmin.exp
rm -f /tmp/create-castopod-superadmin.exp

cat <<EOF >/root/.castopod.credentials
Castopod URL: http://${LOCAL_IP}/cp-admin
Username: ${CASTOPOD_ADMIN_USERNAME}
Email: ${CASTOPOD_ADMIN_EMAIL}
Password: ${CASTOPOD_ADMIN_PASSWORD}
EOF

chmod 600 /root/.castopod.credentials

unset CASTOPOD_ADMIN_USERNAME
unset CASTOPOD_ADMIN_EMAIL
unset CASTOPOD_ADMIN_PASSWORD

cd /
msg_ok "Created Castopod Superadmin"

msg_info "Configuring Caddy"

PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
PHP_FPM_SERVICE="php${PHP_VER}-fpm"
PHP_FPM_SOCKET="/run/php/php${PHP_VER}-fpm.sock"

cat <<EOF >/etc/caddy/Caddyfile
:80 {
    root * /opt/castopod/public
    encode gzip
    php_fastcgi unix/${PHP_FPM_SOCKET}
    file_server
}
EOF

usermod -aG www-data caddy

$STD caddy fmt --overwrite /etc/caddy/Caddyfile
$STD caddy validate \
  --config /etc/caddy/Caddyfile \
  --adapter caddyfile

msg_ok "Configured Caddy"

msg_info "Creating Scheduled Tasks"

cat <<'EOF' >/etc/cron.d/castopod
* * * * * www-data cd /opt/castopod && /usr/bin/php spark tasks:run >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/castopod

msg_ok "Created Scheduled Tasks"

msg_info "Starting Services"

systemctl enable -q "$PHP_FPM_SERVICE" caddy
systemctl restart "$PHP_FPM_SERVICE"
systemctl restart caddy
msg_ok "Started Services"

motd_ssh
customize
cleanup_lxc
