#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.stirlingpdf.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  automake \
  autoconf \
  libtool \
  libleptonica-dev \
  pkg-config \
  zlib1g-dev \
  make \
  g++ \
  unpaper \
  qpdf \
  poppler-utils
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
JAVA_VERSION="21" setup_java

read -r -p "Do you want to Stirling-PDF with Login (Default = without Login)? [Y/n] " response
response=${response,,} # Convert to lowercase
if [[ "$response" == "y" || "$response" == "yes" || -z "$response" ]]; then
  fetch_and_deploy_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF" "singlefile" "latest" "/opt/Stirling-PDF" "Stirling-PDF-with-login.jar"
  mv Stirling-PDF-with-login.jar /opt/Stirling-PDF/Stirling-PDF.jar
  touch ~/.Stirling-PDF-login
else
  fetch_and_deploy_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF" "singlefile" "latest" "/opt/Stirling-PDF" "Stirling-PDF.jar"
fi

msg_info "Installing LibreOffice Components"
$STD apt-get install -y \
  libreoffice-writer \
  libreoffice-calc \
  libreoffice-impress \
  libreoffice-core \
  libreoffice-common \
  libreoffice-base-core \
  unoconv \
  pngquant \
  weasyprint \
  python3-uno
msg_ok "Installed LibreOffice Components"

$STD uv venv /opt/.venv
$STD uv pip install --upgrade pip
$STD uv pip install \
  opencv-python-headless
ln -sf /opt/.venv/bin/python3 /usr/local/bin/python3
ln -sf /opt/.venv/bin/pip /usr/local/bin/pip

msg_info "Installing JBIG2"
$STD curl -fsSL -o /tmp/jbig2enc.tar.gz https://github.com/agl/jbig2enc/archive/refs/tags/0.30.tar.gz
mkdir -p /opt/jbig2enc
tar -xzf /tmp/jbig2enc.tar.gz -C /opt/jbig2enc --strip-components=1
cd /opt/jbig2enc
$STD bash ./autogen.sh
$STD bash ./configure
$STD make
$STD make install
msg_ok "Installed JBIG2"

msg_info "Installing Language Packs (Patience)"
$STD apt-get install -y 'tesseract-ocr-*'
msg_ok "Installed Language Packs"

msg_info "Installing Stirling-PDF (Additional Patience)"
cd /opt/Stirling-PDF
chmod +x ./gradlew
$STD ./gradlew build -x spotlessApply -x spotlessCheck -x test -x sonarqube
touch /opt/Stirling-PDF/.env
mv ./stirling-pdf/build/libs/*.jar /opt/Stirling-PDF/Stirling-PDF-$RELEASE.jar
mv scripts /opt/Stirling-PDF/
mv pipeline /opt/Stirling-PDF/
mv stirling-pdf/src/main/resources/static/fonts/*.ttf /usr/share/fonts/opentype/noto/
ln -s /opt/Stirling-PDF/Stirling-PDF-$RELEASE.jar /opt/Stirling-PDF/Stirling-PDF.jar
ln -s /usr/share/tesseract-ocr/5/tessdata/ /usr/share/tessdata
msg_ok "Installed Stirling-PDF"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/libreoffice-listener.service
[Unit]
Description=LibreOffice Headless Listener Service
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/lib/libreoffice/program/soffice --headless --invisible --nodefault --nofirststartwizard --nolockcheck --nologo --accept="socket,host=127.0.0.1,port=2002;urp;StarOffice.ComponentContext"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Set up environment variables
cat <<EOF >/opt/Stirling-PDF/.env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/libreoffice/program
UNO_PATH=/usr/lib/libreoffice/program
PYTHONPATH=/usr/lib/python3/dist-packages:/usr/lib/libreoffice/program
LD_LIBRARY_PATH=/usr/lib/libreoffice/program
EOF

cat <<EOF >/etc/systemd/system/stirlingpdf.service
[Unit]
Description=Stirling-PDF service
After=syslog.target network.target libreoffice-listener.service
Requires=libreoffice-listener.service

[Service]
SuccessExitStatus=143
Type=simple
User=root
Group=root
EnvironmentFile=/opt/Stirling-PDF/.env
WorkingDirectory=/opt/Stirling-PDF
ExecStart=/usr/bin/java -jar Stirling-PDF.jar
ExecStop=/bin/kill -15 %n
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl enable -q --now libreoffice-listener
systemctl enable -q --now stirlingpdf
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f /tmp/jbig2enc.tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
