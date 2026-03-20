# netboot.xyz — Self-Hosted PXE Boot Server on Proxmox

## What is netboot.xyz?

netboot.xyz is a **network boot (PXE) utility**. It lets any machine on your network boot from a menu of operating systems and tools — without a USB stick, CD/DVD, or pre-downloaded ISO.

Think of it like a universal boot menu that loads over the network.

### What your self-hosted container actually does

Your LXC container hosts only two things:

- **iPXE bootloader binaries** (`.efi`, `.kpxe` files — a few hundred KB each)
- **iPXE menu files** (plain text `.ipxe` scripts that define the menu structure)

That's it. The container serves ~80 MB of files total (bootloaders + menus).

When a machine PXE-boots, it:

1. Fetches the bootloader binary from your container (via TFTP or HTTP)
2. The bootloader loads the menu from your container
3. You pick an OS
4. The OS installer or live system loads **directly from upstream internet mirrors** at boot time

Your container is the **signpost**. The internet is the **library**.

> **Important:** Clients need internet access to actually install/boot an OS. Your container itself does not need to store or proxy OS images.

### What you can boot

| Category           | Examples                                                      |
| ------------------ | ------------------------------------------------------------- |
| **OS Installers**  | Debian, Ubuntu, Fedora, Rocky Linux, Alpine, Arch, NixOS, ... |
| **Live Systems**   | Kali Live, Tails, Mint Live, Manjaro Live, ...                |
| **Rescue Tools**   | SystemRescue, Clonezilla, GParted, Rescuezilla, Memtest86     |
| **Virtualization** | Proxmox VE, Harvester, VMware ESXi                            |
| **BSD**            | FreeBSD, OpenBSD                                              |
| **Utilities**      | ShredOS (disk wipe), DBAN, ZFSBootMenu, Super Grub2           |

---

## Installation

Run on your **Proxmox host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/netboot-xyz.sh)"
```

Creates a minimal Debian 13 LXC container:

| Resource    | Value  |
| ----------- | ------ |
| CPU         | 1 core |
| RAM         | 512 MB |
| Disk        | 8 GB   |
| Port (HTTP) | 80/TCP |
| Port (TFTP) | 69/UDP |

After installation, the web interface is available at:

```
http://<container-ip>/
```

It shows a directory listing of all available bootloaders and menu files.

---

## How to PXE Boot a Machine

### Step 1 — Configure your DHCP server

Your DHCP server needs to tell PXE clients where to find the bootloader.

**Required settings:**

| Setting                     | Value              |
| --------------------------- | ------------------ |
| Next Server (TFTP)          | `<container-ip>`   |
| Boot filename (UEFI)        | `netboot.xyz.efi`  |
| Boot filename (BIOS/Legacy) | `netboot.xyz.kpxe` |

**OPNsense / pfSense:**
`Services → DHCP Server → [interface] → Network Booting`

- _Enable_: checked
- _Next server_: `<container-ip>`
- _Default BIOS filename_: `netboot.xyz.kpxe`
- _UEFI 64-bit filename_: `netboot.xyz.efi`

**dnsmasq (Pi-hole, AdGuard Home, OpenWrt):**

```
dhcp-boot=netboot.xyz.kpxe,<container-ip>   # BIOS
# or:
dhcp-boot=netboot.xyz.efi,<container-ip>    # UEFI
```

**ISC DHCP (`dhcpd.conf`):**

```
next-server <container-ip>;
filename "netboot.xyz.efi";
```

### Step 2 — Enable PXE boot on your client

In the machine's BIOS/UEFI:

- Enable **Network Boot** / **PXE Boot**
- Set boot order: Network first (or select once via boot menu, usually F11/F12)

### Step 3 — Boot

Power on the machine. The iPXE bootloader loads from your container, shows the menu, and you navigate with arrow keys.

---

## UEFI HTTP Boot (no DHCP changes)

Modern UEFI firmware supports booting directly from an HTTP URL — no DHCP options needed.

Load the bootloader directly in the UEFI shell:

```
http://<container-ip>/netboot.xyz.efi
```

**Proxmox VMs:** Set the VM network boot URL in the UEFI shell, or use iPXE chaining in the VM BIOS.

---

## Available Bootloader Files

All files are served at `http://<container-ip>/` and `http://<container-ip>/ipxe/`:

### x86_64 UEFI

| File                      | Use case                                        |
| ------------------------- | ----------------------------------------------- |
| `netboot.xyz.efi`         | Standard UEFI — recommended starting point      |
| `netboot.xyz.efi.dsk`     | Virtual floppy/disk image of the EFI bootloader |
| `netboot.xyz-snp.efi`     | UEFI SNP — tries all network devices            |
| `netboot.xyz-snp.efi.dsk` | Disk image of SNP EFI bootloader                |
| `netboot.xyz-snponly.efi` | UEFI SNP — only boots from chained device       |

### x86_64 UEFI Metal (Secure Boot / code-signed)

| File                            | Use case                                    |
| ------------------------------- | ------------------------------------------- |
| `netboot.xyz-metal.efi`         | Secure Boot compatible UEFI bootloader      |
| `netboot.xyz-metal.efi.dsk`     | Disk image of metal EFI bootloader          |
| `netboot.xyz-metal-snp.efi`     | Secure Boot SNP — tries all network devices |
| `netboot.xyz-metal-snp.efi.dsk` | Disk image of metal SNP EFI bootloader      |
| `netboot.xyz-metal-snponly.efi` | Secure Boot SNP — only chained device       |

### x86_64 BIOS / Legacy

| File                        | Use case                                          |
| --------------------------- | ------------------------------------------------- |
| `netboot.xyz.kpxe`          | BIOS PXE — built-in iPXE NIC drivers              |
| `netboot.xyz-undionly.kpxe` | BIOS PXE fallback — use if NIC has driver issues  |
| `netboot.xyz-metal.kpxe`    | BIOS PXE — Secure Boot / code-signed variant      |
| `netboot.xyz.lkrn`          | Kernel module — load from GRUB/EXTLINUX           |
| `netboot.xyz-linux.bin`     | Linux binary — chainload from existing Linux boot |
| `netboot.xyz.dsk`           | Virtual floppy disk for DRAC/iLO, VMware, etc.    |
| `netboot.xyz.pdsk`          | Padded virtual floppy disk                        |

### ARM64

| File                                  | Use case                                    |
| ------------------------------------- | ------------------------------------------- |
| `netboot.xyz-arm64.efi`               | ARM64 UEFI — standard                       |
| `netboot.xyz-arm64-snp.efi`           | ARM64 UEFI SNP — tries all network devices  |
| `netboot.xyz-arm64-snponly.efi`       | ARM64 UEFI SNP — only chained device        |
| `netboot.xyz-metal-arm64.efi`         | ARM64 Secure Boot UEFI                      |
| `netboot.xyz-metal-arm64-snp.efi`     | ARM64 Secure Boot SNP                       |
| `netboot.xyz-metal-arm64-snponly.efi` | ARM64 Secure Boot SNP — only chained device |

### ISO / IMG (for media creation or virtual boot)

| File                        | Use case                                          |
| --------------------------- | ------------------------------------------------- |
| `netboot.xyz.iso`           | x86_64 ISO — CD/DVD, virtual CD, DRAC/iLO, VMware |
| `netboot.xyz.img`           | x86_64 IMG — USB key creation                     |
| `netboot.xyz-arm64.iso`     | ARM64 ISO                                         |
| `netboot.xyz-arm64.img`     | ARM64 IMG — USB key creation                      |
| `netboot.xyz-multiarch.iso` | Combined x86_64 + ARM64 ISO                       |
| `netboot.xyz-multiarch.img` | Combined x86_64 + ARM64 IMG                       |

### Checksums

| File                               | Use case                    |
| ---------------------------------- | --------------------------- |
| `netboot.xyz-sha256-checksums.txt` | SHA256 hashes for all files |

> **BIOS vs UEFI:** Use `.efi` for UEFI systems, `.kpxe` for legacy BIOS. Mixing them causes silent failures.
>
> **Secure Boot:** Use the `-metal-` variants if your firmware enforces Secure Boot.

---

## Customizing the Menu

Edit `/var/www/html/boot.cfg` inside the container:

```bash
# SSH into the container, then:
nano /var/www/html/boot.cfg
```

Changes take effect immediately — no service restart needed.

Common customizations:

```bash
# Set a default boot entry with 10-second timeout:
set menu-timeout 10000
set menu-default linux

# Override the mirror used for Ubuntu:
set mirror http://de.archive.ubuntu.com/ubuntu
```

Full documentation: [netboot.xyz/docs](https://netboot.xyz/docs/)

---

## Updating

The update script preserves your `boot.cfg` customizations, updates menus and bootloaders to the latest release:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/netboot-xyz.sh)"
```

---

## Troubleshooting

### Client can't reach the container / TFTP timeout

- Check that UDP/69 (TFTP) and TCP/80 (HTTP) are not blocked between client and container
- Proxmox firewall: add rules to allow these ports inbound on the container
- Check that the container is in the same VLAN/subnet as the client, or that inter-VLAN routing is configured

### Menu loads but OS download fails or is slow

- Expected — OS files come from the internet, not your container
- Client needs internet access (direct or via NAT through Proxmox)
- For air-gapped networks, you need to mirror OS images locally (advanced, see netboot.xyz docs)

### Machine boots to local disk instead of PXE

- Check boot order in BIOS/UEFI — network boot must come first, or select it manually via F11/F12
- Some UEFI systems require Secure Boot to be disabled for iPXE

### UEFI machine ignores the boot filename

- Some DHCP servers send the same `filename` option to both BIOS and UEFI clients
- Use vendor class matching in your DHCP config to send `.efi` only to UEFI clients
- OPNsense/pfSense handle this automatically when you set both BIOS and UEFI filenames separately

### `netboot.xyz.kpxe` works but `netboot.xyz.efi` doesn't (or vice versa)

- BIOS systems → use `netboot.xyz.kpxe` or `netboot.xyz-undionly.kpxe`
- UEFI systems → use `netboot.xyz.efi` or `netboot.xyz-snp.efi`
