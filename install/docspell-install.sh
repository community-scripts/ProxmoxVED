#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT |

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup Functions"
setup_local_ip_helper
import_local_ip
msg_ok "Setup Functions"

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
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
    ocrmypdf
msg_ok "Installed Dependencies"

msg_info "Setting up PostgreSQL Repository"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt-get update
msg_ok "Set up PostgreSQL Repository"

msg_info "Install/Set up PostgreSQL Database"
$STD apt-get install -y postgresql-16
DB_NAME=docspell_db
DB_USER=docspell_usr
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
    echo "Docspell-Credentials"
    echo "Docspell Database Name: $DB_NAME"
    echo "Docspell Database User: $DB_USER"
    echo "Docspell Database Password: $DB_PASS"
} >>~/docspell.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Setup Docspell (Patience)"
mkdir -p /opt/docspell
Docspell=$(curl -fsSL https://github.com/eikek/docspell/releases/latest -o - | grep "title>Release" | cut -d " " -f 5)
DocspellDSC=$(curl -fsSL https://github.com/docspell/dsc/releases/latest -o - | grep "title>Release" | cut -d " " -f 4 | sed 's/^v//')
cd /opt
curl -fsSL https://github.com/eikek/docspell/releases/download/v${Docspell}/docspell-joex_${Docspell}_all.deb -o docspell-joex_${Docspell}_all.deb
curl -fsSL https://github.com/eikek/docspell/releases/download/v${Docspell}/docspell-restserver_${Docspell}_all.deb -o docspell-restserver_${Docspell}_all.deb
$STD dpkg -i docspell-*.deb
curl -fsSL https://github.com/docspell/dsc/releases/download/v${DocspellDSC}/dsc_amd64-musl-${DocspellDSC} -o dsc_amd64-musl-${DocspellDSC}
mv dsc_amd* dsc
chmod +x dsc
mv dsc /usr/bin
ln -s /etc/docspell-joex /opt/docspell/docspell-joex && ln -s /etc/docspell-restserver /opt/docspell/docspell-restserver && ln -s /usr/bin/dsc /opt/docspell/dsc
curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq
chmod +x /usr/bin/yq
#JOEX_CONF="/usr/share/docspell-joex/conf/docspell-joex.conf"
#SERVER_CONF="/usr/share/docspell-restserver/conf/docspell-server.conf"
sed -i \
    -e '11s|localhost|'"$LOCAL_IP"'|' \
    -e '17s|localhost|'"$LOCAL_IP"'|' \
    -e '49s|url = .*|url = "jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|' \
    -e '52s|user = .*|user = "'"$DB_USER"'"|' \
    -e '55s|password = .*|password = "'"$DB_PASS"'"|' \
    -e '827s|url = .*|url = "jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|' \
    -e '828s|user = .*|user = "'"$DB_USER"'"|' \
    -e '829s|password = .*|password = "'"$DB_PASS"'"|' \
    /usr/share/docspell-joex/conf/docspell-joex.conf

sed -i \
    -e '16s|http://localhost:7880|http://'"$LOCAL_IP"':7880|' \
    -e '22s|http://localhost:7880|http://'"$LOCAL_IP"':7880|' \
    -e '356s|url = .*|url = "jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|' \
    -e '357s|user = .*|user = "'"$DB_USER"'"|' \
    -e '358s|password = .*|password = "'"$DB_PASS"'"|' \
    -e '401s|url = .*|url = "jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|' \
    /usr/share/docspell-restserver/conf/docspell-server.conf

# sed -i 's|address = "localhost"|address = "0.0.0.0"|' "$JOEX_CONF" "$SERVER_CONF"
# sed -i -E '/backend\s*\{/,/\}/ {
#     /jdbc\s*\{/,/\}/ {
#         s|(url\s*=\s*).*|\1"jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|;
#         s|(user\s*=\s*).*|\1"'"$DB_USER"'"|;
#         s|(password\s*=\s*).*|\1"'"$DB_PASS"'"|;
#     }
# }' "$SERVER_CONF"
# sed -i -E '/postgresql\s*\{/,/\}/ {
#     /jdbc\s*\{/,/\}/ {
#         s|(url\s*=\s*).*|\1"jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|;
#         s|(user\s*=\s*).*|\1"'"$DB_USER"'"|;
#         s|(password\s*=\s*).*|\1"'"$DB_PASS"'"|;
#     }
# }' "$SERVER_CONF"
# sed -i -E '/jdbc\s*\{/,/\}/ {
#     s|(url\s*=\s*).*|\1"jdbc:postgresql://localhost:5432/'"$DB_NAME"'"|;
#     s|(user\s*=\s*).*|\1"'"$DB_USER"'"|;
#     s|(password\s*=\s*).*|\1"'"$DB_PASS"'"|;
# }' "$JOEX_CONF"
msg_ok "Setup Docspell"

msg_info "Setup Apache Solr"
cd /opt/docspell
SOLR_DOWNLOAD_URL="https://downloads.apache.org/lucene/solr/"
latest_version=$(curl -fsSL "$SOLR_DOWNLOAD_URL" | grep -oP '(?<=<a href=")[^"]+(?=/">[0-9])' | head -n 1)
download_url="${SOLR_DOWNLOAD_URL}${latest_version}/solr-${latest_version}.tgz"
curl -fsSL "$download_url" -o "solr-$latest_version.tgz"
tar xzf "solr-$latest_version.tgz"
$STD bash "/opt/docspell/solr-$latest_version/bin/install_solr_service.sh" "solr-$latest_version.tgz"
mv /opt/solr /opt/docspell/solr
systemctl enable -q --now solr
$STD su solr -c '/opt/docspell/solr/bin/solr create -c docspell'
msg_ok "Setup Apache Solr"

msg_info "Setup Services"
systemctl enable -q --now docspell-restserver
systemctl enable -q --now docspell-joex
msg_ok "Setup Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -R /opt/docspell/solr-$latest_version
rm -R /opt/docspell-joex_${Docspell}_all.deb
rm -R /opt/docspell-restserver_${Docspell}_all.deb
rm -R /opt/docspell/solr-$latest_version.tgz
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
