#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.paperless-ngx.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
    redis \
    postgresql \
    build-essential \
    imagemagick \
    fonts-liberation \
    optipng \
    gnupg \
    libpq-dev \
    libmagic-dev \
    mime-support \
    libzbar0 \
    poppler-utils \
    default-libmysqlclient-dev \
    automake \
    libtool \
    pkg-config \
    git \
    libtiff-dev \
    libpng-dev \
    libleptonica-dev
setup_uv
msg_ok "Installed Dependencies"

# msg_info "Installing OCR Dependencies (Patience)"
# $STD apt-get install -y \
#     unpaper \
#     icc-profiles-free \
#     qpdf \
#     liblept5 \
#     libxml2 \
#     pngquant \
#     zlib1g \
#     tesseract-ocr \
#     tesseract-ocr-eng

# cd /tmp
# curl -fsSL "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10051/ghostpdl-10.05.1.tar.gz" -o "ghostscript.tar.gz"
# $STD tar -xzf ghostscript.tar.gz
# cd ghostpdl-10.05.1
# $STD ./configure
# $STD make
# $STD make install
# msg_ok "Installed OCR Dependencies"

msg_info "Installing JBIG2"
$STD git clone https://github.com/ie13/jbig2enc /opt/jbig2enc
cd /opt/jbig2enc
$STD ./autogen.sh
$STD ./configure
$STD make
$STD make install
rm -rf /opt/jbig2enc
msg_ok "Installed JBIG2"

msg_info "Installing Paperless-ngx (Patience)"
LATEST=$(curl -fsSL "https://github.com/paperless-ngx/paperless-ngx/releases/latest" | grep "title>Release" | cut -d " " -f 5)
cd /opt
curl -fsSL "https://github.com/paperless-ngx/paperless-ngx/releases/download/${LATEST}/paperless-ngx-${LATEST}.tar.xz" -o paperless.tar.xz
tar -xf paperless.tar.xz
mv paperless-ngx paperless
rm paperless.tar.xz
cd /opt/paperless

uv venv /opt/paperless/venv
source /opt/paperless/venv/bin/activate
uv pip install --all-extras -r requirements.txt

curl -fsSL "https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/paperless.conf.example" -o /opt/paperless/paperless.conf
mkdir -p consume data media static
sed -i -e 's|#PAPERLESS_REDIS=.*|PAPERLESS_REDIS=redis://localhost:6379|' \
    -e "s|#PAPERLESS_CONSUMPTION_DIR=.*|PAPERLESS_CONSUMPTION_DIR=/opt/paperless/consume|" \
    -e "s|#PAPERLESS_DATA_DIR=.*|PAPERLESS_DATA_DIR=/opt/paperless/data|" \
    -e "s|#PAPERLESS_MEDIA_ROOT=.*|PAPERLESS_MEDIA_ROOT=/opt/paperless/media|" \
    -e "s|#PAPERLESS_STATICDIR=.*|PAPERLESS_STATICDIR=/opt/paperless/static|" \
    paperless.conf

echo "$LATEST" >/opt/"${APPLICATION}"_version.txt
msg_ok "Installed Paperless-ngx"

msg_info "Installing Natural Language Toolkit (Patience)"
/opt/paperless/venv/bin/python3 -m nltk.downloader -d /usr/share/nltk_data all
msg_ok "Installed Natural Language Toolkit"

msg_info "Setting up PostgreSQL database"
DB_NAME=paperlessdb
DB_USER=paperless
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
SECRET_KEY="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"

echo -e "\nPaperless-ngx Database User: \e[32m$DB_USER\e[0m" >>~/paperless.creds
echo -e "Paperless-ngx Database Password: \e[32m$DB_PASS\e[0m" >>~/paperless.creds
echo -e "Paperless-ngx Database Name: \e[32m$DB_NAME\e[0m" >>~/paperless.creds

sed -i -e "s|#PAPERLESS_DBHOST=.*|PAPERLESS_DBHOST=localhost|" \
    -e "s|#PAPERLESS_DBPORT=.*|PAPERLESS_DBPORT=5432|" \
    -e "s|#PAPERLESS_DBNAME=.*|PAPERLESS_DBNAME=$DB_NAME|" \
    -e "s|#PAPERLESS_DBUSER=.*|PAPERLESS_DBUSER=$DB_USER|" \
    -e "s|#PAPERLESS_DBPASS=.*|PAPERLESS_DBPASS=$DB_PASS|" \
    -e "s|#PAPERLESS_SECRET_KEY=.*|PAPERLESS_SECRET_KEY=$SECRET_KEY|" \
    /opt/paperless/paperless.conf

cd /opt/paperless/src
source /opt/paperless/venv/bin/activate
python3 manage.py migrate
msg_ok "Set up PostgreSQL database"

read -r -p "Would you like to add Adminer? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installing Adminer"
    $STD apt install -y adminer
    $STD a2enconf adminer
    systemctl reload apache2
    IP=$(hostname -I | awk '{print $1}')
    echo "" >>~/paperless.creds
    echo -e "Adminer Interface: \e[32m$IP/adminer/\e[0m" >>~/paperless.creds
    echo -e "Adminer System: \e[32mPostgreSQL\e[0m" >>~/paperless.creds
    echo -e "Adminer Server: \e[32mlocalhost:5432\e[0m" >>~/paperless.creds
    echo -e "Adminer Username: \e[32m$DB_USER\e[0m" >>~/paperless.creds
    echo -e "Adminer Password: \e[32m$DB_PASS\e[0m" >>~/paperless.creds
    echo -e "Adminer Database: \e[32m$DB_NAME\e[0m" >>~/paperless.creds
    msg_ok "Installed Adminer"
fi

msg_info "Setting up admin Paperless-ngx User & Password"
cat <<EOF | /opt/paperless/venv/bin/python3 manage.py shell
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('admin', password='$DB_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
echo "" >>~/paperless.creds
echo -e "Paperless-ngx WebUI User: \e[32madmin\e[0m" >>~/paperless.creds
echo -e "Paperless-ngx WebUI Password: \e[32m$DB_PASS\e[0m" >>~/paperless.creds
msg_ok "Set up admin Paperless-ngx User & Password"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/paperless-scheduler.service
[Unit]
Description=Paperless Celery beat
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=/opt/paperless/venv/bin/celery --app paperless beat --loglevel INFO

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/paperless-task-queue.service
[Unit]
Description=Paperless Celery Workers
Requires=redis.service
After=postgresql.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=/opt/paperless/venv/bin/celery --app paperless worker --loglevel INFO

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/paperless-consumer.service
[Unit]
Description=Paperless consumer
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStartPre=/bin/sleep 2
ExecStart=/opt/paperless/venv/bin/python3 manage.py document_consumer

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/paperless-webserver.service
[Unit]
Description=Paperless webserver
After=network.target
Wants=network.target
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=/opt/paperless/venv/bin/granian --interface asginl --ws "paperless.asgi:application"
Environment=GRANIAN_HOST=::
Environment=GRANIAN_PORT=8000
Environment=GRANIAN_WORKERS=1

[Install]
WantedBy=multi-user.target
EOF

sed -i -e 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml

systemctl daemon-reload
$STD systemctl enable -q --now paperless-webserver paperless-scheduler paperless-task-queue paperless-consumer
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/paperless/docker
rm -rf /tmp/ghostscript* /tmp/ghostpdl*
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
