#!/bin/bash
# Test OMF parser output against saved snapshots
# Runs tests in parallel for faster execution

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORPUS_DIR="$SCRIPT_DIR/corpus"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshot"

cd "$PROJECT_ROOT"

UPDATE=false
JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

usage() {
    echo "Usage: $0 [-u|--update] [-j|--jobs N]"
    echo "  -u, --update    Update snapshots that differ"
    echo "  -j, --jobs N    Number of parallel jobs (default: $JOBS)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--update) UPDATE=true; shift ;;
        -j|--jobs)
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --jobs requires a numeric argument"
                exit 1
            fi
            JOBS="$2"; shift 2
            ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    echo "No snapshots found. Run ./generate_snapshots.sh first."
    exit 1
fi

# Create temp directory for results
RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "$RESULTS_DIR"' EXIT

# Export variables for subprocesses
export CORPUS_DIR SNAPSHOT_DIR PROJECT_ROOT UPDATE RESULTS_DIR

# Function to test a single snapshot (runs in subprocess)
test_snapshot() {
    local snapshot="$1"
    local rel_path="${snapshot#$SNAPSHOT_DIR/}"
    rel_path="${rel_path%.json}"
    local corpus_file="$CORPUS_DIR/$rel_path"
    local path_hash=$(echo "$rel_path" | md5sum | cut -d' ' -f1)
    local result_file="$RESULTS_DIR/${path_hash}.result"
    local diff_file="$RESULTS_DIR/${path_hash}.diff"

    if [[ ! -f "$corpus_file" ]]; then
        echo "MISSING:$rel_path" > "$result_file"
        return
    fi

    local tmpfile=$(mktemp)
    if ! PYTHONPATH=src python3 -m omf_parser.cli "$corpus_file" --json 2>/dev/null | jq --arg path "$rel_path" '.filepath = $path' > "$tmpfile"; then
        echo "ERROR:$rel_path" > "$result_file"
        rm -f "$tmpfile"
        return
    fi

    if diff -q "$snapshot" "$tmpfile" > /dev/null 2>&1; then
        echo "OK:$rel_path" > "$result_file"
    else
        if [[ "$UPDATE" == "true" ]]; then
            cp "$tmpfile" "$snapshot"
            echo "UPDATED:$rel_path" > "$result_file"
        else
            echo "FAIL:$rel_path" > "$result_file"
            diff "$snapshot" "$tmpfile" | head -20 > "$diff_file"
        fi
    fi
    rm -f "$tmpfile"
}
export -f test_snapshot

# Find all snapshots
mapfile -t snapshots < <(find "$SNAPSHOT_DIR" -name "*.json" | sort)
total=${#snapshots[@]}

echo "Testing $total snapshots with $JOBS parallel jobs..."
echo

# Run tests in parallel
printf '%s\n' "${snapshots[@]}" | xargs -P "$JOBS" -I {} bash -c 'test_snapshot "$@"' _ {}

# Collect and report results
passed=0
failed=0
updated=0
declare -a ok_list=()
declare -a fail_list=()
declare -a error_list=()
declare -a missing_list=()
declare -a updated_list=()

for result_file in "$RESULTS_DIR"/*.result; do
    [[ -f "$result_file" ]] || continue
    result=$(cat "$result_file")
    status="${result%%:*}"
    path="${result#*:}"

    case "$status" in
        OK)
            passed=$((passed + 1))
            ok_list+=("$path")
            ;;
        UPDATED)
            updated=$((updated + 1))
            passed=$((passed + 1))
            updated_list+=("$path")
            ;;
        FAIL)
            failed=$((failed + 1))
            fail_list+=("$path")
            ;;
        ERROR)
            failed=$((failed + 1))
            error_list+=("$path")
            ;;
        MISSING)
            failed=$((failed + 1))
            missing_list+=("$path")
            ;;
    esac
done

# Report results
if [[ ${#ok_list[@]} -gt 0 ]]; then
    echo "=== PASSED (${#ok_list[@]}) ==="
    printf '  %s\n' "${ok_list[@]}"
    echo
fi

if [[ ${#updated_list[@]} -gt 0 ]]; then
    echo "=== UPDATED (${#updated_list[@]}) ==="
    printf '  %s\n' "${updated_list[@]}"
    echo
fi

if [[ ${#error_list[@]} -gt 0 ]]; then
    echo "=== ERRORS (${#error_list[@]}) ==="
    printf '  %s\n' "${error_list[@]}"
    echo
fi

if [[ ${#missing_list[@]} -gt 0 ]]; then
    echo "=== MISSING CORPUS FILES (${#missing_list[@]}) ==="
    printf '  %s\n' "${missing_list[@]}"
    echo
fi

if [[ ${#fail_list[@]} -gt 0 ]]; then
    echo "=== FAILURES (${#fail_list[@]}) ==="
    for path in "${fail_list[@]}"; do
        echo "  $path"
        diff_file="$RESULTS_DIR/$(echo "$path" | md5sum | cut -d' ' -f1).diff"
        if [[ -f "$diff_file" ]]; then
            sed 's/^/    /' "$diff_file"
        fi
        echo
    done
fi

# Summary
echo "========================================"
echo "Results: $passed passed, $failed failed"
if [[ $updated -gt 0 ]]; then
    echo "         $updated snapshots updated"
fi
echo "========================================"

[[ $failed -gt 0 ]] && exit 1
exit 0
