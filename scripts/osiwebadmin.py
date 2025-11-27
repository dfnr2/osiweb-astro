#!/usr/bin/env -S uv run --quiet python
"""
osiwebadmin.py - OSIWeb Administration Tool

Manages backups, syncing, database operations, and maintenance for osiweb.org
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from getpass import getpass
from pathlib import Path
from typing import Annotated, Optional

import typer
from rich.console import Console
from rich.table import Table

VERSION = "2.1"

# Rich console for output
console = Console()

# Typer app
app = typer.Typer(
    name="osiwebadmin",
    help="OSIWeb Administration Tool - Manage backups, syncing, and maintenance",
    no_args_is_help=True,
    rich_markup_mode="rich",
)


# =============================================================================
# CONFIGURATION
# =============================================================================

DEFAULT_CONFIG_PATHS = [
    Path("osiwebadmin.json"),
    Path(".osiwebadmin.json"),
    Path.home() / ".config" / "osiwebadmin" / "config.json",
]


@dataclass
class Config:
    """Configuration with defaults."""

    # SSH settings
    ssh_key: Path = field(default_factory=lambda: Path.home() / ".ssh" / "id-hostgator-dfenyes")
    ssh_user: str = "dfenyes"
    ssh_host: str = "108.167.172.195"
    webdir: str = "public_html/"

    # Backup sync destination
    destination: str = ""

    # Retention policy defaults
    keep_all: int = 1
    keep_daily: int = 7
    keep_weekly: int = 30

    # Runtime options (set by CLI)
    verbose: int = 0
    dry_run: bool = False


def load_config(config_paths: list[Path] | None = None) -> Config:
    """Load config from first available file, merging with defaults."""
    paths = config_paths or DEFAULT_CONFIG_PATHS
    config = Config()

    for path in paths:
        expanded = path.expanduser()
        if expanded.is_file():
            if config.verbose > 0:
                console.print(f"Loading config from: {expanded}")
            with open(expanded) as f:
                data = json.load(f)

            # Map JSON keys to config attributes
            if "destination" in data:
                config.destination = data["destination"]
            if "keep_all" in data:
                config.keep_all = data["keep_all"]
            if "keep_daily" in data:
                config.keep_daily = data["keep_daily"]
            if "keep_weekly" in data:
                config.keep_weekly = data["keep_weekly"]
            if "verbose" in data:
                config.verbose = data["verbose"]
            break

    return config


def get_db_credentials() -> tuple[str, str, str]:
    """Extract database credentials from public/forum/config.php."""
    config_path = Path("public/forum/config.php")
    if not config_path.exists():
        error(f"Config file not found: {config_path}")
        raise typer.Exit(1)

    content = config_path.read_text()

    db_name_match = re.search(r"\$dbname\s*=\s*'([^']+)'", content)
    db_user_match = re.search(r"\$dbuser\s*=\s*'([^']+)'", content)
    db_pass_match = re.search(r"\$dbpasswd\s*=\s*'([^']+)'", content)

    if not all([db_name_match, db_user_match, db_pass_match]):
        error("Could not parse database credentials from config.php")
        raise typer.Exit(1)

    return db_name_match.group(1), db_user_match.group(1), db_pass_match.group(1)


# =============================================================================
# OUTPUT HELPERS
# =============================================================================


def success(msg: str) -> None:
    """Print success message."""
    console.print(f"[green]✓[/green] {msg}")


def error(msg: str) -> None:
    """Print error message."""
    console.print(f"[red]✗[/red] {msg}", style="red")


def warning(msg: str) -> None:
    """Print warning message."""
    console.print(f"[yellow]⚠[/yellow] {msg}")


def info(msg: str) -> None:
    """Print info message."""
    console.print(f"[blue]ℹ[/blue] {msg}")


# =============================================================================
# UTILITIES
# =============================================================================


def run_cmd(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    input_data: str | None = None,
    verbose: int = 0,
) -> subprocess.CompletedProcess:
    """Run a shell command with consistent error handling."""
    if verbose > 1:
        console.print(f"[dim]Running: {' '.join(cmd)}[/dim]")
    try:
        return subprocess.run(
            cmd,
            check=check,
            capture_output=capture,
            text=True,
            input=input_data,
        )
    except subprocess.CalledProcessError as e:
        error(f"Command failed: {' '.join(cmd)}")
        if e.stderr:
            console.print(f"[dim]{e.stderr}[/dim]")
        raise typer.Exit(1)
    except FileNotFoundError:
        error(f"Command not found: {cmd[0]}")
        raise typer.Exit(1)


def ssh_run(
    config: Config,
    remote_cmd: str,
    *,
    capture: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess:
    """Execute a command on remote server via SSH."""
    cmd = [
        "ssh",
        "-i",
        str(config.ssh_key),
        f"{config.ssh_user}@{config.ssh_host}",
        remote_cmd,
    ]
    return run_cmd(cmd, capture=capture, check=check, verbose=config.verbose)


def ensure_ssh_key_loaded(config: Config) -> None:
    """Add SSH key to agent if not already loaded."""
    key_name = config.ssh_key.name
    result = run_cmd(["ssh-add", "-l"], check=False, capture=True)
    if key_name not in result.stdout:
        run_cmd(["ssh-add", str(config.ssh_key)], check=False, verbose=config.verbose)


def confirm(prompt: str, required_response: str = "yes") -> bool:
    """Prompt user for confirmation. Returns True if confirmed."""
    try:
        response = console.input(f"{prompt} Type '[bold]{required_response}[/bold]' to continue: ")
        return response.strip() == required_response
    except (EOFError, KeyboardInterrupt):
        return False


# =============================================================================
# GLOBAL OPTIONS (via callback)
# =============================================================================

# Store config in context for commands to access
_config: Config | None = None


def version_callback(value: bool) -> None:
    """Print version and exit."""
    if value:
        console.print(f"osiwebadmin v{VERSION}")
        raise typer.Exit(0)


@app.callback(invoke_without_command=True)
def main(
    ctx: typer.Context,
    verbose: Annotated[
        int, typer.Option("-v", "--verbose", count=True, help="Increase verbosity")
    ] = 0,
    dry_run: Annotated[
        bool, typer.Option("-n", "--dry-run", help="Show what would change without doing it")
    ] = False,
    config_file: Annotated[
        Optional[Path], typer.Option("--config", help="Specify config file path")
    ] = None,
    version: Annotated[
        Optional[bool],
        typer.Option("--version", help="Show version and exit", callback=version_callback, is_eager=True),
    ] = None,
) -> None:
    """OSIWeb Administration Tool - Manage backups, syncing, and maintenance."""
    global _config

    # Load config
    config_paths = [config_file] if config_file else None
    _config = load_config(config_paths)

    # CLI options override config
    _config.verbose = max(_config.verbose, verbose)
    _config.dry_run = dry_run

    # Store in context for subcommands
    ctx.obj = _config


def get_config(ctx: typer.Context) -> Config:
    """Get config from context."""
    return ctx.obj or Config()


# =============================================================================
# COMMANDS
# =============================================================================


@app.command()
def backup_db(
    ctx: typer.Context,
    prune: Annotated[
        bool, typer.Option("--prune", help="Prune old backups after successful backup")
    ] = False,
) -> None:
    """Backup database via SSH."""
    config = get_config(ctx)

    # Get database credentials
    db_name, db_user, db_pass = get_db_credentials()

    # Create backup directory
    backup_dir = Path("backups")
    backup_dir.mkdir(exist_ok=True)

    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = backup_dir / f"osiweb-db-{timestamp}.sql.bz2"

    console.print(f"Creating database backup: [bold]{backup_file}[/bold]")
    console.print(f"Connecting to {config.ssh_host}...")
    console.print(f"Database: {db_name}")

    if config.dry_run:
        info("DRY RUN - no backup will be created")
        return

    # SSH to server, run mysqldump, pipe through bzip2
    with console.status("[bold blue]Creating database backup...") as status:
        status.update("Running mysqldump and compressing...")
        remote_cmd = f"mysqldump -u {db_user} -p'{db_pass}' {db_name} | bzip2"
        result = ssh_run(config, remote_cmd, capture=True)

        # Write to file
        backup_file.write_bytes(result.stdout.encode("latin-1") if isinstance(result.stdout, str) else result.stdout)

    # Verify backup isn't empty
    if backup_file.stat().st_size == 0:
        error("Database backup file is empty!")
        raise typer.Exit(1)

    size = backup_file.stat().st_size
    size_str = f"{size / 1024 / 1024:.1f}MB" if size > 1024 * 1024 else f"{size / 1024:.1f}KB"

    success("Database backup completed successfully!")
    console.print(f"File: {backup_file}")
    console.print(f"Size: {size_str}")

    # Run pruning if requested
    if prune:
        console.print()
        console.rule("[bold]PRUNING OLD BACKUPS[/bold]")
        apply_retention_policy(
            backup_dir,
            keep_all_days=config.keep_all,
            keep_daily_days=config.keep_daily,
            keep_weekly_days=config.keep_weekly,
            dry_run=config.dry_run,
            verbose=config.verbose,
        )


@app.command()
def backup_files(ctx: typer.Context) -> None:
    """Backup files (creates .tbz archive)."""
    config = get_config(ctx)

    # Create backup directory
    backup_dir = Path("backups")
    backup_dir.mkdir(exist_ok=True)

    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = backup_dir / f"osiweb-files-{timestamp}.tbz"

    console.print(f"Creating file backup: [bold]{backup_file}[/bold]")
    console.print("This may take a while due to the large forum directory...")

    if config.dry_run:
        info("DRY RUN - no backup will be created")
        return

    # Build tar command
    tar_opts = "-cjf" if config.verbose == 0 else "-cjvf"
    cmd = [
        "tar",
        tar_opts,
        str(backup_file),
        "--exclude=./backups",
        "--exclude=./.git",
        "--exclude=./forum/cache/production",
        ".",
    ]

    with console.status("[bold blue]Creating archive..."):
        run_cmd(cmd, verbose=config.verbose)

    size = backup_file.stat().st_size
    size_str = f"{size / 1024 / 1024:.1f}MB" if size > 1024 * 1024 else f"{size / 1024:.1f}KB"

    success("File backup completed successfully!")
    console.print(f"File: {backup_file}")
    console.print(f"Size: {size_str}")


@app.command()
def restore_db(
    ctx: typer.Context,
    file: Annotated[Path, typer.Argument(help="Backup file to restore")],
) -> None:
    """Restore database from backup file."""
    config = get_config(ctx)

    if not file.exists():
        error(f"Restore file not found: {file}")
        raise typer.Exit(1)

    # Get database credentials
    db_name, db_user, db_pass = get_db_credentials()

    warning("This will REPLACE the entire database!")
    console.print(f"Database: {db_name} on {config.ssh_host}")
    console.print(f"Restore file: {file}")
    console.print()

    if config.dry_run:
        info("DRY RUN - database will not be restored")
        return

    if not confirm("Are you sure you want to restore?"):
        console.print("Restore cancelled")
        raise typer.Exit(1)

    console.print(f"Restoring database from {file}...")

    # Determine decompression command
    if file.suffix == ".bz2" or str(file).endswith(".sql.bz2"):
        decompress_cmd = ["bunzip2", "-c", str(file)]
    elif file.suffix == ".gz" or str(file).endswith(".sql.gz"):
        decompress_cmd = ["gunzip", "-c", str(file)]
    else:
        decompress_cmd = ["cat", str(file)]

    # Pipe decompressed data to remote mysql
    with console.status("[bold blue]Restoring database..."):
        # Get decompressed data
        decompress_result = run_cmd(decompress_cmd, capture=True, verbose=config.verbose)

        # Pipe to remote mysql
        remote_cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name}"
        ssh_cmd = [
            "ssh",
            "-i",
            str(config.ssh_key),
            f"{config.ssh_user}@{config.ssh_host}",
            remote_cmd,
        ]
        run_cmd(ssh_cmd, input_data=decompress_result.stdout, verbose=config.verbose)

    success("Database restored successfully!")
    console.print()
    console.print("[bold]IMPORTANT:[/bold] Clear the forum cache:")
    console.print("  1. Via Admin Panel: ACP → General → Purge Cache")
    console.print("  2. Or delete: public/forum/cache/production/*")

    if "utf8mb4" in str(file).lower():
        console.print()
        info("You restored a UTF8MB4 converted database.")
        console.print("Your forum now supports full Unicode including emojis!")


@app.command()
def syncdn(
    ctx: typer.Context,
    delete: Annotated[
        bool, typer.Option("--delete", help="Delete files not in source")
    ] = False,
) -> None:
    """Sync files FROM server to local."""
    config = get_config(ctx)

    ensure_ssh_key_loaded(config)

    src = f"{config.ssh_user}@{config.ssh_host}:{config.webdir}forum/"
    dest = "./public/forum/"

    console.print("Syncing FROM server to local...")
    console.print(f"Source: {src}")
    console.print(f"Destination: {dest}")

    if config.dry_run:
        info("DRY RUN MODE - no files will be changed")

    # Build rsync command
    rsync_opts = ["-acv", "--progress", "--stats"]
    if delete:
        rsync_opts.append("--delete")
    if config.dry_run:
        rsync_opts.append("-n")

    exclude_file = Path(".rsyncdnignore")
    if exclude_file.exists():
        rsync_opts.extend(["--exclude-from", str(exclude_file)])

    cmd = [
        "rsync",
        *rsync_opts,
        "-e",
        f"ssh -i {config.ssh_key}",
        src,
        dest,
    ]

    run_cmd(cmd, verbose=config.verbose)
    success("Sync from server completed successfully!")


@app.command()
def syncup(
    ctx: typer.Context,
    delete: Annotated[
        bool, typer.Option("--delete", help="Delete files not in source")
    ] = False,
) -> None:
    """Sync files FROM local to server."""
    config = get_config(ctx)

    ensure_ssh_key_loaded(config)

    src = "./dist/"
    dest = f"{config.ssh_user}@{config.ssh_host}:{config.webdir}"

    console.print("Syncing FROM local to server...")
    console.print(f"Source: {src}")
    console.print(f"Destination: {dest}")

    if config.dry_run:
        info("DRY RUN MODE - no files will be changed")

    if delete and not config.dry_run:
        warning("--delete option will remove files on server not present locally!")
        if not confirm("Are you sure?"):
            console.print("Sync cancelled")
            raise typer.Exit(1)

    # Build rsync command
    rsync_opts = ["-acv", "--progress", "--stats"]
    if delete:
        rsync_opts.append("--delete")
    if config.dry_run:
        rsync_opts.append("-n")

    exclude_file = Path(".rsyncupignore")
    if exclude_file.exists():
        rsync_opts.extend(["--exclude-from", str(exclude_file)])

    cmd = [
        "rsync",
        *rsync_opts,
        "-e",
        f"ssh -i {config.ssh_key}",
        src,
        dest,
    ]

    run_cmd(cmd, verbose=config.verbose)
    success("Sync to server completed successfully!")


@app.command()
def maintenance(
    ctx: typer.Context,
    mode: Annotated[str, typer.Argument(help="Mode: on, off, or status")],
) -> None:
    """Set maintenance mode on/off or check status."""
    config = get_config(ctx)

    if mode not in ("on", "off", "status"):
        error("Mode must be 'on', 'off', or 'status'")
        raise typer.Exit(1)

    # Get database credentials
    db_name, db_user, db_pass = get_db_credentials()

    if mode == "on":
        console.print("Enabling maintenance mode on forum...")

        if config.dry_run:
            info("DRY RUN - maintenance mode will not be changed")
            return

        query = """
UPDATE phpbb_config SET config_value='1' WHERE config_name='board_disable';
UPDATE phpbb_config SET config_value='Forum temporarily offline for maintenance. We will be back shortly!' WHERE config_name='board_disable_msg';
"""
        remote_cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -e \"{query}\""
        ssh_run(config, remote_cmd)

        success("Maintenance mode ENABLED")
        console.print("  Regular users will see: 'Forum temporarily offline for maintenance'")
        console.print("  Admins can still log in")

    elif mode == "off":
        console.print("Disabling maintenance mode on forum...")

        if config.dry_run:
            info("DRY RUN - maintenance mode will not be changed")
            return

        query = "UPDATE phpbb_config SET config_value='0' WHERE config_name='board_disable';"
        remote_cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -e \"{query}\""
        ssh_run(config, remote_cmd)

        success("Maintenance mode DISABLED")
        console.print("  Forum is now accessible to all users")

    elif mode == "status":
        console.print("Checking maintenance mode status...")

        query = "SELECT config_value FROM phpbb_config WHERE config_name='board_disable'"
        remote_cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -sN -e \"{query}\""
        result = ssh_run(config, remote_cmd, capture=True)
        status_value = result.stdout.strip()

        if status_value == "1":
            warning("Maintenance mode is currently: ENABLED")
            console.print("  Regular users cannot access the forum")
            console.print("  Only administrators can log in")

            # Get maintenance message
            query_msg = "SELECT config_value FROM phpbb_config WHERE config_name='board_disable_msg'"
            remote_cmd_msg = f"mysql -u {db_user} -p'{db_pass}' {db_name} -sN -e \"{query_msg}\""
            result_msg = ssh_run(config, remote_cmd_msg, capture=True)
            if result_msg.stdout.strip():
                console.print(f"  Message: {result_msg.stdout.strip()}")
        elif status_value == "0":
            success("Maintenance mode is currently: DISABLED")
            console.print("  Forum is accessible to all users")
        else:
            warning(f"Unknown maintenance mode status: {status_value}")


@app.command()
def sync_backups(
    ctx: typer.Context,
    destination: Annotated[Path, typer.Argument(help="Destination directory")],
) -> None:
    """Sync backups to destination directory."""
    config = get_config(ctx)

    source_dir = Path("backups")
    dest_dir = destination.expanduser()

    console.print(f"Syncing backups to: [bold]{dest_dir}[/bold]")

    # Create destination if it doesn't exist
    if not config.dry_run:
        dest_dir.mkdir(parents=True, exist_ok=True)

    if not dest_dir.is_dir() and not config.dry_run:
        error(f"Cannot create destination directory: {dest_dir}")
        raise typer.Exit(1)

    # Build rsync command
    rsync_opts = ["-a", "--ignore-existing"]
    if config.verbose > 0:
        rsync_opts.extend(["-v", "--progress"])
    if config.dry_run:
        info("DRY RUN MODE - no files will be copied")
        rsync_opts.append("-n")

    cmd = ["rsync", *rsync_opts, f"{source_dir}/", f"{dest_dir}/"]

    run_cmd(cmd, verbose=config.verbose)
    success("Backup sync completed successfully")


@app.command()
def prune_backups(
    ctx: typer.Context,
    keep_all: Annotated[
        int, typer.Option("--keep-all", help="Keep all backups newer than N days")
    ] = 1,
    keep_daily: Annotated[
        int, typer.Option("--keep-daily", help="Keep 1/day for backups newer than N days")
    ] = 7,
    keep_weekly: Annotated[
        int, typer.Option("--keep-weekly", help="Keep 1/week for backups newer than N days")
    ] = 30,
) -> None:
    """Apply retention policy to delete old backups."""
    config = get_config(ctx)

    backup_dir = Path("backups")

    console.rule("[bold]PRUNING OLD BACKUPS[/bold]")

    apply_retention_policy(
        backup_dir,
        keep_all_days=keep_all,
        keep_daily_days=keep_daily,
        keep_weekly_days=keep_weekly,
        dry_run=config.dry_run,
        verbose=config.verbose,
    )


@app.command()
def set_password(
    ctx: typer.Context,
    username: Annotated[str, typer.Argument(help="Forum username")],
    stdin: Annotated[
        bool, typer.Option("--stdin", help="Read password from STDIN (single line)")
    ] = False,
) -> None:
    """Set password for a forum user."""
    config = get_config(ctx)

    # Import password hashing from sibling module
    script_dir = Path(__file__).parent
    sys.path.insert(0, str(script_dir))
    try:
        from phpbb_argon2 import generate_hash
    except ImportError as e:
        error(f"Could not import phpbb_argon2: {e}")
        error("Make sure phpbb_argon2.py is in the scripts directory")
        raise typer.Exit(1)

    console.print(f"Setting password for forum user: [bold]{username}[/bold]")

    # Get password
    if stdin:
        password = sys.stdin.readline().rstrip("\n")
    else:
        password = getpass("New password: ")
        password_confirm = getpass("Confirm password: ")

        if password != password_confirm:
            error("Passwords do not match")
            raise typer.Exit(1)

    if not password:
        error("Password cannot be empty")
        raise typer.Exit(1)

    # Generate Argon2 hash
    if config.verbose > 0:
        info("Generating Argon2 hash...")
    password_hash = generate_hash(password)

    if config.verbose > 0:
        info(f"Hash generated: {password_hash[:30]}...")

    # Get database credentials
    db_name, db_user, db_pass = get_db_credentials()

    # Verify user exists
    if config.verbose > 0:
        info("Verifying user exists...")

    query = f"SELECT COUNT(*) FROM phpbb_users WHERE username='{username}'"
    remote_cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -sN -e \"{query}\""
    result = ssh_run(config, remote_cmd, capture=True)
    user_count = result.stdout.strip()

    if user_count == "0":
        error(f"User '{username}' not found in phpbb_users")
        raise typer.Exit(1)
    elif user_count != "1":
        error(f"Multiple users found with username '{username}' (found: {user_count})")
        raise typer.Exit(1)

    # Update password
    if config.dry_run:
        info(f"DRY RUN - would update password for user: {username}")
        info(f"Hash: {password_hash[:50]}...")
        return

    if config.verbose > 0:
        info("Updating password in database...")

    # Escape single quotes in hash for SQL
    escaped_hash = password_hash.replace("'", "''")
    query = f"UPDATE phpbb_users SET user_password='{escaped_hash}' WHERE username='{username}'"
    remote_cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -e \"{query}\""
    ssh_run(config, remote_cmd)

    success(f"Password updated successfully for user: {username}")


# =============================================================================
# RETENTION POLICY
# =============================================================================


def parse_backup_date(filename: str) -> datetime | None:
    """Parse date from backup filename. Returns None if unparseable."""
    # Pattern: YYYYMMDD-HHMMSS or YYYYMMDD_HHMMSS
    m = re.search(r"(\d{8})[-_](\d{6})", filename)
    if m:
        try:
            return datetime.strptime(f"{m.group(1)}{m.group(2)}", "%Y%m%d%H%M%S")
        except ValueError:
            pass

    # Pattern: YYYY-MM-DD
    m = re.search(r"(\d{4}-\d{2}-\d{2})", filename)
    if m:
        try:
            return datetime.strptime(m.group(1), "%Y-%m-%d")
        except ValueError:
            pass

    return None


def apply_retention_policy(
    backup_dir: Path,
    *,
    keep_all_days: int,
    keep_daily_days: int,
    keep_weekly_days: int,
    dry_run: bool,
    verbose: int,
) -> int:
    """Apply tiered retention policy. Returns count of files deleted."""
    if not backup_dir.is_dir():
        error(f"Backup directory not found: {backup_dir}")
        raise typer.Exit(1)

    console.print(f"Applying retention policy to: [bold]{backup_dir}[/bold]")
    if verbose > 0:
        console.print(
            f"Retention: keep-all={keep_all_days}d, keep-daily={keep_daily_days}d, keep-weekly={keep_weekly_days}d"
        )

    now = datetime.now()
    keep_all_cutoff = now - timedelta(days=keep_all_days)
    keep_daily_cutoff = now - timedelta(days=keep_daily_days)
    keep_weekly_cutoff = now - timedelta(days=keep_weekly_days)

    # Buckets: date_key -> list of (filepath, file_datetime)
    daily_buckets: dict[str, list[tuple[Path, datetime]]] = defaultdict(list)
    weekly_buckets: dict[str, list[tuple[Path, datetime]]] = defaultdict(list)
    monthly_buckets: dict[str, list[tuple[Path, datetime]]] = defaultdict(list)

    keep_files: set[Path] = set()
    all_backup_files: list[Path] = []

    # Scan backup files
    for filepath in backup_dir.iterdir():
        if not filepath.is_file():
            continue
        # Only process backup files
        if not any(filepath.name.endswith(ext) for ext in [".sql", ".sql.bz2", ".sql.gz", ".bz2", ".gz", ".tbz"]):
            continue

        file_dt = parse_backup_date(filepath.name)
        if file_dt is None:
            if verbose > 0:
                warning(f"Could not parse date from: {filepath.name}")
            continue

        all_backup_files.append(filepath)

        # Keep everything newer than keep_all_cutoff
        if file_dt >= keep_all_cutoff:
            keep_files.add(filepath)
            if verbose > 0:
                console.print(f"[green]KEEP[/green] (< {keep_all_days} days): {filepath.name}")
            continue

        # Add to buckets for further processing
        daily_key = file_dt.strftime("%Y-%m-%d")
        daily_buckets[daily_key].append((filepath, file_dt))

        # Week starts on Monday
        week_start = file_dt - timedelta(days=file_dt.weekday())
        weekly_key = week_start.strftime("%Y-%m-%d")
        weekly_buckets[weekly_key].append((filepath, file_dt))

        monthly_key = file_dt.strftime("%Y-%m-01")
        monthly_buckets[monthly_key].append((filepath, file_dt))

    if not all_backup_files:
        console.print("No backup files found")
        return 0

    if verbose > 0:
        console.print(f"Found {len(all_backup_files)} backup files")

    # Keep 1 per day for daily retention period
    for day_key, files in daily_buckets.items():
        day_dt = datetime.strptime(day_key, "%Y-%m-%d")
        if keep_daily_cutoff <= day_dt < keep_all_cutoff:
            # Find newest file from this day
            newest = max(files, key=lambda x: x[1])
            keep_files.add(newest[0])
            if verbose > 0:
                console.print(f"[green]KEEP[/green] (daily): {newest[0].name}")

    # Keep 1 per week for weekly retention period
    for week_key, files in weekly_buckets.items():
        week_dt = datetime.strptime(week_key, "%Y-%m-%d")
        if keep_weekly_cutoff <= week_dt < keep_daily_cutoff:
            # Find newest file from this week that isn't already kept
            for filepath, file_dt in sorted(files, key=lambda x: x[1], reverse=True):
                if filepath not in keep_files:
                    keep_files.add(filepath)
                    if verbose > 0:
                        console.print(f"[green]KEEP[/green] (weekly): {filepath.name}")
                    break

    # Keep 1 per month for everything older
    for month_key, files in monthly_buckets.items():
        month_dt = datetime.strptime(month_key, "%Y-%m-%d")
        if month_dt < keep_weekly_cutoff:
            # Find newest file from this month that isn't already kept
            for filepath, file_dt in sorted(files, key=lambda x: x[1], reverse=True):
                if filepath not in keep_files:
                    keep_files.add(filepath)
                    if verbose > 0:
                        console.print(f"[green]KEEP[/green] (monthly): {filepath.name}")
                    break

    # Build delete list
    delete_files = [f for f in all_backup_files if f not in keep_files]

    # Summary
    console.print(f"\n[bold]SUMMARY:[/bold] Keeping {len(keep_files)} files, deleting {len(delete_files)} files")

    if delete_files:
        if verbose > 0 or dry_run:
            console.print("\nFiles to DELETE:")
            for filepath in delete_files:
                console.print(f"  [red]{filepath.name}[/red]")

        if dry_run:
            console.print(f"\n(DRY RUN - {len(delete_files)} files would be deleted)")
        else:
            console.print(f"\nDeleting {len(delete_files)} files...")
            deleted = 0
            for filepath in delete_files:
                try:
                    filepath.unlink()
                    deleted += 1
                    if verbose > 0:
                        console.print(f"Deleted: {filepath.name}")
                except OSError as e:
                    error(f"Error deleting {filepath.name}: {e}")
            success(f"Successfully deleted {deleted}/{len(delete_files)} files")
    else:
        if verbose > 0:
            console.print("No files to delete")

    return len(delete_files) if not dry_run else 0


# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

if __name__ == "__main__":
    app()
