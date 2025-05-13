#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE
# Source: https://github.com/odoo/odoo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  git \
  python3 \
  python3-pip \
  python3-dev \
  build-essential \
  libxslt-dev \
  libzip-dev \
  libldap2-dev \
  libsasl2-dev \
  libjpeg-dev \
  libpq-dev \
  libxml2-dev \
  libjpeg-dev \
  liblcms2-dev \
  libblas-dev \
  libatlas-base-dev \
  libssl-dev \
  libffi-dev \
  xfonts-75dpi \
  xfonts-base \
  make
msg_ok "Installed Dependencies"

msg_info "Creating odoo user and directories"
useradd -r -m -U -d /opt/odoo -s /bin/bash odoo
mkdir -p /opt/odoo/odoo /opt/odoo/venv
chown -R odoo:odoo /opt/odoo
msg_ok "Created user and directory"

msg_info "Cloning Odoo Repository"
git clone --depth 1 --branch 18.0 https://github.com/odoo/odoo.git /opt/odoo/odoo
chown -R odoo:odoo /opt/odoo/odoo
msg_ok "Cloned Odoo Repository"

setup_uv

msg_info "Creating Python Virtual Environment"
uv venv /opt/odoo/.venv
source /opt/odoo/.venv/bin/activate
#uv sync --all-extras
uv pip install --upgrade pip wheel
uv pip install -r /opt/odoo/odoo/requirements.txt
msg_ok "Created and populated Python venv"

msg_info "Creating Configuration File"
cat <<EOF >/opt/odoo/odoo.conf
[options]
addons_path = /opt/odoo/odoo/addons
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = odoo
db_password = odoo
logfile = /var/log/odoo.log
EOF
chown odoo:odoo /opt/odoo/odoo.conf
chmod 640 /opt/odoo/odoo.conf
msg_ok "Created Configuration File"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/odoo.service
[Unit]
Description=Odoo ERP
After=network.target postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
Environment="PATH=/opt/odoo/.venv/bin:/usr/local/bin:/usr/bin"
ExecStart=/opt/odoo/.venv/bin/python3 /opt/odoo/odoo/odoo-bin -config /opt/odoo/odoo.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now odoo
msg_ok "Enabled and Started Odoo Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
