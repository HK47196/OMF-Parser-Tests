#!/bin/bash
# Test OMF parser output against saved snapshots

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORPUS_DIR="$SCRIPT_DIR/corpus"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshot"

cd "$PROJECT_ROOT"

UPDATE=false
[[ "$1" == "-u" || "$1" == "--update" ]] && UPDATE=true

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    echo "No snapshots found. Run ./generate_snapshots.sh first."
    exit 1
fi

mapfile -t snapshots < <(find "$SNAPSHOT_DIR" -name "*.json" | sort)
total=${#snapshots[@]}
current=0
passed=0
failed=0

echo "Testing $total snapshots..."
echo

for snapshot in "${snapshots[@]}"; do
    current=$((current + 1))
    rel_path="${snapshot#$SNAPSHOT_DIR/}"
    rel_path="${rel_path%.json}"
    corpus_file="$CORPUS_DIR/$rel_path"

    if [[ ! -f "$corpus_file" ]]; then
        echo "[$current/$total] MISSING: $rel_path"
        failed=$((failed + 1))
        continue
    fi

    tmpfile=$(mktemp)
    if ! PYTHONPATH=src python3 -m omf_parser.cli "$corpus_file" --json 2>/dev/null | sed 's|"filepath": "[^"]*"|"filepath": "'"$rel_path"'"|' > "$tmpfile"; then
        echo "[$current/$total] ERROR: $rel_path"
        rm -f "$tmpfile"
        failed=$((failed + 1))
        continue
    fi

    if diff -q "$snapshot" "$tmpfile" > /dev/null 2>&1; then
        echo "[$current/$total] OK: $rel_path"
        passed=$((passed + 1))
    else
        if $UPDATE; then
            cp "$tmpfile" "$snapshot"
            echo "[$current/$total] UPDATED: $rel_path"
            passed=$((passed + 1))
        else
            echo "[$current/$total] FAIL: $rel_path"
            diff "$snapshot" "$tmpfile" | head -20
            failed=$((failed + 1))
        fi
    fi
    rm -f "$tmpfile"
done

echo
echo "Results: $passed passed, $failed failed"
[[ $failed -gt 0 ]] && exit 1
exit 0
