#!/usr/bin/env bash

# === Configuration ===
DAILY_RETENTION_DAYS="8"     # Days to keep daily backups
WEEKLY_RETENTION_WEEKS="12"  # Weeks to keep weekly archives
MONTHLY_RETENTION_MONTHS="12" # Months to keep monthly archives

DRY_RUN="1" # 1: Only show what would be done. 0: Actually delete (CAUTION!).
LOG_FILE="/var/log/lxc_backup_cleanup.log"
STORAGE_CFG_FILE="/etc/pve/storage.cfg"

# === Helper functions for logging ===
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }
log_info() { log "INFO: $1"; }
log_warning() { log "WARNING: $1"; }
log_error() { log "ERROR: $1"; }

# === Main script ===
set -e 
set -o pipefail

log_info "Starting LXC Backup GFS Cleanup Script."
log_info "Retention rules: Daily=${DAILY_RETENTION_DAYS}d, Weekly=${WEEKLY_RETENTION_WEEKS}w, Monthly=${MONTHLY_RETENTION_MONTHS}m. Dry Run: ${DRY_RUN}."

# Check for required commands
for cmd in pct pvesm awk date; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command '$cmd' not found. Please install."
        exit 1
    fi
done
log_info "All dependencies are present."

# Get list of LXC container IDs
LXC_IDS_RAW=$(pct list | awk 'NR>1 {print $1}')
if [ -z "$LXC_IDS_RAW" ]; then
    log_warning "No LXC containers found. Exiting script."
    exit 0
fi
LXC_IDS_STR=$(echo "$LXC_IDS_RAW" | tr '\n' ' ')
log_info "Found LXC IDs: $LXC_IDS_STR"

# Check storage configuration file
if [ ! -r "$STORAGE_CFG_FILE" ]; then
    log_error "Storage configuration file '$STORAGE_CFG_FILE' not readable. Exiting script."
    exit 1
fi

# Find backup storage locations
BACKUP_STORAGES_RAW=$(awk '/^([a-z]+):/ { current_id = $2 } /^\s+content\s+/ { if (current_id && $0 ~ /backup/) { print current_id; current_id = "" } }' "$STORAGE_CFG_FILE")
if [ -z "$BACKUP_STORAGES_RAW" ]; then
    log_warning "No backup storages found in '$STORAGE_CFG_FILE'. Exiting script."
    exit 0
fi
log_info "Found backup storages: $(echo "$BACKUP_STORAGES_RAW" | tr '\n' ' ')"

CURRENT_EPOCH=$(date +%s)
TOTAL_IDENTIFIED_FOR_DELETION=0
TOTAL_ACTUALLY_DELETED_COUNT=0

# Process each storage location
for storage_name in $BACKUP_STORAGES_RAW; do
    log_info "Processing storage: $storage_name"
    
    # List all backups in current storage
    ALL_BACKUPS_ON_STORAGE_RAW=$(pvesm list "$storage_name" --content backup 2>&1)
    pvesm_exit_code=$?

    if [ $pvesm_exit_code -ne 0 ]; then
        log_error "Error listing backups on storage '$storage_name'. Output: $ALL_BACKUPS_ON_STORAGE_RAW"
        continue
    fi

    # Process each LXC container
    for lxc_id in $LXC_IDS_STR; do
        log_info "Analyzing backups for LXC ID $lxc_id on storage $storage_name"

        # Process backup data through awk for date analysis
        vm_backup_data_for_awk=$(echo "$ALL_BACKUPS_ON_STORAGE_RAW" | awk -v vmid_filter="$lxc_id" '
            NR > 1 && $NF == vmid_filter && $1 ~ /vzdump-lxc-/ {
                volid = $1;
                if (match(volid, /([0-9]{4})_([0-9]{2})_([0-9]{2})/)) {
                    year = substr(volid, RSTART, 4);
                    month_num = substr(volid, RSTART + 5, 2);
                    day_num = substr(volid, RSTART + 8, 2);
                    date_str = year "-" month_num "-" day_num;
                    
                    cmd_epoch = "date -d \"" date_str "\" +%s";
                    cmd_yw = "date -d \"" date_str "\" +\"%G-%V\""; 
                    cmd_ym = "date -d \"" date_str "\" +\"%Y-%m\""; 
                    
                    epoch = ""; yw = ""; ym = "";
                    if ((cmd_epoch | getline epoch) > 0) close(cmd_epoch); else epoch="ERROR";
                    if ((cmd_yw | getline yw) > 0) close(cmd_yw); else yw="ERROR";
                    if ((cmd_ym | getline ym) > 0) close(cmd_ym); else ym="ERROR";

                    if (epoch != "ERROR" && yw != "ERROR" && ym != "ERROR") {
                        print epoch, volid, yw, ym;
                    }
                }
            }
        ' | sort -k1,1nr) 

        if [ -z "$vm_backup_data_for_awk" ]; then
            log_info "No valid backup entries found for LXC ID $lxc_id on $storage_name or error in date processing."
            continue
        fi

        # Process through GFS rules
        gfs_awk_output=$(echo "$vm_backup_data_for_awk" | awk \
            -v DAILY_DAYS="$DAILY_RETENTION_DAYS" \
            -v WEEKLY_WEEKS="$WEEKLY_RETENTION_WEEKS" \
            -v MONTHLY_MONTHS="$MONTHLY_RETENTION_MONTHS" \
            -v CURRENT_EPOCH_AWK="$CURRENT_EPOCH" \
            -v lxc_id_awk="$lxc_id" '
        BEGIN {
            kept_weekly_slots_count = 0;
            kept_monthly_slots_count = 0;
            identified_for_deletion_this_vm = 0;
        }
        {
            epoch = $1; volid = $2; year_week = $3; year_month = $4;
            age_seconds = CURRENT_EPOCH_AWK - epoch;
            age_days = int(age_seconds / 86400);
            keep_this_backup = 0; 
            reason = "";

            if (age_days <= DAILY_DAYS) {
                keep_this_backup = 1;
                reason = "Daily (within " DAILY_DAYS " days)";
            }

            if (keep_this_backup == 0 && age_days <= (WEEKLY_WEEKS * 7)) {
                if (!(year_week in kept_weekly_slots)) {
                    keep_this_backup = 1;
                    kept_weekly_slots[year_week] = volid; 
                    reason = "Weekly archive for week " year_week;
                }
            }

            if (keep_this_backup == 0 && age_days <= (MONTHLY_MONTHS * 31)) { 
                if (!(year_month in kept_monthly_slots)) {
                    keep_this_backup = 1;
                    kept_monthly_slots[year_month] = volid; 
                    reason = "Monthly archive for month " year_month;
                }
            }

            if (keep_this_backup == 1) {
                printf "GFS_KEEP_INFO: %s (LXC: %s, Age: %d days, Reason: %s)\n", volid, lxc_id_awk, age_days, reason;
            } else {
                printf "GFS_DELETE_INFO: %s (LXC: %s, Age: %d days, no GFS rule applies)\n", volid, lxc_id_awk, age_days;
                print "GFS_DELETE_CMD: pvesm free " volid;
                identified_for_deletion_this_vm++;
            }
        }
        END {
            print "AWK_IDENTIFIED_COUNT:"identified_for_deletion_this_vm;
        }
        ')

        # Process GFS output
        while IFS= read -r line; do
            case "$line" in
                GFS_KEEP_INFO:*|GFS_DELETE_INFO:*)
                    log_info "${line#*: }" 
                    ;;
                GFS_DELETE_CMD:*)
                    actual_cmd="${line#*: }"
                    log_info "Command to execute: $actual_cmd"
                    if [ "$DRY_RUN" -eq "0" ]; then
                        log_info "Executing: $actual_cmd"
                        if eval "$actual_cmd"; then
                            log_info "SUCCESS: $actual_cmd"
                            TOTAL_ACTUALLY_DELETED_COUNT=$((TOTAL_ACTUALLY_DELETED_COUNT + 1))
                        else
                            log_error "ERROR executing: $actual_cmd (Exit code: $?)"
                        fi
                    fi
                    ;;
                AWK_IDENTIFIED_COUNT:*)
                    CURRENT_IDENTIFIED_COUNT=${line#*:}
                    TOTAL_IDENTIFIED_FOR_DELETION=$((TOTAL_IDENTIFIED_FOR_DELETION + CURRENT_IDENTIFIED_COUNT))
                    ;;
            esac
        done < <(echo "$gfs_awk_output")
    done 
done 

# Final summary
log_info "LXC Backup GFS Cleanup Script completed."
if [ "$DRY_RUN" -eq "1" ]; then
    log_info "Dry Run: ${TOTAL_IDENTIFIED_FOR_DELETION} backup(s) would be deleted according to GFS rules."
else
    log_info "Actual deletion: ${TOTAL_ACTUALLY_DELETED_COUNT} backup(s) were successfully deleted."
    log_info "${TOTAL_IDENTIFIED_FOR_DELETION} backup(s) were identified for deletion in total."
fi

set +e
set +o pipefail
exit 0
