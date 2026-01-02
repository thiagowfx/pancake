#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [DIRECTORY]

Reconcile .apk-new configuration files on Alpine Linux.

When Alpine Linux upgrades a package with modified configuration files, the
new configuration is saved with a .apk-new suffix. This script helps review
and reconcile these files interactively.

ARGUMENTS:
    DIRECTORY    Directory to search for .apk-new files (default: /etc)

OPTIONS:
    -h, --help    Show this help message and exit
    -c, --count   Print number of pending reconciliations and exit

ACTIONS:
    v, view       Show diff between original and new file
    k, keep       Keep your current file, discard the new version
    r, replace    Replace your current file with the new version
    m, merge      Open both files in \$DIFFTOOL (or vimdiff) for manual merge
    s, skip       Skip this file for now

ENVIRONMENT:
    DIFFTOOL    Diff tool to use for merging (default: vimdiff)

EXAMPLES:
    $cmd                    Reconcile files in /etc
    $cmd /etc/nginx         Reconcile files in /etc/nginx only
    $cmd --count            Print number of pending reconciliations
    doas $cmd               Run with root privileges (usually required)

EXIT CODES:
    0    All files processed successfully
    1    Error occurred or no files found
EOF
}

: "${DIFFTOOL:=vimdiff}"

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "diff"
        "find"
        # keep-sorted end
    )
    local missing_deps=()

    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

show_diff() {
    local original="$1"
    local new_file="$2"

    if [[ -f "$original" ]]; then
        diff --color=auto -u "$original" "$new_file" || true
    else
        echo "Original file does not exist. New file contents:"
        cat "$new_file"
    fi
}

process_file() {
    local new_file="$1"
    local original="${new_file%.apk-new}"

    echo "=============================================="
    echo "File: $new_file"
    echo "Original: $original"
    echo "=============================================="

    while true; do
        echo ""
        echo "[v]iew diff  [k]eep original  [r]eplace with new  [m]erge  [s]kip"
        read -r -p "Action: " action

        case "$action" in
            v|V|view)
                show_diff "$original" "$new_file"
                ;;
            k|K|keep)
                echo "Removing $new_file..."
                rm "$new_file"
                echo "Done. Kept original file."
                return 0
                ;;
            r|R|replace)
                if [[ -f "$original" ]]; then
                    echo "Replacing $original with $new_file..."
                    mv "$new_file" "$original"
                else
                    echo "Creating $original from $new_file..."
                    mv "$new_file" "$original"
                fi
                echo "Done."
                return 0
                ;;
            m|M|merge)
                if ! command -v "$DIFFTOOL" &> /dev/null; then
                    echo "Error: $DIFFTOOL not found. Set DIFFTOOL environment variable."
                    continue
                fi
                if [[ ! -f "$original" ]]; then
                    echo "Error: Original file does not exist. Use [r]eplace instead."
                    continue
                fi
                "$DIFFTOOL" "$original" "$new_file"
                echo ""
                read -r -p "Merge complete. Remove $new_file? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm "$new_file"
                    echo "Removed $new_file."
                fi
                return 0
                ;;
            s|S|skip)
                echo "Skipping $new_file..."
                return 0
                ;;
            *)
                echo "Invalid action. Enter v, k, r, m, or s."
                ;;
        esac
    done
}

main() {
    local count_mode=false
    local search_dir="/etc"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--count)
                count_mode=true
                shift
                ;;
            *)
                search_dir="$1"
                shift
                ;;
        esac
    done

    if [[ ! -d "$search_dir" ]]; then
        echo "Error: Directory '$search_dir' does not exist."
        exit 1
    fi

    check_dependencies

    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$search_dir" -name "*.apk-new" -type f -print0 2>/dev/null)

    if [[ $count_mode == true ]]; then
        echo "${#files[@]}"
        exit 0
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No .apk-new files found."
        exit 0
    fi

    echo "Searching for .apk-new files in $search_dir..."
    echo "Found ${#files[@]} file(s) to process."
    echo ""

    local processed=0
    for file in "${files[@]}"; do
        process_file "$file"
        processed=$((processed + 1))
        echo ""
    done

    echo "=============================================="
    echo "Processed $processed file(s)."
}

main "$@"
