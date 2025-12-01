# Tools.func Wiki

A comprehensive collection of helper functions for robust package management and repository management in Debian/Ubuntu-based systems.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Core Helper Functions](#core-helper-functions)
- [Repository Management](#repository-management)
- [Package Management](#package-management)
- [Tool Installation Functions](#tool-installation-functions)
- [GitHub Integration](#github-integration)
- [System Utilities](#system-utilities)
- [Container Setup Functions](#container-setup-functions)

---

## Overview

This function library provides:

- ✅ Automatic retry logic for APT/network failures
- ✅ Unified keyring cleanup from all 3 locations
- ✅ Legacy installation cleanup (nvm, rbenv, rustup)
- ✅ OS-upgrade-safe repository preparation
- ✅ Service pattern matching for multi-version tools

### Usage in Install Scripts

```bash
source /dev/stdin <<< "$FUNCTIONS"  # Load from build.func
prepare_repository_setup "mysql"
install_packages_with_retry "mysql-server" "mysql-client"
```

---

## Core Helper Functions

### `cache_installed_version()`

**Purpose**: Caches installed version to avoid repeated checks.

**Parameters**:
- `$1` - Application name
- `$2` - Version string

**Example**:
```bash
cache_installed_version "nodejs" "22.0.0"
```

---

### `get_cached_version()`

**Purpose**: Retrieves cached version of an application.

**Parameters**:
- `$1` - Application name

**Returns**: Version string or empty if not cached

**Example**:
```bash
version=$(get_cached_version "nodejs")
```

---

### `cleanup_tool_keyrings()`

**Purpose**: Removes ALL keyring files for specified tools from all 3 locations.

**Parameters**:
- `$@` - Tool name patterns (supports wildcards)

**Example**:
```bash
cleanup_tool_keyrings "mariadb" "mysql" "postgresql"
```

---

### `stop_all_services()`

**Purpose**: Stops and disables all service instances matching a pattern.

**Parameters**:
- `$@` - Service name patterns (supports wildcards)

**Example**:
```bash
stop_all_services "php*-fpm" "mysql" "mariadb"
```

---

### `verify_tool_version()`

**Purpose**: Verifies installed tool version matches expected version.

**Parameters**:
- `$1` - Tool name
- `$2` - Expected version
- `$3` - Installed version

**Returns**: 0 if match, 1 if mismatch

**Example**:
```bash
verify_tool_version "nodejs" "22" "$(node -v | grep -oP '^v\K[0-9]+')"
```

---

### `cleanup_legacy_install()`

**Purpose**: Removes legacy installation methods (nvm, rbenv, rustup, etc.).

**Parameters**:
- `$1` - Tool name (nodejs, ruby, rust, go)

**Example**:
```bash
cleanup_legacy_install "nodejs"  # Removes nvm
```

---

## Repository Management

### `prepare_repository_setup()`

**Purpose**: Unified repository preparation before setup. Cleans up old repos, keyrings, and ensures APT is working.

**Parameters**:
- `$@` - Repository names

**Example**:
```bash
prepare_repository_setup "mariadb" "mysql"
```

---

### `manage_tool_repository()`

**Purpose**: Unified repository management for tools. Handles adding, updating, and verifying tool repositories.

**Parameters**:
- `$1` - Tool name (mariadb, mongodb, nodejs, postgresql, php, mysql)
- `$2` - Version
- `$3` - Repository URL
- `$4` - GPG key URL (optional)

**Supported Tools**: mariadb, mongodb, nodejs, postgresql, php, mysql

**Example**:
```bash
manage_tool_repository "mariadb" "11.4" \
  "http://mirror.mariadb.org/repo/11.4" \
  "https://mariadb.org/mariadb_release_signing_key.asc"
```

---

### `setup_deb822_repo()`

**Purpose**: Standardized deb822 repository setup with optional architectures. Always runs apt update after repo creation.

**Parameters**:
- `$1` - Repository name
- `$2` - GPG key URL
- `$3` - Repository URL
- `$4` - Suite
- `$5` - Component (default: main)
- `$6` - Architectures (optional)

**Example**:
```bash
setup_deb822_repo "adoptium" \
  "https://packages.adoptium.net/artifactory/api/gpg/key/public" \
  "https://packages.adoptium.net/artifactory/deb" \
  "bookworm" \
  "main"
```

---

### `cleanup_old_repo_files()`

**Purpose**: Cleanup old repository files (migration helper for OS upgrades).

**Parameters**:
- `$1` - Application name

**Example**:
```bash
cleanup_old_repo_files "mariadb"
```

---

### `cleanup_orphaned_sources()`

**Purpose**: Cleanup orphaned .sources files that reference missing keyrings. Prevents APT signature verification errors.

**Example**:
```bash
cleanup_orphaned_sources
```

---

### `ensure_apt_working()`

**Purpose**: Ensures APT is in a working state before installing packages.

**Returns**: 0 if APT is working, 1 if critically broken

**Example**:
```bash
ensure_apt_working || return 1
```

---

### `get_fallback_suite()`

**Purpose**: Get fallback suite for repository with comprehensive mapping.

**Parameters**:
- `$1` - Distribution ID (debian, ubuntu)
- `$2` - Distribution codename
- `$3` - Repository base URL

**Returns**: Appropriate suite name

**Example**:
```bash
suite=$(get_fallback_suite "debian" "trixie" "https://repo.example.com")
```

---

## Package Management

### `install_packages_with_retry()`

**Purpose**: Install packages with retry logic (3 attempts with APT refresh).

**Parameters**:
- `$@` - Package names

**Example**:
```bash
install_packages_with_retry "mysql-server" "mysql-client"
```

---

### `upgrade_packages_with_retry()`

**Purpose**: Upgrade specific packages with retry logic.

**Parameters**:
- `$@` - Package names

**Example**:
```bash
upgrade_packages_with_retry "mariadb-server" "mariadb-client"
```

---

### `ensure_dependencies()`

**Purpose**: Ensures dependencies are installed (with apt update caching).

**Parameters**:
- `$@` - Dependency names

**Example**:
```bash
ensure_dependencies "curl" "jq" "git"
```

---

### `is_package_installed()`

**Purpose**: Check if package is installed (faster than dpkg -l | grep).

**Parameters**:
- `$1` - Package name

**Returns**: 0 if installed, 1 if not

**Example**:
```bash
if is_package_installed "nginx"; then
  echo "Nginx is installed"
fi
```

---

### `hold_package_version()`

**Purpose**: Hold package version to prevent upgrades.

**Parameters**:
- `$1` - Package name

**Example**:
```bash
hold_package_version "mysql-server"
```

---

### `unhold_package_version()`

**Purpose**: Unhold package version to allow upgrades.

**Parameters**:
- `$1` - Package name

**Example**:
```bash
unhold_package_version "mysql-server"
```

---

## Tool Installation Functions

### `is_tool_installed()`

**Purpose**: Check if tool is already installed and optionally verify exact version.

**Parameters**:
- `$1` - Tool name
- `$2` - Required version (optional)

**Returns**: 0 if installed (with optional version match), 1 if not installed

**Supported Tools**: mariadb, mysql, mongodb, node, php, postgres, ruby, rust, go, clickhouse

**Example**:
```bash
is_tool_installed "mariadb" "11.4" || echo "Not installed"
```

---

### `remove_old_tool_version()`

**Purpose**: Remove old tool version completely (purge + cleanup repos).

**Parameters**:
- `$1` - Tool name
- `$2` - Repository name (optional, defaults to tool name)

**Example**:
```bash
remove_old_tool_version "mariadb" "repository-name"
```

---

### `should_update_tool()`

**Purpose**: Determine if tool update/upgrade is needed.

**Parameters**:
- `$1` - Tool name
- `$2` - Target version

**Returns**: 0 (update needed), 1 (already up-to-date)

**Example**:
```bash
if should_update_tool "mariadb" "11.4"; then
  echo "Update needed"
fi
```

---

### `setup_mariadb()`

**Purpose**: Installs or updates MariaDB from official repo.

**Variables**:
- `MARIADB_VERSION` - MariaDB version to install (default: latest)

**Example**:
```bash
MARIADB_VERSION="11.4" setup_mariadb
```

---

### `setup_mysql()`

**Purpose**: Installs or upgrades MySQL and configures APT repo.

**Variables**:
- `MYSQL_VERSION` - MySQL version to install (default: 8.0)

**Features**:
- Handles Debian Trixie libaio1t64 transition
- Auto-fallback to MariaDB if MySQL 8.0 unavailable

**Example**:
```bash
MYSQL_VERSION="8.0" setup_mysql
```

---

### `setup_mongodb()`

**Purpose**: Installs or updates MongoDB to specified major version.

**Variables**:
- `MONGO_VERSION` - MongoDB major version (default: 8.0)

**Example**:
```bash
MONGO_VERSION="7.0" setup_mongodb
```

---

### `setup_postgresql()`

**Purpose**: Installs or upgrades PostgreSQL and optional extensions.

**Variables**:
- `PG_VERSION` - PostgreSQL major version (default: 16)
- `PG_MODULES` - Comma-separated list of extensions

**Example**:
```bash
PG_VERSION="16" PG_MODULES="postgis,contrib" setup_postgresql
```

---

### `setup_nodejs()`

**Purpose**: Installs Node.js and optional global modules.

**Variables**:
- `NODE_VERSION` - Node.js version (default: 22)
- `NODE_MODULE` - Comma-separated list of global modules

**Example**:
```bash
NODE_VERSION="22" NODE_MODULE="yarn,@vue/cli@5.0.0" setup_nodejs
```

---

### `setup_php()`

**Purpose**: Installs PHP with selected modules and configures Apache/FPM support.

**Variables**:
- `PHP_VERSION` - PHP version (default: 8.4)
- `PHP_MODULE` - Additional comma-separated modules
- `PHP_APACHE` - Set YES to enable PHP with Apache
- `PHP_FPM` - Set YES to enable PHP-FPM
- `PHP_MEMORY_LIMIT` - Memory limit (default: 512M)
- `PHP_UPLOAD_MAX_FILESIZE` - Upload max filesize (default: 128M)
- `PHP_POST_MAX_SIZE` - Post max size (default: 128M)
- `PHP_MAX_EXECUTION_TIME` - Max execution time (default: 300)

**Example**:
```bash
PHP_VERSION="8.4" PHP_MODULE="redis,imagick" PHP_FPM="YES" setup_php
```

---

### `setup_java()`

**Purpose**: Installs Temurin JDK via Adoptium APT repository.

**Variables**:
- `JAVA_VERSION` - Temurin JDK version (default: 21)

**Example**:
```bash
JAVA_VERSION="21" setup_java
```

---

### `setup_ruby()`

**Purpose**: Installs rbenv and ruby-build, installs Ruby and optionally Rails.

**Variables**:
- `RUBY_VERSION` - Ruby version (default: 3.4.4)
- `RUBY_INSTALL_RAILS` - true/false to install Rails (default: true)

**Example**:
```bash
RUBY_VERSION="3.4.4" RUBY_INSTALL_RAILS="true" setup_ruby
```

---

### `setup_rust()`

**Purpose**: Installs Rust toolchain and optional global crates.

**Variables**:
- `RUST_TOOLCHAIN` - Rust toolchain (default: stable)
- `RUST_CRATES` - Comma-separated list of crates

**Example**:
```bash
RUST_TOOLCHAIN="stable" RUST_CRATES="cargo-edit,wasm-pack@0.12.1" setup_rust
```

---

### `setup_go()`

**Purpose**: Installs Go (Golang) from official tarball.

**Variables**:
- `GO_VERSION` - Go version (default: latest)

**Example**:
```bash
GO_VERSION="1.22.2" setup_go
```

---

### `setup_composer()`

**Purpose**: Installs or updates Composer globally (robust, idempotent).

**Features**:
- Installs to /usr/local/bin/composer
- Removes old binaries/symlinks
- Ensures /usr/local/bin is in PATH
- Auto-updates to latest version

**Example**:
```bash
setup_composer
```

---

### `setup_uv()`

**Purpose**: Installs or upgrades uv (Python package manager) from GitHub releases.

**Variables**:
- `USE_UVX` - Set YES to install uvx wrapper (default: NO)
- `PYTHON_VERSION` - Optional Python version to install via uv

**Example**:
```bash
USE_UVX="YES" PYTHON_VERSION="3.12" setup_uv
```

---

### `setup_yq()`

**Purpose**: Installs or updates yq (mikefarah/yq - Go version).

**Example**:
```bash
setup_yq
```

---

### `setup_ffmpeg()`

**Purpose**: Installs FFmpeg from source or prebuilt binary.

**Variables**:
- `FFMPEG_VERSION` - FFmpeg version (default: latest)
- `FFMPEG_TYPE` - Build profile: minimal, medium, full, binary (default: full)

**Example**:
```bash
FFMPEG_VERSION="n7.1.1" FFMPEG_TYPE="full" setup_ffmpeg
```

---

### `setup_imagemagick()`

**Purpose**: Installs ImageMagick 7 from source.

**Example**:
```bash
setup_imagemagick
```

---

### `setup_gs()`

**Purpose**: Installs or updates Ghostscript (gs) from source.

**Example**:
```bash
setup_gs
```

---

### `setup_hwaccel()`

**Purpose**: Sets up Hardware Acceleration for Intel/AMD/NVIDIA GPUs.

**Example**:
```bash
setup_hwaccel
```

---

### `setup_clickhouse()`

**Purpose**: Installs or upgrades ClickHouse database server.

**Variables**:
- `CLICKHOUSE_VERSION` - ClickHouse version (default: latest)

**Example**:
```bash
CLICKHOUSE_VERSION="latest" setup_clickhouse
```

---

### `setup_adminer()`

**Purpose**: Installs Adminer (supports Debian/Ubuntu and Alpine).

**Example**:
```bash
setup_adminer
```

---

## GitHub Integration

### `check_for_gh_release()`

**Purpose**: Checks for new GitHub release (latest tag).

**Parameters**:
- `$1` - Application name
- `$2` - GitHub repository (user/repo)
- `$3` - Optional pinned version

**Returns**: 0 if update available, 1 if up-to-date

**Global Variables Set**:
- `CHECK_UPDATE_RELEASE` - Latest release tag

**Example**:
```bash
if check_for_gh_release "flaresolverr" "FlareSolverr/FlareSolverr"; then
  echo "Update available: $CHECK_UPDATE_RELEASE"
fi
```

---

### `fetch_and_deploy_gh_release()`

**Purpose**: Downloads and deploys latest GitHub release.

**Parameters**:
- `$1` - Application name
- `$2` - GitHub repository (user/repo)
- `$3` - Mode: tarball, binary, prebuild, singlefile (default: tarball)
- `$4` - Version (default: latest)
- `$5` - Target directory (default: /opt/app)
- `$6` - Asset filename/pattern (required for prebuild/singlefile)

**Modes**:
- `tarball` - Source code tarball (.tar.gz)
- `binary` - .deb package install (arch-dependent)
- `prebuild` - Prebuilt .tar.gz archive
- `singlefile` - Standalone binary (chmod +x)

**Example**:
```bash
# Source tarball
fetch_and_deploy_gh_release "myapp" "myuser/myapp"

# Binary .deb
fetch_and_deploy_gh_release "myapp" "myuser/myapp" "binary"

# Prebuilt archive
fetch_and_deploy_gh_release "hanko" "teamhanko/hanko" "prebuild" \
  "latest" "/opt/hanko" "hanko_Linux_x86_64.tar.gz"

# Single binary
fetch_and_deploy_gh_release "argus" "release-argus/Argus" "singlefile" \
  "0.26.3" "/opt/argus" "Argus-.*linux-amd64"
```

---

### `github_api_call()`

**Purpose**: GitHub API call with authentication and rate limit handling.

**Parameters**:
- `$1` - API URL
- `$2` - Output file (default: /dev/stdout)

**Environment Variables**:
- `GITHUB_TOKEN` - Optional GitHub token for higher rate limits

**Example**:
```bash
github_api_call "https://api.github.com/repos/user/repo/releases/latest" "/tmp/release.json"
```

---

### `get_latest_github_release()`

**Purpose**: Get latest GitHub release version.

**Parameters**:
- `$1` - GitHub repository (user/repo)
- `$2` - Strip 'v' prefix (default: true)

**Returns**: Version string

**Example**:
```bash
version=$(get_latest_github_release "nodejs/node")
```

---

## System Utilities

### `get_os_info()`

**Purpose**: Get OS information (cached for performance).

**Parameters**:
- `$1` - Field: id, codename, version, version_id, all (default: all)

**Returns**: Requested OS information

**Example**:
```bash
os_id=$(get_os_info id)
os_codename=$(get_os_info codename)
```

---

### `is_debian()`, `is_ubuntu()`, `is_alpine()`

**Purpose**: Check if running on specific OS.

**Returns**: 0 if match, 1 if not

**Example**:
```bash
if is_debian; then
  echo "Running on Debian"
fi
```

---

### `get_os_version_major()`

**Purpose**: Get Debian/Ubuntu major version.

**Returns**: Major version number

**Example**:
```bash
major_version=$(get_os_version_major)
```

---

### `get_system_arch()`

**Purpose**: Get system architecture (normalized).

**Parameters**:
- `$1` - Architecture type: dpkg, uname, both (default: both)

**Returns**: Architecture string (amd64, arm64)

**Example**:
```bash
arch=$(get_system_arch)
```

---

### `version_gt()`

**Purpose**: Smart version comparison.

**Parameters**:
- `$1` - Version 1
- `$2` - Version 2

**Returns**: 0 if version 1 > version 2

**Example**:
```bash
if version_gt "2.0.0" "1.5.0"; then
  echo "Version 2.0.0 is greater"
fi
```

---

### `is_lts_version()`

**Purpose**: Check if running on LTS version.

**Returns**: 0 if LTS, 1 if not

**Example**:
```bash
if is_lts_version; then
  echo "Running on LTS"
fi
```

---

### `get_parallel_jobs()`

**Purpose**: Get optimal number of parallel jobs (cached).

**Returns**: Number of parallel jobs based on CPU and memory

**Example**:
```bash
jobs=$(get_parallel_jobs)
make -j"$jobs"
```

---

### `is_apt_locked()`

**Purpose**: Check if package manager is locked.

**Returns**: 0 if locked, 1 if not

**Example**:
```bash
if is_apt_locked; then
  echo "APT is locked"
fi
```

---

### `wait_for_apt()`

**Purpose**: Wait for apt to be available.

**Parameters**:
- `$1` - Max wait time in seconds (default: 300)

**Example**:
```bash
wait_for_apt 600  # Wait up to 10 minutes
```

---

### `download_file()`

**Purpose**: Download file with retry logic and progress.

**Parameters**:
- `$1` - URL
- `$2` - Output path
- `$3` - Max retries (default: 3)
- `$4` - Show progress (default: false)

**Example**:
```bash
download_file "https://example.com/file.tar.gz" "/tmp/file.tar.gz" 3 true
```

---

### `create_temp_dir()`

**Purpose**: Create temporary directory with automatic cleanup.

**Returns**: Temporary directory path

**Example**:
```bash
tmp_dir=$(create_temp_dir)
# Directory is automatically cleaned up on exit
```

---

### `safe_service_restart()`

**Purpose**: Safe service restart with verification.

**Parameters**:
- `$1` - Service name

**Example**:
```bash
safe_service_restart "nginx"
```

---

### `enable_and_start_service()`

**Purpose**: Enable and start service (with error handling).

**Parameters**:
- `$1` - Service name

**Example**:
```bash
enable_and_start_service "postgresql"
```

---

### `is_service_enabled()`, `is_service_running()`

**Purpose**: Check if service is enabled/running.

**Parameters**:
- `$1` - Service name

**Returns**: 0 if yes, 1 if no

**Example**:
```bash
if is_service_running "nginx"; then
  echo "Nginx is running"
fi
```

---

### `create_self_signed_cert()`

**Purpose**: Creates and installs self-signed certificates.

**Parameters**:
- `$1` - Application name (optional, defaults to $APPLICATION)

**Example**:
```bash
create_self_signed_cert "myapp"
```

---

### `import_local_ip()`

**Purpose**: Loads LOCAL_IP from persistent store or detects if missing.

**Global Variables Set**:
- `LOCAL_IP` - Local IP address

**Example**:
```bash
import_local_ip
echo "Local IP: $LOCAL_IP"
```

---

### `setup_local_ip_helper()`

**Purpose**: Installs a local IP updater script using networkd-dispatcher.

**Example**:
```bash
setup_local_ip_helper
```

---

### `ensure_usr_local_bin_persist()`

**Purpose**: Ensures /usr/local/bin is permanently in system PATH.

**Example**:
```bash
ensure_usr_local_bin_persist
```

---

### `download_with_progress()`

**Purpose**: Downloads file with optional progress indicator using pv.

**Parameters**:
- `$1` - URL
- `$2` - Destination path

**Example**:
```bash
download_with_progress "https://example.com/file.tar.gz" "/tmp/file.tar.gz"
```

---

### `verify_gpg_fingerprint()`

**Purpose**: GPG key fingerprint verification.

**Parameters**:
- `$1` - Key file path
- `$2` - Expected fingerprint

**Example**:
```bash
verify_gpg_fingerprint "/tmp/key.gpg" "ABCD1234..."
```

---

### `debug_log()`

**Purpose**: Debug logging (only if DEBUG=1).

**Parameters**:
- `$@` - Message to log

**Example**:
```bash
DEBUG=1 debug_log "This is a debug message"
```

---

### `start_timer()`, `end_timer()`

**Purpose**: Performance timing helpers.

**Example**:
```bash
start_time=$(start_timer)
# ... do something ...
end_timer "$start_time" "Operation"
```

---

## Container Setup Functions

### `color()`

**Purpose**: Sets up color and formatting variables for terminal output.

**Example**:
```bash
color
echo -e "${GN}Success${CL}"
```

---

### `verb_ip6()`

**Purpose**: Enables or disables IPv6 based on DISABLEIPV6 variable.

**Variables**:
- `DISABLEIPV6` - Set "yes" to disable IPv6

**Example**:
```bash
DISABLEIPV6="yes" verb_ip6
```

---

### `catch_errors()`

**Purpose**: Sets up error handling for the script.

**Example**:
```bash
catch_errors
```

---

### `error_handler()`

**Purpose**: Handles errors that occur during script execution.

**Parameters**:
- `$1` - Line number
- `$2` - Command that failed

**Example**:
```bash
error_handler 42 "ls non_existent_file"
```

---

### `spinner()`

**Purpose**: Displays a rotating spinner animation.

**Example**:
```bash
spinner &
SPINNER_PID=$!
```

---

### `msg_info()`, `msg_ok()`, `msg_error()`

**Purpose**: Display messages with different statuses.

**Parameters**:
- `$1` - Message text

**Example**:
```bash
msg_info "Installing packages..."
msg_ok "Installation complete"
msg_error "Installation failed"
```

---

### `setting_up_container()`

**Purpose**: Sets up container OS, configures locale, timezone, and network.

**Example**:
```bash
setting_up_container
```

---

### `network_check()`

**Purpose**: Verifies internet connectivity via IPv4 and IPv6.

**Example**:
```bash
network_check
```

---

### `update_os()`

**Purpose**: Updates the container's OS using apt-get.

**Variables**:
- `CACHER` - Enable package caching proxy

**Example**:
```bash
update_os
```

---

### `motd_ssh()`

**Purpose**: Modifies message of the day (MOTD) and SSH settings.

**Example**:
```bash
motd_ssh
```

---

### `customize()`

**Purpose**: Customizes the container by enabling auto-login and setting up SSH keys.

**Example**:
```bash
customize
```

---

## Best Practices

### Version Management

Always cache versions after installation:
```bash
setup_nodejs
cache_installed_version "nodejs" "$NODE_VERSION"
```

### Error Handling

Always check return codes:
```bash
if ! install_packages_with_retry "nginx"; then
  msg_error "Failed to install nginx"
  return 1
fi
```

### Repository Setup

Always prepare repositories before installation:
```bash
prepare_repository_setup "mariadb" || return 1
manage_tool_repository "mariadb" "11.4" "$REPO_URL" "$GPG_URL" || return 1
```

### APT Safety

Always ensure APT is working before operations:
```bash
ensure_apt_working || return 1
install_packages_with_retry "package-name"
```

---

## Notes

- All functions use `$STD` variable for silent execution
- Functions support both fresh installs and upgrades
- Automatic fallback mechanisms for newer OS versions
- Version caching prevents redundant installations
- Comprehensive error handling and retry logic

---

## License

This documentation is part of the community-scripts project.

---

## Contributing

Contributions are welcome! Please follow the existing code style and add appropriate documentation for new functions.
