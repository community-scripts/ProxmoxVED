#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# Import Functions und Setup
# shellcheck source=/dev/null
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Configuring environment"
DATA_DIR="$YB_HOME/var/data"
TEMP_DIR="$YB_HOME/var/tmp"
BOTO_DIR="$YB_HOME/.boto"
# The following ENV vars are set for the yugabyted process
YB_MANAGED_DEVOPS_USE_PYTHON3=1
YB_DEVOPS_USE_PYTHON3=1
BOTO_PATH=$BOTO_DIR/config
AZCOPY_JOB_PLAN_LOCATION=/tmp/azcopy/jobs-plan
AZCOPY_LOG_LOCATION=/tmp/azcopy/logs

# Save environment for users and update
cat >/etc/environment <<EOF
YB_SERIES=$YB_SERIES
YB_HOME=$YB_HOME
DATA_DIR=$DATA_DIR
TEMP_DIR=$TEMP_DIR
YB_MANAGED_DEVOPS_USE_PYTHON3=$YB_MANAGED_DEVOPS_USE_PYTHON3
YB_DEVOPS_USE_PYTHON3=$YB_DEVOPS_USE_PYTHON3
BOTO_PATH=$BOTO_PATH
AZCOPY_JOB_PLAN_LOCATION=$AZCOPY_JOB_PLAN_LOCATION
AZCOPY_LOG_LOCATION=$AZCOPY_LOG_LOCATION
EOF

# Create data dirs from ENV vars, required before creating venv
mkdir -p "$YB_HOME" "$DATA_DIR" "$TEMP_DIR" "$BOTO_DIR"
# Set working dir
cd "$YB_HOME" || exit
msg_ok "Configured environment"

# Create unprivileged user to run DB, required before creating venv
msg_info "Creating yugabyte user"
useradd --home-dir "$YB_HOME" \
  --uid 10001 \
  --no-create-home \
  --no-user-group \
  --shell /sbin/nologin \
  yugabyte
# Make sure user has permission to create venv
chown -R yugabyte "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
msg_ok "Created yugabyte user"

msg_info "Setting up Python virtual environment"
PYTHON_VERSION=3.11 setup_uv
# Create venv as yugabyte user to ensure correct permissions when sourcing later
$STD sudo -u yugabyte uv venv --python 3.11 "$YB_HOME/.venv"
source "$YB_HOME/.venv/bin/activate"
# Install required packages
$STD uv pip install --upgrade pip
$STD uv pip install --upgrade lxml
$STD uv pip install --upgrade s3cmd
$STD uv pip install --upgrade psutil
msg_ok "Setup Python virtual environment"

# venv should be sourced before installing google-cloud-cli,
# that's why we don't do this first
msg_info "Installing Dependencies"
# Add microsoft-prod repo for azcopy
setup_deb822_repo \
  "microsoft-prod" \
  "https://packages.microsoft.com/keys/microsoft.asc" \
  "https://packages.microsoft.com/debian/12/prod/" \
  "bookworm" \
  "main" \
  "amd64,arm64,armhf" \
  "true"

# Add cloud.google repo for gsutil, supplied by google-cloud-cli
setup_deb822_repo \
  "cloud.google" \
  "https://packages.cloud.google.com/apt/doc/apt-key.gpg" \
  "https://packages.cloud.google.com/apt/" \
  "cloud-sdk" \
  "main" \
  "" \
  "true"

# Update to source added repos
$STD apt update -y
$STD apt install -y \
  file \
  diffutils \
  gettext \
  locales-all \
  iotop \
  less \
  libncurses-dev \
  net-tools \
  openssl \
  libssl-dev \
  rsync \
  procps \
  sysstat \
  tcpdump \
  gnu-which \
  binutils \
  tar \
  chrony \
  apt-transport-https \
  gnupg \
  azcopy \
  google-cloud-cli
msg_ok "Installed Dependencies"

# yugabyted will expect `chronyc sources` to succeed
msg_info "Restarting chronyd in container mode"
# Start chronyd with the -x option to disable control of the system clock
sed -i 's|^ExecStart=!/usr/sbin/chronyd|ExecStart=!/usr/sbin/chronyd -x|' \
  /usr/lib/systemd/system/chrony.service
systemctl daemon-reload
if systemctl restart chronyd; then
  msg_ok "chronyd running correctly"
else
  msg_error "Failed to restart chronyd"
  journalctl -xeu chronyd.service
  exit 1
fi

msg_info "Setup ${APP}"
# Get latest version and build number for our series
read -r VERSION RELEASE < <(
  curl -fsSL https://github.com/yugabyte/yugabyte-db/raw/refs/heads/master/docs/data/currentVersions.json |
    jq -r ".dbVersions[] | select(.series == \"${YB_SERIES}\") | [.version, .appVersion] | @tsv"
)
# Download the corresponding tarball
curl -OfsSL "https://software.yugabyte.com/releases/${VERSION}/yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"
tar -xzf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz" --strip 1
rm -rf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"

# Extract share/ybc-*.tar.gz to get bins required for ysql_conn_mgr
tar -xzf share/ybc-*.tar.gz
rm -rf ybc-*/conf/
# yugabyted expects yb-controller-server file in ybc/bin
mv ybc-* ybc

# Strip unneeded symbols from object files in $YB_HOME
# This is a step taken from the official Dockerfile
for a in $(find . -exec file {} \; | grep -i elf | cut -f1 -d:); do
  $STD strip --strip-unneeded "$a" || true
done

# Link yugabyte bins to /usr/local/bin/
for a in ysqlsh ycqlsh yugabyted yb-admin yb-ts-cli; do
  ln -s "$YB_HOME/bin/$a" "/usr/local/bin/$a"
done

# Set BOTO config for YugabyteDB
echo -e "[GSUtil]\nstate_dir=/tmp/gsutil" >"$BOTO_PATH"
msg_ok "Setup ${APP}"

# Make sure we supply required licensing
msg_info "Copying licenses"
ghr_url=https://raw.githubusercontent.com/yugabyte/yugabyte-db/master
mkdir /licenses
curl -fsSL ${ghr_url}/LICENSE.md -o /licenses/LICENSE.md
curl -fsSL ${ghr_url}/licenses/APACHE-LICENSE-2.0.txt -o /licenses/APACHE-LICENSE-2.0.txt
curl -fsSL ${ghr_url}/licenses/POLYFORM-FREE-TRIAL-LICENSE-1.0.0.txt \
  -o /licenses/POLYFORM-FREE-TRIAL-LICENSE-1.0.0.txt
msg_ok "Copied licenses"

# Make sure ulimits match those required by YugabyteDB
msg_info "Setting default ulimits in /etc/security/limits.conf"
cat <<EOF >/etc/security/limits.conf
*                -       core            unlimited
*                -       data            unlimited
*                -       fsize           unlimited
*                -       sigpending      119934
*                -       memlock         64
*                -       rss             unlimited
*                -       nofile          1048576
*                -       msgqueue        819200
*                -       stack           8192
*                -       cpu             unlimited
*                -       nproc           12000
*                -       locks           unlimited
EOF
msg_ok "Set default ulimits in /etc/security/limits.conf"

# Append tmp_dir to TSERVER_FLAGS to make sure yugabyted user has permissions to access it
TSERVER_FLAGS+="tmp_dir=$TEMP_DIR"

# Create service file with user selected options, correct limits, ENV vars, etc.
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"${NSAPP}.service"
[Unit]
Description=${APPLICATION} Service
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
RestartForceExitStatus=SIGPIPE
StartLimitInterval=0
ExecStart=/usr/local/bin/yugabyted start --secure \
--backup_daemon=$BACKUP_DAEMON \
--fault_tolerance=$FAULT_TOLERANCE \
--advertise_address=$(hostname -I | awk '{print $1}') \
--tserver_flags="$TSERVER_FLAGS" \
--data_dir=$DATA_DIR \
--cloud_location=$CLOUD_LOCATION \
--callhome=false \
$JOIN_CLUSTER

Environment="PATH=$YB_HOME/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="YB_HOME=$YB_HOME"
Environment="YB_MANAGED_DEVOPS_USE_PYTHON3=$YB_MANAGED_DEVOPS_USE_PYTHON3"
Environment="YB_DEVOPS_USE_PYTHON3=$YB_DEVOPS_USE_PYTHON3"
Environment="BOTO_PATH=$BOTO_PATH"
Environment="AZCOPY_JOB_PLAN_LOCATION=$AZCOPY_JOB_PLAN_LOCATION"
Environment="AZCOPY_LOG_LOCATION=$AZCOPY_LOG_LOCATION"
WorkingDirectory=$YB_HOME
TimeoutStartSec=30
LimitCORE=infinity
LimitNOFILE=1048576
LimitNPROC=12000
RestartSec=5
PermissionsStartOnly=True
User=yugabyte
TimeoutStopSec=300
Restart=always

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Service"

motd_ssh
customize

msg_info "Setting permissions"
chown -R yugabyte "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
chmod -R 755 "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
# Make sure gsutil and azcopy tmp dirs exist and allow yugabyte user access
mkdir -m 777 /tmp/gsutil /tmp/azcopy
msg_ok "Permissions set"

# Cleanup
$STD uv cache clean
rm -rf \
  ~/.cache \
  "$YB_HOME/.cache"
cleanup_lxc
