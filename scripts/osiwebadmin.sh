#!/bin/bash

# OSIWeb Administration Script
# Manages backups, syncing, database operations, and maintenance for osiweb.org

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

usage() {
    echo "OSIWeb Administration Tool"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Backup Options:"
    echo "  -f, --backup-files       Backup files (creates .tbz archive)"
    echo "  -d, --backup-db          Backup database (via SSH)"
    echo ""
    echo "Sync Options:"
    echo "  --syncdn                 Sync files FROM server to local"
    echo "  --syncup                 Sync files FROM local to server"
    echo "  --delete                 Delete files not in source (use with sync)"
    echo "  -n, --dry-run           Show what would be synced without doing it"
    echo ""
    echo "Database Options:"
    echo "  -r, --restore FILE       Restore database from backup file"
    echo "  -m, --maintenance on|off Set maintenance mode"
    echo ""
    echo "Other Options:"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -h, --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -f                    # Backup files"
    echo "  $0 -d                    # Backup database"
    echo "  $0 --syncdn              # Download from server"
    echo "  $0 --syncup --dry-run    # Preview upload changes"
    echo "  $0 --syncup --delete     # Upload and delete removed files"
    echo "  $0 -m on                 # Enable maintenance mode"
    echo "  $0 -r backup.sql         # Restore database"
    echo ""
    echo "UTF8MB4 Conversion Workflow:"
    echo "  $0 -m on                 # Enable maintenance mode"
    echo "  $0 -d                    # Create backup"
    echo "  ./convert-to-utf8mb4.sh  # Convert backup"
    echo "  $0 -r backups/*-utf8mb4.sql  # Restore converted backup"
    echo "  $0 -m off                # Disable maintenance mode"
    exit 1
}

# Parse arguments - handle both short and long options
ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-files)
            BACKUP_FILES=true
            shift
            ;;
        --backup-db)
            BACKUP_DB=true
            shift
            ;;
        --syncdn)
            SYNC_DOWN=true
            shift
            ;;
        --syncup)
            SYNC_UP=true
            shift
            ;;
        --delete)
            DELETE_SYNC="--delete"
            shift
            ;;
        --dry-run)
            DRY_RUN="-n"
            shift
            ;;
        --verbose)
            VERBOSE="v"
            echo "Verbose mode enabled"
            shift
            ;;
        --restore)
            shift
            RESTORE_FILE="$1"
            shift
            ;;
        --maintenance)
            shift
            MAINTENANCE_MODE="$1"
            shift
            ;;
        --help)
            usage
            ;;
        -*)
            # Save short options for getopts
            ARGS+=("$1")
            if [[ "$1" == "-r" || "$1" == "-m" ]]; then
                # These options take arguments
                shift
                ARGS+=("$1")
            fi
            shift
            ;;
        *)
            # Unknown argument
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Process short options with getopts
set -- "${ARGS[@]}"
while getopts "vfdnhr:m:" opt; do
    case $opt in
        v)
            VERBOSE="v"
            echo "Verbose mode enabled"
            ;;
        f)
            BACKUP_FILES=true
            ;;
        d)
            BACKUP_DB=true
            ;;
        n)
            DRY_RUN="-n"
            ;;
        r)
            RESTORE_FILE="$OPTARG"
            ;;
        m)
            MAINTENANCE_MODE="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            usage
            ;;
    esac
done

# If no operation specified, show usage
if [ "$BACKUP_FILES" = false ] && [ "$BACKUP_DB" = false ] && [ -z "$RESTORE_FILE" ] && [ -z "$MAINTENANCE_MODE" ] && [ "$SYNC_DOWN" = false ] && [ "$SYNC_UP" = false ]; then
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

echo ""
echo "All requested operations completed successfully!"
