#!/bin/bash
cd /Volumes/User/dave/vsrc/osiweb-astro/public/forum/files || exit 1
batch=1
total=0
max_size=$((100 * 1024 * 1024))
files_to_add=""

for f in *; do
    if [ -f "$f" ]; then
        size=$(wc -c < "$f" 2>/dev/null)
        if [ $((total + size)) -gt $max_size ] && [ -n "$files_to_add" ]; then
            echo "Batch $batch: Adding $(echo "$files_to_add" | wc -w) files, total size: $((total / 1024 / 1024))MB"
            echo "$files_to_add" | xargs git add
            git commit -m "Adding forum files batch $batch"
            batch=$((batch + 1))
            total=0
            files_to_add=""
        fi
        total=$((total + size))
        files_to_add="$files_to_add $f"
    fi
done

if [ -n "$files_to_add" ]; then
    echo "Final batch $batch: Adding $(echo "$files_to_add" | wc -w) files, total size: $((total / 1024 / 1024))MB"
    echo "$files_to_add" | xargs git add
    git commit -m "Adding forum files batch $batch"
fi

echo "Done! Committed all files in $batch batches"
