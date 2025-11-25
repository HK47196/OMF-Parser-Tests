#!/bin/bash
# Generate JSON snapshots for OMF corpus files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORPUS_DIR="$SCRIPT_DIR/corpus"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshot"

cd "$PROJECT_ROOT"

# Clean existing snapshots
rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR"

total=$(find "$CORPUS_DIR" -type f \( -name "*.LIB" -o -name "*.lib" -o -name "*.OBJ" -o -name "*.obj" -o -name "*.o" -o -name "*.O" \) | wc -l)
current=0
failed=0

echo "Generating snapshots for $total files..."

find "$CORPUS_DIR" -type f \( -name "*.LIB" -o -name "*.lib" -o -name "*.OBJ" -o -name "*.obj" -o -name "*.o" -o -name "*.O" \) | sort | while read -r file; do
    current=$((current + 1))
    rel_path="${file#$CORPUS_DIR/}"
    snapshot_path="$SNAPSHOT_DIR/${rel_path}.json"

    mkdir -p "$(dirname "$snapshot_path")"

    if PYTHONPATH=src python3 -m omf_parser.cli "$file" --json 2>/dev/null | sed 's|"filepath": "[^"]*"|"filepath": "'"$rel_path"'"|' > "$snapshot_path"; then
        echo "[$current/$total] $rel_path"
    else
        echo "[$current/$total] FAILED: $rel_path"
        rm -f "$snapshot_path"
        failed=$((failed + 1))
    fi
done

echo
echo "Done! ($failed failed)"
