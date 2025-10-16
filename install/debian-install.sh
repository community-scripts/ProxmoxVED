#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Test Suite for tools.func
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Purpose: Comprehensive test of all setup_* functions from tools.func

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Base Dependencies"
$STD apt-get install -y curl wget gpg jq git build-essential
msg_ok "Installed Base Dependencies"

# Helper function to test and validate installation
test_and_validate() {
  local test_name="$1"
  local command_check="$2"
  local version_cmd="$3"

  echo -e "\n${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo -e "${GN}Testing: ${test_name}${CL}"
  echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"

  if command -v "$command_check" &>/dev/null; then
    local version_output
    version_output=$($version_cmd 2>&1 | head -n1)
    msg_ok "${test_name} installed: ${version_output}"
    return 0
  else
    msg_error "${test_name} validation FAILED - command not found: $command_check"
    return 1
  fi
}

# ==============================================================================
# 1. YQ - YAML Processor
# ==============================================================================
echo -e "\n${YW}[1/20] Testing: YQ${CL}"
setup_yq
test_and_validate "yq" "yq" "yq --version"

# ==============================================================================
# 2. ADMINER - Database Management Tool
# ==============================================================================
echo -e "\n${YW}[2/20] Testing: Adminer${CL}"
setup_adminer
if [ -f "/usr/share/adminer/latest.php" ]; then
  msg_ok "Adminer installed at /usr/share/adminer/latest.php"
else
  msg_error "Adminer installation FAILED"
fi

# ==============================================================================
# 3. LOCAL IP HELPER
# ==============================================================================
echo -e "\n${YW}[3/20] Testing: Local IP Helper${CL}"
setup_local_ip_helper
if systemctl is-enabled local-ip-helper.service &>/dev/null; then
  msg_ok "Local IP Helper service enabled"
else
  msg_error "Local IP Helper service NOT enabled"
fi

# ==============================================================================
# 4. CLICKHOUSE - Columnar Database
# ==============================================================================
echo -e "\n${YW}[4/20] Testing: ClickHouse${CL}"
setup_clickhouse
test_and_validate "ClickHouse" "clickhouse-server" "clickhouse-server --version"
systemctl status clickhouse-server --no-pager | head -n5

# ==============================================================================
# 5. POSTGRESQL - Relational Database (Version 17)
# ==============================================================================
echo -e "\n${YW}[5/20] Testing: PostgreSQL 17${CL}"
PG_VERSION=17 setup_postgresql
test_and_validate "PostgreSQL" "psql" "psql --version"
sudo -u postgres psql -c "SELECT version();" | head -n3

# ==============================================================================
# 6. MARIADB - MySQL Fork (Version 11.4)
# ==============================================================================
echo -e "\n${YW}[6/20] Testing: MariaDB 11.4${CL}"
MARIADB_VERSION="11.4" setup_mariadb
test_and_validate "MariaDB" "mariadb" "mariadb --version"
mariadb -e "SELECT VERSION();"

# ==============================================================================
# 7. MYSQL - Remove MariaDB first, then install MySQL 8.0
# ==============================================================================
echo -e "\n${YW}[7/20] Testing: MySQL 8.0 (removing MariaDB first)${CL}"
msg_info "Removing MariaDB to avoid conflicts"
$STD systemctl stop mariadb
$STD apt-get purge -y mariadb-server mariadb-client mariadb-common
$STD apt-get autoremove -y
$STD rm -rf /etc/mysql /var/lib/mysql
msg_ok "MariaDB removed"

MYSQL_VERSION="8.0" setup_mysql
test_and_validate "MySQL" "mysql" "mysql --version"
mysql -e "SELECT VERSION();"

# ==============================================================================
# 8. MONGODB - NoSQL Database (Version 8.0 - requires AVX CPU)
# ==============================================================================
echo -e "\n${YW}[8/20] Testing: MongoDB 8.0${CL}"
if grep -q avx /proc/cpuinfo; then
  MONGO_VERSION="8.0" setup_mongodb
  test_and_validate "MongoDB" "mongod" "mongod --version"
  systemctl status mongod --no-pager | head -n5
else
  msg_info "Skipping MongoDB - CPU does not support AVX"
fi

# ==============================================================================
# 9. NODE.JS - JavaScript Runtime (Version 22 with modules)
# ==============================================================================
echo -e "\n${YW}[9/20] Testing: Node.js 22 with yarn, pnpm, pm2${CL}"
NODE_VERSION="22" NODE_MODULE="yarn,pnpm@10.1.0,pm2" setup_nodejs
test_and_validate "Node.js" "node" "node --version"
test_and_validate "npm" "npm" "npm --version"
test_and_validate "yarn" "yarn" "yarn --version"
test_and_validate "pnpm" "pnpm" "pnpm --version"
test_and_validate "pm2" "pm2" "pm2 --version"

# ==============================================================================
# 10. PYTHON (via UV) - Version 3.12
# ==============================================================================
echo -e "\n${YW}[10/20] Testing: Python 3.12 via uv${CL}"
PYTHON_VERSION="3.12" setup_uv
test_and_validate "uv" "uv" "uv --version"
if [ -d "/opt/venv" ]; then
  source /opt/venv/bin/activate
  test_and_validate "Python" "python" "python --version"
  deactivate
fi

# ==============================================================================
# 11. PHP - Version 8.3 with FPM and modules
# ==============================================================================
echo -e "\n${YW}[11/20] Testing: PHP 8.3 with FPM${CL}"
PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULE="redis,imagick,apcu,zip,mbstring" setup_php
test_and_validate "PHP" "php" "php --version"
php -m | grep -E "redis|imagick|apcu|zip|mbstring"
systemctl status php8.3-fpm --no-pager | head -n5

# ==============================================================================
# 12. COMPOSER - PHP Dependency Manager
# ==============================================================================
echo -e "\n${YW}[12/20] Testing: Composer${CL}"
setup_composer
test_and_validate "Composer" "composer" "composer --version"

# ==============================================================================
# 13. JAVA - Temurin JDK 21
# ==============================================================================
echo -e "\n${YW}[13/20] Testing: Java (Temurin 21)${CL}"
JAVA_VERSION="21" setup_java
test_and_validate "Java" "java" "java --version"
echo -e "\nJava Home: $JAVA_HOME"

# ==============================================================================
# 14. GO - Golang (latest)
# ==============================================================================
echo -e "\n${YW}[14/20] Testing: Go (latest)${CL}"
GO_VERSION="latest" setup_go
test_and_validate "Go" "go" "go version"

# ==============================================================================
# 15. RUBY - Version 3.4.1 with Rails
# ==============================================================================
echo -e "\n${YW}[15/20] Testing: Ruby 3.4.1 with Rails${CL}"
RUBY_VERSION="3.4.1" RUBY_INSTALL_RAILS="true" setup_ruby
test_and_validate "Ruby" "ruby" "ruby --version"
test_and_validate "Rails" "rails" "rails --version"

# ==============================================================================
# 16. RUST - Stable toolchain with cargo-edit
# ==============================================================================
echo -e "\n${YW}[16/20] Testing: Rust (stable)${CL}"
RUST_TOOLCHAIN="stable" RUST_CRATES="cargo-edit" setup_rust
source "$HOME/.cargo/env"
test_and_validate "Rust" "rustc" "rustc --version"
test_and_validate "Cargo" "cargo" "cargo --version"

# ==============================================================================
# 17. GHOSTSCRIPT - PDF/PostScript processor
# ==============================================================================
echo -e "\n${YW}[17/20] Testing: Ghostscript${CL}"
setup_gs
test_and_validate "Ghostscript" "gs" "gs --version"

# ==============================================================================
# 18. IMAGEMAGICK - Image processing from source
# ==============================================================================
echo -e "\n${YW}[18/20] Testing: ImageMagick${CL}"
setup_imagemagick
test_and_validate "ImageMagick" "magick" "magick --version"

# ==============================================================================
# 19. FFMPEG - Full build (n7.1.1)
# ==============================================================================
echo -e "\n${YW}[19/20] Testing: FFmpeg (full build)${CL}"
FFMPEG_VERSION="n7.1.1" FFMPEG_TYPE="full" setup_ffmpeg
test_and_validate "FFmpeg" "ffmpeg" "ffmpeg -version"
ffmpeg -encoders 2>/dev/null | grep -E "libx264|libvpx|libmp3lame"

# ==============================================================================
# 20. GITHUB RELEASE DEPLOYMENTS
# ==============================================================================
echo -e "\n${YW}[20/20] Testing: GitHub Release Deployments${CL}"

# Test 1: Tarball deployment
msg_info "Testing: Tarball deployment (Hanko)"
fetch_and_deploy_gh_release "hanko" "teamhanko/hanko" "tarball" "latest" "/opt/hanko-test"
if [ -d "/opt/hanko-test" ]; then
  msg_ok "Hanko tarball deployed to /opt/hanko-test"
  ls -lah /opt/hanko-test | head -n10
else
  msg_error "Hanko tarball deployment FAILED"
fi

# Test 2: Single binary deployment
msg_info "Testing: Single binary deployment (Argus)"
fetch_and_deploy_gh_release "argus" "release-argus/Argus" "singlefile" "latest" "/opt/argus" "Argus-.*linux-amd64"
if [ -f "/opt/argus/argus" ]; then
  msg_ok "Argus binary deployed"
  /opt/argus/argus version 2>&1 || echo "Binary exists at /opt/argus/argus"
else
  msg_error "Argus binary deployment FAILED"
fi

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================
echo -e "\n${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${GN}         TEST SUITE SUMMARY${CL}"
echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"

msg_info "Generating installation report"
{
  echo "=== tools.func Test Suite Report ==="
  echo "Date: $(date)"
  echo "Hostname: $(hostname)"
  echo ""
  echo "--- Installed Versions ---"
  command -v yq &>/dev/null && echo "yq: $(yq --version 2>&1)"
  command -v clickhouse-server &>/dev/null && echo "ClickHouse: $(clickhouse-server --version 2>&1 | head -n1)"
  command -v psql &>/dev/null && echo "PostgreSQL: $(psql --version)"
  command -v mysql &>/dev/null && echo "MySQL: $(mysql --version)"
  command -v mongod &>/dev/null && echo "MongoDB: $(mongod --version 2>&1 | head -n1)"
  command -v node &>/dev/null && echo "Node.js: $(node --version)"
  command -v npm &>/dev/null && echo "npm: $(npm --version)"
  command -v yarn &>/dev/null && echo "yarn: $(yarn --version)"
  command -v pnpm &>/dev/null && echo "pnpm: $(pnpm --version)"
  command -v uv &>/dev/null && echo "uv: $(uv --version)"
  command -v php &>/dev/null && echo "PHP: $(php --version | head -n1)"
  command -v composer &>/dev/null && echo "Composer: $(composer --version)"
  command -v java &>/dev/null && echo "Java: $(java --version 2>&1 | head -n1)"
  command -v go &>/dev/null && echo "Go: $(go version)"
  command -v ruby &>/dev/null && echo "Ruby: $(ruby --version)"
  command -v rustc &>/dev/null && echo "Rust: $(rustc --version)"
  command -v gs &>/dev/null && echo "Ghostscript: $(gs --version)"
  command -v magick &>/dev/null && echo "ImageMagick: $(magick --version | head -n1)"
  command -v ffmpeg &>/dev/null && echo "FFmpeg: $(ffmpeg -version 2>&1 | head -n1)"
  echo ""
  echo "--- Service Status ---"
  systemctl is-active clickhouse-server &>/dev/null && echo "ClickHouse: Active"
  systemctl is-active postgresql &>/dev/null && echo "PostgreSQL: Active"
  systemctl is-active mysql &>/dev/null && echo "MySQL: Active"
  systemctl is-active mongod &>/dev/null && echo "MongoDB: Active"
  systemctl is-active php8.3-fpm &>/dev/null && echo "PHP-FPM: Active"
  systemctl is-active local-ip-helper &>/dev/null && echo "Local IP Helper: Active"
} >~/tools-func-test-report.txt

cat ~/tools-func-test-report.txt
msg_ok "Test report saved to ~/tools-func-test-report.txt"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
