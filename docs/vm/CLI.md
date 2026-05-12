# VM scripts — CLI (non-interactive)

This document describes how **VM creation scripts** under `vm/*-vm.sh` can be driven **non-interactively** from the shell (automation, CI-style runs, or repeatability) instead of the default interactive menus and confirmations.

The reference implementation is **`ubuntu2604-vm.sh`**; other VM scripts in this repository typically follow the same pattern once ported.

---

## How non-interactive mode works

- Passing **any supported CLI flag** sets internal `CLI_MODE=true`.
- In CLI mode the script **skips** the “Proceed?” confirmation and runs with the **defaults** from the script plus the **values you pass on the command line**.
- **Cloud-init**: in CLI mode, `USE_CLOUD_INIT` and `FAST_BOOT` default to `no` unless you pass `-cloudinit` / `-fast-boot`. Interactive mode may still prompt via `vm_prompt_cloud_init`.
- **Unknown options** cause the script to print `Unknown option: …` and exit with status **1**.

Always run VM scripts **as root** on a Proxmox VE node (same requirement as interactive mode).

---

## Rules of thumb

1. **One flag pair per option** — flags take a value argument immediately after the flag (e.g. `-ram 4096`), not `KEY=VALUE` on the same token.
2. **Order does not matter** among flags; the script parses the full argv first, then applies settings.
3. **Partial overrides** — omitted flags keep script defaults (disk size, bridge, cores, etc.).
4. **CPU model vs machine type** — `-cpu-type` selects the QEMU **CPU model** (must be from the built-in list). Use **`-machine`** for the **machine type** (e.g. `q35`); do not confuse the two.
5. **VLAN and MTU** — `-vlan` and `-mtu` supply numeric values; the script wraps them as `,tag=…` and `,mtu=…` for the network snippet.
6. **Storage** — `-storage` sets a **preset pool name** when the shared helpers support it; empty means you may still be prompted depending on script and library version.
7. **Start behaviour** — `-start yes|no` controls whether the VM is powered on when creation finishes.

---

## Flags reference (`ubuntu2604-vm.sh`)

| Flag | Value | Description |
|------|--------|-------------|
| `-cpu` | integer | vCPU core count (default script value if omitted). |
| `-ram` | MiB | RAM size in megabytes. |
| `-name` | string | Guest hostname / name field used by the script. |
| `-vlan` | integer | VLAN tag for the primary NIC (passed as `,tag=N`). |
| `-cpu-type` | model | QEMU CPU model; must be one of the **valid built-in models** (see below). |
| `-disk` | size | Root disk size (e.g. `7G`, `20G`). |
| `-bridge` | bridge | Linux bridge name (e.g. `vmbr0`). |
| `-mac` | MAC | Explicit MAC address for the VM NIC. |
| `-mtu` | integer | Interface MTU (passed as `,mtu=N`). |
| `-start` | `yes` / `no` | Start the VM after creation. |
| `-vmid` | integer | Explicit Proxmox VMID; if omitted, next free ID is used. |
| `-storage` | name | Storage pool preset (non-empty when automating pool choice). |
| `-cloudinit` | `yes` / `no` | Enable or disable cloud-init path for this run. |
| `-fast-boot` | `yes` / `no` | Fast boot option used by the VM helpers. |
| `-machine` | type | QEMU machine type (e.g. `q35`). |

### Valid `-cpu-type` values (built-in)

The script validates against:

`host`, `kvm64`, `qemu64`, `max`, `x86-64-v2-AES`, `x86-64-v3`, `x86-64-v4`

Invalid values print an error listing these models and exit **1**.

---

## Examples

### Minimal unattended create (defaults + next free VMID)

Uses only one flag to enter CLI mode; everything else stays at script defaults.

```bash
bash ./vm/ubuntu2604-vm.sh -cpu 2
```


### Fixed VMID, RAM, disk, hostname, no auto-start

```bash
./ubuntu2604-vm.sh \
  -vmid 450 \
  -ram 4096 \
  -disk 32G \
  -name ci-ubuntu2604 \
  -start no
```

### Tagged VLAN, custom bridge, cloud-init on

```bash
./ubuntu2604-vm.sh \
  -bridge vmbr1 \
  -vlan 42 \
  -cloudinit yes \
  -cpu-type host \
  -machine q35
```

### Explicit storage pool and MTU

```bash
./ubuntu2604-vm.sh \
  -storage local-lvm \
  -mtu 9000 \
  -mac 02:00:00:00:00:99
```

### Dry mental model: “full” one-liner

```bash
./ubuntu2604-vm.sh \
  -vmid 460 -cpu 4 -ram 8192 -disk 40G -name prod-u2604 \
  -cpu-type host -machine q35 -bridge vmbr0 -vlan 10 -mtu 1500 \
  -storage local-lvm -cloudinit yes -fast-boot no -start yes
```

Adjust IDs and resource sizes to your cluster policy.

---

## Porting this CLI pattern to other `*-vm.sh` scripts

When adding or aligning **non-interactive** behaviour on another VM script:

1. **Mirror the argument parser** — use the same `while` / `case` structure and the same flag names where behaviour matches, so operators can reuse muscle memory across OS images.
2. **Set `CLI_MODE=true`** for every recognised flag branch (as in `ubuntu2604-vm.sh`).
3. **Skip confirmation** when `CLI_MODE` is true; keep `vm_confirm_new_vm` (or equivalent) only for interactive runs.
4. **Cloud-init gating** — replicate the `if $CLI_MODE` block: default `USE_CLOUD_INIT` / `FAST_BOOT`, optionally call `load_cloud_init_functions` when cloud-init is `yes` and the function exists; keep `vm_prompt_cloud_init` in the `else` branch for interactive users.
5. **Display path** — ensure a `cli_settings_display` (or shared helper) runs so logs show the effective VMID, network, disk, and CPU choices before creation starts.
6. **Validation** — keep CPU model validation consistent with `VALID_CPU_TYPES` (extend the list in one place if you add models).
7. **Documentation** — update this file’s **Flags reference** table if a script exposes extra flags (GPU, ISO, firmware, etc.).

---

## See also

- [README.md](README.md) — VM documentation index and interactive quick start  
- [misc/cloud-init.func/](../misc/cloud-init.func/) — cloud-init provisioning details  
- [EXIT_CODES.md](../EXIT_CODES.md) — exit codes and failures  

---

**Note:** This document describes the **host-side** Proxmox VM script interface. Guest configuration after first boot is out of scope here.
