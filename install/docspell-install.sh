#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y --no-install-recommends \
  unzip \
  htop \
  gnupg2 \
  ca-certificates \
  default-jdk \
  apt-transport-https \
  ghostscript \
  tesseract-ocr \
  tesseract-ocr-deu \
  tesseract-ocr-eng \
  unpaper \
  unoconv \
  wkhtmltopdf \
  ocrmypdf \
  wget \
  zip \
  curl \
  sudo \
  git \
  make \
  mc

mkdir -p /opt/docspell && cd /opt/docspell
SOLR_DOWNLOAD_URL="https://downloads.apache.org/lucene/solr/"
latest_version=$(curl -s "$SOLR_DOWNLOAD_URL" | grep -oP '(?<=<a href=")[^"]+(?=/">[0-9])' | head -n 1)
download_url="${SOLR_DOWNLOAD_URL}${latest_version}/solr-${latest_version}.tgz"
$STD  wget "$download_url"
tar xzf "solr-$latest_version.tgz"
$STD  bash "/opt/docspell/solr-$latest_version/bin/install_solr_service.sh" "solr-$latest_version.tgz"
mv /opt/solr /opt/docspell/solr
$STD systemctl start solr
$STD su solr -c '/opt/docspell/solr/bin/solr create -c docspell'
msg_ok "Installed Dependencies"

msg_info "Install/Set up PostgreSQL Database"
DB_NAME=docspelldb
DB_USER=docspell
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc|gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y postgresql-16
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
$STD systemctl enable postgresql
echo "" >>~/docspell.creds
echo -e "Docspell Database Name: $DB_NAME" >>~/docspell.creds
echo -e "Docspell Database User: $DB_USER" >>~/docspell.creds
echo -e "Docspell Database Password: $DB_PASS" >>~/docspell.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Setup Docspell (Patience)"
Docspell=$(wget -q https://github.com/eikek/docspell/releases/latest -O - | grep "title>Release" | cut -d " " -f 5)
DocspellDSC=$(wget -q https://github.com/docspell/dsc/releases/latest -O - | grep "title>Release" | cut -d " " -f 4 | sed 's/^v//')
cd /opt
$STD wget https://github.com/eikek/docspell/releases/download/v${Docspell}/docspell-joex_${Docspell}_all.deb
$STD wget https://github.com/eikek/docspell/releases/download/v${Docspell}/docspell-restserver_${Docspell}_all.deb
$STD dpkg -i docspell-*
$STD wget https://github.com/docspell/dsc/releases/download/v${DocspellDSC}/dsc_amd64-musl-${DocspellDSC}
mv dsc_amd* dsc
chmod +x dsc
mv dsc /usr/bin
ln -s /etc/docspell-joex /opt/docspell/docspell-joex && ln -s /etc/docspell-restserver /opt/docspell/docspell-restserver && ln -s /usr/bin/dsc /opt/docspell/dsc
cd /opt && rm -R solr-$latest_version && rm -R docspell-joex_${Docspell}_all.deb  && rm -R docspell-restserver_${Docspell}_all.deb
cd /opt/docspell && rm -R solr-$latest_version.tgz && rm -R solr-$latest_version
sudo sed -i "s|url = \"jdbc:postgresql://localhost:5432/db\"|url = \"jdbc:postgresql://localhost:5432/$DB_NAME\"|" /opt/docspell/docspell-restserver/docspell-server.conf
sudo sed -i "s|url = \"jdbc:postgresql://localhost:5432/db\"|url = \"jdbc:postgresql://localhost:5432/$DB_NAME\"|" /opt/docspell/docspell-joex/docspell-joex.conf
sudo sed -i "s/user=.*/user=$DB_USER/" /opt/docspell/docspell-restserver/docspell-server.conf
sudo sed -i "s/password=.*/password=$DB_PASS/" /opt/docspell/docspell-restserver/docspell-server.conf
sudo sed -i "s/user=.*/user=$DB_USER/" /opt/docspell/docspell-joex/docspell-joex.conf
sudo sed -i "s/password=.*/password=$DB_PASS/" /opt/docspell/docspell-joex/docspell-joex.conf
systemctl start docspell-restserver
systemctl enable docspell-restserver
systemctl start docspell-joex
systemctl enable docspell-joex

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
