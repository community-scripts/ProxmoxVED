#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  make \
  apache2 \
  libapache2-mod-php \
  redis
msg_ok "Installed Dependencies"

setup_mariadb
PHP_VERSION="8.3" PHP_APACHE="YES" PHP_FPM="YES" PHP_MODULE="bcmath,bz2,cli,exif,common,curl,tidy,fpm,gd,intl,mbstring,xml,mysql,zip" setup_php
setup_composer

msg_info "Setting up Database"
DB_NAME=wallabag_db
DB_USER=wallabag
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
SECRET_KEY="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)"
$STD mariadb -u root -e "CREATE DATABASE $DB_NAME;"
$STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
$STD mariadb -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "Wallabag Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
} >>~/wallabag.creds
msg_ok "Set up Database"

fetch_and_deploy_gh_release "wallabag" "wallabag/wallabag" "prebuild" "latest" "/opt/wallabag" "wallabag-*.tar.gz"

msg_info "Installing Wallabag (Patience)"
cd /opt/wallabag
useradd -d /opt/wallabag -s /bin/bash -M wallabag
chown -R wallabag:wallabag /opt/wallabag
mv /opt/wallabag/app/config/parameters.yml.dist /opt/wallabag/app/config/parameters.yml
sed -i \
  -e 's|database_name: wallabag|database_name: wallabag_db|' \
  -e 's|database_port: ~|database_port: 3306|' \
  -e 's|database_user: root|database_user: wallabag|' \
  -e 's|database_password: ~|database_password: '"$DB_PASS"'|' \
  -e 's|secret: .*|secret: '"$SECRET_KEY"'|' \
  /opt/wallabag/app/config/parameters.yml

export COMPOSER_ALLOW_SUPERUSER=1
sudo -u wallabag make install --no-interaction

export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction
msg_ok "Installed Wallabag"

msg_info "Setting up Virtual Host"
cat <<EOF >/etc/nginx/conf.d/wallabag.conf
server {
    root /opt/wallabag/web;
    server_name $IPADDRESS;

    location / {
        # try to serve file directly, fallback to app.php
        try_files $uri /app.php$is_args$args;
    }
    location ~ ^/app\.php(/|$) {
        # if, for some reason, you are still using PHP 5,
        # then replace /run/php/php7.0 by /var/run/php5
        fastcgi_pass unix:/run/php/php7.0-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        # When you are using symlinks to link the document root to the
        # current version of your application, you should pass the real
        # application path instead of the path to the symlink to PHP
        # FPM.
        # Otherwise, PHP's OPcache may not properly detect changes to
        # your PHP files (see https://github.com/zendtech/ZendOptimizerPlus/issues/126
        # for more information).
        fastcgi_param  SCRIPT_FILENAME  $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        # Prevents URIs that include the front controller. This will 404:
        # http://domain.tld/app.php/some-path
        # Remove the internal directive to allow URIs like this
        internal;
    }

    # return 404 for all other php files not matching the front controller
    # this prevents access to other php files you don't want to be accessible.
    location ~ \.php$ {
        return 404;
    }

    error_log /var/log/nginx/wallabag_error.log;
    access_log /var/log/nginx/wallabag_access.log;
}
EOF

$STD a2enmod rewrite
$STD a2ensite wallabag.conf
$STD a2dissite 000-default.conf
systemctl reload apache2
msg_ok "Configured Virtual Host"

msg_info "Setting Permissions"
chown -R www-data:www-data /opt/wallabag/{bin,app/config,vendor,data,var,web}
msg_ok "Set Permissions"

msg_info "Running Wallabag Installation"
php bin/console wallabag:install --env=prod
msg_ok "Wallabag Installed"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
