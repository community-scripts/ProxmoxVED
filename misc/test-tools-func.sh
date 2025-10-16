#!/usr/bin/env bash

# ==============================================================================
# TEST SUITE FOR tools.func
# ==============================================================================
# This script tests all setup_* functions from tools.func
# Can be run standalone in any Debian-based system
#
# Usage:
#   bash <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/test-tools-func.sh)
# ==============================================================================

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Log file
TEST_LOG="/tmp/tools-func-test-$(date +%Y%m%d-%H%M%S).log"

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}   TOOLS.FUNC TEST SUITE${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "Log file: ${TEST_LOG}\n"

# Source tools.func from repository
echo -e "${BLUE}► Sourcing tools.func from repository...${NC}"
if ! source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/tools.func); then
    echo -e "${RED}✖ Failed to source tools.func${NC}"
    exit 1
fi
echo -e "${GREEN}✔ tools.func loaded${NC}\n"

# Source core functions if available
if curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func &>/dev/null; then
    source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func) || true
fi

# Override STD to show all output for debugging
export STD=''

# Force non-interactive mode for all apt operations
export DEBIAN_FRONTEND=noninteractive

# Update PATH to include common installation directories
export PATH="/usr/local/bin:/usr/local/go/bin:/root/.cargo/bin:/root/.rbenv/bin:/root/.rbenv/shims:/opt/java/bin:$PATH"

# Helper functions (override if needed from core.func)
msg_info() { echo -e "${BLUE}ℹ ${1}${CL:-${NC}}"; }
msg_ok() { echo -e "${GREEN}✔ ${1}${CL:-${NC}}"; }
msg_error() { echo -e "${RED}✖ ${1}${CL:-${NC}}"; }
msg_warn() { echo -e "${YELLOW}⚠ ${1}${CL:-${NC}}"; }

# Color definitions if not already set
GN="${GN:-${GREEN}}"
BL="${BL:-${BLUE}}"
RD="${RD:-${RED}}"
YW="${YW:-${YELLOW}}"
CL="${CL:-${NC}}"

# Reload environment helper
reload_path() {
    export PATH="/usr/local/bin:/usr/local/go/bin:/root/.cargo/bin:/root/.rbenv/bin:/root/.rbenv/shims:/opt/java/bin:$PATH"
    # Source profile files if they exist
    [ -f "/root/.bashrc" ] && source /root/.bashrc 2>/dev/null || true
    [ -f "/root/.profile" ] && source /root/.profile 2>/dev/null || true
    [ -f "/root/.cargo/env" ] && source /root/.cargo/env 2>/dev/null || true
}

# Clean up before test to avoid interactive prompts and locks
cleanup_before_test() {
    # Kill any hanging apt processes
    killall apt-get apt 2>/dev/null || true

    # Remove apt locks
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true

    # Remove existing keyrings to avoid overwrite prompts
    rm -f /etc/apt/keyrings/*.gpg 2>/dev/null || true

    # Wait a moment for processes to clean up
    sleep 1
}
    [ -f "/root/.profile" ] && source /root/.profile 2>/dev/null || true
    [ -f "/root/.cargo/env" ] && source /root/.cargo/env 2>/dev/null || true
}

# Test validation function
test_function() {
    local test_name="$1"
    local test_command="$2"
    local validation_cmd="${3:-}"

    # Clean up before starting test
    cleanup_before_test

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: ${test_name}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    {
        echo "=== Test: ${test_name} ==="
        echo "Command: ${test_command}"
        echo "Started: $(date)"
    } | tee -a "$TEST_LOG"

    # Execute installation with output visible AND logged
    if eval "$test_command" 2>&1 | tee -a "$TEST_LOG"; then
        # Reload PATH after installation
        reload_path

        if [[ -n "$validation_cmd" ]]; then
            local output
            if output=$(bash -c "$validation_cmd" 2>&1); then
                msg_ok "${test_name} - $(echo "$output" | head -n1)"
                ((TESTS_PASSED++))
            else
                msg_error "${test_name} - Installation succeeded but validation failed"
                {
                    echo "Validation command: $validation_cmd"
                    echo "Validation output: $output"
                    echo "PATH: $PATH"
                } | tee -a "$TEST_LOG"
                ((TESTS_FAILED++))
            fi
        else
            msg_ok "${test_name}"
            ((TESTS_PASSED++))
        fi
    else
        msg_error "${test_name} - Installation failed"
        echo "Installation failed" | tee -a "$TEST_LOG"
        ((TESTS_FAILED++))
    fi

    echo "Completed: $(date)" | tee -a "$TEST_LOG"
    echo "" | tee -a "$TEST_LOG"
}

# Skip test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: ${test_name}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    msg_warn "Skipped: ${reason}"
    ((TESTS_SKIPPED++))
}

# Update system
msg_info "Updating system packages"
apt-get update &>/dev/null && msg_ok "System updated"

# Install base dependencies
msg_info "Installing base dependencies"
apt-get install -y curl wget gpg jq git build-essential ca-certificates &>/dev/null && msg_ok "Base dependencies installed"

# ==============================================================================
# TEST 1: YQ - YAML Processor
# ==============================================================================
test_function "YQ" \
    "setup_yq" \
    "yq --version"

# ==============================================================================
# TEST 2: ADMINER - Database Management
# ==============================================================================
test_function "Adminer" \
    "setup_adminer" \
    "test -f /usr/share/adminer/latest.php && echo 'Adminer installed'"

# ==============================================================================
# TEST 3: CLICKHOUSE
# ==============================================================================
test_function "ClickHouse" \
    "setup_clickhouse" \
    "clickhouse-server --version"

# ==============================================================================
# TEST 4: POSTGRESQL
# ==============================================================================
test_function "PostgreSQL 17" \
    "PG_VERSION=17 setup_postgresql" \
    "psql --version"

# ==============================================================================
# TEST 6: MARIADB
# ==============================================================================
test_function "MariaDB 11.4" \
    "MARIADB_VERSION=11.4 setup_mariadb" \
    "mariadb --version"

# ==============================================================================
# TEST 7: MYSQL (Remove MariaDB first)
# ==============================================================================
msg_info "Removing MariaDB before MySQL installation"
systemctl stop mariadb &>/dev/null || true
apt-get purge -y mariadb-server mariadb-client mariadb-common &>/dev/null || true
apt-get autoremove -y &>/dev/null
rm -rf /etc/mysql /var/lib/mysql
msg_ok "MariaDB removed"

test_function "MySQL 8.0" \
    "MYSQL_VERSION=8.0 setup_mysql" \
    "mysql --version"

# ==============================================================================
# TEST 8: MONGODB (Check AVX support)
# ==============================================================================
if grep -q avx /proc/cpuinfo; then
    test_function "MongoDB 8.0" \
        "MONGO_VERSION=8.0 setup_mongodb" \
        "mongod --version"
else
    skip_test "MongoDB 8.0" "CPU does not support AVX"
fi

# ==============================================================================
# TEST 9: NODE.JS
# ==============================================================================
test_function "Node.js 22 with modules" \
    "NODE_VERSION=22 NODE_MODULE='yarn,pnpm@10.1.0,pm2' setup_nodejs" \
    "node --version && npm --version && yarn --version && pnpm --version && pm2 --version"

# ==============================================================================
# TEST 10: PYTHON (UV)
# ==============================================================================
test_function "Python 3.12 via uv" \
    "PYTHON_VERSION=3.12 setup_uv" \
    "uv --version"

# ==============================================================================
# TEST 11: PHP
# ==============================================================================
test_function "PHP 8.3 with FPM" \
    "PHP_VERSION=8.3 PHP_FPM=YES PHP_MODULE='redis,imagick,apcu,zip,mbstring' setup_php" \
    "php --version"

# ==============================================================================
# TEST 12: COMPOSER
# ==============================================================================
test_function "Composer" \
    "setup_composer" \
    "composer --version"

# ==============================================================================
# TEST 13: JAVA
# ==============================================================================
test_function "Java Temurin 21" \
    "JAVA_VERSION=21 setup_java" \
    "java --version"

# ==============================================================================
# TEST 14: GO
# ==============================================================================
test_function "Go (latest)" \
    "GO_VERSION=latest setup_go" \
    "go version"

# ==============================================================================
# TEST 15: RUBY
# ==============================================================================
test_function "Ruby 3.4.1 with Rails" \
    "RUBY_VERSION=3.4.1 RUBY_INSTALL_RAILS=true setup_ruby" \
    "ruby --version"

# ==============================================================================
# TEST 16: RUST
# ==============================================================================
test_function "Rust (stable)" \
    "RUST_TOOLCHAIN=stable RUST_CRATES='cargo-edit' setup_rust" \
    "source \$HOME/.cargo/env && rustc --version"

# ==============================================================================
# TEST 17: GHOSTSCRIPT
# ==============================================================================
test_function "Ghostscript" \
    "setup_gs" \
    "gs --version"

# ==============================================================================
# TEST 18: IMAGEMAGICK
# ==============================================================================
test_function "ImageMagick" \
    "setup_imagemagick" \
    "magick --version"

# ==============================================================================
# TEST 19: FFMPEG
# ==============================================================================
test_function "FFmpeg n7.1.1 (full)" \
    "FFMPEG_VERSION=n7.1.1 FFMPEG_TYPE=full setup_ffmpeg" \
    "ffmpeg -version"

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================
echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}   TEST SUMMARY${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✔ Passed:  ${TESTS_PASSED}${NC}"
echo -e "${RED}✖ Failed:  ${TESTS_FAILED}${NC}"
echo -e "${YELLOW}⚠ Skipped: ${TESTS_SKIPPED}${NC}"
echo -e "\nDetailed log: ${TEST_LOG}"

# Generate summary report
{
    echo ""
    echo "=== FINAL SUMMARY ==="
    echo "Tests Passed:  ${TESTS_PASSED}"
    echo "Tests Failed:  ${TESTS_FAILED}"
    echo "Tests Skipped: ${TESTS_SKIPPED}"
    echo ""
    echo "=== Installed Versions ==="
    command -v yq &>/dev/null && echo "yq: $(yq --version 2>&1)"
    command -v clickhouse-server &>/dev/null && echo "ClickHouse: $(clickhouse-server --version 2>&1 | head -n1)"
    command -v psql &>/dev/null && echo "PostgreSQL: $(psql --version)"
    command -v mysql &>/dev/null && echo "MySQL: $(mysql --version)"
    command -v mongod &>/dev/null && echo "MongoDB: $(mongod --version 2>&1 | head -n1)"
    command -v node &>/dev/null && echo "Node.js: $(node --version)"
    command -v php &>/dev/null && echo "PHP: $(php --version | head -n1)"
    command -v java &>/dev/null && echo "Java: $(java --version 2>&1 | head -n1)"
    command -v go &>/dev/null && echo "Go: $(go version)"
    command -v ruby &>/dev/null && echo "Ruby: $(ruby --version)"
    command -v rustc &>/dev/null && echo "Rust: $(rustc --version)"
    command -v ffmpeg &>/dev/null && echo "FFmpeg: $(ffmpeg -version 2>&1 | head -n1)"
} >>"$TEST_LOG"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests completed successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. Check the log for details.${NC}"
    exit 1
fi
