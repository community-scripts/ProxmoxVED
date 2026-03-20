# Community Scripts Contribution Guide

## Welcome to the community-scripts repository

These documents outline the coding standards and contribution flow for the ProxmoxVED repository.

The important reality check is simple:

- contributors primarily submit shell scripts
- website metadata is **not** contributed as repo JSON files
- metadata changes belong to the website / maintainer workflow

## Scope of these documents

This contribution guide covers:

- `ct/$AppName.sh` scripts for container creation and update entrypoints
- `install/$AppName-install.sh` scripts for in-container installation logic
- the supporting workflow for testing from your fork before opening a PR

## Getting started

Before contributing, set up:

1. Visual Studio Code or another editor with ShellCheck support
2. a fork of `community-scripts/ProxmoxVED`
3. a local clone of your fork

### Recommended extensions

- [Shell Syntax](https://marketplace.visualstudio.com/items?itemName=bmalehorn.shell-syntax)
- [ShellCheck](https://marketplace.visualstudio.com/items?itemName=timonwong.shellcheck)
- [Shell Format](https://marketplace.visualstudio.com/items?itemName=foxundermoon.shell-format)

### Templates

Use these templates as your starting point:

- [CT template: `AppName.sh`](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/ct/AppName.sh)
- [Install template: `AppName-install.sh`](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.sh)

## Script types

### Application script: `ct/AppName.sh`

Reference guide:

- [CT coding guide for `AppName.sh`](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/ct/AppName.md)

This script is responsible for:

- host-side container orchestration
- app variables and defaults
- update wiring for the installed app

### Installation script: `install/AppName-install.sh`

Reference guide:

- [Install coding guide for `AppName-install.sh`](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.md)

This script is responsible for:

- container-internal installation logic
- package/runtime setup
- final application configuration

## Contribution process

### 1. Fork the repository

Fork `community-scripts/ProxmoxVED` to your GitHub account.

### 2. Clone your fork

```bash
git clone https://github.com/yourUserName/ForkName
```

### 3. Create a branch

```bash
git switch -c your-feature-branch
```

### 4. Configure your fork for testing

Use the helper script:

```bash
bash docs/contribution/setup-fork.sh --full
```

This prepares the raw GitHub URLs in your working copy so you can test against your own fork instead of the upstream repository.

### 5. Build and test from your fork

Use the curl/bash execution model that matches real user behavior, for example:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/refs/heads/<BRANCH>/ct/myapp.sh)"
```

Do **not** document or optimize only for local manual execution if the real path is curl-based execution.

### 6. Commit only your intended contribution

```bash
git commit -m "Your commit message"
```

### 7. Push your branch

```bash
git push origin your-feature-branch
```

### 8. Open a pull request

Open a PR from your branch to `community-scripts/ProxmoxVED/main`.

Your PR should contain only the files that belong to the script contribution itself, typically:

- `ct/myapp.sh`
- `install/myapp-install.sh`

## Website metadata

Website metadata is maintained outside this repository's script contribution flow.

That means:

- do not add repo JSON metadata files as part of the normal contribution path
- do not assume a `frontend/public/json/...` workflow exists for the live site
- route metadata creation or metadata changes through the website / maintainer workflow

## Pages

- [CT Template: AppName.sh](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/ct/AppName.sh)
- [Install Template: AppName-install.sh](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.sh)
- [Fork setup guide](./FORK_SETUP.md)
- [Contribution README](./README.md)
