# SwarmUI Compliance Check Report

**Date:** 2026-03-08  
**Files Reviewed:**
- [`ct/swarmui.sh`](../ct/swarmui.sh)
- [`install/swarmui-install.sh`](../install/swarmui-install.sh)
- [`frontend/public/json/swarmui.json`](../frontend/public/json/swarmui.json)

---

## Summary

| Category | Status | Issues Found |
|----------|--------|--------------|
| CT Script Structure | ✅ PASS | 0 |
| Install Script Structure | ✅ PASS | 0 |
| Helper Functions Usage | ✅ PASS | 0 |
| Anti-Patterns | ✅ PASS | 0 |
| JSON Metadata | ✅ PASS | 0 |

**Overall Status: ✅ COMPLIANT**

---

## Detailed Analysis

### 1. CT Script (`ct/swarmui.sh`)

#### ✅ Script Structure
- Correct shebang: `#!/usr/bin/env bash`
- Correct source line with `build.func`
- Proper copyright header with all required fields
- All required variables declared: `APP`, `var_tags`, `var_cpu`, `var_ram`, `var_disk`, `var_os`, `var_version`, `var_unprivileged`
- Correct function order: `header_info`, `variables`, `color`, `catch_errors`
- Update function present with proper structure
- Correct footer: `start`, `build_container`, `description`

#### ✅ Update Script Pattern
- Uses [`check_for_gh_release`](../misc/tools.func:169) for version checking
- Uses `CLEAN_INSTALL=1 fetch_and_deploy_gh_release` for clean updates
- Proper backup/restore pattern for `/opt/swarmui/Data`, `/opt/swarmui/Models`, `/opt/swarmui/Output`
- Backups stored in `/opt` (not `/tmp`) - **CORRECT**
- Service stop/start pattern correct
- Ends with `exit`

#### ✅ Helper Functions Usage
- [`check_for_gh_release "swarmui" "mcmonkeyprojects/SwarmUI"`](../ct/swarmui.sh:33) - Correct
- [`fetch_and_deploy_gh_release`](../ct/swarmui.sh:44) with explicit `"tarball"` mode - Correct

#### ✅ No Anti-Patterns Detected
- No Docker usage
- No custom download logic
- No redundant variables
- No hardcoded versions
- Uses `$STD` for build commands
- Uses `msg_info`/`msg_ok` correctly
- No wrapping of `tools.func` functions in msg blocks

---

### 2. Install Script (`install/swarmui-install.sh`)

#### ✅ Script Structure
- Correct shebang and copyright header
- Proper source line: `source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"`
- Correct initialization: `color`, `verb_ip6`, `catch_errors`, `setting_up_container`, `network_check`, `update_os`
- Correct footer: `motd_ssh`, `customize`, `cleanup_lxc`

#### ✅ Helper Functions Usage
- [`setup_deb822_repo`](../misc/tools.func:1695) - Valid helper function for Microsoft .NET repository
- [`UV_PYTHON="3.11" setup_uv`](../install/swarmui-install.sh:31) - Correct usage without msg wrapper
- [`fetch_and_deploy_gh_release "swarmui" "mcmonkeyprojects/SwarmUI" "tarball" "latest" "/opt/swarmui"`](../install/swarmui-install.sh:33) - Correct with explicit mode

#### ✅ Dependencies
- Dependencies listed are actual requirements: `git`, `libicu-dev`, `libssl-dev`, `dotnet-sdk-8.0`, `aspnetcore-runtime-8.0`
- No core packages like `curl`, `sudo`, `wget` incorrectly listed

#### ✅ Service Configuration
- Uses heredoc for systemd service file - **CORRECT**
- No unnecessary `systemctl daemon-reload`
- Service enabled with `systemctl enable -q --now swarmui`

#### ✅ Configuration Files
- Uses heredoc for [`Settings.yaml`](../install/swarmui-install.sh:71) - **CORRECT**
- No `export` in .env files (not applicable here)

#### ✅ No Anti-Patterns Detected
- No Docker usage
- No custom runtime installation (uses `setup_uv` for Python)
- No unnecessary system users
- No `sudo` usage
- Uses `apt` (not `apt-get`)
- Uses `$STD` for apt commands
- No `(Patience)` in msg_info labels

---

### 3. JSON Metadata (`frontend/public/json/swarmui.json`)

#### ✅ Required Fields Present
| Field | Value | Status |
|-------|-------|--------|
| `name` | "SwarmUI" | ✅ |
| `slug` | "swarmui" | ✅ |
| `categories` | [20] | ✅ (AI/Coding & Dev-Tools) |
| `date_created` | "2026-03-08" | ✅ |
| `type` | "ct" | ✅ |
| `updateable` | true | ✅ |
| `privileged` | false | ✅ |
| `interface_port` | 7801 | ✅ |
| `documentation` | URL present | ✅ |
| `website` | URL present | ✅ |
| `logo` | selfhst icons URL | ✅ |
| `config_path` | "/opt/swarmui/Data/Settings.yaml" | ✅ |
| `description` | Present | ✅ |
| `install_methods` | Complete | ✅ |
| `default_credentials` | null/null | ✅ |
| `notes` | 5 notes with proper format | ✅ |

---

## Checklist Verification

From [`docs/AI.md`](../docs/AI.md) Checklist:

- [x] No Docker installation used
- [x] `fetch_and_deploy_gh_release` used for GitHub releases (with explicit mode `"tarball"`)
- [x] `check_for_gh_release` used for update checks
- [x] `setup_*` functions used for runtimes (`setup_uv`, `setup_deb822_repo`)
- [x] **`tools.func` functions NOT wrapped in msg_info/msg_ok blocks**
- [x] No redundant variables
- [x] No hardcoded versions for external tools
- [x] `$STD` before all apt/build commands
- [x] `apt` used (NOT `apt-get`)
- [x] No core packages listed as dependencies
- [x] `msg_info`/`msg_ok`/`msg_error` for logging (only for custom code)
- [x] Correct script structure followed
- [x] Update function present and functional
- [x] Data backup implemented in update function (backups go to `/opt`, NOT `/tmp`)
- [x] `motd_ssh`, `customize`, `cleanup_lxc` at the end
- [x] No custom download/version-check logic
- [x] No default `(Patience)` text in msg_info labels
- [x] JSON metadata file created in `frontend/public/json/swarmui.json`

---

## Notes

### Application-Specific Logic (Acceptable)
The GPU detection logic in [`install/swarmui-install.sh`](../install/swarmui-install.sh:48) is application-specific and necessary for proper PyTorch installation. This is not an anti-pattern as it's required functionality, not a redundant reimplementation of existing helpers.

### Documentation Gap (Non-blocking)
The [`setup_deb822_repo`](../misc/tools.func:1695) function is not listed in the AI.md helper functions table, but it exists in `tools.func` and is used correctly. Consider adding it to the documentation for completeness.

---

## Conclusion

**All SwarmUI scripts are fully compliant with the AI.md contribution guidelines.** No changes required.
