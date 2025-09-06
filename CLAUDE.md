# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the OSI (Ohio Scientific Inc.) historical documentation and community website, containing vintage computing resources and a phpBB forum. The site hosts technical documentation, disk images, firmware, and community discussions about Ohio Scientific computers from the late 1970s and early 1980s.

## Key Architecture Components

### Main Website Structure
- **Static content**: PDF manuals, disk images, firmware ROMs, and historical documents organized in themed directories
- **phpBB Forum**: Community discussion forum at `/forum/` running phpBB 3.3.x
- **Database**: MySQL database (`dfenyes_osiforum`) for the phpBB forum
- **Web server**: Appears to be hosted on HostGator with PHP support

### Directory Organization
- `/forum/` - phpBB 3.3.x forum installation
- `/manuals/` - Hardware and software documentation PDFs
- `/disk_images/` - Vintage disk images in .65D and other formats
- `/firmware/` - ROM images and monitor programs
- `/books/` - Scanned computer books
- `/software/` - Historical software archives
- `/backups/` - Database and file backups

## Common Development Commands

### Database Management
```bash
# Convert database from latin1 to utf8mb4 for full Unicode support
./convert-to-utf8mb4.sh -i backups/database.sql -o backups/database-utf8mb4.sql

# Clean up temporary and junk files
./cleanup-files.sh
```

### phpBB Forum Management
- Forum config: `/forum/config.php`
- Admin panel: Access via `/forum/adm/`
- Cache clearing: Delete contents of `/forum/cache/` (except .htaccess and index.htm)
- Extensions: Managed through `/forum/ext/`

### File Permissions
Ensure proper permissions for phpBB:
- Directories: 755
- Files: 644
- Config files: 640
- Cache/store directories: 777 (or owned by web server user)

## Database Configuration

The forum uses MySQL with these connection details defined in `/forum/config.php`:
- Database type: MySQL
- Database name: `dfenyes_osiforum`
- Table prefix: `phpbb_`
- Character set: Should be migrated to utf8mb4 using the conversion script

## Important Notes

### Security Considerations
- Database credentials are stored in `/forum/config.php`
- The `_private/` directory contains access restrictions
- Regular backups are stored in `/backups/`

### phpBB Specifics
- Version: phpBB 3.3.x
- Environment: Production
- Cache driver: File-based caching
- Installed extensions:
  - davidiq/reimg - Image resizing
  - hifikabin/largefont - Font size adjustments
  - phpbb/viglink - Monetization (can be disabled)

### Content Types
The repository contains primarily:
1. Historical documentation (PDFs)
2. Vintage disk images and ROMs
3. phpBB forum for community discussions
4. Static HTML pages for navigation

### Maintenance Tasks
- Regular database backups (SQL dumps in `/backups/`)
- Forum cache clearing when making style changes
- Database character set migration for emoji support
- Cleanup of temporary files and logs

## Development Workflow

1. **Forum modifications**: Work in `/forum/` directory, clear cache after changes
2. **Database updates**: Always backup first, use provided scripts for migrations
3. **Static content**: Add new documents to appropriate themed directories
4. **Testing**: No automated tests present; manual testing required for forum functionality