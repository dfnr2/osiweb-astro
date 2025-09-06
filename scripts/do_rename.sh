#\!/bin/bash

# Function to clean filename
clean_filename() {
    echo "$1" | tr ' ' '_' | tr -d "'" | tr -d '"'
}

echo "=== Starting actual rename process ==="
echo ""

# Rename files outside upload/
find . \( -name "* *" -o -name "*'*" -o -name '*"*' \) -type f 2>/dev/null | grep -v "^./upload/" | sort | while IFS= read -r file; do
    new_name=$(clean_filename "$file")
    echo "Renaming: $file -> $new_name"
    mkdir -p "$(dirname "$new_name")"
    mv "$file" "$new_name"
    
    # Fix references in HTML/PHP files
    old_search="${file#./}"
    new_search="${new_name#./}"
    
    # Fix direct references
    grep -rl "$old_search" --include="*.html" --include="*.htm" --include="*.php" . 2>/dev/null | while read -r html; do
        echo "  Fixing references in: $html"
        sed -i.bak "s|$old_search|$new_search|g" "$html"
        rm "${html}.bak"
    done
    
    # Fix URL-encoded spaces
    old_encoded=$(echo "$old_search" | sed 's/ /%20/g')
    new_encoded="$new_search"
    if [ "$old_encoded" \!= "$old_search" ]; then
        grep -rl "$old_encoded" --include="*.html" --include="*.htm" --include="*.php" . 2>/dev/null | while read -r html; do
            echo "  Fixing URL-encoded references in: $html"
            sed -i.bak "s|$old_encoded|$new_encoded|g" "$html"
            rm "${html}.bak"
        done
    fi
    
    # Fix URL-encoded apostrophes
    if echo "$old_search" | grep -q "'"; then
        old_apostrophe_encoded=$(echo "$old_search" | sed "s/'/%27/g")
        grep -rl "$old_apostrophe_encoded" --include="*.html" --include="*.htm" --include="*.php" . 2>/dev/null | while read -r html; do
            echo "  Fixing URL-encoded apostrophe in: $html"
            sed -i.bak "s|$old_apostrophe_encoded|$new_search|g" "$html"
            rm "${html}.bak"
        done
        
        old_apostrophe_html=$(echo "$old_search" | sed "s/'/\&#39;/g")
        grep -rl "$old_apostrophe_html" --include="*.html" --include="*.htm" --include="*.php" . 2>/dev/null | while read -r html; do
            echo "  Fixing HTML-encoded apostrophe in: $html"
            sed -i.bak "s|$old_apostrophe_html|$new_search|g" "$html"
            rm "${html}.bak"
        done
    fi
done

# Rename files in upload/
find ./upload \( -name "* *" -o -name "*'*" -o -name '*"*' \) -type f 2>/dev/null | while IFS= read -r file; do
    new_name=$(clean_filename "$file")
    echo "Renaming: $file -> $new_name"
    mkdir -p "$(dirname "$new_name")"
    mv "$file" "$new_name"
done

# Clean up directories with spaces or quotes
find . \( -name "* *" -o -name "*'*" -o -name '*"*' \) -type d 2>/dev/null | sort -r | while IFS= read -r dir; do
    new_dir=$(clean_filename "$dir")
    if [ -d "$dir" ]; then
        echo "Renaming directory: $dir -> $new_dir"
        mv "$dir" "$new_dir" 2>/dev/null
    fi
done

echo ""
echo "=== Rename complete ==="
echo "Files with spaces/quotes remaining: $(find . \( -name "* *" -o -name "*'*" -o -name '*"*' \) -type f 2>/dev/null | wc -l)"
echo "Dirs with spaces/quotes remaining: $(find . \( -name "* *" -o -name "*'*" -o -name '*"*' \) -type d 2>/dev/null | wc -l)"
