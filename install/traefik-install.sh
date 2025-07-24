#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://traefik.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y apt-transport-https
msg_ok "Installed Dependencies"

RELEASE=$(curl -fsSL https://api.github.com/repos/traefik/traefik/releases | grep -oP '"tag_name":\s*"v\K[\d.]+?(?=")' | sort -V | tail -n 1)
msg_info "Installing Traefik v${RELEASE}"
mkdir -p /etc/traefik/{conf.d,ssl,sites-available}
curl -fsSL "https://github.com/traefik/traefik/releases/download/v${RELEASE}/traefik_v${RELEASE}_linux_amd64.tar.gz" -o "traefik_v${RELEASE}_linux_amd64.tar.gz"
tar -C /tmp -xzf traefik*.tar.gz
mv /tmp/traefik /usr/bin/
rm -rf traefik*.tar.gz
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed Traefik v${RELEASE}"

msg_info "Creating Traefik configuration"
cat <<EOF >/etc/traefik/traefik.yaml
providers:
  file:
    directory: /etc/traefik/conf.d/
    watch: true

entryPoints:
  web:
    address: ':80'
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ':443'
    http:
      tls:
        certResolver: letsencrypt
    # Uncomment below if using cloudflare
    /*
    forwardedHeaders:
      trustedIPs:
      - 173.245.48.0/20
      - 103.21.244.0/22
      - 103.22.200.0/22
      - 103.31.101.64/22
      - 141.101.64.0/18
      - 108.162.192.0/18
      - 190.93.240.0/20
      - 188.114.96.0/20
      - 197.234.240.0/22
      - 198.41.128.0/17
      - 162.158.0.0/15
      - 104.16.0.0/13
      - 104.16.0.0/13
      - 172.64.0.0/13
      - 131.0.72.0/22
    */
    asDefault: true
  traefik:
    address: ':8080'

certificatesResolvers:
  letsencrypt:
    acme:
      email: "foo@bar.com"
      storage: /etc/traefik/ssl/acme.json
      tlsChallenge: {}

# Uncomment below if you are using self signed or no certificate
#serversTransport:
#  insecureSkipVerify: true

api:
  dashboard: true
  insecure: true

log:
  filePath: /var/log/traefik/traefik.log
  format: json
  level: INFO

accessLog:
  filePath: /var/log/traefik/traefik-access.log
  format: json
  filters:
    statusCodes:
      - "200"
      - "400-599"
    retryAttempts: true
    minDuration: "10ms"
  bufferingSize: 0
  fields:
    headers:
      defaultMode: drop
      names:
        User-Agent: keep
EOF
msg_ok "Created Traefik configuration"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/traefik.service
[Unit]
Description=Traefik is an open-source Edge Router that makes publishing your services a fun and easy experience

[Service]
Type=notify
ExecStart=/usr/bin/traefik --configFile=/etc/traefik/traefik.yaml
Restart=on-failure
ExecReload=/bin/kill -USR1 \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now traefik
msg_ok "Created Service"

msg_info "Creating site templates"
cat <<EOF >/etc/traefik/template.yaml.tpl
http:
  routers:
    ${hostname}:
      rule: Host(`${FQDN}`)
      service: ${hostname}
      tls:
        certResolver: letsencrypt
  services:
    ${hostname}:
      loadbalancer:
        servers:
        - url: "${URL}"
EOF
msg_ok: "Template Created"
msg_info: "Creating Helper Scripts"
cat <<EOF >/usr/bin/addsite
#!/bin/bash

function setup_site() {
    hostname="$(whiptail --inputbox "Enter the hostname of the Site" 8 78 --title "Hostname" 3>&1 1>&2 2>&3)"
    exitstatus=$?
    [[ "$exitstatus" = 1 ]] && return;
    FQDN="$(whiptail --inputbox "Enter the FQDN of the Site" 8 78 --title "FQDN" 3>&1 1>&2 2>&3)"
    exitstatus=$?
    [[ "$exitstatus" = 1 ]] && return;
    URL="$(whiptail --inputbox "Enter the URL of the Site (For example http://192.168.x.x:8080)" 8 78 --title "URL" 3>&1 1>&2 2>&3)"
    exitstatus=$?
    [[ "$exitstatus" = 1 ]] && return;
    filename="/etc/traefik/sites-available/${hostname}.yaml"
    export hostname FQDN URL
    envsubst '${hostname} ${FQDN} ${URL}' < /etc/traefik/template.yaml.tpl > ${filename}
}

setup_site
EOF
cat <<EOF >/usr/bin/ensite
#!/bin/bash

function ensite() {
    DIR="/etc/traefik/sites-available"
    files=( "$DIR"/* )

    opts=()
    for f in "${files[@]}"; do
      name="${f##*/}"
      opts+=( "$name" "" )
    done

    choice=$(whiptail \
      --title "Select an entry" \
      --menu "Choose a site" \
      20 60 12 \
      "${opts[@]}" \
      3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
      ln -s $DIR/$choice /etc/traefik/conf.d
    else
      return
    fi
}

ensite
EOF
cat <<EOF >/usr/bin/dissite
#!/bin/bash

function dissite() {
    DIR="/etc/traefik/conf.d"
    files=( "$DIR"/* )

    opts=()
    for f in "${files[@]}"; do
      name="${f##*/}"
      opts+=( "$name" "" )
    done

    choice=$(whiptail \
      --title "Select an entry" \
      --menu "Choose a site" \
      20 60 12 \
      "${opts[@]}" \
      3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
      rm $DIR/$choice
    else
      return
    fi
}

dissite
EOF

cat <<EOF >/usr/bin/editsite
#!/bin/bash

function edit_site() {
    DIR="/etc/traefik/sites-available"
    files=( "$DIR"/* )

    opts=()
    for f in "${files[@]}"; do
      name="${f##*/}"
      opts+=( "$name" "" )
    done

    choice=$(whiptail \
      --title "Select an entry" \
      --menu "Choose a site" \
      20 60 12 \
      "${opts[@]}" \
      3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
      nano $DIR/$choice
    else
      return
    fi
}

edit_site
EOF
msg_ok "Helper Scripts Created"
msg_info "Commands available are as below:"
msg_info "addsite - creating a config"
msg_info "ensite - enables a config"
msg_info "dissite - disables a config"
msg_info "editsite - edits a config"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
