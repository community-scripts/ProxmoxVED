#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: nnsense
# License: MIT | https://github.com/nnsense/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/kieraneglin/pinchflat

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  elixir \
  erlang-dev \
  erlang-inets \
  erlang-os-mon \
  erlang-runtime-tools \
  erlang-syntax-tools \
  erlang-xmerl \
  git \
  libsqlite3-dev \
  locales \
  openssh-client \
  openssl \
  pipx \
  pkg-config \
  procps \
  python3-mutagen \
  unzip \
  zip
msg_ok "Installed Dependencies"

NODE_VERSION="20" NODE_MODULE="yarn" setup_nodejs
FFMPEG_TYPE="binary" setup_ffmpeg

case "$(dpkg --print-architecture)" in
  arm64)
    DENO_ASSET="deno-aarch64-unknown-linux-gnu.zip"
    YT_DLP_ASSET="yt-dlp_linux_aarch64"
    ;;
  *)
    DENO_ASSET="deno-x86_64-unknown-linux-gnu.zip"
    YT_DLP_ASSET="yt-dlp_linux"
    ;;
esac
fetch_and_deploy_gh_release "deno" "denoland/deno" "prebuild" "latest" "/usr/local/bin" "$DENO_ASSET"
fetch_and_deploy_gh_release "yt-dlp" "yt-dlp/yt-dlp" "singlefile" "latest" "/usr/local/bin" "$YT_DLP_ASSET"

msg_info "Installing Apprise"
export PIPX_HOME=/opt/pipx
export PIPX_BIN_DIR=/usr/local/bin
$STD pipx install apprise
msg_ok "Installed Apprise"

msg_info "Setting Locale"
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
$STD locale-gen
msg_ok "Set Locale"

fetch_and_deploy_gh_release "pinchflat" "kieraneglin/pinchflat" "tarball" "latest" "/opt/pinchflat-src"

msg_info "Configuring Pinchflat"
CONFIG_PATH="/opt/pinchflat/config"
LOCAL_DOWNLOADS_PATH="/opt/pinchflat/downloads"
DOWNLOADS_PATH="${DOWNLOADS_PATH:-$LOCAL_DOWNLOADS_PATH}"
SECRET_KEY_BASE=$(openssl rand -base64 48)

mkdir -p \
  /etc/elixir_tzdata_data \
  /etc/yt-dlp/plugins \
  /opt/pinchflat/app \
  "$CONFIG_PATH/db" \
  "$CONFIG_PATH/extras" \
  "$CONFIG_PATH/logs" \
  "$CONFIG_PATH/metadata" \
  "$DOWNLOADS_PATH"
ln -sfn "$CONFIG_PATH" /config
ln -sfn "$DOWNLOADS_PATH" /downloads
chmod ugo+rw /etc/elixir_tzdata_data /etc/yt-dlp /etc/yt-dlp/plugins

cat <<EOF >/opt/pinchflat/.env
LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_ALL=en_US.UTF-8
MIX_ENV=prod
PHX_SERVER=true
PORT=8945
RUN_CONTEXT=selfhosted
CONFIG_PATH=${CONFIG_PATH}
MEDIA_PATH=${DOWNLOADS_PATH}
TZ_DATA_PATH=/etc/elixir_tzdata_data
SECRET_KEY_BASE=${SECRET_KEY_BASE}
EOF
msg_ok "Configured Pinchflat"

msg_info "Building Pinchflat"
cd /opt/pinchflat-src
export MIX_ENV=prod
export ERL_FLAGS="+JPperf true"
$STD mix local.hex --force
$STD mix local.rebar --force
$STD mix deps.get --only prod
$STD mix deps.compile
$STD yarn --cwd assets install
$STD mix assets.deploy
$STD mix compile
$STD mix release --overwrite
rm -rf /opt/pinchflat/app
cp -r _build/prod/rel/pinchflat /opt/pinchflat/app
msg_ok "Built Pinchflat"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/pinchflat.service
[Unit]
Description=Pinchflat
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/pinchflat/.env
WorkingDirectory=/opt/pinchflat/app
UMask=0022
ExecStartPre=/opt/pinchflat/app/bin/check_file_permissions
ExecStartPre=/opt/pinchflat/app/bin/migrate
ExecStart=/opt/pinchflat/app/bin/pinchflat start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pinchflat
msg_ok "Created Service"

cat <<EOF >/opt/pinchflat/README
Pinchflat is installed as a systemd service.

Web UI: http://<LXC-IP>:8945
Config path: ${CONFIG_PATH}
Downloads path: ${DOWNLOADS_PATH}

If an external downloads path was selected, mount it inside the LXC at the same path.
If the path did not exist during installation, it was created locally and can later be replaced by the mount.
EOF

motd_ssh
customize
cleanup_lxc
