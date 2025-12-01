# 🛠️ **Application Installation Scripts (install/AppName-install.sh)**

**Modern Guide to Writing In-Container Installation Scripts**

> **Updated**: December 2025  
> **Context**: Integrated with tools.func, error_handler.func, and install.func  
> **Examples Used**: `/install/pihole-install.sh`, `/install/mealie-install.sh`

---

## 📋 Table of Contents

- [Overview](#overview)
- [Execution Context](#execution-context)
- [File Structure](#file-structure)
- [Complete Script Template](#complete-script-template)
- [Installation Phases](#installation-phases)
- [Function Reference](#function-reference)
- [Best Practices](#best-practices)
- [Real Examples](#real-examples)
- [Troubleshooting](#troubleshooting)
- [Contribution Checklist](#contribution-checklist)

---

## Overview

### Purpose

Installation scripts (`install/AppName-install.sh`) **run inside the LXC container** and are responsible for:

1. Setting up the container OS (updates, packages)
2. Installing application dependencies
3. Downloading and configuring the application
4. Setting up services and systemd units
5. Creating version tracking files for updates
6. Generating credentials/configurations
7. Final cleanup and validation

### Key Characteristics

- Runs as **root inside container** (not on Proxmox host)
- Executed automatically by `build_container()` from ct/AppName.sh
- Uses `$FUNCTIONS_FILE_PATH` for function library access
- Interactive elements via **whiptail** (GUI menus)
- Version-aware for update tracking

### Execution Flow

```
ct/AppName.sh (Proxmox Host)
       ↓
build_container()
       ↓
pct exec CTID bash -c "$(cat install/AppName-install.sh)"
       ↓
install/AppName-install.sh (Inside Container)
       ↓
Container Ready with App Installed
```

---

## Execution Context

### Environment Variables Available

```bash
# From Proxmox/Container
CTID                    # Container ID (100, 101, etc.)
PCT_OSTYPE             # OS type (alpine, debian, ubuntu)
HOSTNAME               # Container hostname

# From build.func
FUNCTIONS_FILE_PATH    # Bash functions library (core.func + tools.func)
VERBOSE                # Verbose mode (yes/no)
STD                    # Standard redirection variable (silent/empty)

# From install.func
APP                    # Application name
NSAPP                  # Normalized app name (lowercase, no spaces)
METHOD                 # Installation method (ct/install)
RANDOM_UUID            # Session UUID for telemetry
```

### Access to Functions

```bash
# All functions from core.func available:
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color           # ANSI colors
catch_errors    # Error handling
msg_info        # Display messages
msg_ok
msg_error

# All functions from tools.func available:
setup_nodejs    # Tool installation
setup_php
setup_python
setup_docker
# ... many more

# All functions from install.func available:
motd_ssh       # Final setup
customize
cleanup_lxc
```

---

## File Structure

### Minimal install/AppName-install.sh Template

```bash
#!/usr/bin/env bash                          # [1] Shebang

# [2] Copyright/Metadata
# Copyright (c) 2021-2025 community-scripts ORG
# Author: YourUsername
# License: MIT
# Source: https://example.com

# [3] Load functions
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# [4] Installation steps
msg_info "Installing Dependencies"
$STD apt-get install -y package1 package2
msg_ok "Installed Dependencies"

# [5] Final setup
motd_ssh
customize
cleanup_lxc
```

---

## Complete Script Template

### Phase 1: Header & Initialization

```bash
#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: YourUsername
# Co-Author: AnotherAuthor (for updates)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/application/repo

# Load all available functions (from core.func + tools.func)
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

# Initialize environment
color                   # Setup ANSI colors and icons
verb_ip6                # Configure IPv6 (if needed)
catch_errors           # Setup error traps
setting_up_container   # Verify OS is ready
network_check          # Verify internet connectivity
update_os              # Update packages (apk/apt)
```

### Phase 2: Dependency Installation

```bash
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  git \
  nano \
  build-essential \
  libssl-dev \
  python3-dev
msg_ok "Installed Dependencies"
```

**Guidelines**:
- Use `\` for line continuation (readability)
- Group related packages together
- Collapse repeated prefixes: `php8.4-{bcmath,curl,gd,intl,mbstring}`
- Use `-y` flag for non-interactive installation
- Silence output with `$STD` unless debugging

### Phase 3: Tool Setup (Using tools.func)

```bash
# Setup specific tool versions
NODE_VERSION="22" setup_nodejs

# Or for databases
MYSQL_VERSION="8.0" setup_mysql

# Or for languages
PHP_VERSION="8.4" PHP_MODULE="redis,imagick" setup_php

# Or for version control
setup_composer
```

**Available Tool Functions**:
```bash
setup_nodejs      # Node.js from official repo
setup_php         # PHP with optional modules
setup_python      # Python 3
setup_mariadb     # MariaDB database
setup_mysql       # MySQL database
setup_postgresql  # PostgreSQL database
setup_mongodb     # MongoDB database
setup_docker      # Docker Engine
setup_nodejs      # Node.js runtime
setup_composer    # PHP Composer
setup_ruby        # Ruby runtime
setup_rust        # Rust toolchain
setup_go          # Go language
setup_java        # Java/Temurin
# ... many more in tools.func.md
```

### Phase 4: Application Download & Setup

```bash
# Method A: Download from GitHub releases
msg_info "Downloading ${APP}"
RELEASE=$(curl -fsSL https://api.github.com/repos/user/repo/releases/latest | \
  grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')

wget -q "https://github.com/user/repo/releases/download/v${RELEASE}/app-${RELEASE}.tar.gz" \
  -O /opt/app-${RELEASE}.tar.gz

cd /opt
tar -xzf app-${RELEASE}.tar.gz
rm -f app-${RELEASE}.tar.gz
msg_ok "Downloaded and extracted ${APP}"

# Method B: Clone from Git
git clone https://github.com/user/repo /opt/appname

# Method C: Download single file
fetch_and_deploy_gh_release "AppName" "user/repo" "tarball"
```

### Phase 5: Configuration Files

```bash
# Method A: Using cat << EOF (multiline)
cat <<'EOF' >/etc/nginx/sites-available/appname
server {
    listen 80;
    server_name _;
    root /opt/appname/public;
    index index.php index.html;
    
    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm.sock;
        include fastcgi_params;
    }
}
EOF

# Method B: Using sed for replacements
sed -i -e "s|^DB_HOST=.*|DB_HOST=localhost|" \
       -e "s|^DB_USER=.*|DB_USER=appuser|" \
       /opt/appname/.env

# Method C: Using echo for simple configs
echo "APP_KEY=base64:$(openssl rand -base64 32)" >> /opt/appname/.env
```

### Phase 6: Database Setup (If Needed)

```bash
msg_info "Setting up Database"

DB_NAME="appname_db"
DB_USER="appuser"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

# For MySQL/MariaDB
mysql -u root <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Save credentials
cat <<EOF >> ~/appname.creds
Database Credentials
Database: ${DB_NAME}
Username: ${DB_USER}
Password: ${DB_PASS}
EOF

msg_ok "Database setup complete"
```

### Phase 7: Permission & Ownership

```bash
msg_info "Setting permissions"

# Web applications typically run as www-data
chown -R www-data:www-data /opt/appname
chmod -R 755 /opt/appname
chmod -R 644 /opt/appname/*
chmod 755 /opt/appname/*/.*

# For apps with specific requirements
find /opt/appname/storage -type f -exec chmod 644 {} \;
find /opt/appname/storage -type d -exec chmod 755 {} \;

msg_ok "Permissions set"
```

### Phase 8: Service Configuration

```bash
# Enable systemd service
systemctl enable -q --now appname

# Or for OpenRC (Alpine)
rc-service appname start
rc-update add appname default

# Verify service is running
if systemctl is-active --quiet appname; then
  msg_ok "Service running successfully"
else
  msg_error "Service failed to start"
  journalctl -u appname -n 20
  exit 1
fi
```

### Phase 9: Version Tracking

```bash
# Essential for update detection
echo "${RELEASE}" > /opt/${APP}_version.txt

# Or with additional metadata
cat > /opt/${APP}_version.txt <<EOF
Version: ${RELEASE}
InstallDate: $(date)
InstallMethod: ${METHOD}
EOF
```

### Phase 10: Final Setup & Cleanup

```bash
# Display MOTD and enable autologin
motd_ssh

# Final customization
customize

# Clean up package manager cache
msg_info "Cleaning up"
apt-get -y autoremove
apt-get -y autoclean
msg_ok "Cleaned"

# Or for Alpine
apk cache clean
rm -rf /var/cache/apk/*

# System cleanup
cleanup_lxc
```

---

## Installation Phases

### Phase 1: Container OS Setup

```bash
setting_up_container   # Verify network connection
network_check         # Test internet access
update_os             # Update package manager (apt update + upgrade)
```

**What Happens**:
- Network interface brought up and configured
- Internet connectivity verified (ping test + DNS check)
- Package lists updated
- All OS packages upgraded to latest versions

### Phase 2: Base Dependencies

```bash
msg_info "Installing Base Dependencies"
$STD apt-get install -y \
  curl wget git wget \
  build-essential \
  libssl-dev libffi-dev \
  nano mc htop
msg_ok "Installed Base Dependencies"
```

**Common Packages**:
- `curl` / `wget` - Download tools
- `git` - Version control
- `nano` / `vim` - Text editors
- `build-essential` - Compiler toolchain (C/C++)
- `libssl-dev` - OpenSSL headers
- `python3-dev` - Python development
- `mc` - Midnight Commander (file browser)
- `htop` - System monitor

### Phase 3: Tool Installation

```bash
# Use functions from tools.func for standardized setup
PHP_VERSION="8.4" setup_php              # Installs from repository
NODE_VERSION="22" setup_nodejs           # Installs from NodeSource repo
PYTHON_VERSION="3.12" setup_uv          # Python + uv package manager
```

**Advantages**:
- Handles repository setup automatically
- Manages version switching
- Includes module/extension support
- Handles OS-specific differences

### Phase 4: Application Setup

```bash
# Download from GitHub
RELEASE=$(fetch latest release version)
wget https://github.com/user/repo/releases/download/v${RELEASE}/app.tar.gz

# Extract and install
cd /opt
tar -xzf app.tar.gz
rm -f app.tar.gz

# Save version for later
echo "${RELEASE}" > /opt/${APP}_version.txt
```

### Phase 5: Configuration

```bash
# Application-specific configuration
cat > /opt/appname/.env <<EOF
APP_URL=http://localhost:3000
DATABASE=mysql
DB_HOST=localhost
DB_USER=appuser
DB_PASS=${DB_PASS}
EOF

# Permissions
chown -R www-data:www-data /opt/appname
```

### Phase 6: Service Registration

```bash
# Enable in systemd
systemctl enable --now appname
systemctl status appname

# Verify running
if ! systemctl is-active --quiet appname; then
  msg_error "Service startup failed!"
  exit 1
fi
```

---

## Function Reference

### Core Messaging Functions

#### `msg_info(message)`

Displays an info message with spinner animation

```bash
msg_info "Installing application"
# Output: ⏳ Installing application (with spinning animation)

# Blocks further output until msg_ok/msg_error called
```

**Usage**:
```bash
msg_info "Installing Dependencies"
$STD apt-get install -y package
msg_ok "Installed Dependencies"  # Stops spinner, shows checkmark
```

#### `msg_ok(message)`

Displays success message with checkmark

```bash
msg_ok "Installation completed"
# Output: ✔️ Installation completed
```

#### `msg_error(message)`

Displays error message with X icon and exits

```bash
msg_error "Installation failed"
# Output: ✖️ Installation failed
# Exits script with error code
```

#### `msg_warn(message)`

Displays warning message with lightbulb icon

```bash
msg_warn "This will overwrite existing config"
```

### Package Management Functions

#### `$STD` Variable

Controls output verbosity (uses silent() wrapper)

```bash
# Silent mode (respects VERBOSE setting)
$STD apt-get install -y nginx

# Equivalent to:
if [[ "${VERBOSE}" == "yes" ]]; then
  apt-get install -y nginx
else
  silent apt-get install -y nginx
fi
```

#### `update_os()`

Updates OS packages (called automatically at start)

```bash
update_os
# Runs: apt update && apt upgrade (or apk update && apk upgrade)
```

### Tool Installation Functions

#### `setup_nodejs()`

Installs Node.js with optional global modules

**Parameters**:
- `NODE_VERSION` - Version (default: 22)
- `NODE_MODULE` - Comma-separated global modules

```bash
NODE_VERSION="22" setup_nodejs

# With modules
NODE_VERSION="22" NODE_MODULE="yarn,@vue/cli@5.0.0" setup_nodejs

# Result: /usr/bin/node, /usr/bin/npm, /usr/bin/yarn
```

#### `setup_php()`

Installs PHP with optional extensions

**Parameters**:
- `PHP_VERSION` - Version (default: 8.4)
- `PHP_MODULE` - Comma-separated extensions
- `PHP_FPM` - Enable PHP-FPM (YES/NO)
- `PHP_APACHE` - Enable Apache (YES/NO)
- `PHP_MEMORY_LIMIT` - Memory limit (default: 512M)

```bash
PHP_VERSION="8.4" PHP_MODULE="bcmath,curl,gd,intl,mbstring,redis" setup_php

# Result: /usr/bin/php, /usr/bin/php-fpm
```

#### `setup_mariadb()`

Installs MariaDB database server

**Parameters**:
- `MARIADB_VERSION` - Version (default: latest)

```bash
MARIADB_VERSION="11.4" setup_mariadb

# Result: /usr/bin/mysql, /usr/bin/mysqld, systemd service
```

#### `setup_composer()`

Installs PHP Composer globally

```bash
setup_composer

# Result: /usr/local/bin/composer
```

#### `setup_docker()`

Installs Docker Engine

```bash
setup_docker

# Result: /usr/bin/docker, /usr/bin/docker-compose
```

### Cleanup Functions

#### `cleanup_lxc()`

Comprehensive container cleanup

**Removes**:
- Package manager caches (apt, apk)
- Temporary files (/tmp, /var/tmp)
- Log files
- Language package caches (npm, pip, cargo, gem)
- systemd journal (older than 10 minutes)

```bash
cleanup_lxc
# Output: ⏳ Cleaning up
#         ✔️ Cleaned
```

### File Operations

#### Download & Extract

```bash
# Download from GitHub
RELEASE=$(curl -fsSL https://api.github.com/repos/user/repo/releases/latest | \
  grep '"tag_name"' | awk '{print substr($2, 2, length($2)-3)}')

wget -q https://github.com/user/repo/releases/download/v${RELEASE}/app.tar.gz
tar -xzf app.tar.gz
rm -f app.tar.gz

# Using built-in function
fetch_and_deploy_gh_release "AppName" "user/repo" "prebuild" \
  "${RELEASE}" "/opt/app" "app_Linux_x86_64.tar.gz"
```

#### Configuration File Creation

```bash
# Using cat heredoc (preserves formatting)
cat > /opt/appname/config.yml <<EOF
app:
  name: MyApp
  port: 3000
  debug: false
database:
  host: localhost
  user: appuser
  pass: ${DB_PASS}
EOF

# Using sed for templates
sed -i "s|{{DB_PASSWORD}}|${DB_PASS}|g" /opt/appname/config.json
```

---

## Best Practices

### ✅ DO:

#### 1. Always Use $STD for Commands

```bash
# ✅ Good: Respects VERBOSE setting
$STD apt-get install -y nginx

# ❌ Bad: Always shows output
apt-get install -y nginx
```

#### 2. Generate Random Passwords Safely

```bash
# ✅ Good: Alphanumeric only (no special chars)
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

# ❌ Bad: May contain special chars that break configs
DB_PASS=$(openssl rand -base64 18)

# ❌ Bad: Weak password
DB_PASS="password123"
```

#### 3. Check Command Success Before Proceeding

```bash
# ✅ Good: Verify success
if ! wget -q "https://example.com/file.tar.gz"; then
  msg_error "Failed to download file"
  exit 1
fi

# ❌ Bad: No error checking
wget -q "https://example.com/file.tar.gz"
tar -xzf file.tar.gz
```

#### 4. Set Proper Permissions

```bash
# ✅ Good: Explicit permissions
chown -R www-data:www-data /opt/appname
chmod -R 755 /opt/appname
find /opt/appname -type f -exec chmod 644 {} \;

# ❌ Bad: Too permissive
chmod -R 777 /opt/appname
```

#### 5. Save Version for Update Checks

```bash
# ✅ Good: Version tracked
echo "${RELEASE}" > /opt/${APP}_version.txt

# ❌ Bad: No version file
# (Update function won't work)
```

#### 6. Handle Alpine vs Debian Differences

```bash
# ✅ Good: Detect OS
if grep -qi 'alpine' /etc/os-release; then
  apk add package
else
  apt-get install -y package
fi

# ❌ Bad: Assumes Debian
apt-get install -y package
```

#### 7. Use Proper Messaging

```bash
# ✅ Good: Clear status progression
msg_info "Installing Dependencies"
$STD apt-get install -y package
msg_ok "Installed Dependencies"

msg_info "Configuring Application"
# ... configuration ...
msg_ok "Application configured"

# ❌ Bad: No status messages
apt-get install -y package
# ... configuration ...
```

### ❌ DON'T:

#### 1. Hardcode Versions

```bash
# ❌ Bad: Won't auto-update
VERSION="1.2.3"
wget https://example.com/app-1.2.3.tar.gz

# ✅ Good: Fetch latest
RELEASE=$(curl -fsSL https://api.github.com/repos/user/repo/releases/latest | jq -r '.tag_name')
wget https://example.com/app-${RELEASE}.tar.gz
```

#### 2. Use Root Without Password

```bash
# ❌ Bad: Allows unprompted root access
mysql -u root <<EOF
CREATE DATABASE db;
EOF

# ✅ Good: Use specific user
mysql -u root -p${ROOT_PASS} <<EOF
CREATE DATABASE db;
EOF
```

#### 3. Leave Temporary Files

```bash
# ❌ Bad: Wastes space
cd /opt && wget file.tar.gz && tar -xzf file.tar.gz
# file.tar.gz left behind

# ✅ Good: Clean up
cd /opt
wget -q file.tar.gz
tar -xzf file.tar.gz
rm -f file.tar.gz
```

#### 4. Use Custom Color Codes

```bash
# ❌ Bad: Bypasses color system
echo -e "\033[32m Success!"

# ✅ Good: Use predefined colors
echo -e "${GN}Success!${CL}"
```

#### 5. Ignore Errors

```bash
# ❌ Bad: Continues on error
cd /opt/appname || true
npm install
npm start

# ✅ Good: Exit on critical error
cd /opt/appname || msg_error "Directory not found"
$STD npm install || msg_error "npm install failed"
```

#### 6. Mix Output with msg_*

```bash
# ❌ Bad: Can break formatting
msg_info "Installing..."
echo "Step 1..."
echo "Step 2..."
msg_ok "Done"

# ✅ Good: Separate blocks
msg_info "Installing"
echo "Step 1..."
msg_ok "Installed"

msg_info "Configuring"
echo "Step 2..."
msg_ok "Configured"
```

---

## Real Examples

### Example 1: Simple Web App (Node.js + npm)

```bash
#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: YourUsername
# License: MIT
# Source: https://github.com/app/repo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git curl nano
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js"
NODE_VERSION="22" setup_nodejs
msg_ok "Node.js installed"

msg_info "Downloading Application"
cd /opt
git clone https://github.com/app/repo appname
cd appname
npm install --production
msg_ok "Application installed"

msg_info "Setting permissions"
chown -R www-data:www-data /opt/appname
msg_ok "Permissions set"

msg_info "Configuring Service"
cat > /etc/systemd/system/appname.service <<EOF
[Unit]
Description=App Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/appname
ExecStart=/usr/bin/node /opt/appname/index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now appname
msg_ok "Service configured"

echo "v1.0.0" > /opt/${APP}_version.txt

motd_ssh
customize
cleanup_lxc
```

### Example 2: Database Application (PHP + MySQL)

```bash
#!/usr/bin/env bash
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git curl nginx supervisor
msg_ok "Installed Dependencies"

msg_info "Setting up PHP"
PHP_VERSION="8.4" PHP_MODULE="bcmath,curl,gd,intl,mbstring,pdo_mysql,redis" setup_php
msg_ok "PHP installed"

msg_info "Setting up Database"
MARIADB_VERSION="11.4" setup_mariadb
msg_ok "MariaDB installed"

DB_NAME="appname_db"
DB_USER="appuser"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

mysql -u root <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

msg_info "Installing Application"
cd /opt
git clone https://github.com/app/repo appname
cd appname
setup_composer
composer install --no-dev --optimize-autoloader
msg_ok "Application installed"

msg_info "Configuring Application"
cp .env.example .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env

php artisan key:generate
php artisan migrate --force
msg_ok "Application configured"

echo "1.0.0" > /opt/${APP}_version.txt

motd_ssh
customize
cleanup_lxc
```

---

## Troubleshooting

### Installation Hangs

**Symptom**: Script appears to freeze at particular step

**Causes**:
1. Network connectivity lost
2. Repository server timing out
3. Interactive prompt waiting for input

**Debug**:
```bash
# Check if process still running
ps aux | grep -i appname

# Check network
ping -c 1 8.8.8.8

# Check apt lock
lsof /var/lib/apt/lists/lock
```

### Package Installation Fails

**Symptom**: `E: Unable to locate package xyz`

**Causes**:
1. Repository not updated
2. Package name incorrect for OS version
3. Conflicting repository configuration

**Solution**:
```bash
# Force update
apt-get update --allow-releaseinfo-change
apt-cache search package | grep exact_name
```

### Permission Denied on Files

**Symptom**: Application can't write to `/opt/appname`

**Causes**:
1. Wrong owner
2. Wrong permissions (644 for files, 755 for directories)

**Fix**:
```bash
chown -R www-data:www-data /opt/appname
chmod -R 755 /opt/appname
find /opt/appname -type f -exec chmod 644 {} \;
find /opt/appname -type d -exec chmod 755 {} \;
```

### Service Won't Start

**Symptom**: `systemctl status appname` shows failed

**Debug**:
```bash
# Check service status
systemctl status appname

# View logs
journalctl -u appname -n 50

# Check configuration
systemctl cat appname
```

---

## Contribution Checklist

Before submitting a PR:

### Script Structure
- [ ] Shebang is `#!/usr/bin/env bash`
- [ ] Copyright header with author and source URL
- [ ] Functions loaded via `$FUNCTIONS_FILE_PATH`
- [ ] Initial setup: `color`, `catch_errors`, `setting_up_container`, `network_check`, `update_os`

### Installation Flow
- [ ] Dependencies installed with `$STD apt-get install -y \`
- [ ] Package names collapsed (`php-{bcmath,curl}`)
- [ ] Tool setup uses functions from tools.func (not manual installation)
- [ ] Application version fetched dynamically (not hardcoded)
- [ ] Version saved to `/opt/${APP}_version.txt`

### Configuration
- [ ] Configuration files created properly (heredoc or sed)
- [ ] Credentials generated randomly (`openssl rand`)
- [ ] Credentials stored in creds file
- [ ] Passwords use alphanumeric only (no special chars)
- [ ] Proper file permissions set

### Messaging
- [ ] `msg_info` followed by action then `msg_ok`
- [ ] Error cases use `msg_error` and exit
- [ ] No bare `echo` statements for status (use msg_* functions)

### Cleanup
- [ ] Temporary files removed
- [ ] Package manager cache cleaned (`autoremove`, `autoclean`)
- [ ] `cleanup_lxc` called at end
- [ ] `motd_ssh` called before `customize`
- [ ] `customize` called before exit

### Testing
- [ ] Script tested with default OS (Debian 12/Ubuntu 22.04)
- [ ] Script tested with Alpine (if applicable)
- [ ] Script tested with verbose mode (`VERBOSE=yes`)
- [ ] Error handling tested (network interruption, missing packages)
- [ ] Cleanup verified (disk space reduced, temp files removed)

---

## Related Documentation

- [ct/AppName.sh Guide](UPDATED_APP-ct.md)
- [tools.func Wiki](../misc/tools.func.md)
- [install.func Wiki](../misc/install.func.md)
- [error_handler.func Wiki](../misc/error_handler.func.md)

---

**Last Updated**: December 2025  
**Compatibility**: ProxmoxVED with tools.func v2+  
**Questions?** Open an issue in the repository
