#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joost van den Berg
# License: MIT | https://github.com/montagneid/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/umbraco/Umbraco-CMS

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_project_name="cms"

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
  curl \
  wget \
  ca-certificates \
  uuid-runtime

msg_info "Installing .NET SDK 10.0 using Microsoft install script"
wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
$STD ./dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet
rm dotnet-install.sh
ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
export DOTNET_ROOT=/usr/share/dotnet
export PATH=$PATH:$DOTNET_ROOT
msg_ok "Installed .NET SDK 10.0"

msg_info "Installing Nginx and FTP Server"
$STD apt-get install -y \
  nginx \
  vsftpd
msg_ok "Installed Nginx and FTP Server"

read -r -p "${TAB3}Enable PostgreSQL database (allow remote connections)? (Default: SQLite) <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Setting up PostgreSQL (Patience)"
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="${var_project_name}_db" PG_DB_USER="${var_project_name}_user" PG_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  setup_postgresql_db
  sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/17/main/postgresql.conf
  echo "host    all             all             0.0.0.0/0               scram-sha-256" >> /etc/postgresql/17/main/pg_hba.conf
  systemctl restart postgresql
  msg_ok "PostgreSQL setup completed"
fi

msg_info "Installing dotnet Umbraco templates and create project (Patience)"
cd /var/www/html
$STD dotnet new install Umbraco.Templates
$STD dotnet new umbraco --force -n "$var_project_name"
msg_ok "Umbraco templates installed and project created"

msg_info "Configuring database connection and unattended setup"
cd /var/www/html/$var_project_name
UMBRACO_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
apt-get install -y jq &>/dev/null

if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  $STD dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
  $STD dotnet add package Our.Umbraco.PostgreSql
  jq --arg dbname "$PG_DB_NAME" \
    --arg dbuser "$PG_DB_USER" \
    --arg dbpass "$PG_DB_PASS" '. + {
    "ConnectionStrings": {
      "umbracoDbDSN": ("Host=localhost;Port=5432;SSL Mode=Allow;Database=" + $dbname + ";Username=" + $dbuser + ";Password=" + $dbpass),
      "umbracoDbDSN_ProviderName": "Npgsql2"
    }
  }' /var/www/html/$var_project_name/appsettings.json > /tmp/appsettings.tmp && mv /tmp/appsettings.tmp /var/www/html/$var_project_name/appsettings.json
else
  jq '. + {
    "ConnectionStrings": {
      "umbracoDbDSN": "Data Source=|DataDirectory|/Umbraco.sqlite.db;Cache=Shared;Foreign Keys=True;Pooling=True",
      "umbracoDbDSN_ProviderName": "Microsoft.Data.Sqlite"
    }
  }' /var/www/html/$var_project_name/appsettings.json > /tmp/appsettings.tmp && mv /tmp/appsettings.tmp /var/www/html/$var_project_name/appsettings.json
fi

jq --arg umbracopass "$UMBRACO_PASS" '. + {
  "Umbraco": {
    "CMS": {
      "_Comment": "Remove the Unattended section after first run",    
      "Unattended": {
        "InstallUnattended": true,
        "UnattendedUserName": "admin",
        "UnattendedUserEmail": "admin@umbraco.local",
        "UnattendedUserPassword": $umbracopass
      }
    }
  }
}' /var/www/html/$var_project_name/appsettings.json > /tmp/appsettings.tmp && mv /tmp/appsettings.tmp /var/www/html/$var_project_name/appsettings.json
ln -sf /var/www/html/$var_project_name/appsettings.json ~/umbraco.creds
msg_ok "Database connection and unattended setup configured"

msg_info "Setting up Nginx Server"
rm -f /var/www/html/index.nginx-debian.html

cat <<EOF >/etc/nginx/sites-available/default
map \$http_connection \$connection_upgrade {
  "~*Upgrade" \$http_connection;
  default keep-alive;
}
server {
  listen 443 ssl default_server;
  listen [::]:443 ssl default_server;
  ssl_certificate /etc/nginx/certificate/nginx-certificate.crt;
  ssl_certificate_key /etc/nginx/certificate/nginx.key;
  location / {
      proxy_pass         https://127.0.0.1:7000/;
      proxy_http_version 1.1;
      proxy_set_header   Upgrade \$http_upgrade;
      proxy_set_header   Connection \$connection_upgrade;
      proxy_set_header   Host \$host;
      proxy_cache_bypass \$http_upgrade;
      proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto \$scheme;
      proxy_buffering on;
      proxy_buffer_size 16k;
      proxy_buffers 8 32k;
      proxy_busy_buffers_size 64k;
  }
}
EOF

mkdir /etc/nginx/certificate
cd /etc/nginx/certificate
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes -out nginx-certificate.crt -keyout nginx.key -subj "/C=NL/ST=State/L=City/O=Organization/CN=localhost" &>/dev/null

systemctl reload nginx
msg_ok "Nginx Server created"

msg_info "Creating Kestrel Umbraco Service"
cat <<EOF >/usr/local/bin/umbraco-start.sh
#!/usr/bin/env bash
/usr/bin/dotnet /var/www/html/$var_project_name-publish/$var_project_name.dll --urls "https://0.0.0.0:7000" &
EOF
chmod +x /usr/local/bin/umbraco-start.sh

cat <<EOF >/etc/systemd/system/umbraco-kestrel.service
[Unit]
Description=Umbraco CMS running on Linux

[Service]
WorkingDirectory=/var/www/html/$var_project_name-publish
ExecStart=/usr/local/bin/umbraco-start.sh
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=umbraco
User=root
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_NOLOGO=true
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now umbraco-kestrel
msg_ok "Umbraco Kestrel Service created"

msg_info "Creating dotnet publish script"
cat <<EOF >/var/www/html/$var_project_name/publish.sh
#!/usr/bin/env bash
cd /var/www/html/$var_project_name
systemctl stop umbraco-kestrel.service
dotnet publish -c Release -o /var/www/html/$var_project_name-publish
systemctl start umbraco-kestrel.service
EOF
chmod +x /var/www/html/$var_project_name/publish.sh
msg_ok "Dotnet publish script created"

msg_info "Building and publishing project (Patience)"
$STD /var/www/html/$var_project_name/publish.sh
msg_ok "Umbraco published successfully to /var/www/html/$var_project_name-publish"

msg_info "Setting up FTP Server"
useradd ftpuser
FTP_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
usermod --password $(echo ${FTP_PASS} | openssl passwd -1 -stdin) ftpuser
mkdir -p /var/www/html
usermod -d /var/www/html ftp
usermod -d /var/www/html ftpuser
chown -R ftpuser:ftpuser /var/www/html

sed -i "s|#write_enable=YES|write_enable=YES|g" /etc/vsftpd.conf
sed -i "s|#chroot_local_user=YES|chroot_local_user=NO|g" /etc/vsftpd.conf

systemctl restart -q vsftpd.service

{
  echo "FTP Credentials"
  echo "Username: ftpuser"
  echo "Password: $FTP_PASS"
} >>~/ftp.creds
msg_ok "FTP server setup completed"

msg_info "Creating Visual Studio FTP Publish Profile"
PROJECT_GUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
CONTAINER_IP=$(hostname -I | awk '{print $1}')
PUBLISH_PROFILE_DIR="/var/www/html/${var_project_name}/Properties/PublishProfiles"
mkdir -p "$PUBLISH_PROFILE_DIR"

cat >"$PUBLISH_PROFILE_DIR/FTPProfile.pubxml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <PropertyGroup>
    <WebPublishMethod>FTP</WebPublishMethod>
    <LaunchSiteAfterPublish>true</LaunchSiteAfterPublish>
    <LastUsedBuildConfiguration>Release</LastUsedBuildConfiguration>
    <LastUsedPlatform>Any CPU</LastUsedPlatform>
    <SiteUrlToLaunchAfterPublish>https://${CONTAINER_IP}</SiteUrlToLaunchAfterPublish>
    <ExcludeApp_Data>false</ExcludeApp_Data>
    <ProjectGuid>${PROJECT_GUID}</ProjectGuid>
    <publishUrl>${CONTAINER_IP}</publishUrl>
    <DeleteExistingFiles>true</DeleteExistingFiles>
    <FtpPassiveMode>true</FtpPassiveMode>
    <FtpSitePath>${var_project_name}-publish</FtpSitePath>
    <UserName>ftpuser</UserName>
    <_SavePWD>true</_SavePWD>
    <_TargetId>FTP</_TargetId>
  </PropertyGroup>
</Project>
EOF
msg_ok "Publish Profile created"

motd_ssh
customize
cleanup_lxc
