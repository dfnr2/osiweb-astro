#!/usr/bin/env python3
"""
Backup Sync and Pruning Script

Syncs backup directory to a dedicated location, then applies tiered retention policy.
"""

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict


def run_rsync(source_dir, dest_dir, verbose=0):
    """Copy new backup files from source to destination"""
    # Ensure destination directory exists
    Path(dest_dir).mkdir(parents=True, exist_ok=True)
    
    # Build rsync command with appropriate verbosity
    rsync_flags = ["-a", "--ignore-existing"]
    if verbose > 0:
        rsync_flags.append("-v")
    if verbose > 1:
        rsync_flags.append("--progress")
    
    cmd = ["rsync"] + rsync_flags + [f"{source_dir}/", f"{dest_dir}/"]
    
    if verbose > 0:
        print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        if verbose > 0:
            print("Copy completed successfully")
        if verbose > 1 and result.stdout:
            print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Rsync failed: {e}")
        if e.stderr:
            print(f"Error output: {e.stderr}")
        return False
    return True


def parse_backup_date(filename):
    """Extract date from backup filename
    
    Supports formats like:
    - osiweb-db-20250906-144834.sql.bz2
    - database_backup_20250906_144834.sql
    - backup-2025-09-06.sql.bz2
    """
    # Pattern 1: YYYYMMDD-HHMMSS or YYYYMMDD_HHMMSS
    pattern1 = r'(\d{8})[_-](\d{6})'
    match1 = re.search(pattern1, filename)
    if match1:
        date_str = match1.group(1)
        time_str = match1.group(2)
        return datetime.strptime(f"{date_str}{time_str}", "%Y%m%d%H%M%S")
    
    # Pattern 2: YYYY-MM-DD format
    pattern2 = r'(\d{4}-\d{2}-\d{2})'
    match2 = re.search(pattern2, filename)
    if match2:
        return datetime.strptime(match2.group(1), "%Y-%m-%d")
    
    return None


def get_backup_files(directory, verbose=0):
    """Get all backup files with their parsed dates"""
    backup_files = []
    
    for filename in os.listdir(directory):
        filepath = os.path.join(directory, filename)
        if not os.path.isfile(filepath):
            continue
            
        # Skip non-backup files
        if not any(ext in filename.lower() for ext in ['.sql', '.bz2', '.gz']):
            continue
            
        date = parse_backup_date(filename)
        if date:
            backup_files.append((filepath, filename, date))
            if verbose > 2:
                print(f"Found backup: {filename} -> {date.strftime('%Y-%m-%d %H:%M:%S')}")
        else:
            if verbose > 0:
                print(f"Warning: Could not parse date from {filename}")
    
    # Sort by date (newest first)
    backup_files.sort(key=lambda x: x[2], reverse=True)
    return backup_files


def apply_retention_policy(backup_files, keep_all_days=1, keep_daily_days=7, keep_weekly_days=30, verbose=0):
    """Apply tiered retention policy and return files to keep/delete
    
    Args:
        backup_files: List of (filepath, filename, date) tuples
        keep_all_days: Keep all files newer than this many days
        keep_daily_days: Keep 1/day for files newer than this many days  
        keep_weekly_days: Keep 1/week for files newer than this many days
        verbose: Verbosity level
    """
    now = datetime.now()
    keep_files = set()
    delete_files = []
    
    # Calculate thresholds
    keep_all_threshold = now - timedelta(days=keep_all_days)
    keep_daily_threshold = now - timedelta(days=keep_daily_days)
    keep_weekly_threshold = now - timedelta(days=keep_weekly_days)
    
    if verbose > 1:
        print(f"Retention thresholds:")
        print(f"  Keep all: < {keep_all_days} days (after {keep_all_threshold.strftime('%Y-%m-%d %H:%M')})")
        print(f"  Keep daily: < {keep_daily_days} days (after {keep_daily_threshold.strftime('%Y-%m-%d %H:%M')})")
        print(f"  Keep weekly: < {keep_weekly_days} days (after {keep_weekly_threshold.strftime('%Y-%m-%d %H:%M')})")
        print(f"  Keep monthly: >= {keep_weekly_days} days (before {keep_weekly_threshold.strftime('%Y-%m-%d %H:%M')})")
        print()
    
    # Group files by time periods for easier processing
    daily_buckets = defaultdict(list)  # date -> [files]
    weekly_buckets = defaultdict(list)  # week_start_date -> [files] 
    monthly_buckets = defaultdict(list)  # month_start_date -> [files]
    
    for filepath, filename, file_date in backup_files:
        # 1. Keep everything newer than keep_all_threshold
        if file_date >= keep_all_threshold:
            keep_files.add(filepath)
            if verbose > 0:
                print(f"KEEP (< {keep_all_days} days): {filename}")
            continue
            
        # Group into buckets for further processing
        day_key = file_date.date()
        daily_buckets[day_key].append((filepath, filename, file_date))
        
        # Week bucket (Monday as week start)
        days_since_monday = file_date.weekday()
        week_start = file_date.date() - timedelta(days=days_since_monday)
        weekly_buckets[week_start].append((filepath, filename, file_date))
        
        # Month bucket
        month_start = file_date.date().replace(day=1)
        monthly_buckets[month_start].append((filepath, filename, file_date))
    
    # 2. Keep 1 per day for daily retention period
    for day in sorted(daily_buckets.keys(), reverse=True):
        day_dt = datetime.combine(day, datetime.min.time())
        if keep_daily_threshold <= day_dt < keep_all_threshold:
            # Keep the newest file from this day
            day_files = daily_buckets[day]
            day_files.sort(key=lambda x: x[2], reverse=True)  # newest first
            keep_file = day_files[0]
            keep_files.add(keep_file[0])
            if verbose > 0:
                print(f"KEEP (daily): {keep_file[1]}")
    
    # 3. Keep 1 per week for weekly retention period
    for week_start in sorted(weekly_buckets.keys(), reverse=True):
        week_start_dt = datetime.combine(week_start, datetime.min.time())
        if keep_weekly_threshold <= week_start_dt < keep_daily_threshold:
            # Keep the newest file from this week
            week_files = weekly_buckets[week_start]
            week_files.sort(key=lambda x: x[2], reverse=True)
            keep_file = week_files[0]
            if keep_file[0] not in keep_files:  # Don't double-count daily keeps
                keep_files.add(keep_file[0])
                if verbose > 0:
                    print(f"KEEP (weekly): {keep_file[1]}")
    
    # 4. Keep 1 per month for everything older than weekly threshold
    for month_start in sorted(monthly_buckets.keys(), reverse=True):
        month_start_dt = datetime.combine(month_start, datetime.min.time())
        if month_start_dt < keep_weekly_threshold:
            # Keep the newest file from this month
            month_files = monthly_buckets[month_start]
            month_files.sort(key=lambda x: x[2], reverse=True)
            keep_file = month_files[0]
            if keep_file[0] not in keep_files:  # Don't double-count
                keep_files.add(keep_file[0])
                if verbose > 0:
                    print(f"KEEP (monthly): {keep_file[1]}")
    
    # Everything else gets deleted
    for filepath, filename, file_date in backup_files:
        if filepath not in keep_files:
            delete_files.append((filepath, filename, file_date))
    
    return list(keep_files), delete_files


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Sync backup directory and apply tiered retention policy",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage with default thresholds (1/7/30 days)
  %(prog)s -s ./backups -d ~/Dropbox/osiweb-backups
  
  # Dry run to see what would be deleted
  %(prog)s -s ./backups -d ~/Dropbox/osiweb-backups --dry-run
  
  # Custom thresholds: keep all for 2 days, daily for 14 days, weekly for 60 days
  %(prog)s -s ./backups -d ~/Dropbox/osiweb-backups --keep-all 2 --keep-daily 14 --keep-weekly 60
  
  # Verbose output
  %(prog)s -s ./backups -d ~/Dropbox/osiweb-backups -vv
  
Retention Policy:
  1. Keep ALL files newer than --keep-all days (default: 1 day)
  2. Keep 1 per DAY for files newer than --keep-daily days (default: 7 days)
  3. Keep 1 per WEEK for files newer than --keep-weekly days (default: 30 days)  
  4. Keep 1 per MONTH for all files older than --keep-weekly days
        """)
    
    parser.add_argument('-s', '--source', required=True,
                       help='Source backup directory to sync from')
    
    parser.add_argument('-d', '--destination', required=True,
                       help='Destination directory for backups')
    
    parser.add_argument('-n', '--dry-run', action='store_true',
                       help='Show what would be deleted without actually deleting files')
    
    parser.add_argument('--keep-all', type=int, default=1, metavar='DAYS',
                       help='Keep all files newer than this many days (default: 1)')
    
    parser.add_argument('--keep-daily', type=int, default=7, metavar='DAYS',
                       help='Keep 1 per day for files newer than this many days (default: 7)')
    
    parser.add_argument('--keep-weekly', type=int, default=30, metavar='DAYS',
                       help='Keep 1 per week for files newer than this many days (default: 30)')
    
    parser.add_argument('-v', '--verbose', action='count', default=0,
                       help='Increase verbosity (-v, -vv, -vvv)')
    
    args = parser.parse_args()
    
    # Validate arguments
    if not os.path.exists(args.source):
        parser.error(f"Source directory does not exist: {args.source}")
    
    if args.keep_all < 0 or args.keep_daily < 0 or args.keep_weekly < 0:
        parser.error("Retention periods must be non-negative")
    
    if args.keep_all > args.keep_daily:
        parser.error("--keep-all must be <= --keep-daily")
    
    if args.keep_daily > args.keep_weekly:
        parser.error("--keep-daily must be <= --keep-weekly")
    
    return args


def main():
    args = parse_args()
    
    if args.verbose > 0:
        print(f"Source: {args.source}")
        print(f"Destination: {args.destination}")
        print(f"Dry run: {args.dry_run}")
        print(f"Retention: keep-all={args.keep_all}d, keep-daily={args.keep_daily}d, keep-weekly={args.keep_weekly}d")
        print("-" * 60)
    
    # Step 1: Copy files
    if args.verbose > 0:
        print("Copying files...")
    
    if not run_rsync(args.source, args.destination, args.verbose):
        print("Copy failed, aborting")
        sys.exit(1)
    
    if args.verbose > 0:
        print("\n" + "=" * 60)
        print("APPLYING RETENTION POLICY")
        print("=" * 60)
    
    # Step 2: Get all backup files
    backup_files = get_backup_files(args.destination, args.verbose)
    if not backup_files:
        print("No backup files found")
        return
    
    if args.verbose > 0:
        print(f"\nFound {len(backup_files)} backup files")
    
    # Step 3: Apply retention policy
    keep_files, delete_files = apply_retention_policy(
        backup_files, 
        args.keep_all, 
        args.keep_daily, 
        args.keep_weekly, 
        args.verbose
    )
    
    # Step 4: Show summary and delete files
    if args.verbose > 0 or delete_files:
        print(f"\n" + "-" * 60)
        print(f"SUMMARY: Keeping {len(keep_files)} files, deleting {len(delete_files)} files")
        print("-" * 60)
    
    if delete_files:
        if args.verbose > 0:
            print("\nFiles to DELETE:")
            for filepath, filename, file_date in sorted(delete_files, key=lambda x: x[2], reverse=True):
                print(f"  {filename} ({file_date.strftime('%Y-%m-%d %H:%M:%S')})")
        
        if not args.dry_run:
            if args.verbose > 0:
                print(f"\nDeleting {len(delete_files)} files...")
            deleted_count = 0
            for filepath, filename, file_date in delete_files:
                try:
                    os.remove(filepath)
                    deleted_count += 1
                    if args.verbose > 1:
                        print(f"Deleted: {filename}")
                except OSError as e:
                    print(f"Error deleting {filename}: {e}")
            
            if args.verbose > 0:
                print(f"Successfully deleted {deleted_count}/{len(delete_files)} files")
        else:
            print(f"\n(DRY RUN - {len(delete_files)} files would be deleted)")
    else:
        if args.verbose > 0:
            print("\nNo files to delete")
    
    if args.verbose > 0:
        print("Done.")


if __name__ == "__main__":
    main()