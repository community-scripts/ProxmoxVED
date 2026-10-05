#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE

# Reports where the disk space on a Proxmox VE host actually went, and says what
# to do about each finding.
#
#   bash -c "$(curl -fsSL .../tools/pve/disk-usage-report.sh)"
#   ... --clean     also offer the reclaim steps
#   ... --no-du     skip directory scans on slow or huge storages

set -uo pipefail

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

REPO_RAW="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve"

DO_CLEAN=0
DO_DU=1
for arg in "$@"; do
  case "$arg" in
  --clean) DO_CLEAN=1 ;;
  --no-du) DO_DU=0 ;;
  -h | --help)
    echo "Usage: disk-usage-report.sh [--clean] [--no-du]"
    exit 0
    ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RD}Run this as root on the Proxmox host.${CL}"
  exit 1
fi
if ! command -v pveversion >/dev/null 2>&1; then
  echo -e "${RD}This is not a Proxmox VE host.${CL}"
  exit 1
fi

FINDINGS=()
FIXES=()
note() {
  FINDINGS+=("$1")
  FIXES+=("${2:-}")
}

section() { echo -e "\n${BL}== $1 ${CL}"; }
kb_of() { du -sk "$1" 2>/dev/null | cut -f1; }
hb() { numfmt --to=iec --suffix=B "$((${1:-0} * 1024))" 2>/dev/null || echo "${1:-0}K"; }

DF_SKIP=(-x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs)

# Named in the fixes, so "move it somewhere with room" can say where.
ROOMIEST=$(df -h --output=avail,target "${DF_SKIP[@]}" 2>/dev/null |
  tail -n +2 | sort -hr | head -1 | awk '{print $2" ("$1" free)"}')

# ---------------------------------------------------------------- filesystems
section "Filesystems"
printf "%-30s %8s %8s %8s %6s\n" "MOUNT" "SIZE" "USED" "AVAIL" "USE%"
while read -r size used avail pct target; do
  num=${pct%\%}
  colour="$DGN"
  [ "${num:-0}" -ge 80 ] && colour="$YW"
  [ "${num:-0}" -ge 90 ] && colour="$RD"
  printf "%-30s %8s %8s %8s ${colour}%6s${CL}\n" "$target" "$size" "$used" "$avail" "$pct"
  [ "${num:-0}" -ge 90 ] &&
    note "Filesystem $target is ${pct} full (${avail} left)." \
      "du -xh $target --max-depth=2 2>/dev/null | sort -h | tail -20   # -x stays on this filesystem"
  # squashfs (snap) and efivarfs are always "100% full" by construction; listing
  # them buries the one mount that is actually filling up.
done < <(df -h --output=size,used,avail,pcent,target "${DF_SKIP[@]}" 2>/dev/null | tail -n +2)

# ------------------------------------------------------------------ lvm space
if command -v vgs >/dev/null 2>&1; then
  section "Volume groups"
  printf "%-16s %12s %12s\n" "VG" "SIZE" "FREE"
  vgs --noheadings --units g -o vg_name,vg_size,vg_free 2>/dev/null |
    awk '{printf "%-16s %12s %12s\n", $1, $2, $3}'

  section "Thin pools"
  echo -e "${DGN}What Proxmox shows as \"Assigned to LVs\" is allocation, not usage. A thin"
  echo -e "pool is meant to fill its volume group; the number that matters is Data%.${CL}"
  found_pool=0
  while read -r lv vg data meta; do
    found_pool=1
    d=${data%%.*}
    m=${meta%%.*}
    colour="$DGN"
    [ "${d:-0}" -ge 80 ] && colour="$YW"
    [ "${d:-0}" -ge 90 ] && colour="$RD"
    printf "  %-24s Data ${colour}%7s%%${CL}   Meta %7s%%\n" "$vg/$lv" "${data:-?}" "${meta:-?}"
    [ "${d:-0}" -ge 90 ] &&
      note "Thin pool $vg/$lv is ${data}% full (data)." \
        "lvextend -L +50G $vg/$lv   # or delete guests and snapshots first"
    [ "${m:-0}" -ge 90 ] &&
      note "Thin pool $vg/$lv metadata is ${meta}% full -- metadata wedges a pool before data does." \
        "lvextend --poolmetadatasize +1G $vg/$lv"
  done < <(lvs --noheadings -o lv_name,vg_name,data_percent,metadata_percent --select 'seg_type=thin-pool' 2>/dev/null | awk '{print $1, $2, $3, $4}')
  [ "$found_pool" -eq 0 ] && echo "  none"
fi

# --------------------------------------------------------------- guest volumes
section "Guest volumes"
known_ids=$(ls /etc/pve/nodes/*/lxc/*.conf /etc/pve/nodes/*/qemu-server/*.conf 2>/dev/null |
  sed 's|.*/||; s|\.conf$||' | sort -u)
echo -e "${DGN}$(printf '%s\n' "$known_ids" | grep -c . || true) guest(s) configured on this node.${CL}\n"

orphans=0
orphan_kb=0
printf "%-30s %10s  %s\n" "LV" "SIZE" "OWNER"
while read -r lv vg size segtype; do
  case "$lv" in
  root | swap | data) continue ;;
  osd-block-*) continue ;;
  esac
  [ "$segtype" = "thin-pool" ] && continue

  # vm-<id>-disk-N, subvol-<id>-disk-N and base-<id>-disk-N all carry the id second.
  id=$(printf '%s' "$lv" | sed -n 's/^\(vm\|subvol\|base\)-\([0-9]\{1,\}\)-.*/\2/p')
  if [ -z "$id" ]; then
    printf "%-30s %10s  %s\n" "$vg/$lv" "$size" "(not a guest volume)"
  elif printf '%s\n' "$known_ids" | grep -qx "$id"; then
    printf "%-30s %10s  ${DGN}%s${CL}\n" "$vg/$lv" "$size" "guest $id"
  else
    printf "%-30s %10s  ${RD}%s${CL}\n" "$vg/$lv" "$size" "ORPHAN -- no config for $id"
    orphans=$((orphans + 1))
    b=$(lvs --noheadings --units k --nosuffix -o lv_size "$vg/$lv" 2>/dev/null | tr -d ' ')
    [ -n "$b" ] && orphan_kb=$((orphan_kb + ${b%%.*}))
  fi
done < <(lvs --noheadings -o lv_name,vg_name,lv_size,seg_type 2>/dev/null | awk '{print $1, $2, $3, $4}')

[ "$orphans" -gt 0 ] &&
  note "$orphans orphaned LV(s) holding $(hb "$orphan_kb")." \
    "bash -c \"\$(curl -fsSL $REPO_RAW/clean-orphaned-lvm.sh)\"   # asks before each removal"

# ------------------------------------------------------------------ snapshots
section "Snapshots"
# A snapshot is identified by having an origin. lv_attr "V" only means thin
# volume, which every guest disk on a thin pool is. Fields are pipe-separated so
# an empty origin does not shift the columns.
snaps=$(lvs --noheadings --separator '|' -o lv_name,vg_name,lv_size,origin,data_percent 2>/dev/null |
  awk -F'|' '{for(i=1;i<=NF;i++) gsub(/^[ \t]+|[ \t]+$/,"",$i);
              if ($4 != "") printf "  %-26s %10s  of %-18s data %s%%\n", $2"/"$1, $3, $4, ($5==""?"-":$5)}')
if [ -n "$snaps" ]; then
  echo "$snaps"
  note "Snapshots exist and keep consuming thin-pool space until removed." \
    "pct listsnapshot <id> / qm listsnapshot <id>, then pct delsnapshot <id> <name>"
else
  echo "  none"
fi

# --------------------------------------------------------------- dir storages
if [ "$DO_DU" -eq 1 ] && [ -f /etc/pve/storage.cfg ]; then
  section "Directory storages"
  while read -r name path; do
    [ -d "$path" ] || continue
    total_kb=$(kb_of "$path")

    # A dir storage whose path is not its own mountpoint spends the filesystem it
    # sits on -- usually the root one, which is normally the whole problem.
    host_mount=$(findmnt -no TARGET --target "$path" 2>/dev/null)
    hpct=$(df --output=pcent "$path" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -n "$host_mount" ] && [ "$host_mount" != "$path" ]; then
      echo -e "${YW}${name}${CL}  ${path}  ($(hb "$total_kb"))  ${RD}on ${host_mount}${CL}"
      # local on /var/lib/vz is the Proxmox default, so only escalate this once
      # the filesystem underneath is actually short of room.
      [ "${hpct:-0}" -ge 85 ] &&
        note "Storage '${name}' (${path}) is not a separate mount -- its $(hb "$total_kb") sit on ${host_mount}, which is ${hpct}% full." \
          "Mount a filesystem at ${path}, or move the content to ${ROOMIEST:-a roomier mount} and re-create the storage there."
    else
      echo -e "${YW}${name}${CL}  ${path}  ($(hb "$total_kb"))"
    fi

    for sub in dump template/iso template/cache images snippets; do
      [ -d "$path/$sub" ] || continue
      sub_kb=$(kb_of "$path/$sub")
      printf "    %-18s %s\n" "$sub" "$(hb "$sub_kb")"
      [ "${hpct:-0}" -ge 85 ] || continue
      case "$sub" in
      template/iso)
        [ "${sub_kb:-0}" -gt 10485760 ] &&
          note "ISO images in ${path}/${sub} take $(hb "$sub_kb")." \
            "ls -lhS ${path}/${sub}   # delete the installers you no longer need"
        ;;
      template/cache)
        [ "${sub_kb:-0}" -gt 5242880 ] &&
          note "LXC templates in ${path}/${sub} take $(hb "$sub_kb")." \
            "pveam list ${name}   # then: pveam remove ${name}:vztmpl/<file>"
        ;;
      dump)
        [ "${sub_kb:-0}" -gt 5242880 ] &&
          note "Backups in ${path}/${sub} take $(hb "$sub_kb") on a filesystem that is ${hpct}% full." \
            "Move them to ${ROOMIEST:-a roomier mount}, or set a retention with: pvesm set ${name} --prune-backups keep-last=3"
        ;;
      esac
    done
  done < <(awk '/^dir:/{name=$2} /^[[:space:]]+path[[:space:]]/{if(name!=""){print name, $2; name=""}}' /etc/pve/storage.cfg)
fi

# ------------------------------------------------------------------ host dirs
section "Host directories"
for d in /var/log /var/cache/apt /var/lib/vz /var/tmp /root /tmp /var/lib/snapd; do
  [ -d "$d" ] || continue
  kb=$(kb_of "$d")
  printf "  %-20s %s\n" "$d" "$(hb "$kb")"
  case "$d" in
  /var/log)
    if [ "${kb:-0}" -gt 2097152 ]; then
      # Name the culprit here instead of handing over a du command to run.
      biggest=$(du -xh --max-depth=1 "$d" 2>/dev/null | awk -v self="$d" '$2 != self' |
        sort -h | tail -3 | awk '{printf "%s (%s)  ", $2, $1}')
      [ -n "$biggest" ] && printf "    %-18s %s\n" "biggest:" "$biggest"
      note "/var/log holds $(hb "$kb"). Biggest: ${biggest:-unknown}" \
        "Anything under /var/log that logrotate does not own -- a *_bak or *.old copy made once by hand -- never shrinks again."
    fi
    jkb=$(kb_of /var/log/journal)
    [ "${jkb:-0}" -gt 1048576 ] &&
      note "The systemd journal holds $(hb "$jkb") and is uncapped." \
        "journalctl --vacuum-size=200M, then make it stick: echo 'SystemMaxUse=200M' >>/etc/systemd/journald.conf && systemctl restart systemd-journald"
    ;;
  /var/cache/apt)
    [ "${kb:-0}" -gt 1048576 ] &&
      note "The apt cache holds $(hb "$kb")." "apt-get clean"
    ;;
  /var/lib/snapd)
    [ "${kb:-0}" -gt 1048576 ] &&
      note "snapd holds $(hb "$kb"), and it keeps old revisions of every snap." \
        "snap list --all   # then: snap remove <name> --revision=<old>"
    ;;
  esac
done
jsize=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?B' | tail -1)
[ -n "$jsize" ] && printf "  %-20s %s\n" "systemd journal" "$jsize"

kernels=$(dpkg -l 'proxmox-kernel-*' 2>/dev/null | awk '/^ii/{print $2}' | grep -cE 'proxmox-kernel-[0-9]+\.' || true)
[ "${kernels:-0}" -gt 2 ] &&
  note "${kernels} Proxmox kernels installed." \
    "bash -c \"\$(curl -fsSL $REPO_RAW/kernel-clean.sh)\"   # keeps the running one"

# -------------------------------------------------------------------- summary
section "Summary"
if [ "${#FINDINGS[@]}" -eq 0 ]; then
  echo -e "${GN}Nothing stands out. No filesystem or thin pool is near full.${CL}"
else
  for i in "${!FINDINGS[@]}"; do
    echo -e "\n  ${YW}*${CL} ${FINDINGS[$i]}"
    [ -n "${FIXES[$i]}" ] && echo -e "    ${DGN}${FIXES[$i]}${CL}"
  done
fi

# ---------------------------------------------------------------------- clean
if [ "$DO_CLEAN" -eq 1 ]; then
  section "Reclaim"
  echo -e "${DGN}Only reversible steps are offered here. Deleting volumes, kernels, ISOs or"
  echo -e "backups is left to you and the dedicated tools, which ask per item.${CL}\n"

  read -rp "Clear the apt package cache? [y/N]: " a
  [[ "$a" =~ ^[Yy]$ ]] && apt-get clean && echo "  done"

  read -rp "Trim the systemd journal to 200M? [y/N]: " a
  [[ "$a" =~ ^[Yy]$ ]] && journalctl --vacuum-size=200M >/dev/null 2>&1 && echo "  done"

  if [ -d /var/lib/vz/template/cache ]; then
    read -rp "List cached LXC templates by size for review? [y/N]: " a
    [[ "$a" =~ ^[Yy]$ ]] && ls -lhS /var/lib/vz/template/cache 2>/dev/null
  fi
  if [ -d /var/lib/vz/template/iso ]; then
    read -rp "List ISO images by size for review? [y/N]: " a
    [[ "$a" =~ ^[Yy]$ ]] && ls -lhS /var/lib/vz/template/iso 2>/dev/null
  fi
fi

echo
