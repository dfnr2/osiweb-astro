#!/usr/bin/env bash

# OSIWeb Administration Script
# Manages backups, syncing, database operations, and maintenance for osiweb.org
# Version 2.0

VERSION="2.2"

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
VERBOSE=0
BACKUP_FILES=false
BACKUP_DB=false
BACKUP_DB_PRUNE=false
RESTORE_FILE=""
MAINTENANCE_MODE=""
SYNC_DOWN=false
SYNC_UP=false
DEPLOY=false
DELETE_SYNC=""
DRY_RUN=""
SYNC_BACKUPS=""
SYNC_BACKUPS_REQUESTED=false
PRUNE_BACKUPS=false
KEEP_ALL_DAYS=1
KEEP_DAILY_DAYS=7
KEEP_WEEKLY_DAYS=30
CONFIG_FILES=()
SET_PASSWORD_USER=""
PASSWORD_STDIN=false

usage() {
    echo "OSIWeb Administration Tool v${VERSION}"
    echo "Usage: $0 [GLOBAL_OPTIONS] COMMAND [COMMAND_OPTIONS]"
    echo ""
    echo "Global Options:"
    echo "  -v, --verbose           Increase verbosity (can be used multiple times)"
    echo "  -n, --dry-run          Show what would change without doing it"
    echo "  --config FILE           Specify config file path (can be used multiple times)"
    echo "  -h, --help              Show this help"
    echo ""
    echo "Commands:"
    echo "  syncdn [OPTIONS]        Sync files FROM server to local"
    echo "  syncup [OPTIONS]        Sync files FROM local to server"
    echo "  deploy [OPTIONS]        Build the site and upload it to the server"
    echo "  backup_db [OPTIONS]     Backup database via SSH"
    echo "  backup_files            Backup files (creates .tbz archive)"
    echo "  restore_db FILE         Restore database from backup file"
    echo "  maintenance on|off      Set maintenance mode"
    echo "  sync_backups DIR        Sync backups to destination directory"
    echo "  prune_backups [OPTIONS] Apply retention policy to delete old backups"
    echo "  set_password USER       Set password for a forum user"
    echo ""
    echo "Sync Command Options (syncdn/syncup/deploy):"
    echo "  --delete                Delete files not in source"
    echo ""
    echo "Backup DB Options:"
    echo "  --prune                 Prune old backups after successful backup"
    echo ""
    echo "Prune Backups Options:"
    echo "  --keep-all DAYS         Keep all backups newer than N days (default: 1)"
    echo "  --keep-daily DAYS       Keep 1/day for backups newer than N days (default: 7)"
    echo "  --keep-weekly DAYS      Keep 1/week for backups newer than N days (default: 30)"
    echo ""
    echo "Set Password Options:"
    echo "  --stdin                 Read password from STDIN (single line)"
    echo ""
    echo "Examples:"
    echo "  $0 backup_files                              # Backup files"
    echo "  $0 backup_db                                 # Backup database"
    echo "  $0 backup_db --prune                         # Backup database and prune old backups"
    echo "  $0 syncdn                                    # Download from server"
    echo "  $0 -n syncup                                 # Preview upload changes"
    echo "  $0 syncup --delete                           # Upload and delete removed files"
    echo "  $0 deploy                                    # Build the site and upload to server"
    echo "  $0 -n deploy                                 # Build, then preview upload changes"
    echo "  $0 maintenance on                            # Enable maintenance mode"
    echo "  $0 restore_db backup.sql                     # Restore database"
    echo "  $0 -v backup_db                              # Backup DB with verbose output"
    echo "  $0 sync_backups ~/Dropbox/osiweb-backups     # Sync backups to destination"
    echo "  $0 -n prune_backups --keep-daily 14          # Preview prune with custom retention"
    echo "  $0 set_password johndoe                      # Set password for user 'johndoe'"
    echo "  echo 'newpass' | $0 set_password johndoe --stdin  # Set password non-interactively"
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
            VERBOSE=$((VERBOSE + 1))
            shift
            ;;
        -vv)
            VERBOSE=$((VERBOSE + 2))
            shift
            ;;
        -vvv)
            VERBOSE=$((VERBOSE + 3))
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
    syncdn|syncup|deploy)
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
        elif [ "$COMMAND" = "deploy" ]; then
            DEPLOY=true
        else
            SYNC_UP=true
        fi
        ;;

    backup_db)
        # Parse backup_db options
        set -- "${COMMAND_ARGS[@]}"
        while [[ $# -gt 0 ]]; do
            case $1 in
                --prune)
                    BACKUP_DB_PRUNE=true
                    shift
                    ;;
                -*)
                    echo "Error: Unknown option for backup_db: $1"
                    usage
                    ;;
                *)
                    echo "Error: backup_db does not accept positional arguments"
                    usage
                    ;;
            esac
        done
        BACKUP_DB=true
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
        if [ ${#COMMAND_ARGS[@]} -gt 1 ]; then
            echo "Error: sync_backups accepts at most one argument (destination directory)"
            usage
        fi
        if [ ${#COMMAND_ARGS[@]} -eq 1 ]; then
            SYNC_BACKUPS="${COMMAND_ARGS[0]}"
        fi
        # Empty SYNC_BACKUPS will be filled from config.destination in load_config,
        # or fail later if no destination is configured
        SYNC_BACKUPS_REQUESTED=true
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

    set_password)
        # Parse set_password options and arguments
        set -- "${COMMAND_ARGS[@]}"
        while [[ $# -gt 0 ]]; do
            case $1 in
                --stdin)
                    PASSWORD_STDIN=true
                    shift
                    ;;
                -*)
                    echo "Error: Unknown option for set_password: $1"
                    usage
                    ;;
                *)
                    if [ -z "$SET_PASSWORD_USER" ]; then
                        SET_PASSWORD_USER="$1"
                    else
                        echo "Error: set_password accepts only one username"
                        usage
                    fi
                    shift
                    ;;
            esac
        done
        if [ -z "$SET_PASSWORD_USER" ]; then
            echo "Error: set_password requires a username"
            usage
        fi
        ;;

    *)
        echo "Error: Unknown command: $COMMAND"
        usage
        ;;
esac

# SSH/Server settings (loaded from config file)
SSH_KEY=""
SSH_USER=""
SSH_HOST=""
WEBDIR="public_html/"
BACKUP_SOURCE="backups"

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

    [ "$VERBOSE" -gt 0 ] && echo "Loading config from: $config_file"

    # Load SSH settings (required)
    SSH_KEY=$(jq -r '.ssh_key // ""' "$config_file")
    SSH_USER=$(jq -r '.ssh_user // ""' "$config_file")
    SSH_HOST=$(jq -r '.ssh_host // ""' "$config_file")

    # Load optional settings with defaults
    WEBDIR=$(jq -r '.webdir // "public_html/"' "$config_file")
    BACKUP_SOURCE=$(jq -r '.source // "backups"' "$config_file")

    # Only fall back to config.destination when sync_backups was explicitly invoked,
    # otherwise the destination presence in config would silently trigger a sync
    # after every other command.
    if [ -z "$SYNC_BACKUPS" ] && [ "$SYNC_BACKUPS_REQUESTED" = true ]; then
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

    if [ "$VERBOSE" -eq 0 ]; then
        local verbose_level=$(jq -r '.verbose // 0' "$config_file")
        if [ "$verbose_level" -gt 0 ]; then
            VERBOSE="$verbose_level"
        fi
    fi
}

# Validate that required SSH settings are present
validate_ssh_config() {
    local missing=""
    if [ -z "$SSH_KEY" ]; then
        missing="$missing ssh_key"
    fi
    if [ -z "$SSH_USER" ]; then
        missing="$missing ssh_user"
    fi
    if [ -z "$SSH_HOST" ]; then
        missing="$missing ssh_host"
    fi

    if [ -n "$missing" ]; then
        echo "Error: Missing required config settings:$missing"
        echo "Please add these to osiwebadmin.json"
        exit 1
    fi

    # Expand tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
}

# Ensure SSH key is loaded in agent
ensure_ssh_key_loaded() {
    validate_ssh_config
    local key_name=$(basename "$SSH_KEY")
    if ! ssh-add -l 2>/dev/null | grep -q "$key_name"; then
        ssh-add "$SSH_KEY" 2>/dev/null
    fi
}

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
    [ "$VERBOSE" -gt 1 ] && echo "Trying config file: $expanded_path"
    if [ -f "$expanded_path" ]; then
        load_config "$expanded_path"
        break  # Stop after loading the first found config file
    fi
done

# If no operation specified, show usage
if [ "$BACKUP_FILES" = false ] && [ "$BACKUP_DB" = false ] && [ -z "$RESTORE_FILE" ] && [ -z "$MAINTENANCE_MODE" ] && [ "$SYNC_DOWN" = false ] && [ "$SYNC_UP" = false ] && [ "$DEPLOY" = false ] && [ "$SYNC_BACKUPS_REQUESTED" = false ] && [ "$PRUNE_BACKUPS" = false ] && [ -z "$SET_PASSWORD_USER" ]; then
    echo "Error: Must specify an operation"
    usage
fi

# sync_backups requires a destination from CLI arg or config.destination
if [ "$SYNC_BACKUPS_REQUESTED" = true ] && [ -z "$SYNC_BACKUPS" ]; then
    echo "Error: No destination specified. Provide a destination argument or set 'destination' in config."
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_SOURCE"

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
    local source_dir="$BACKUP_SOURCE"
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
    if [ "$VERBOSE" -gt 0 ]; then
        rsync_opts="$rsync_opts -v --progress"
    fi

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN MODE - no files will be copied"
        rsync_opts="$rsync_opts -n"
    fi

    # Run rsync
    rsync $rsync_opts "${source_dir}/" "${dest_dir}/"

    if [ $? -eq 0 ]; then
        [ "$VERBOSE" -gt 0 ] && echo "✓ Backup sync completed successfully"
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
    [ "$VERBOSE" -gt 0 ] && echo "Retention: keep-all=${KEEP_ALL_DAYS}d, keep-daily=${KEEP_DAILY_DAYS}d, keep-weekly=${KEEP_WEEKLY_DAYS}d"

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
        [[ "$filename" == *.sql* ]] || [[ "$filename" == *.bz2 ]] || [[ "$filename" == *.gz ]] || [[ "$filename" == *.tbz ]] || continue

        local file_epoch=$(parse_backup_date "$filename")
        if [ -z "$file_epoch" ]; then
            [ "$VERBOSE" -gt 0 ] && echo "Warning: Could not parse date from $filename"
            continue
        fi

        file_count=$((file_count + 1))

        # 1. Keep everything newer than keep_all_threshold
        if [ "$file_epoch" -ge "$keep_all_threshold" ]; then
            keep_files["$filepath"]=1
            [ "$VERBOSE" -gt 0 ] && echo "KEEP (< ${KEEP_ALL_DAYS} days): $filename"
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

    [ "$VERBOSE" -gt 0 ] && echo "Found $file_count backup files"

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
                [ "$VERBOSE" -gt 0 ] && echo "KEEP (daily): $(basename "$newest_file")"
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
                [ "$VERBOSE" -gt 0 ] && echo "KEEP (weekly): $(basename "$newest_file")"
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
                [ "$VERBOSE" -gt 0 ] && echo "KEEP (monthly): $(basename "$newest_file")"
            fi
        fi
    done

    # Build delete list
    local delete_count=0
    for filepath in "$backup_dir"/*; do
        [ -f "$filepath" ] || continue
        local filename=$(basename "$filepath")
        [[ "$filename" == *.sql* ]] || [[ "$filename" == *.bz2 ]] || [[ "$filename" == *.gz ]] || [[ "$filename" == *.tbz ]] || continue

        if [ -z "${keep_files[$filepath]}" ]; then
            delete_files+=("$filepath")
            delete_count=$((delete_count + 1))
        fi
    done

    # Summary and deletion
    echo "SUMMARY: Keeping ${#keep_files[@]} files, deleting $delete_count files"

    if [ "$delete_count" -gt 0 ]; then
        if [ "$VERBOSE" -gt 0 ] || [ -n "$DRY_RUN" ]; then
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
                    [ "$VERBOSE" -gt 0 ] && echo "Deleted: $(basename "$filepath")"
                else
                    echo "Error deleting: $(basename "$filepath")"
                fi
            done
            echo "✓ Successfully deleted $deleted/$delete_count files"
        fi
    else
        [ "$VERBOSE" -gt 0 ] && echo "No files to delete"
    fi

    return 0
}

# Backup files
if [ "$BACKUP_FILES" = true ]; then
    BACKUP_FILE="${BACKUP_SOURCE}/osiweb-files-${TIMESTAMP}.tbz"
    echo "Creating file backup: ${BACKUP_FILE}"
    echo "This may take a while due to the large forum directory..."

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN - no backup will be created"
    else
        # Create tarball with bzip2 compression excluding backups directory and .git
        TAR_VERBOSE=""
        [ "$VERBOSE" -gt 0 ] && TAR_VERBOSE="v"
        tar -cj${TAR_VERBOSE}f "${BACKUP_FILE}" \
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
fi

# Backup database
if [ "$BACKUP_DB" = true ]; then
    # Get database credentials
    get_db_credentials
    validate_ssh_config

    DB_BACKUP_FILE="${BACKUP_SOURCE}/osiweb-db-${TIMESTAMP}.sql.bz2"

    echo "Creating database backup: ${DB_BACKUP_FILE}"
    echo "Connecting to ${SSH_HOST}..."
    echo "Database: ${DB_NAME}"

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN - no backup will be created"
    else
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

            # Run pruning if --prune flag was specified
            if [ "$BACKUP_DB_PRUNE" = true ]; then
                echo ""
                echo "============================================================"
                echo "PRUNING OLD BACKUPS"
                echo "============================================================"

                if ! apply_retention_policy "$BACKUP_SOURCE"; then
                    echo "Warning: Backup pruning failed, but backup was successful"
                fi
            fi
        else
            echo "Database backup failed!"
            echo "Check your SSH connection and database credentials."
            exit 1
        fi
    fi
fi

# Handle maintenance mode
if [ -n "$MAINTENANCE_MODE" ]; then
    # Get database credentials
    get_db_credentials
    validate_ssh_config

    if [ "$MAINTENANCE_MODE" = "on" ]; then
        echo "Enabling maintenance mode on forum..."

        if [ -n "$DRY_RUN" ]; then
            echo "DRY RUN - maintenance mode will not be changed"
        else
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
        fi

    elif [ "$MAINTENANCE_MODE" = "off" ]; then
        echo "Disabling maintenance mode on forum..."

        if [ -n "$DRY_RUN" ]; then
            echo "DRY RUN - maintenance mode will not be changed"
        else
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
        fi

    elif [ "$MAINTENANCE_MODE" = "status" ]; then
        echo "Checking maintenance mode status..."
        STATUS=$(ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
            "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} -sN -e \"SELECT config_value FROM phpbb_config WHERE config_name='board_disable'\"")

        if [ $? -eq 0 ]; then
            if [ "$STATUS" = "1" ]; then
                echo "⚠️  Maintenance mode is currently: ENABLED"
                echo "  Regular users cannot access the forum"
                echo "  Only administrators can log in"

                # Also get the maintenance message
                MESSAGE=$(ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
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
    validate_ssh_config

    echo "WARNING: This will REPLACE the entire database!"
    echo "Database: ${DB_NAME} on ${SSH_HOST}"
    echo "Restore file: ${RESTORE_FILE}"
    echo ""

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN - database will not be restored"
    else
        read -p "Are you sure you want to restore? Type 'yes' to continue: " CONFIRM

        if [ "$CONFIRM" != "yes" ]; then
            echo "Restore cancelled"
            exit 1
        fi

        echo "Restoring database from ${RESTORE_FILE}..."

        # Detect if file is compressed
        if [[ "$RESTORE_FILE" == *.bz2 ]]; then
            echo "Detected bzip2 compressed file, decompressing..."
            bunzip2 -c "$RESTORE_FILE" | ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
                "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"
        elif [[ "$RESTORE_FILE" == *.gz ]]; then
            echo "Detected gzip compressed file, decompressing..."
            gunzip -c "$RESTORE_FILE" | ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
                "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"
        else
            echo "Restoring uncompressed SQL file..."
            cat "$RESTORE_FILE" | ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
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
fi

# Handle syncdn (download from server)
if [ "$SYNC_DOWN" = true ]; then
    ensure_ssh_key_loaded

    SRC="$SSH_USER@$SSH_HOST:$WEBDIR"
    EXCLUDE="--exclude-from=.rsyncdnignore"

    echo "Syncing FROM server to local..."
    echo "Source: $SRC"
    echo "Destination: ./public/forum/"

    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN MODE - no files will be changed"
    fi

    RSYNC_OPTS="-acv --progress --stats"
    [ "$VERBOSE" -gt 0 ] && RSYNC_OPTS="$RSYNC_OPTS -v"
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

# Handle deploy (build the site, then upload to server)
# Source of truth is the repo: build ./dist/ from the repo, then fall through
# to the syncup handler below to push it. Does NOT pull from the server (syncdn).
if [ "$DEPLOY" = true ]; then
    echo "Building site (npm run build)..."
    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN MODE - build still runs (local only, produces ./dist/)"
    fi

    npm run build
    if [ $? -ne 0 ]; then
        echo "✗ Build failed!"
        exit 1
    fi
    echo "✓ Build completed successfully!"

    # Hand off to the syncup handler below to perform the upload
    SYNC_UP=true
fi

# Handle syncup (upload to server)
if [ "$SYNC_UP" = true ]; then
    ensure_ssh_key_loaded

    DEST="$SSH_USER@$SSH_HOST:$WEBDIR"
    EXCLUDE="--exclude-from=.rsyncupignore"

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
    [ "$VERBOSE" -gt 0 ] && RSYNC_OPTS="$RSYNC_OPTS -v"
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
    PRUNE_DIR="$BACKUP_SOURCE"
    if [ -n "$SYNC_BACKUPS" ]; then
        # If we synced, prune the destination
        PRUNE_DIR="$SYNC_BACKUPS"
    fi

    if ! apply_retention_policy "$PRUNE_DIR"; then
        echo "Backup pruning failed!"
        exit 1
    fi
fi

# Handle set_password
if [ -n "$SET_PASSWORD_USER" ]; then
    # Get database credentials
    get_db_credentials
    validate_ssh_config

    # Find the script directory and project root
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    ARGON2_SCRIPT="$SCRIPT_DIR/phpbb_argon2.py"

    if [ ! -f "$ARGON2_SCRIPT" ]; then
        echo "Error: phpbb_argon2.py not found at: $ARGON2_SCRIPT"
        exit 1
    fi

    if [ ! -f "$PROJECT_ROOT/pyproject.toml" ]; then
        echo "Error: pyproject.toml not found at: $PROJECT_ROOT"
        exit 1
    fi

    # Check if uv is available, install if needed
    if ! command -v uv &> /dev/null; then
        echo "uv not found, installing..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # Add to PATH for this session
        export PATH="$HOME/.local/bin:$PATH"
        if ! command -v uv &> /dev/null; then
            echo "Error: Failed to install uv"
            exit 1
        fi
        echo "✓ uv installed successfully"
    fi

    echo "Setting password for forum user: $SET_PASSWORD_USER"

    # Get the password
    if [ "$PASSWORD_STDIN" = true ]; then
        PASSWORD=$(head -n 1)
    else
        # Use getpass-style prompt (no echo)
        read -s -p "New password: " PASSWORD
        echo ""
        read -s -p "Confirm password: " PASSWORD_CONFIRM
        echo ""

        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            echo "Error: Passwords do not match"
            exit 1
        fi
    fi

    if [ -z "$PASSWORD" ]; then
        echo "Error: Password cannot be empty"
        exit 1
    fi

    # Generate the Argon2 hash using the Python script via uv
    [ "$VERBOSE" -gt 0 ] && echo "Generating Argon2 hash..."
    PASSWORD_HASH=$(echo "$PASSWORD" | uv run --project "$PROJECT_ROOT" python "$ARGON2_SCRIPT" --stdin 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$PASSWORD_HASH" ]; then
        echo "Error: Failed to generate password hash"
        exit 1
    fi

    [ "$VERBOSE" -gt 0 ] && echo "Hash generated: ${PASSWORD_HASH:0:30}..."

    # SQL is sent to mysql via stdin (not -e) so '$' chars in values are not
    # expanded by the remote shell, which would otherwise corrupt Argon2 hashes.
    # Escape single quotes in values for SQL string literals.
    ESCAPED_USER="${SET_PASSWORD_USER//\'/\'\'}"
    ESCAPED_HASH="${PASSWORD_HASH//\'/\'\'}"

    # First verify the user exists
    [ "$VERBOSE" -gt 0 ] && echo "Verifying user exists..."
    USER_EXISTS=$(printf "SELECT COUNT(*) FROM phpbb_users WHERE username='%s'\n" "$ESCAPED_USER" | \
        ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
        "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} -sN")

    if [ "$USER_EXISTS" != "1" ]; then
        if [ "$USER_EXISTS" = "0" ]; then
            echo "Error: User '$SET_PASSWORD_USER' not found in phpbb_users"
        else
            echo "Error: Multiple users found with username '$SET_PASSWORD_USER' (found: $USER_EXISTS)"
        fi
        exit 1
    fi

    # Update the password in the database
    if [ -n "$DRY_RUN" ]; then
        echo "DRY RUN - would update password for user: $SET_PASSWORD_USER"
        echo "Hash: ${PASSWORD_HASH:0:50}..."
    else
        [ "$VERBOSE" -gt 0 ] && echo "Updating password in database..."

        printf "UPDATE phpbb_users SET user_password='%s' WHERE username='%s'\n" \
            "$ESCAPED_HASH" "$ESCAPED_USER" | \
            ssh -i "${SSH_KEY}" "${SSH_USER}@${SSH_HOST}" \
            "mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"

        if [ $? -eq 0 ]; then
            echo "✓ Password updated successfully for user: $SET_PASSWORD_USER"
        else
            echo "✗ Failed to update password"
            exit 1
        fi
    fi
fi

echo ""
echo "All requested operations completed successfully!"
