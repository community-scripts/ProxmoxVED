#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jay Brame (bramej)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Skylark-Software/Janua

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Janua pins the FreeRDP release its guacd patches are built and tested against.
FREERDP_VERSION="3.10.3"
GUAC_VERSION="1.6.0"
PG_CONNECTOR_VERSION="42.7.4"

msg_info "Installing Dependencies"
# Mirrors the Janua guacd build's dependency set (FreeRDP 3 + guacamole-server),
# adapted for Debian 13 (libwebkit2gtk-4.1-dev). Base packages already present
# (curl, gnupg, ca-certificates, sudo) are intentionally not listed.
$STD apt install -y \
  build-essential cmake ninja-build git pkg-config zip \
  libssl-dev libx11-dev libxext-dev libxinerama-dev libxcursor-dev \
  libxkbfile-dev libxv-dev libxi-dev libxdamage-dev libxrandr-dev \
  libxrender-dev libxfixes-dev libasound2-dev libcups2-dev libpulse-dev \
  libjpeg-dev libgsm1-dev libusb-1.0-0-dev libudev-dev libdbus-glib-1-dev \
  uuid-dev libxml2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  libfaad-dev libcairo2-dev libpango1.0-dev libpng-dev libavcodec-dev \
  libavutil-dev libavformat-dev libswscale-dev libswresample-dev \
  libopenh264-dev libx264-dev libpkcs11-helper1-dev libkrb5-dev libcjson-dev \
  libsdl2-dev libsdl2-ttf-dev libfuse3-dev libwebkit2gtk-4.1-dev \
  libpipewire-0.3-dev libtool-bin libvncserver-dev libssh2-1-dev \
  libtelnet-dev libwebsockets-dev libvorbis-dev libwebp-dev
msg_ok "Installed Dependencies"

JAVA_VERSION="17" setup_java
PG_VERSION="16" setup_postgresql

fetch_and_deploy_gh_release "janua" "Skylark-Software/Janua" "tarball" "latest" "/opt/janua/src"

msg_info "Building FreeRDP ${FREERDP_VERSION} (Patience)"
curl -fsSL "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/${FREERDP_VERSION}.tar.gz" -o /tmp/freerdp.tar.gz
mkdir -p /opt/janua/freerdp
tar -xzf /tmp/freerdp.tar.gz --strip-components=1 -C /opt/janua/freerdp
cd /opt/janua/freerdp
$STD cmake -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DWITH_SERVER=ON \
  -DWITH_CHANNELS=ON \
  -DWITH_CLIENT_CHANNELS=ON \
  -DWITH_SERVER_CHANNELS=ON \
  -DCHANNEL_RDPGFX=ON \
  -DCHANNEL_RDPSND=ON \
  -DWITH_PULSE=ON \
  -DWITH_ALSA=ON \
  -DWITH_PIPEWIRE=ON \
  -DWITH_JPEG=ON \
  -DWITH_OPENSSL=ON \
  -DWITH_GSM=ON \
  -DWITH_FAAD2=ON \
  -DWITH_FAAC=OFF \
  -DWITH_FFMPEG=ON \
  -DWITH_SWSCALE=ON \
  -DWITH_CAIRO=ON \
  -DWITH_PKCS11=ON \
  -DWITH_KRB5=ON \
  -DWITH_OPENH264=ON \
  -DWITH_VIDEO_FFMPEG=ON \
  -DWITH_INTERNAL_MD4=ON \
  -DWITH_INTERNAL_MD5=ON \
  -DWITH_INTERNAL_RC4=ON \
  -DBUILD_SHARED_LIBS=ON
$STD cmake --build build -j"$(nproc)"
$STD cmake --install build
$STD ldconfig
msg_ok "Built FreeRDP ${FREERDP_VERSION}"

msg_info "Building Janua Desktop Gateway (Patience)"
mkdir -p /opt/janua/server
curl -fsSL "https://dlcdn.apache.org/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz" -o /tmp/guacamole-server.tar.gz
tar -xzf /tmp/guacamole-server.tar.gz --strip-components=1 -C /opt/janua/server
cd /opt/janua/server
# git apply --recount tolerates the Janua patches' hunk-count headers, which the
# stricter patch(1) on Debian 13 rejects as "malformed".
for p in /opt/janua/src/guacd/patches/*.patch; do
  $STD git apply --recount -p1 "$p"
done
export CPPFLAGS="-Wno-error=deprecated-declarations"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
$STD autoreconf -fi
$STD ./configure --with-init-dir=/etc/init.d --with-rdp --with-ssh --with-vnc
$STD make -j"$(nproc)"
$STD make install
$STD ldconfig
msg_ok "Built Janua Desktop Gateway"

msg_info "Setup Apache Tomcat"
TOMCAT_VERSION=$(curl -fsSL https://dlcdn.apache.org/tomcat/tomcat-9/ | grep -oP '(?<=href=")v[^"/]+(?=/")' | sed 's/^v//' | sort -V | tail -n1)
mkdir -p /opt/janua/tomcat9
curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" | tar -xz -C /opt/janua/tomcat9 --strip-components=1
useradd -r -d /opt/janua/tomcat9 -s /bin/false tomcat
msg_ok "Setup Apache Tomcat ${TOMCAT_VERSION}"

msg_info "Setup Janua web application"
mkdir -p /etc/guacamole/extensions /etc/guacamole/lib
curl -fsSL "https://dlcdn.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war" -o /tmp/guacamole.war
# Rebrand: swap the Guacamole logos for Janua's and deploy at the /janua context.
mkdir -p /tmp/branding/images
cp /opt/janua/src/web/images/logo-64.png /tmp/branding/images/logo-64.png
cp /opt/janua/src/web/images/logo-144.png /tmp/branding/images/logo-144.png
cp /tmp/guacamole.war /opt/janua/tomcat9/webapps/janua.war
cd /tmp/branding
$STD zip -u /opt/janua/tomcat9/webapps/janua.war images/logo-64.png images/logo-144.png
cp /opt/janua/src/guacamole-branding/janua-branding.jar /etc/guacamole/extensions/janua-branding.jar
msg_ok "Setup Janua web application"

PG_DB_NAME="janua_db" PG_DB_USER="janua" setup_postgresql_db

msg_info "Setup Database Schema"
curl -fsSL "https://dlcdn.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz" -o /tmp/guacamole-auth-jdbc.tar.gz
tar -xzf /tmp/guacamole-auth-jdbc.tar.gz -C /tmp
mv /tmp/guacamole-auth-jdbc-"${GUAC_VERSION}"/postgresql/guacamole-auth-jdbc-postgresql-"${GUAC_VERSION}".jar /etc/guacamole/extensions/
curl -fsSL "https://jdbc.postgresql.org/download/postgresql-${PG_CONNECTOR_VERSION}.jar" -o /etc/guacamole/lib/postgresql.jar
cat /tmp/guacamole-auth-jdbc-"${GUAC_VERSION}"/postgresql/schema/*.sql | $STD sudo -u postgres psql -d "$PG_DB_NAME"
$STD sudo -u postgres psql -d "$PG_DB_NAME" -c "GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO ${PG_DB_USER}; GRANT SELECT,USAGE ON ALL SEQUENCES IN SCHEMA public TO ${PG_DB_USER};"
msg_ok "Setup Database Schema"

msg_info "Securing admin account"
# The schema ships guacadmin/guacadmin — rename it to admin and set a generated
# password so the install never leaves default credentials. Guacamole stores a
# per-user salt and SHA-256(password + uppercase-hex-salt).
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
ADMIN_SALT=$(openssl rand -hex 32 | tr '[:lower:]' '[:upper:]')
ADMIN_HASH=$(printf '%s' "${ADMIN_PASS}${ADMIN_SALT}" | sha256sum | awk '{print toupper($1)}')
$STD sudo -u postgres psql -d "$PG_DB_NAME" -c "UPDATE guacamole_entity SET name='${ADMIN_USER}' WHERE name='guacadmin' AND type='USER';"
$STD sudo -u postgres psql -d "$PG_DB_NAME" -c "UPDATE guacamole_user SET password_salt=decode('${ADMIN_SALT}','hex'), password_hash=decode('${ADMIN_HASH}','hex'), password_date=now() WHERE entity_id=(SELECT entity_id FROM guacamole_entity WHERE name='${ADMIN_USER}' AND type='USER');"
msg_ok "Secured admin account"

msg_info "Configuring Janua"
cat <<EOF >/etc/guacamole/guacamole.properties
guacd-hostname: 127.0.0.1
guacd-port: 4822
postgresql-hostname: 127.0.0.1
postgresql-port: 5432
postgresql-database: ${PG_DB_NAME}
postgresql-username: ${PG_DB_USER}
postgresql-password: ${PG_DB_PASS}
EOF
chmod 640 /etc/guacamole/guacamole.properties
chown root:tomcat /etc/guacamole/guacamole.properties
# guacd's default "localhost" bind resolves to ::1 on Debian 13, but guacamole
# connects to 127.0.0.1 — pin it to IPv4 so sessions actually connect.
cat <<EOF >/etc/guacamole/guacd.conf
[server]
bind_host = 127.0.0.1
bind_port = 4822
EOF
msg_ok "Configured Janua"

msg_info "Creating Services"
JAVA_HOME=$(update-alternatives --query javadoc | grep Value: | head -n1 | sed 's/Value: //' | sed 's@bin/javadoc$@@')
cat <<EOF >/etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat (Janua web)
After=network.target postgresql.service

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_PID=/opt/janua/tomcat9/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/janua/tomcat9"
Environment="CATALINA_BASE=/opt/janua/tomcat9"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
Environment="GUACAMOLE_HOME=/etc/guacamole"
ExecStart=/opt/janua/tomcat9/bin/startup.sh
ExecStop=/opt/janua/tomcat9/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/guacd.service
[Unit]
Description=Janua Desktop Gateway Daemon
After=network.target tomcat.service

[Service]
Type=forking
ExecStart=/etc/init.d/guacd start
ExecStop=/etc/init.d/guacd stop
ExecReload=/etc/init.d/guacd restart
PIDFile=/var/run/guacd.pid

[Install]
WantedBy=multi-user.target
EOF
mkdir -p /var/guacamole /home/daemon/.config/freerdp
chown daemon:daemon /var/guacamole /home/daemon/.config/freerdp
# Tomcat runs as User=tomcat but the tree (incl. the deployed WAR) was written as
# root — hand it over so Tomcat can write logs/work/temp and expand the webapp.
chown -R tomcat:tomcat /opt/janua/tomcat9
# guacamole-server installs a SysV init script at /etc/init.d/guacd that our
# systemd unit shadows; reload so systemd sees the explicit unit before enabling.
systemctl daemon-reload
systemctl enable -q --now guacd tomcat
msg_ok "Created Services"

echo -e "${INFO}${YW}Janua admin login — save this now, it is not stored anywhere:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${ADMIN_USER}${CL} / ${BGN}${ADMIN_PASS}${CL}"

motd_ssh
customize
cleanup_lxc
