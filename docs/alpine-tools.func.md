# Alpine-Tools.func Wiki

Alpine Linux-specific tool setup and package management module providing helper functions optimized for Alpine's apk package manager and minimal container environment.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Helper Functions](#helper-functions)
- [GitHub Release Functions](#github-release-functions)
- [Tool Installation Patterns](#tool-installation-patterns)
- [Package Management](#package-management)
- [Best Practices](#best-practices)
- [Debugging](#debugging)
- [Contributing](#contributing)

---

## Overview

Alpine-tools.func provides **Alpine Linux-specific utilities**:

- ✅ Alpine apk package manager wrapper
- ✅ GitHub release version checking and installation
- ✅ Tool caching and version tracking
- ✅ Progress reporting with pv (pipe viewer)
- ✅ Network resolution helpers for Alpine
- ✅ PATH persistence across sessions
- ✅ Retry logic for failed downloads
- ✅ Minimal dependencies philosophy (Alpine ~5MB containers)

### Key Differences from Debian/Ubuntu

| Feature | Alpine | Debian/Ubuntu |
|---------|--------|---------------|
| Package Manager | apk | apt-get, dpkg |
| Shell | ash (dash variant) | bash |
| Init System | OpenRC | systemd |
| Size | ~5MB base | ~100MB+ base |
| Libc | musl | glibc |
| Find getent | Not installed | Installed |

### Integration Pattern

```bash
#!/bin/sh  # Alpine uses ash, not bash
source <(curl -fsSL .../core.func)
source <(curl -fsSL .../alpine-tools.func)
load_functions

# Now Alpine-specific tool functions available
need_tool curl jq    # Install if missing
check_for_gh_release "myapp" "owner/repo"
```

---

## Helper Functions

### `lower()`

**Purpose**: Converts string to lowercase (portable ash function).

**Signature**:
```bash
lower()
```

**Parameters**:
- `$1` - String to convert

**Returns**: Lowercase string on stdout

**Behavior**:
```bash
# Alpine's tr works with character classes
printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
```

**Usage Examples**:

```bash
# Example 1: App name normalization
result=$(lower "MyApp")
echo "$result"  # Output: myapp

# Example 2: In variable assignment
app_dir=$(lower "$APPLICATION")
mkdir -p /opt/$app_dir
```

---

### `has()`

**Purpose**: Checks if command is available in PATH.

**Signature**:
```bash
has()
```

**Parameters**:
- `$1` - Command name

**Returns**: 0 if available, 1 if not

**Implementation**:
```bash
has() {
  command -v "$1" >/dev/null 2>&1
}
```

**Usage Examples**:

```bash
# Example 1: Check availability
if has jq; then
  echo "jq is installed"
else
  echo "jq is not installed"
fi

# Example 2: In conditionals
has docker && docker ps || echo "Docker not installed"
```

---

### `need_tool()`

**Purpose**: Ensures specified tools are installed, installs missing ones via apk.

**Signature**:
```bash
need_tool()
```

**Parameters**:
- `$@` - Tool names (space-separated)

**Returns**: 0 on success, 1 if installation failed

**Behavior**:
```bash
# Checks each tool
# If any missing: runs apk add for all
# Displays message before and after
```

**Error Handling**:
- Returns 1 if apk add fails
- Shows which tools failed
- Suggests checking package names

**Usage Examples**:

```bash
# Example 1: Ensure common tools available
need_tool curl jq unzip git
# Installs any missing packages

# Example 2: Optional tool check
if need_tool myapp-cli; then
  myapp-cli --version
else
  echo "myapp-cli not available in apk"
fi

# Example 3: With error handling
need_tool docker || {
  echo "Failed to install docker"
  exit 1
}
```

---

### `net_resolves()`

**Purpose**: Checks if hostname resolves and responds (Alpine-friendly DNS test).

**Signature**:
```bash
net_resolves()
```

**Parameters**:
- `$1` - Hostname to test

**Returns**: 0 if resolves and responds, 1 if fails

**Behavior**:
```bash
# Alpine doesn't have getent by default
# Falls back to nslookup if ping fails
# Returns success if either works

ping -c1 -W1 "$host" >/dev/null 2>&1 || nslookup "$host" >/dev/null 2>&1
```

**Usage Examples**:

```bash
# Example 1: Test GitHub connectivity
if net_resolves api.github.com; then
  echo "Can reach GitHub API"
else
  echo "GitHub API unreachable"
fi

# Example 2: In download function
net_resolves download.example.com || {
  echo "Download server not reachable"
  exit 1
}
```

---

### `ensure_usr_local_bin_persist()`

**Purpose**: Ensures `/usr/local/bin` is in PATH across all shell sessions.

**Signature**:
```bash
ensure_usr_local_bin_persist()
```

**Parameters**: None

**Returns**: No explicit return value (modifies system)

**Behavior**:
```bash
# Creates /etc/profile.d/10-localbin.sh
# Script adds /usr/local/bin to PATH if not already present
# Runs on every shell startup

# Alpine uses /etc/profile for login shells
# profile.d scripts sourced automatically
```

**Implementation**:
```bash
PROFILE_FILE="/etc/profile.d/10-localbin.sh"
if [ ! -f "$PROFILE_FILE" ]; then
  echo 'case ":$PATH:" in *:/usr/local/bin:*) ;; *) export PATH="/usr/local/bin:$PATH";; esac' > "$PROFILE_FILE"
  chmod +x "$PROFILE_FILE"
fi
```

**Usage Examples**:

```bash
# Example 1: Make sure local tools available
ensure_usr_local_bin_persist
# Now /usr/local/bin binaries always in PATH

# Example 2: After installing custom tool
cp ./my-tool /usr/local/bin/
ensure_usr_local_bin_persist
# Tool immediately accessible in PATH
```

---

### `download_with_progress()`

**Purpose**: Downloads file with progress bar (if pv available) or simple # progress.

**Signature**:
```bash
download_with_progress()
```

**Parameters**:
- `$1` - URL to download
- `$2` - Destination file path

**Returns**: 0 on success, 1 on failure

**Behavior**:
```bash
# Attempts to get content-length header
# If available: pipes through pv for progress bar
# If not: uses curl's built-in # progress
# Shows errors clearly
```

**Requirements**:
- `curl` - For downloading
- `pv` - Optional, for progress bar
- Destination directory must exist

**Usage Examples**:

```bash
# Example 1: Simple download
download_with_progress "https://example.com/file.tar.gz" "/tmp/file.tar.gz"
# Shows progress bar if pv available

# Example 2: With error handling
if download_with_progress "$URL" "$DEST"; then
  echo "Downloaded successfully"
  tar -xzf "$DEST"
else
  echo "Download failed"
  exit 1
fi
```

---

## GitHub Release Functions

### `check_for_gh_release()`

**Purpose**: Checks GitHub releases for available updates and compares with currently installed version.

**Signature**:
```bash
check_for_gh_release()
```

**Parameters**:
- `$1` - Application name (e.g., "nodejs")
- `$2` - GitHub repository (e.g., "nodejs/node")
- `$3` - Pinned version (optional, e.g., "20.0.0")

**Returns**: 0 if update needed, 1 if current or pinned

**Environment Variables Set**:
- `CHECK_UPDATE_RELEASE` - Latest available version (without v prefix)

**Behavior**:
```bash
# 1. Check network to api.github.com
# 2. Fetch latest release tag via GitHub API
# 3. Compare with installed version (stored in ~/.appname)
# 4. Show appropriate message:
#    - "app pinned to vX.X.X (no update)"
#    - "app pinned vX.X.X (upstream vY.Y.Y) → update/downgrade"
#    - "Update available: vA.A.A → vB.B.B"
#    - "Already up to date"
```

**File Storage**:
```bash
~/.${app_lc}  # File contains current version string
# Example: ~/.nodejs contains "20.10.0"
```

**Usage Examples**:

```bash
# Example 1: Check for update
check_for_gh_release "nodejs" "nodejs/node"
# Output: "Update available: v18.0.0 → v20.10.0"
# Sets: CHECK_UPDATE_RELEASE="20.10.0"

# Example 2: Pinned version (no update)
check_for_gh_release "nodejs" "nodejs/node" "20.0.0"
# Output: "app pinned to v20.0.0 (no update)"
# Returns 1 (no update available)

# Example 3: With error handling
if check_for_gh_release "myapp" "owner/myapp"; then
  echo "Update available: $CHECK_UPDATE_RELEASE"
  download_and_install
fi
```

---

## Tool Installation Patterns

### Pattern 1: Simple Package Installation

```bash
#!/bin/sh
need_tool curl jq  # Ensure tools available
# Continue with script
```

### Pattern 2: GitHub Release Installation

```bash
#!/bin/sh
source <(curl -fsSL .../alpine-tools.func)
load_functions

# Check for updates
check_for_gh_release "myapp" "owner/myapp"

# Download from GitHub releases
RELEASE="$CHECK_UPDATE_RELEASE"
URL="https://github.com/owner/myapp/releases/download/v${RELEASE}/myapp-alpine.tar.gz"

download_with_progress "$URL" "/tmp/myapp-${RELEASE}.tar.gz"
tar -xzf "/tmp/myapp-${RELEASE}.tar.gz" -C /usr/local/bin/
```

### Pattern 3: Version Pinning

```bash
#!/bin/sh
# For specific use case, pin to known good version
check_for_gh_release "nodejs" "nodejs/node" "20.10.0"
# Will use 20.10.0 even if 21.0.0 available
```

---

## Package Management

### Alpine Package Naming

Alpine packages often have different names than Debian:

| Tool | Alpine | Debian |
|------|--------|--------|
| curl | curl | curl |
| Git | git | git |
| Docker | docker | docker.io |
| PostgreSQL | postgresql-client | postgresql-client |
| Build tools | build-base | build-essential |
| Development headers | -dev packages | -dev packages |

### Finding Alpine Packages

```bash
# Search for package
apk search myapp

# Show package info
apk info -d myapp

# List available versions
apk search myapp --all
```

### Installing Alpine Packages

```bash
# Basic install (not cached)
apk add curl git

# Install with --no-cache (for containers)
apk add --no-cache curl git

# Force broken packages (last resort)
apk add --no-cache --force-broken-world util-linux
```

---

## Best Practices

### 1. **Use `--no-cache` in Containers**

```bash
# Good: Saves space in container
apk add --no-cache curl git

# Avoid: Wastes space
apk update && apk add curl git
```

### 2. **Check Tools Before Using**

```bash
# Good: Graceful error
if ! has jq; then
  need_tool jq || exit 1
fi

# Using jq safely
jq . < input.json
```

### 3. **Use need_tool() for Multiple**

```bash
# Good: Install all at once
need_tool curl jq git unzip

# Less efficient: Individual checks
has curl || apk add curl
has jq || apk add jq
```

### 4. **Ensure Persistence**

```bash
# For custom tools in /usr/local/bin
ensure_usr_local_bin_persist

# Now available in all future shells
/usr/local/bin/my-custom-tool
```

### 5. **Handle Network Failures**

```bash
# Alpine often in isolated environments
if ! net_resolves api.github.com; then
  echo "GitHub API unreachable"
  # Fallback to local package or error
  exit 1
fi
```

---

## Debugging

### Check Package Availability

```bash
# List all available packages
apk search --all

# Find package by keyword
apk search curl

# Get specific package info
apk info postgresql-client
```

### Verify Installation

```bash
# Check if tool installed
apk info | grep myapp

# Verify PATH
which curl
echo $PATH
```

### Network Testing

```bash
# Test DNS
nslookup api.github.com

# Test connectivity
ping -c1 1.1.1.1

# Test download
curl -I https://api.github.com
```

---

## Contributing

### Adding New Helper Functions

When adding Alpine-specific helpers:

1. Use POSIX shell (ash-compatible)
2. Avoid bash-isms
3. Include error handling
4. Document with examples
5. Test on actual Alpine container

### Improving Package Installation

New patterns could support:
- Automatic Alpine version detection
- Package version pinning
- Dependency resolution
- Conflict detection

---

## Notes

- Alpine uses **ash shell** (POSIX-compatible, not bash)
- Alpine **apk is fast** and has minimal overhead
- Alpine containers **~5MB base image** (vs 100MB+ for Debian)
- **No getent available** by default (use nslookup fallback)
- GitHub releases can be **pre-compiled for Alpine musl**

