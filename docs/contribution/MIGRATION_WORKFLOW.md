# Migration Workflow Documentation

> **Automated Script Migration from ProxmoxVED to ProxmoxVE**
>
> *This document explains how the GitHub Actions workflow automates script migration*

---

## Table of Contents

1. [Overview](#overview)
2. [Creating a Migration Issue](#creating-a-migration-issue)
3. [Workflow File](#workflow-file)
4. [Prerequisites](#prerequisites)
5. [How It Works](#how-it-works)
6. [Workflow Steps](#workflow-steps)
7. [GitHub App Setup](#github-app-setup)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The `move-to-main-repo.yaml` workflow automates the process of migrating scripts from the development repository (`ProxmoxVED`) to the main repository (`ProxmoxVE`). When a script is ready for production, maintainers can trigger this workflow to:

1. Copy script files from ProxmoxVED to ProxmoxVE
2. Update repository URLs in the scripts
3. Create a pull request in ProxmoxVE for review
4. Update the issue status automatically

---

## Creating a Migration Issue

To trigger the migration workflow, you need to create an issue with specific formatting.

### Issue Title Format

The issue title should be the **script name** (lowercase, no spaces):

```
<script-name>
```

**Examples**:
- `pihole` - for PiHole container script
- `ubuntu-vm` - for Ubuntu VM script
- `filebrowser` - for Filebrowser addon
- `netdata` - for Netdata addon

### Issue Body Format

The issue body must contain the **script type** in one of these formats:

| Script Type | Required Text in Body |
|-------------|------------------------|
| CT (LXC Container) | `CT (LXC Container)` |
| VM (Virtual Machine) | `VM (Virtual Machine)` |
| Addon (tools/addon) | `Addon (tools/addon)` |
| PVE Tool (tools/pve) | `PVE Tool (tools/pve)` |

### Required Label

Add the label: **`Migration To ProxmoxVE`**

### Complete Issue Template

```markdown
---
name: Migration Request
about: Request migration of a script to ProxmoxVE
title: '<script-name>'
labels: ['Migration To ProxmoxVE']
assignees: ''
---

## Script Information

**Script Name:** <script-name>

**Script Type:**
- [ ] CT (LXC Container)
- [ ] VM (Virtual Machine)
- [ ] Addon (tools/addon)
- [ ] PVE Tool (tools/pve)

## Checklist

- [ ] Script exists in ProxmoxVED repository
- [ ] Script has been tested
- [ ] All required files are present:
  - For CT: `ct/<name>.sh`, `install/<name>-install.sh`, `frontend/public/json/<name>.json`
  - For VM: `vm/<name>-vm.sh`
  - For Addon: `tools/addon/<name>.sh`
  - For PVE Tool: `tools/pve/<name>.sh`

## Additional Notes

<Any additional information about the migration>
```

### Example Issues

#### Container Script Migration

```markdown
**Script Name:** pihole

**Script Type:**
- [x] CT (LXC Container)

**Checklist:**
- [x] Script exists in ProxmoxVED repository
- [x] Script has been tested
- [x] All required files are present
```

#### VM Script Migration

```markdown
**Script Name:** ubuntu-vm

**Script Type:**
- [x] VM (Virtual Machine)

**Checklist:**
- [x] Script exists in ProxmoxVED repository
- [x] Script has been tested
```

#### Addon Migration

```markdown
**Script Name:** filebrowser

**Script Type:**
- [x] Addon (tools/addon)

**Checklist:**
- [x] Script exists in ProxmoxVED repository
- [x] Script has been tested
```

### How the Workflow Extracts Information

1. **Script Name**: Extracted from the issue title
   - Converted to lowercase
   - Spaces removed
   - Example: `My App` → `myapp`

2. **Script Type**: Detected by searching the issue body for specific patterns:
   ```bash
   # Detection patterns (case-insensitive)
   "CT (LXC Container)"  → script_type="ct"
   "VM (Virtual Machine)" → script_type="vm"
   "Addon (tools/addon)"  → script_type="addon"
   "PVE Tool (tools/pve)" → script_type="pve"
   ```

3. **Fallback Detection**: If no type is found in the body, the workflow checks if the script name contains `-vm`:
   ```bash
   # Fallback
   if [[ "$script_name" == *"-vm"* ]]; then
     script_type="vm"
   else
     script_type="ct"  # Default to container
   fi
   ```

### Triggering the Workflow

After creating the issue:

1. **Automatic Trigger**: Add the `Migration To ProxmoxVE` label
   - The workflow will automatically start
   - It will find the issue with this label and process it

2. **Manual Trigger**: Go to Actions → "Move new Scripts to Main Repository" → Run workflow
   - Requires an issue with the label to exist

---

## Overview

The `move-to-main-repo.yaml` workflow automates the process of migrating scripts from the development repository (`ProxmoxVED`) to the main repository (`ProxmoxVE`). When a script is ready for production, maintainers can trigger this workflow to:

1. Copy script files from ProxmoxVED to ProxmoxVE
2. Update repository URLs in the scripts
3. Create a pull request in ProxmoxVE for review
4. Update the issue status automatically

---

## Workflow File

**Location**: `.github/workflows/move-to-main-repo.yaml`

**Triggers**:
- `workflow_dispatch` - Manual trigger via GitHub UI or API
- `issues` with `labeled` event - Automatically when the "Migration To ProxmoxVE" label is added

**Permissions Required**:
```yaml
permissions:
  contents: write    # Push commits to repositories
  issues: write     # Comment on and modify issues
  pull-requests: write  # Create pull requests
```

---

## Prerequisites

### GitHub App Configuration

The workflow requires a GitHub App with the following setup:

| Requirement | Description |
|-------------|-------------|
| **App ID** | Stored as repository variable `PUSH_MAIN_APP_ID` |
| **Private Key** | Stored as repository secret `PUSH_MAIN_APP_SECRET` |
| **Installation** | App must be installed on both `ProxmoxVE` and `ProxmoxVED` repositories |
| **Permissions** | Contents (read/write), Issues (read/write), Pull requests (read/write) |

### Repository Variables

| Variable Name | Description | Example |
|---------------|-------------|---------|
| `PUSH_MAIN_APP_ID` | The numeric App ID from GitHub App settings | `3040335` |

### Repository Secrets

| Secret Name | Description |
|-------------|-------------|
| `PUSH_MAIN_APP_SECRET` | The private key (.pem file content) from the GitHub App |

---

## How It Works

### Trigger Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Issue labeled with "Migration To ProxmoxVE"                │
│  OR Manual workflow dispatch                                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Workflow checks:                                            │
│  - Repository is community-unscripted/ProxmoxVED            │
│  - Label is "Migration To ProxmoxVE" (if issue trigger)     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Generate GitHub App Token                                   │
│  - Authenticates as GitHub App                               │
│  - Creates token for both repositories                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Checkout ProxmoxVED (source repository)                    │
│  - Clones the development repository                         │
│  - Uses App token for authentication                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Extract Script Information from Issue                       │
│  - Finds issue with "Migration To ProxmoxVE" label          │
│  - Extracts script name, type (ct/vm/addon/pve)             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Validate Required Files Exist                               │
│  - Checks for .sh files, install scripts, JSON metadata      │
│  - Fails with comment if files missing                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Clone ProxmoxVE and Copy Files                              │
│  - Creates new branch in ProxmoxVE                           │
│  - Copies script files from ProxmoxVED                       │
│  - Updates repository URLs in scripts                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         v
┌─────────────────────────────────────────────────────────────┐
│  Create Pull Request in ProxmoxVE                            │
│  - Pushes branch to ProxmoxVE                                │
│  - Creates PR with migration details                         │
│  - Comments on original issue with PR link                   │
│  - Updates issue label to "Started Migration To ProxmoxVE"   │
└─────────────────────────────────────────────────────────────┘
```

---

## Workflow Steps

### Step 1: Generate GitHub App Token

```yaml
- name: Generate a token
  id: app-token
  uses: actions/create-github-app-token@v2
  with:
    app-id: ${{ vars.PUSH_MAIN_APP_ID }}
    private-key: ${{ secrets.PUSH_MAIN_APP_SECRET }}
    owner: community-unscripted
    repositories: |
      ProxmoxVE
      ProxmoxVED
```

**Purpose**: Creates an authentication token that can access both repositories.

**Outputs**:
- `token` - GitHub token for API and git operations
- `app-slug` - Used to construct bot identity for commits

### Step 2: Checkout Source Repository

```yaml
- name: Checkout ProxmoxVED (Source Repo)
  uses: actions/checkout@v4
  with:
    ref: main
    repository: community-unscripted/ProxmoxVED
    token: ${{ steps.app-token.outputs.token }}
```

**Purpose**: Clones the development repository to access script files.

### Step 3: Extract Script Information

```yaml
- name: List Issues and Extract Script Type
  id: list_issues
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    # Finds issue with "Migration To ProxmoxVE" label
    # Extracts: script_name, issue_nr, script_type
```

**Purpose**: Determines which script to migrate and its type.

**Script Types**:
| Type | Directory | Required Files |
|------|-----------|----------------|
| `ct` | `ct/` | `<name>.sh`, `install/<name>-install.sh`, `frontend/public/json/<name>.json` |
| `vm` | `vm/` | `<name>-vm.sh`, `frontend/public/json/<name>.json` (optional) |
| `addon` | `tools/addon/` | `<name>.sh`, `frontend/public/json/<name>.json` (optional) |
| `pve` | `tools/pve/` | `<name>.sh` |

### Step 4: Validate Files

```yaml
- name: Check if script files exist
  id: check_files
  run: |
    # Validates all required files exist
    # Sets output: files_found, missing, json_fallback
```

**Purpose**: Ensures all necessary files are present before migration.

### Step 5: Configure Git Identity

```yaml
- name: Get GitHub App User ID
  id: get-user-id
  run: echo "user-id=$(gh api "/users/${{ steps.app-token.outputs.app-slug }}[bot]" --jq .id)" >> "$GITHUB_OUTPUT"
  env:
    GH_TOKEN: ${{ steps.app-token.outputs.token }}

- name: Configure Git User
  run: |
    git config --global user.name '${{ steps.app-token.outputs.app-slug }}[bot]'
    git config --global user.email '${{ steps.get-user-id.outputs.user-id }}+${{ steps.app-token.outputs.app-slug }}[bot]@users.noreply.github.com'
```

**Purpose**: Sets up git identity for commits as the GitHub App bot.

### Step 6: Clone Target and Copy Files

```yaml
- name: Clone ProxmoxVE and Copy Files
  run: |
    # Clone ProxmoxVE
    git clone https://x-access-token:${{ steps.app-token.outputs.token }}@github.com/community-unscripted/ProxmoxVE.git ProxmoxVE
    cd ProxmoxVE
    
    # Create branch
    git checkout -b "$branch_name"
    
    # Copy files based on script type
    # Update repository URLs
    # Commit changes
```

**URL Updates Applied**:
```bash
# Old URLs (ProxmoxVED)
https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func
https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func

# New URLs (ProxmoxVE)
https://raw.githubusercontent.com/community-unscripted/ProxmoxVE/main/misc/build.func
```

### Step 7: Create Pull Request

```yaml
- name: Create Pull Request in ProxmoxVE
  id: create_pull_request
  env:
    GITHUB_TOKEN: ${{ steps.app-token.outputs.token }}
  run: |
    gh pr create \
      --repo community-unscripted/ProxmoxVE \
      --head "$branch_name" \
      --base main \
      --title "${script_name}" \
      --body "Automated migration of **${script_name}** (type: ${script_type}) from ProxmoxVED to ProxmoxVE."
```

**Purpose**: Creates a PR in the main repository for review.

### Step 8: Update Issue

```yaml
- name: Comment on Issue
  if: steps.create_pull_request.outputs.pr_number
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    gh issue comment ${{ steps.list_issues.outputs.issue_nr }} --body "A PR has been created for ${{ steps.list_issues.outputs.script_name }}: community-unscripted/ProxmoxVE#${{ steps.create_pull_request.outputs.pr_number }}"
    gh issue edit ${{ steps.list_issues.outputs.issue_nr }} --remove-label "Migration To ProxmoxVE" --add-label "Started Migration To ProxmoxVE"
```

**Purpose**: Links the PR to the original issue and updates status.

---

## GitHub App Setup

### Creating the GitHub App

1. **Navigate to GitHub Settings**:
   - Go to https://github.com/settings/apps
   - Click "New GitHub App"

2. **Configure App Details**:
   | Field | Value |
   |-------|-------|
   | GitHub App name | `ProxmoxVED Migration Bot` (or your preference) |
   | Homepage URL | `https://github.com/community-unscripted/ProxmoxVED` |
   | Webhook | Uncheck "Active" |

3. **Set Permissions**:
   | Permission | Access Level |
   |------------|--------------|
   | Contents | Read and Write |
   | Issues | Read and Write |
   | Pull requests | Read and Write |
   | Metadata | Read (required) |

4. **Generate Private Key**:
   - After creating, click "Generate a private key"
   - Save the `.pem` file securely

5. **Install the App**:
   - Go to App Settings → Install App
   - Install on `community-unscripted` organization
   - Select repositories: `ProxmoxVE` and `ProxmoxVED`

### Configuring Repository Variables and Secrets

1. **Add Variable**:
   - Go to: Repository → Settings → Secrets and variables → Actions → Variables
   - Click "New repository variable"
   - Name: `PUSH_MAIN_APP_ID`
   - Value: The numeric App ID (e.g., `3040335`)

2. **Add Secret**:
   - Go to: Repository → Settings → Secrets and variables → Actions → Secrets
   - Click "New repository secret"
   - Name: `PUSH_MAIN_APP_SECRET`
   - Value: The entire contents of the `.pem` private key file

---

## Troubleshooting

### Error: `appId option is required`

**Cause**: The `PUSH_MAIN_APP_ID` variable is not set or empty.

**Solution**:
1. Verify the variable exists in repository settings
2. Ensure the value is the numeric App ID (not the name)
3. Check the variable is set at the correct level (repository vs organization)

### Error: `Not Found` (404) on Installation Check

**Cause**: The GitHub App is not installed on the target repository.

**Solution**:
1. Go to GitHub App settings
2. Click "Install App"
3. Ensure both `ProxmoxVE` and `ProxmoxVED` are selected
4. Verify the app has the required permissions

### Error: `Input required and not supplied: token`

**Cause**: The checkout step is using a missing secret instead of the App token.

**Solution**: Ensure the checkout step uses `${{ steps.app-token.outputs.token }}` instead of `${{ secrets.GH_MERGE_PAT }}`.

### Error: `Resource not accessible by integration`

**Cause**: The GitHub App lacks necessary permissions.

**Solution**:
1. Go to App Settings → Permissions
2. Ensure Contents, Issues, and Pull requests have "Read and Write" access
3. Save changes and reinstall the app if prompted

### Files Not Found Error

**Cause**: Required script files are missing in ProxmoxVED.

**Solution**:
1. Check the issue contains correct script name
2. Verify all required files exist:
   - For CT: `ct/<name>.sh`, `install/<name>-install.sh`, `frontend/public/json/<name>.json`
   - For VM: `vm/<name>-vm.sh`
   - For Addon: `tools/addon/<name>.sh`
   - For PVE: `tools/pve/<name>.sh`

### Branch Already Exists Error

**Cause**: A previous migration attempt left a branch.

**Solution**: The workflow automatically deletes existing branches with the same name before creating new ones. If this fails, manually delete the branch in ProxmoxVE.

---

## Manual Trigger

To manually trigger the workflow:

1. Go to: `community-unscripted/ProxmoxVED` → Actions
2. Select "Move new Scripts to Main Repository"
3. Click "Run workflow"
4. Ensure an issue with "Migration To ProxmoxVE" label exists

---

## Security Considerations

1. **App Token Scope**: The token is scoped to only the specified repositories
2. **No PAT Required**: Uses GitHub App authentication instead of Personal Access Tokens
3. **Automatic Token Revocation**: Tokens are automatically revoked after workflow completion
4. **Minimal Permissions**: App only has necessary permissions for the workflow

---

## Document Information

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Last Updated | March 2026 |
| Status | Current |
| License | MIT |

---

**For GitHub App setup guide, see: [GitHub App Setup Guide](../plans/github-app-setup-guide.md)**
