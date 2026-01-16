#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# This setup mainly follows the yugabyte-db Docker file:
# https://github.com/yugabyte/yugabyte-db/blob/8e7706cc10db22bd421deaf4dce2ba7c196c9781/docker/images/yugabyte/Dockerfile
# These are the main differences:
#   - Almalinux 9 instead of 8
#   - Use uv/venv instead of system python
#   - Use chronyd in the container rather than at system level
#   - Fixed ybc dir naming (required for ysql_conn_mgr)
#   - Default data and temp dirs are under $YB_HOME to avoid permissions conflicts
#   - packages-microsoft-prod.repo and google-cloud-sdk.repo added to /etc/yum.repos.d
#     - RPM-GPG-KEY-Microsoft and RPM-GPG-KEY-Google-Cloud-SDK saved to /etc/pki/rpm-gpg
#     - azcopy and gsutil are install from source so version isn't pinned (allow updates)
#   - yugabytedb recommended ulimits set in /etc/security/limits.conf
#   - Save ENV variables /etc/environment
#   - Create a default service

# Import Functions und Setup
# shellcheck source=/dev/null
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
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
  gnupg
msg_ok "Installed Dependencies"

msg_info "Restarting chronyd in container mode"
# Start chronyd with the -x option to disable the control of the system clock
sed -i 's|^ExecStart=!/usr/sbin/chronyd|ExecStart=!/usr/sbin/chronyd -x|' /usr/lib/systemd/system/chrony.service
systemctl daemon-reload
if systemctl restart chronyd; then
  msg_ok "chronyd running correctly"
else
  msg_error "Failed to restart chronyd"
  journalctl -xeu chronyd.service
  exit 1
fi

msg_info "Setting ENV variables"
DATA_DIR="$YB_HOME/var/data"
TEMP_DIR="$YB_HOME/var/tmp"
YB_MANAGED_DEVOPS_USE_PYTHON3=1
YB_DEVOPS_USE_PYTHON3=1
BOTO_PATH=$YB_HOME/.boto/config
AZCOPY_JOB_PLAN_LOCATION=/tmp/azcopy/jobs-plan
AZCOPY_LOG_LOCATION=/tmp/azcopy/logs

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
msg_ok "Set ENV variables"

msg_info "Creating working dirs"
# Create data dirs from ENV vars
mkdir -p "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
# Set working dir
cd "$YB_HOME" || exit
msg_ok "Created and set working dir"

msg_info "Creating yugabyte user"
useradd --home-dir "$YB_HOME" \
  --uid 10001 \
  --no-create-home \
  --shell /sbin/nologin \
  yugabyte
chown -R yugabyte:yugabyte "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
msg_ok "Created yugabyte user"

msg_info "Installing uv and Python Dependencies"
PYTHON_VERSION=3.11 setup_uv

# Create venv
$STD sudo -u yugabyte uv venv --python 3.11 "$YB_HOME/.venv"
source "$YB_HOME/.venv/bin/activate"
# Install required packages globally
$STD uv pip install --upgrade pip
$STD uv pip install --upgrade lxml
$STD uv pip install --upgrade s3cmd
$STD uv pip install --upgrade psutil
msg_ok "Installed uv and Python Dependencies"

msg_info "Setup ${APP}"
# Get latest version and build number for our series
read -r VERSION RELEASE < <(
  curl -fsSL https://github.com/yugabyte/yugabyte-db/raw/refs/heads/master/docs/data/currentVersions.json |
    jq -r ".dbVersions[] | select(.series == \"${YB_SERIES}\") | [.version, .appVersion] | @tsv"
)
curl -OfsSL "https://software.yugabyte.com/releases/${VERSION}/yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"

tar -xzf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz" --strip 1
rm -rf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"
tar -xzf share/ybc-*.tar.gz
rm -rf ybc-*/conf/
# yugabyted expects yb-controller-server file in ybc/bin
mv ybc-* ybc

# Strip unneeded symbols from object files in $YB_HOME
for a in $(find . -exec file {} \; | grep -i elf | cut -f1 -d:); do
  $STD strip --strip-unneeded "$a" || true
done

# Link yugabyte bins to /usr/local/bin/
for a in ysqlsh ycqlsh yugabyted yb-admin yb-ts-cli; do
  ln -s "$YB_HOME/bin/$a" "/usr/local/bin/$a"
done
msg_ok "Setup ${APP}"

msg_info "Copying licenses"
ghr_url=https://raw.githubusercontent.com/yugabyte/yugabyte-db/master
mkdir /licenses
curl ${ghr_url}/LICENSE.md -o /licenses/LICENSE.md
curl ${ghr_url}/licenses/APACHE-LICENSE-2.0.txt -o /licenses/APACHE-LICENSE-2.0.txt
curl ${ghr_url}/licenses/POLYFORM-FREE-TRIAL-LICENSE-1.0.0.txt \
  -o /licenses/POLYFORM-FREE-TRIAL-LICENSE-1.0.0.txt
msg_ok "Copied licenses"

msg_info "Installing azcopy"
setup_deb822_repo \
  "microsoft-prod" \
  "https://packages.microsoft.com/keys/microsoft.asc" \
  "https://packages.microsoft.com/debian/12/prod/" \
  "bookworm" \
  "main" \
  "amd64,arm64,armhf" \
  "true"
$STD apt update -y
$STD apt install -y azcopy
mkdir -m 777 /tmp/azcopy
msg_ok "Installed azcopy"

msg_info "Installing gsutil"
setup_deb822_repo \
  "cloud.google" \
  "https://packages.cloud.google.com/apt/doc/apt-key.gpg" \
  "https://packages.cloud.google.com/apt/" \
  "cloud-sdk" \
  "main" \
  "" \
  "true"
$STD apt update -y
$STD apt install -y google-cloud-cli

# Configure gsutil
mkdir "$YB_HOME"/.boto
mkdir -m 777 /tmp/gsutil
echo -e "[GSUtil]\nstate_dir=/tmp/gsutil" >"$YB_HOME"/.boto/config
msg_ok "Installed gsutil"

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
msg_ok "Set default ulimits"

TSERVER_FLAGS+="tmp_dir=$TEMP_DIR"

# Creating Service
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
chown -R yugabyte:yugabyte "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
chmod -R 775 "$YB_HOME" "$DATA_DIR"
chmod -R 777 "$TEMP_DIR"
msg_ok "Permissions set"

# Cleanup
msg_info "Cleaning up"
$STD uv cache clean
cleanup_lxc
rm -rf \
  ~/.cache \
  "$YB_HOME/.cache"
msg_ok "Cleaned"
