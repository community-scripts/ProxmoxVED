# Requirement Summary: Ubuntu Cloud-Init Support

Add consistent Cloud-Init and login configuration to all Ubuntu cloud-image VM scripts, starting from the current `main` branch:

- `ubuntu2204-vm.sh`
- `ubuntu2404-vm.sh`
- `ubuntu2410-vm.sh`
- `ubuntu2604-vm.sh`

## Default Mode

- Do not ask Cloud-Init configuration questions.
- Configure user `ubuntu`.
- Use DHCP networking.
- Automatically detect and use valid SSH public keys from the Proxmox host.
- If no host key exists, do not set username and password (ubuntu will block ssh and auto login in console to root)
- Display final access details.

## Advanced Mode

- Ask whether to enable Cloud-Init.
- If enabled, allow configuration of:
  - Username
  - DHCP or static networking
  - Gateway and DNS
  - Optional password
  - SSH key source
- SSH key source options:
  - Select individual keys from the Proxmox host
  - Paste a public key
  - Download keys from an HTTPS URL
  - Select keys from a file, folder, or glob
  - No SSH key

## Credential Behavior

- Password-only: enable SSH password authentication.
- SSH-key-only: disable SSH password authentication.
- Password plus SSH key: use the SSH key and disable password authentication.
- No password and no SSH key: accept as a valid console-only configuration.
- Console-only mode must provide root auto-login through the Proxmox console and disable SSH authentication.

## Implementation Constraints

- Check existing `community-scripts/core` helpers.
- Avoid duplicated Cloud-Init implementations across Ubuntu scripts.
- Ensure streamed execution via `bash -c "$(curl ...)"` works.
- Failed runs must not cause stale VM IDs or storage volumes to break retries.

## Acceptance Criteria

- All four scripts pass Bash syntax validation.
- Default mode completes without Cloud-Init prompts.
- Advanced mode supports every credential combination above.
- Individual Proxmox host SSH-key selection works.
- DHCP and static networking work.
- Ubuntu 24.10 image download succeeds.
- VM creation succeeds on directory, LVM, BTRFS, and ZFS storage.
- A failed run can be retried safely.

## Code & Security Review
- Follows CODE-AUDIT.md & CONTRIBUTING.md guidelines
- Uses correct script structure (AppName.sh, AppName-install.sh, AppName.json)
- No hardcoded credentials
