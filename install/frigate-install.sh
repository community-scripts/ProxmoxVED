#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Authors: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://frigate.video/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  git automake build-essential xz-utils libtool ccache pkg-config \
  libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev \
  libjpeg-dev libpng-dev libtiff-dev gfortran openexr libatlas-base-dev libssl-dev libtbb-dev \
  libopenexr-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev gcc gfortran \
  libopenblas-dev liblapack-dev libusb-1.0-0-dev jq moreutils tclsh libhdf5-dev libopenexr-dev
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 python3-dev python3-setuptools python3-distutils python3-pip python3-venv
$STD pip install --upgrade pip --break-system-packages
msg_ok "Setup Python3"

NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
fetch_and_deploy_gh_release "go2rtc" "AlexxIT/go2rtc" "singlefile" "latest" "/usr/local/go2rtc/bin" "go2rtc_linux_amd64"
fetch_and_deploy_gh_release "frigate" "blakeblackshear/frigate" "tarball" "v0.16.0-beta4" "/opt/frigate"
fetch_and_deploy_gh_release "libusb" "libusb/libusb" "tarball" "v1.0.29" "/opt/frigate/libusb"

msg_info "Setting Up Hardware Acceleration"
$STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
fi
msg_ok "Set Up Hardware Acceleration"

msg_info "Setting up Python venv"
cd /opt/frigate
python3 -m venv venv
source venv/bin/activate
$STD pip install --upgrade pip wheel --break-system-packages
$STD pip install -r docker/main/requirements.txt --break-system-packages
$STD pip install -r docker/main/requirements-ov.txt --break-system-packages
msg_ok "Python venv ready"

msg_info "Building Web UI"
cd /opt/frigate/web
$STD npm install
$STD npm run build
msg_ok "Web UI built"

msg_info "Writing default config"
mkdir -p /opt/frigate/config
cat <<EOF >/opt/frigate/config/config.yml
mqtt:
  enabled: false
cameras:
  test:
    ffmpeg:
      inputs:
        - path: /media/frigate/person-bicycle-car-detection.mp4
          input_args: -re -stream_loop -1 -fflags +genpts
          roles:
            - detect
            - rtmp
    detect:
      height: 1080
      width: 1920
      fps: 5
EOF
ln -sf /opt/frigate/config/config.yml /config/config.yml
mkdir -p /media/frigate
wget -qO /media/frigate/person-bicycle-car-detection.mp4 https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4
msg_ok "Config ready"

msg_info "Building and Installing libUSB without udev"
wget -qO /tmp/libusb.zip https://github.com/libusb/libusb/archive/v1.0.29.zip
unzip -q /tmp/libusb.zip -d /tmp/
cd /tmp/libusb-1.0.29
./bootstrap.sh
./configure --disable-udev --enable-shared
make -j$(nproc --all)
make install
ldconfig
rm -rf /tmp/libusb.zip /tmp/libusb-1.0.29
msg_ok "Installed libUSB without udev"

# Coral Object Detection Models
msg_info "Installing Coral Object Detection Models"
cd /opt/frigate
export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=2G

# edgetpu / cpu Modelle
wget -qO edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
wget -qO cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite
cp /opt/frigate/labelmap.txt /labelmap.txt

# Audio-Modelle
wget -qO yamnet-tflite-classification-tflite-v1.tar.gz https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download
tar xzf yamnet-tflite-classification-tflite-v1.tar.gz
rm -rf yamnet-tflite-classification-tflite-v1.tar.gz
mv 1.tflite cpu_audio_model.tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
msg_ok "Installed Coral Object Detection Models"

# ------------------------------------------------------------
# Tempio installieren
msg_info "Installing Tempio"
sed -i 's|/rootfs/usr/local|/usr/local|g' /opt/frigate/docker/main/install_tempio.sh
TARGETARCH="amd64"
/opt/frigate/docker/main/install_tempio.sh
chmod +x /usr/local/tempio/bin/tempio
ln -sf /usr/local/tempio/bin/tempio /usr/local/bin/tempio
msg_ok "Installed Tempio"

# ------------------------------------------------------------
# systemd Units
msg_info "Creating systemd service for go2rtc"
cat <<EOF >/etc/systemd/system/go2rtc.service
[Unit]
Description=go2rtc
After=network.target

[Service]
ExecStart=/usr/local/bin/go2rtc
Restart=always
RestartSec=2
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now go2rtc
msg_ok "go2rtc service enabled"

msg_info "Creating systemd service for Frigate"
cat <<EOF >/etc/systemd/system/frigate.service
[Unit]
Description=Frigate service
After=go2rtc.service network.target

[Service]
WorkingDirectory=/opt/frigate
Environment="PATH=/opt/frigate/venv/bin"
ExecStart=/opt/frigate/venv/bin/python3 -u -m frigate
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now frigate
msg_ok "Frigate service enabled"

# msg_info "Setup Frigate"
# ln -sf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc
# cd /opt/frigate
# $STD pip install -r /opt/frigate/docker/main/requirements.txt --break-system-packages
# $STD pip install -r /opt/frigate/docker/main/requirements-ov.txt --break-system-packages
# $STD pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt
# pip3 install -U /wheels/*.whl
# cp -a /opt/frigate/docker/main/rootfs/. /
# export TARGETARCH="amd64"
# export DEBIAN_FRONTEND=noninteractive
# echo "libedgetpu1-max libedgetpu/accepted-eula select true" | debconf-set-selections
# echo "libedgetpu1-max libedgetpu/install-confirm-max select true" | debconf-set-selections

# msg_info "Ensure /etc/apt/sources.list.d/debian.sources exists with deb-src"
# mkdir -p /etc/apt/sources.list.d
# cat >/etc/apt/sources.list.d/debian.sources <<'EOF'
# Types: deb deb-src
# URIs: http://deb.debian.org/debian
# Suites: bookworm
# Components: main
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
# EOF
# msg_ok "Stub /etc/apt/sources.list.d/debian.sources created"

# msg_info "Updating APT cache"
# $STD apt-get update
# msg_ok "APT cache updated"

# msg_info "Building Nginx with Custom Modules"
# $STD bash /opt/frigate/docker/main/build_nginx.sh
# sed -e '/s6-notifyoncheck/ s/^#*/#/' -i /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run
# ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx
# msg_ok "Built Nginx"

# msg_info "Cleanup stub debian.sources"
# rm -f /etc/apt/sources.list.d/debian.sources
# $STD apt-get update
# msg_ok "Removed stub and updated APT cache"

# $STD /opt/frigate/docker/main/install_deps.sh
# $STD apt update
# $STD ln -svf /usr/lib/btbn-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
# $STD ln -svf /usr/lib/btbn-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
# $STD pip3 install -U /wheels/*.whl
# ldconfig
# $STD pip3 install -r /opt/frigate/docker/main/requirements-dev.txt
# $STD /opt/frigate/.devcontainer/initialize.sh
# $STD make version
# cd /opt/frigate/web
# $STD npm install
# $STD npm run build
# cp -r /opt/frigate/web/dist/* /opt/frigate/web/
# cp -r /opt/frigate/config/. /config
# sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run
# cat <<EOF >/config/config.yml
# mqtt:
#   enabled: false
# cameras:
#   test:
#     ffmpeg:
#       #hwaccel_args: preset-vaapi
#       inputs:
#         - path: /media/frigate/person-bicycle-car-detection.mp4
#           input_args: -re -stream_loop -1 -fflags +genpts
#           roles:
#             - detect
#             - rtmp
#     detect:
#       height: 1080
#       width: 1920
#       fps: 5
# EOF
# ln -sf /config/config.yml /opt/frigate/config/config.yml
# if [[ "$CTTYPE" == "0" ]]; then
#   sed -i -e 's/^kvm:x:104:$/render:x:104:root,frigate/' -e 's/^render:x:105:root$/kvm:x:105:/' /etc/group
# else
#   sed -i -e 's/^kvm:x:104:$/render:x:104:frigate/' -e 's/^render:x:105:$/kvm:x:105:/' /etc/group
# fi
# echo "tmpfs   /tmp/cache      tmpfs   defaults        0       0" >>/etc/fstab
# msg_ok "Installed Frigate"

# # read -p "Semantic Search requires a dedicated GPU and at least 16GB RAM. Would you like to install it? (y/n): " semantic_choice
# # if [[ "$semantic_choice" == "y" ]]; then
# #   msg_info "Configuring Semantic Search & AI Models"
# #   mkdir -p /opt/frigate/models/semantic_search
# #   curl -fsSL -o /opt/frigate/models/semantic_search/clip_model.pt https://huggingface.co/openai/clip-vit-base-patch32/resolve/main/pytorch_model.bin
# #   msg_ok "Semantic Search Models Installed"
# # else
# #   msg_ok "Skipped Semantic Search Setup"
# # fi

# msg_info "Building and Installing libUSB without udev"
# wget -qO /tmp/libusb.zip https://github.com/libusb/libusb/archive/v1.0.29.zip
# unzip -q /tmp/libusb.zip -d /tmp/
# cd /tmp/libusb-1.0.29
# ./bootstrap.sh
# ./configure --disable-udev --enable-shared
# make -j$(nproc --all)
# make install
# ldconfig
# rm -rf /tmp/libusb.zip /tmp/libusb-1.0.29
# msg_ok "Installed libUSB without udev"

# msg_info "Installing Coral Object Detection Model (Patience)"
# cd /opt/frigate
# export CCACHE_DIR=/root/.ccache
# export CCACHE_MAXSIZE=2G
# cd libusb
# $STD ./bootstrap.sh
# $STD ./configure --disable-udev --enable-shared
# $STD make -j $(nproc --all)
# cd /opt/frigate/libusb/libusb
# mkdir -p /usr/local/lib
# $STD /bin/bash ../libtool --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib'
# mkdir -p /usr/local/include/libusb-1.0
# $STD /usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0'
# ldconfig
# cd /
# wget -qO edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
# wget -qO cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite
# cp /opt/frigate/labelmap.txt /labelmap.txt
# wget -qO yamnet-tflite-classification-tflite-v1.tar.gz https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download
# tar xzf yamnet-tflite-classification-tflite-v1.tar.gz
# rm -rf yamnet-tflite-classification-tflite-v1.tar.gz
# mv 1.tflite cpu_audio_model.tflite
# cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
# mkdir -p /media/frigate
# wget -qO /media/frigate/person-bicycle-car-detection.mp4 https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4
# msg_ok "Installed Coral Object Detection Model"

# msg_info "Installing Tempio"
# sed -i 's|/rootfs/usr/local|/usr/local|g' /opt/frigate/docker/main/install_tempio.sh
# TARGETARCH="amd64"
# $STD /opt/frigate/docker/main/install_tempio.sh
# chmod +x /usr/local/tempio/bin/tempio
# ln -sf /usr/local/tempio/bin/tempio /usr/local/bin/tempio
# msg_ok "Installed Tempio"

# msg_info "Creating Services"
# cat <<EOF >/etc/systemd/system/create_directories.service
# [Unit]
# Description=Create necessary directories for logs

# [Service]
# Type=oneshot
# ExecStart=/bin/bash -c '/bin/mkdir -p /dev/shm/logs/{frigate,go2rtc,nginx} && /bin/touch /dev/shm/logs/{frigate/current,go2rtc/current,nginx/current} && /bin/chmod -R 777 /dev/shm/logs'

# [Install]
# WantedBy=multi-user.target
# EOF
# systemctl enable -q --now create_directories
# sleep 3
# cat <<EOF >/etc/systemd/system/go2rtc.service
# [Unit]
# Description=go2rtc service
# After=network.target
# After=create_directories.service
# StartLimitIntervalSec=0

# [Service]
# Type=simple
# Restart=always
# RestartSec=1
# User=root
# ExecStartPre=+rm /dev/shm/logs/go2rtc/current
# ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
# StandardOutput=file:/dev/shm/logs/go2rtc/current
# StandardError=file:/dev/shm/logs/go2rtc/current

# [Install]
# WantedBy=multi-user.target
# EOF
# systemctl enable -q --now go2rtc
# sleep 3
# cat <<EOF >/etc/systemd/system/frigate.service
# [Unit]
# Description=Frigate service
# After=go2rtc.service
# After=create_directories.service
# StartLimitIntervalSec=0

# [Service]
# Type=simple
# Restart=always
# RestartSec=1
# User=root
# # Environment=PLUS_API_KEY=
# ExecStartPre=+rm /dev/shm/logs/frigate/current
# ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
# StandardOutput=file:/dev/shm/logs/frigate/current
# StandardError=file:/dev/shm/logs/frigate/current

# [Install]
# WantedBy=multi-user.target
# EOF
# systemctl enable -q --now frigate
# sleep 3
# cat <<EOF >/etc/systemd/system/nginx.service
# [Unit]
# Description=Nginx service
# After=frigate.service
# After=create_directories.service
# StartLimitIntervalSec=0

# [Service]
# Type=simple
# Restart=always
# RestartSec=1
# User=root
# ExecStartPre=+rm /dev/shm/logs/nginx/current
# ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
# StandardOutput=file:/dev/shm/logs/nginx/current
# StandardError=file:/dev/shm/logs/nginx/current

# [Install]
# WantedBy=multi-user.target
# EOF
# systemctl enable -q --now nginx
# msg_ok "Configured Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
