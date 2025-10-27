#!/usr/bin/env bash

# OSIWeb Administration Script
# Manages backups, syncing, database operations, and maintenance for osiweb.org
# Version 2.0

VERSION="2.0"

# Require bash 4.0 or higher for associative arrays
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Error: This script requires bash 4.0 or higher (you have $BASH_VERSION)"
    echo "On macOS, install a newer bash with: port install bash"
    echo "Then add /opt/local/bin to your PATH, or run directly with: /opt/local/bin/bash $0"
    exit 1
fi

# Default config file search paths (tried in order if --backup-config not specified)
# Modify this list to customize default config file locations
DEFAULT_CONFIG_PATHS=(
    "osiwebadmin.json"
    ".osiwebadmin.json"
    "$HOME/.config/osiwebadmin/config.json"
)

# Parse command line options
VERBOSE=""
BACKUP_FILES=false
BACKUP_DB=false
RESTORE_FILE=""
MAINTENANCE_MODE=""
SYNC_DOWN=false
SYNC_UP=false
DELETE_SYNC=""
DRY_RUN=""
SYNC_BACKUPS=""
PRUNE_BACKUPS=false
KEEP_ALL_DAYS=1
KEEP_DAILY_DAYS=7
KEEP_WEEKLY_DAYS=30
CONFIG_FILES=()

usage() {
    echo "OSIWeb Administration Tool v${VERSION}"
    echo "Usage: $0 [GLOBAL_OPTIONS] COMMAND [COMMAND_OPTIONS]"
    echo ""
    echo "Global Options:"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -n, --dry-run          Show what would change without doing it"
    echo "  --config FILE           Specify config file path (can be used multiple times)"
    echo "  -h, --help              Show this help"
    echo ""
    echo "Commands:"
    echo "  syncdn [OPTIONS]        Sync files FROM server to local"
    echo "  syncup [OPTIONS]        Sync files FROM local to server"
    echo "  backup_db               Backup database via SSH"
    echo "  backup_files            Backup files (creates .tbz archive)"
    echo "  restore_db FILE         Restore database from backup file"
    echo "  maintenance on|off      Set maintenance mode"
    echo "  sync_backups DIR        Sync backups to destination directory"
    echo "  prune_backups [OPTIONS] Apply retention policy to delete old backups"
    echo ""
    echo "Sync Command Options (syncdn/syncup):"
    echo "  --delete                Delete files not in source"
    echo ""
    echo "Prune Backups Options:"
    echo "  --keep-all DAYS         Keep all backups newer than N days (default: 1)"
    echo "  --keep-daily DAYS       Keep 1/day for backups newer than N days (default: 7)"
    echo "  --keep-weekly DAYS      Keep 1/week for backups newer than N days (default: 30)"
    echo ""
    echo "Examples:"
    echo "  $0 backup_files                              # Backup files"
    echo "  $0 backup_db                                 # Backup database"
    echo "  $0 syncdn                                    # Download from server"
    echo "  $0 -n syncup                                 # Preview upload changes"
    echo "  $0 syncup --delete                           # Upload and delete removed files"
    echo "  $0 maintenance on                            # Enable maintenance mode"
    echo "  $0 restore_db backup.sql                     # Restore database"
    echo "  $0 -v backup_db                              # Backup DB with verbose output"
    echo "  $0 sync_backups ~/Dropbox/osiweb-backups     # Sync backups to destination"
    echo "  $0 -n prune_backups --keep-daily 14          # Preview prune with custom retention"
    echo ""
    echo "UTF8MB4 Conversion Workflow:"
    echo "  $0 maintenance on                            # Enable maintenance mode"
    echo "  $0 backup_db                                 # Create backup"
    echo "  ./convert-to-utf8mb4.sh                      # Convert backup"
    echo "  $0 restore_db backups/*-utf8mb4.sql          # Restore converted backup"
    echo "  $0 maintenance off                           # Disable maintenance mode"
    exit 1
}

# Parse global options first
COMMAND=""
COMMAND_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE="v"
            echo "Verbose mode enabled"
            shift
            ;;
        -n|--dry-run)
            DRY_RUN="-n"
            shift
            ;;
        --config)
            shift
            CONFIG_FILES+=("$1")
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Error: Unknown global option: $1"
            usage
            ;;
        *)
            # First non-option argument is the command
            COMMAND="$1"
            shift
            # Remaining arguments are command-specific
            COMMAND_ARGS=("$@")
            break
            ;;
    esac
done

# Check if command is provided
if [ -z "$COMMAND" ]; then
    usage
fi

# Parse command-specific options based on command
case "$COMMAND" in
    syncdn|syncup)
        # Parse sync options
        set -- "${COMMAND_ARGS[@]}"
        while [[ $# -gt 0 ]]; do
            case $1 in
                --delete)
                    DELETE_SYNC="--delete"
                    shift
                    ;;
                -*)
                    echo "Error: Unknown option for $COMMAND: $1"
                    usage
                    ;;
                *)
                    echo "Error: $COMMAND does not accept positional arguments"
                    usage
                    ;;
            esac
        done

        # Set the appropriate flag
        if [ "$COMMAND" = "syncdn" ]; then
            SYNC_DOWN=true
        else
            SYNC_UP=true
        fi
        ;;

    backup_db)
        BACKUP_DB=true
        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            echo "Error: backup_db does not accept any options"
            usage
        fi
        ;;

    backup_files)
        BACKUP_FILES=true
        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            echo "Error: backup_files does not accept any options"
            usage
        fi
        ;;

    restore_db)
        if [ ${#COMMAND_ARGS[@]} -ne 1 ]; then
            echo "Error: restore_db requires exactly one argument (backup file)"
            usage
        fi
        RESTORE_FILE="${COMMAND_ARGS[0]}"
        ;;

    maintenance)
        if [ ${#COMMAND_ARGS[@]} -ne 1 ]; then
            echo "Error: maintenance requires exactly one argument (on|off|status)"
            usage
        fi
        MAINTENANCE_MODE="${COMMAND_ARGS[0]}"
        if [[ ! "$MAINTENANCE_MODE" =~ ^(on|off|status)$ ]]; then
            echo "Error: maintenance argument must be 'on', 'off', or 'status'"
            usage
        fi
        ;;

    sync_backups)
        if [ ${#COMMAND_ARGS[@]} -ne 1 ]; then
            echo "Error: sync_backups requires exactly one argument (destination directory)"
            usage
        fi
        SYNC_BACKUPS="${COMMAND_ARGS[0]}"
        ;;

    prune_backups)
        # Parse prune_backups options
        set -- "${COMMAND_ARGS[@]}"
        while [[ $# -gt 0 ]]; do
            case $1 in
                --keep-all)
                    shift
                    KEEP_ALL_DAYS="$1"
                    shift
                    ;;
                --keep-daily)
                    shift
                    KEEP_DAILY_DAYS="$1"
                    shift
                    ;;
                --keep-weekly)
                    shift
                    KEEP_WEEKLY_DAYS="$1"
                    shift
                    ;;
                -*)
                    echo "Error: Unknown option for prune_backups: $1"
                    usage
                    ;;
                *)
                    echo "Error: prune_backups does not accept positional arguments"
                    usage
                    ;;
            esac
        done
        PRUNE_BACKUPS=true
        ;;

    *)
        echo "Error: Unknown command: $COMMAND"
        usage
        ;;
esac

# Load config file
# If --config specified, use those paths in order; otherwise try default paths
# Stop after the first config file is successfully loaded
CONFIG_SEARCH_PATHS=()
if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
    # No config files specified on command line, use defaults
    CONFIG_SEARCH_PATHS=("${DEFAULT_CONFIG_PATHS[@]}")
else
    # Use specified config files
    CONFIG_SEARCH_PATHS=("${CONFIG_FILES[@]}")
fi

# Try each path until one loads successfully
for config_path in "${CONFIG_SEARCH_PATHS[@]}"; do
    # Expand tilde in path
    expanded_path="${config_path/#\~/$HOME}"
    if [ -f "$expanded_path" ]; then
        load_config "$expanded_path"
        break  # Stop after loading the first found config file
    fi
done

# If no operation specified, show usage
if [ "$BACKUP_FILES" = false ] && [ "$BACKUP_DB" = false ] && [ -z "$RESTORE_FILE" ] && [ -z "$MAINTENANCE_MODE" ] && [ "$SYNC_DOWN" = false ] && [ "$SYNC_UP" = false ] && [ -z "$SYNC_BACKUPS" ] && [ "$PRUNE_BACKUPS" = false ]; then
    echo "Error: Must specify an operation"
    usage
fi

# Create backup directory if it doesn't exist
mkdir -p backups

# Generate timestamp for backup filenames
TIMESTAMP=$(date +%Y%m%d-%H%M%S)


# Function to extract database credentials from config.php
get_db_credentials() {
    if [ ! -f "public/forum/config.php" ]; then
        echo "Error: public/forum/config.php not found!"
        exit 1
    fi

    DB_NAME=$(grep '^\$dbname' public/forum/config.php | cut -d"'" -f2)
    DB_USER=$(grep '^\$dbuser' public/forum/config.php | cut -d"'" -f2)
    DB_PASS=$(grep '^\$dbpasswd' public/forum/config.php | cut -d"'" -f2)

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
        echo "Error: Could not parse database credentials from public/forum/config.php"
        exit 1
    fi
}

# Load configuration from JSON file
load_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        echo "Error: Config file not found: $config_file"
        exit 1
    fi

    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for config file parsing but not installed"
        echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
        exit 1
    fi

    [ -n "$VERBOSE" ] && echo "Loading config from: $config_file"

    # Parse JSON config and set variables if they haven't been set via command line
    if [ -z "$SYNC_BACKUPS" ]; then
        SYNC_BACKUPS=$(jq -r '.destination // ""' "$config_file")
    fi

    # Only override defaults if not set via command line
    if [ "$KEEP_ALL_DAYS" = "1" ]; then
        KEEP_ALL_DAYS=$(jq -r '.keep_all // 1' "$config_file")
    fi

    if [ "$KEEP_DAILY_DAYS" = "7" ]; then
        KEEP_DAILY_DAYS=$(jq -r '.keep_daily // 7' "$config_file")
    fi

    if [ "$KEEP_WEEKLY_DAYS" = "30" ]; then
        KEEP_WEEKLY_DAYS=$(jq -r '.keep_weekly // 30' "$config_file")
    fi

    if [ "$VERBOSE" = "" ]; then
        local verbose_level=$(jq -r '.verbose // 0' "$config_file")
        if [ "$verbose_level" -gt 0 ]; then
            VERBOSE="v"
        fi
    fi
}

# Parse date from backup filename and return epoch timestamp
# Supports formats like:
#   - osiweb-db-20250906-144834.sql.bz2
#   - database_backup_20250906_144834.sql
#   - backup-2025-09-06.sql.bz2
# Requires GNU date
parse_backup_date() {
    local filename="$1"

    # Pattern 1: YYYYMMDD-HHMMSS or YYYYMMDD_HHMMSS
    if [[ "$filename" =~ ([0-9]{8})[-_]([0-9]{6}) ]]; then
        local date_str="${BASH_REMATCH[1]}"
        local time_str="${BASH_REMATCH[2]}"
        # Convert to YYYY-MM-DD HH:MM:SS format for date command
        local formatted="${date_str:0:4}-${date_str:4:2}-${date_str:6:2} ${time_str:0:2}:${time_str:2:2}:${time_str:4:2}"
        date -d "$formatted" "+%s" 2>/dev/null
        return $?
    fi

    # Pattern 2: YYYY-MM-DD format
    if [[ "$filename" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        local date_str="${BASH_REMATCH[1]}"
        date -d "$date_str" "+%s" 2>/dev/null
        return $?
    fi

    return 1
}

# Sync backups to destination directory using rsync
sync_backups_to_destination() {
    local source_dir="backups"
    local dest_dir="$SYNC_BACKUPS"

    # Expand tilde in destination path
    dest_dir="${dest_dir/#\~/$HOME}"

    echo "Syncing backups to: ${dest_dir}"

    # Create destination directory if it doesn't exist
    mkdir -p "${dest_dir}" 2>/dev/null

    if [ ! -d "${dest_dir}" ]; then
        echo "Error: Cannot create destination directory: ${dest_dir}"
        return 1
    fi

    # Build rsync command
    local rsync_opts="-a --ignore-existing"
    if [ -n "$VERBOSE" ]; then
        rsync_opts="$rsync_opts -v --progress"
    fi

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN MODE - no files will be copied"
        rsync_opts="$rsync_opts -n"
    fi

    # Run rsync
    rsync $rsync_opts "${source_dir}/" "${dest_dir}/"

    if [ $? -eq 0 ]; then
        [ -n "$VERBOSE" ] && echo "✓ Backup sync completed successfully"
        return 0
    else
        echo "✗ Backup sync failed"
        return 1
    fi
}

# Apply tiered retention policy to backups
apply_retention_policy() {
    local backup_dir="$1"

    # Expand tilde in backup path
    backup_dir="${backup_dir/#\~/$HOME}"

    if [ ! -d "$backup_dir" ]; then
        echo "Error: Backup directory not found: $backup_dir"
        return 1
    fi

    echo "Applying retention policy to: ${backup_dir}"
    [ -n "$VERBOSE" ] && echo "Retention: keep-all=${KEEP_ALL_DAYS}d, keep-daily=${KEEP_DAILY_DAYS}d, keep-weekly=${KEEP_WEEKLY_DAYS}d"

    local now_epoch=$(date +%s)
    local keep_all_threshold=$((now_epoch - KEEP_ALL_DAYS * 86400))
    local keep_daily_threshold=$((now_epoch - KEEP_DAILY_DAYS * 86400))
    local keep_weekly_threshold=$((now_epoch - KEEP_WEEKLY_DAYS * 86400))

    # Arrays to track files
    declare -A keep_files
    declare -a delete_files
    declare -A daily_buckets
    declare -A weekly_buckets
    declare -A monthly_buckets

    # Process all backup files
    local file_count=0
    for filepath in "$backup_dir"/*; do
        [ -f "$filepath" ] || continue

        local filename=$(basename "$filepath")

        # Skip non-backup files
        [[ "$filename" == *.sql* ]] || [[ "$filename" == *.bz2 ]] || [[ "$filename" == *.gz ]] || continue

        local file_epoch=$(parse_backup_date "$filename")
        if [ -z "$file_epoch" ]; then
            [ -n "$VERBOSE" ] && echo "Warning: Could not parse date from $filename"
            continue
        fi

        file_count=$((file_count + 1))

        # 1. Keep everything newer than keep_all_threshold
        if [ "$file_epoch" -ge "$keep_all_threshold" ]; then
            keep_files["$filepath"]=1
            [ -n "$VERBOSE" ] && echo "KEEP (< ${KEEP_ALL_DAYS} days): $filename"
            continue
        fi

        # Store in buckets for further processing
        # Convert epoch to date components (works with GNU date)
        local file_date=$(date -d "@$file_epoch" "+%Y-%m-%d" 2>/dev/null)

        # Daily bucket
        daily_buckets["$file_date"]+="$filepath|$file_epoch "

        # Weekly bucket (Monday as week start)
        local day_of_week=$(date -d "@$file_epoch" "+%u")
        local days_back=$((day_of_week - 1))
        local week_epoch=$((file_epoch - days_back * 86400))
        local week_start=$(date -d "@$week_epoch" "+%Y-%m-%d" 2>/dev/null)
        weekly_buckets["$week_start"]+="$filepath|$file_epoch "

        # Monthly bucket
        local month_start=$(date -d "@$file_epoch" "+%Y-%m-01")
        monthly_buckets["$month_start"]+="$filepath|$file_epoch "
    done

    if [ "$file_count" -eq 0 ]; then
        echo "No backup files found"
        return 0
    fi

    [ -n "$VERBOSE" ] && echo "Found $file_count backup files"

    # 2. Keep 1 per day for daily retention period
    for day_key in "${!daily_buckets[@]}"; do
        local day_epoch=$(date -d "$day_key" "+%s" 2>/dev/null)
        if [ "$day_epoch" -ge "$keep_daily_threshold" ] && [ "$day_epoch" -lt "$keep_all_threshold" ]; then
            # Find newest file from this day
            local newest_file=""
            local newest_epoch=0
            for item in ${daily_buckets[$day_key]}; do
                local file_path="${item%|*}"
                local file_epoch="${item#*|}"
                if [ "$file_epoch" -gt "$newest_epoch" ]; then
                    newest_file="$file_path"
                    newest_epoch="$file_epoch"
                fi
            done
            if [ -n "$newest_file" ]; then
                keep_files["$newest_file"]=1
                [ -n "$VERBOSE" ] && echo "KEEP (daily): $(basename "$newest_file")"
            fi
        fi
    done

    # 3. Keep 1 per week for weekly retention period
    for week_key in "${!weekly_buckets[@]}"; do
        local week_epoch=$(date -d "$week_key" "+%s" 2>/dev/null)
        if [ "$week_epoch" -ge "$keep_weekly_threshold" ] && [ "$week_epoch" -lt "$keep_daily_threshold" ]; then
            # Find newest file from this week
            local newest_file=""
            local newest_epoch=0
            for item in ${weekly_buckets[$week_key]}; do
                local file_path="${item%|*}"
                local file_epoch="${item#*|}"
                if [ "$file_epoch" -gt "$newest_epoch" ] && [ -z "${keep_files[$file_path]}" ]; then
                    newest_file="$file_path"
                    newest_epoch="$file_epoch"
                fi
            done
            if [ -n "$newest_file" ]; then
                keep_files["$newest_file"]=1
                [ -n "$VERBOSE" ] && echo "KEEP (weekly): $(basename "$newest_file")"
            fi
        fi
    done

    # 4. Keep 1 per month for everything older than weekly threshold
    for month_key in "${!monthly_buckets[@]}"; do
        local month_epoch=$(date -d "$month_key" "+%s" 2>/dev/null)
        if [ "$month_epoch" -lt "$keep_weekly_threshold" ]; then
            # Find newest file from this month
            local newest_file=""
            local newest_epoch=0
            for item in ${monthly_buckets[$month_key]}; do
                local file_path="${item%|*}"
                local file_epoch="${item#*|}"
                if [ "$file_epoch" -gt "$newest_epoch" ] && [ -z "${keep_files[$file_path]}" ]; then
                    newest_file="$file_path"
                    newest_epoch="$file_epoch"
                fi
            done
            if [ -n "$newest_file" ]; then
                keep_files["$newest_file"]=1
                [ -n "$VERBOSE" ] && echo "KEEP (monthly): $(basename "$newest_file")"
            fi
        fi
    done

    # Build delete list
    local delete_count=0
    for filepath in "$backup_dir"/*; do
        [ -f "$filepath" ] || continue
        local filename=$(basename "$filepath")
        [[ "$filename" == *.sql* ]] || [[ "$filename" == *.bz2 ]] || [[ "$filename" == *.gz ]] || continue

        if [ -z "${keep_files[$filepath]}" ]; then
            delete_files+=("$filepath")
            delete_count=$((delete_count + 1))
        fi
    done

    # Summary and deletion
    echo "SUMMARY: Keeping ${#keep_files[@]} files, deleting $delete_count files"

    if [ "$delete_count" -gt 0 ]; then
        if [ -n "$VERBOSE" ] || [ -n "$DRY_RUN" ]; then
            echo ""
            echo "Files to DELETE:"
            for filepath in "${delete_files[@]}"; do
                echo "  $(basename "$filepath")"
            done
        fi

        if [ -n "$DRY_RUN" ]; then
            echo ""
            echo "(DRY RUN - $delete_count files would be deleted)"
        else
            echo ""
            echo "Deleting $delete_count files..."
            local deleted=0
            for filepath in "${delete_files[@]}"; do
                if rm "$filepath" 2>/dev/null; then
                    deleted=$((deleted + 1))
                    [ -n "$VERBOSE" ] && echo "Deleted: $(basename "$filepath")"
                else
                    echo "Error deleting: $(basename "$filepath")"
                fi
            done
            echo "✓ Successfully deleted $deleted/$delete_count files"
        fi
    else
        [ -n "$VERBOSE" ] && echo "No files to delete"
    fi

    return 0
}

# Backup files
if [ "$BACKUP_FILES" = true ]; then
    BACKUP_FILE="backups/osiweb-files-${TIMESTAMP}.tbz"
    echo "Creating file backup: ${BACKUP_FILE}"
    echo "This may take a while due to the large forum directory..."

    # Create tarball with bzip2 compression excluding backups directory and .git
    tar -cj${VERBOSE}f "${BACKUP_FILE}" \
        --exclude='./backups' \
        --exclude='./.git' \
        --exclude='./forum/cache/production' \
        .

    if [ $? -eq 0 ]; then
        SIZE=$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')
        echo "File backup completed successfully!"
        echo "File: ${BACKUP_FILE}"
        echo "Size: ${SIZE}"
    else
        echo "File backup failed!"
        exit 1
    fi
fi

# Backup database
if [ "$BACKUP_DB" = true ]; then
    # Get database credentials
    get_db_credentials

    DB_BACKUP_FILE="backups/osiweb-db-${TIMESTAMP}.sql.bz2"
    SSH_KEY="~/.ssh/id-hostgator-dfenyes"
    SSH_USER="dfenyes"
    SSH_HOST="108.167.172.195"

    echo "Creating database backup: ${DB_BACKUP_FILE}"
    echo "Connecting to ${SSH_HOST}..."
    echo "Database: ${DB_NAME}"

    # Expand the tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"

    # SSH to server, run mysqldump, and pipe back compressed with bzip2
    ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
        "mysqldump -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} | bzip2" > "${DB_BACKUP_FILE}"

    if [ $? -eq 0 ]; then
        SIZE=$(ls -lh "${DB_BACKUP_FILE}" | awk '{print $5}')
        echo "Database backup completed successfully!"
        echo "File: ${DB_BACKUP_FILE}"
        echo "Size: ${SIZE}"

        # Verify the backup isn't empty
        if [ ! -s "${DB_BACKUP_FILE}" ]; then
            echo "Warning: Database backup file is empty!"
            exit 1
        fi
    else
        echo "Database backup failed!"
        echo "Check your SSH connection and database credentials."
        exit 1
    fi
fi

# Handle maintenance mode
if [ -n "$MAINTENANCE_MODE" ]; then
    # Get database credentials
    get_db_credentials

    SSH_KEY="~/.ssh/id-hostgator-dfenyes"
    SSH_USER="dfenyes"
    SSH_HOST="108.167.172.195"

    # Expand the tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"

    if [ "$MAINTENANCE_MODE" = "on" ]; then
        echo "Enabling maintenance mode on forum..."
        # Use single quotes for SQL to avoid escaping issues
        ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" <<EOF
mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} <<'SQL'
UPDATE phpbb_config SET config_value='1' WHERE config_name='board_disable';
UPDATE phpbb_config SET config_value='Forum temporarily offline for maintenance. We will be back shortly!' WHERE config_name='board_disable_msg';
SQL
EOF

        if [ $? -eq 0 ]; then
            echo "✓ Maintenance mode ENABLED"
            echo "  Regular users will see: 'Forum temporarily offline for maintenance'"
            echo "  Admins can still log in"
        else
            echo "✗ Failed to enable maintenance mode"
            exit 1
        fi

    elif [ "$MAINTENANCE_MODE" = "off" ]; then
        echo "Disabling maintenance mode on forum..."
        ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" <<EOF
mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} <<'SQL'
UPDATE phpbb_config SET config_value='0' WHERE config_name='board_disable';
SQL
EOF

        if [ $? -eq 0 ]; then
            echo "✓ Maintenance mode DISABLED"
            echo "  Forum is now accessible to all users"
        else
            echo "✗ Failed to disable maintenance mode"
            exit 1
        fi

    elif [ "$MAINTENANCE_MODE" = "status" ]; then
        echo "Checking maintenance mode status..."
        STATUS=$(ssh -i "${SSH_KEY}" "${SSH_USER}@${HOST_IP}" \
            "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} -sN -e \"SELECT config_value FROM phpbb_config WHERE config_name='board_disable'\"")

        if [ $? -eq 0 ]; then
            if [ "$STATUS" = "1" ]; then
                echo "⚠️  Maintenance mode is currently: ENABLED"
                echo "  Regular users cannot access the forum"
                echo "  Only administrators can log in"

                # Also get the maintenance message
                MESSAGE=$(ssh -i "${SSH_KEY}" "${SSH_USER}@${HOST_IP}" \
                    "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} -sN -e \"SELECT config_value FROM phpbb_config WHERE config_name='board_disable_msg'\"")
                if [ -n "$MESSAGE" ]; then
                    echo "  Message shown to users: $MESSAGE"
                fi
            elif [ "$STATUS" = "0" ]; then
                echo "✅ Maintenance mode is currently: DISABLED"
                echo "  Forum is accessible to all users"
            else
                echo "⚠️  Unknown maintenance mode status: $STATUS"
            fi
        else
            echo "✗ Failed to check maintenance mode status"
            exit 1
        fi
    else
        echo "Error: Maintenance mode must be 'on', 'off', or 'status'"
        exit 1
    fi
fi

# Handle database restore
if [ -n "$RESTORE_FILE" ]; then
    # Check if restore file exists
    if [ ! -f "$RESTORE_FILE" ]; then
        echo "Error: Restore file '$RESTORE_FILE' not found"
        exit 1
    fi

    # Get database credentials
    get_db_credentials

    SSH_KEY="~/.ssh/id-hostgator-dfenyes"
    SSH_USER="dfenyes"
    SSH_HOST="108.167.172.195"

    # Expand the tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"

    echo "WARNING: This will REPLACE the entire database!"
    echo "Database: ${DB_NAME} on ${SSH_HOST}"
    echo "Restore file: ${RESTORE_FILE}"
    echo ""
    read -p "Are you sure you want to restore? Type 'yes' to continue: " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo "Restore cancelled"
        exit 1
    fi

    echo "Restoring database from ${RESTORE_FILE}..."

    # Detect if file is compressed
    if [[ "$RESTORE_FILE" == *.bz2 ]]; then
        echo "Detected bzip2 compressed file, decompressing..."
        bunzip2 -c "$RESTORE_FILE" | ssh -i "${SSH_KEY}" "${SSH_USER}@${HOST_IP}" \
            "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"
    elif [[ "$RESTORE_FILE" == *.gz ]]; then
        echo "Detected gzip compressed file, decompressing..."
        gunzip -c "$RESTORE_FILE" | ssh -i "${SSH_KEY}" "${SSH_USER}@${HOST_IP}" \
            "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"
    else
        echo "Restoring uncompressed SQL file..."
        cat "$RESTORE_FILE" | ssh -i "${SSH_KEY}" "${SSH_USER}@${HOST_IP}" \
            "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"
    fi

    if [ $? -eq 0 ]; then
        echo "✓ Database restored successfully!"
        echo ""
        echo "IMPORTANT: Clear the forum cache:"
        echo "  1. Via Admin Panel: ACP → General → Purge Cache"
        echo "  2. Or delete: public/forum/cache/production/*"
        echo ""
        if [[ "$RESTORE_FILE" == *utf8mb4* ]]; then
            echo "Note: You restored a UTF8MB4 converted database."
            echo "Your forum now supports full Unicode including emojis! 🎉"
        fi
    else
        echo "✗ Database restore failed!"
        echo "Check your SSH connection and MySQL credentials"
        exit 1
    fi
fi

# Handle syncdn (download from server)
if [ "$SYNC_DOWN" = true ]; then
    SSH_KEY="~/.ssh/id-hostgator-dfenyes"
    SSH_USER="dfenyes"
    SSH_HOST="108.167.172.195"

    WEBDIR="public_html/"
    SRC="$SSH_USER@$SSH_HOST:$WEBDIR"
    EXCLUDE="--exclude-from=.rsyncdnignore"

    # Expand the tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"

    # Check if SSH key is in agent, add if not
    if ! ssh-add -l | grep -q "id-hostgator-dfenyes"; then
        ssh-add "$SSH_KEY" 2>/dev/null
    fi

    echo "Syncing FROM server to local..."
    echo "Source: $SRC"
    echo "Destination: ./public/forum/"

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN MODE - no files will be changed"
    fi

    RSYNC_OPTS="-acv --progress --stats"
    [ -n "$VERBOSE" ] && RSYNC_OPTS="$RSYNC_OPTS -v"
    [ -n "$DELETE_SYNC" ] && RSYNC_OPTS="$RSYNC_OPTS $DELETE_SYNC"
    [ -n "$DRY_RUN" ] && RSYNC_OPTS="$RSYNC_OPTS $DRY_RUN"

    rsync $RSYNC_OPTS $EXCLUDE -e "ssh -i $SSH_KEY" "$SRC/forum/" ./public/forum/

    if [ $? -eq 0 ]; then
        echo "✓ Sync from server completed successfully!"
    else
        echo "✗ Sync from server failed!"
        exit 1
    fi
fi

# Handle syncup (upload to server)
if [ "$SYNC_UP" = true ]; then
    SSH_KEY="~/.ssh/id-hostgator-dfenyes"
    SSH_USER="dfenyes"
    SSH_HOST="108.167.172.195"

    WEBDIR="public_html/"
    DEST="$SSH_USER@$SSH_HOST:$WEBDIR"
    EXCLUDE="--exclude-from=.rsyncupignore"

    # Expand the tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"

    # Check if SSH key is in agent, add if not
    if ! ssh-add -l | grep -q "id-hostgator-dfenyes"; then
        ssh-add "$SSH_KEY" 2>/dev/null
    fi

    echo "Syncing FROM local to server..."
    echo "Source: ./dist/"
    echo "Destination: $DEST"

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN MODE - no files will be changed"
    fi

    if [ -n "$DELETE_SYNC" ]; then
        echo "WARNING: --delete option will remove files on server not present locally!"
        if [ -z "$DRY_RUN" ]; then
            read -p "Are you sure? Type 'yes' to continue: " CONFIRM
            if [ "$CONFIRM" != "yes" ]; then
                echo "Sync cancelled"
                exit 1
            fi
        fi
    fi

    RSYNC_OPTS="-acv --progress --stats"
    [ -n "$VERBOSE" ] && RSYNC_OPTS="$RSYNC_OPTS -v"
    [ -n "$DELETE_SYNC" ] && RSYNC_OPTS="$RSYNC_OPTS $DELETE_SYNC"
    [ -n "$DRY_RUN" ] && RSYNC_OPTS="$RSYNC_OPTS $DRY_RUN"

    rsync $RSYNC_OPTS $EXCLUDE -e "ssh -i $SSH_KEY" ./dist/ "$DEST"

    if [ $? -eq 0 ]; then
        echo "✓ Sync to server completed successfully!"
    else
        echo "✗ Sync to server failed!"
        exit 1
    fi
fi

# Handle backup sync
if [ -n "$SYNC_BACKUPS" ]; then
    echo ""
    echo "============================================================"
    echo "SYNCING BACKUPS"
    echo "============================================================"

    if ! sync_backups_to_destination; then
        echo "Backup sync failed!"
        exit 1
    fi
fi

# Handle backup pruning
if [ "$PRUNE_BACKUPS" = true ]; then
    echo ""
    echo "============================================================"
    echo "PRUNING OLD BACKUPS"
    echo "============================================================"

    # Determine which directory to prune
    PRUNE_DIR="backups"
    if [ -n "$SYNC_BACKUPS" ]; then
        # If we synced, prune the destination
        PRUNE_DIR="$SYNC_BACKUPS"
    fi

    if ! apply_retention_policy "$PRUNE_DIR"; then
        echo "Backup pruning failed!"
        exit 1
    fi
fi

echo ""
echo "All requested operations completed successfully!"
