#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [SEARCH_TERM]

Interactive ephemeral workspace manager. Create and navigate to temporary project directories with fuzzy finding and scoring.

Inspired by https://github.com/tobi/try

OPTIONS:
    -h, --help       Show this help message and exit
    -p, --path PATH  Set base path for workspaces (default: ~/workspace/tries)

FEATURES:
    - Interactive directory selection with fuzzy search
    - Automatic date-prefixed directories
    - Recency scoring for recent workspaces
    - Create new workspaces on the fly
    - Quick create with + prefix

EXAMPLES:
    $cmd                 Open interactive selector
    $cmd react           Filter for react-related workspaces
    $cmd +myproject      Create workspace named myproject
    $cmd + myproject     Create workspace named myproject (space-separated)
    $cmd +               Create workspace with random name
    $cmd -p ~/projects   Use custom workspace path

PREREQUISITES:
    - fzf (for fuzzy finding)
    - A shell that supports BASH_REMATCH

EXIT CODES:
    0    Successfully selected/created workspace
    1    Cancelled or error
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "fzf"
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

generate_random_name() {
    local words_file="/usr/share/dict/words"

    if [[ ! -f "$words_file" ]]; then
        # Fallback if words file doesn't exist
        echo "workspace-$$-$RANDOM"
        return 0
    fi

    # Pick a random word from the dictionary
    local line_count
    line_count=$(wc -l < "$words_file")
    local random_line=$((RANDOM % line_count + 1))
    sed -n "${random_line}p" "$words_file" | tr -d "'" | tr '[:upper:]' '[:lower:]'
}

create_new_workspace() {
    local tries_path="$1"
    local search_term="$2"

    local date_prefix
    date_prefix=$(date +%Y-%m-%d)

    local new_dir
    if [[ -n "$search_term" ]]; then
        new_dir="$date_prefix-$search_term"
    else
        echo "Enter workspace name (without date prefix):"
        echo "Use *, ?, or - for random name"
        read -r -p "> " new_dir || return 1
        [[ -z "$new_dir" ]] && return 1

        # Check for random name request
        if [[ "$new_dir" == "*" ]] || [[ "$new_dir" == "?" ]] || [[ "$new_dir" == "-" ]]; then
            new_dir=$(generate_random_name)
        fi

        new_dir="$date_prefix-$new_dir"
    fi

    # Sanitize directory name (replace spaces with hyphens)
    new_dir="${new_dir// /-}"

    local full_path="$tries_path/$new_dir"

    # Create directory if it doesn't exist
    if [[ ! -d "$full_path" ]]; then
        mkdir -p "$full_path" || return 1
    fi

    # Change to the directory and spawn a shell
    if cd "$full_path" 2>/dev/null; then
        # Successfully changed directory - spawn a new shell
        "${SHELL:-/bin/bash}"
        return 0
    else
        echo "Error: Failed to change to directory: $full_path"
        return 1
    fi
}

main() {
    check_dependencies

    local tries_path="${TRY_PATH:-$HOME/workspace/tries}"
    local search_term=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p | --path)
                tries_path="$2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option: $1"
                exit 1
                ;;
            +)
                # Handle "+ name" syntax (space-separated)
                shift
                search_term="+${1:-}"
                shift || true
                ;;
            *)
                search_term="$1"
                shift
                ;;
        esac
    done

    tries_path=$(cd "$tries_path" 2>/dev/null || mkdir -p "$tries_path" && cd "$tries_path" && pwd)

    # If search_term starts with +, create new workspace
    if [[ "$search_term" == +* ]]; then
        local new_name="${search_term#+}"
        new_name="${new_name#[[:space:]]}"  # Trim leading whitespace

        # Check for random name shortcuts: +*, +?, or +-
        if [[ "$new_name" == "*" ]] || [[ "$new_name" == "?" ]] || [[ "$new_name" == "-" ]]; then
            new_name=$(generate_random_name)
        fi

        # If still empty, pass empty string (will prompt interactively in create_new_workspace)
        create_new_workspace "$tries_path" "$new_name"
        exit $?
    fi

    # Collect all directories with metadata
    local -a items=()
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        [[ "$dir" == .* ]] && continue

        local path="$tries_path/$dir"
        [[ ! -d "$path" ]] && continue

        # Get modification time (in epoch seconds) for recency scoring
        local mtime
        mtime=$(date -r "$path" +%s 2>/dev/null || echo 0)

        # Format relative time
        local now
        now=$(date +%s)
        local seconds_ago=$((now - mtime))
        local time_text

        if [[ $seconds_ago -lt 60 ]]; then
            time_text="just now"
        elif [[ $seconds_ago -lt 3600 ]]; then
            time_text="$((seconds_ago / 60))m ago"
        elif [[ $seconds_ago -lt 86400 ]]; then
            time_text="$((seconds_ago / 3600))h ago"
        elif [[ $seconds_ago -lt 604800 ]]; then
            time_text="$((seconds_ago / 86400))d ago"
        else
            time_text="$((seconds_ago / 604800))w ago"
        fi

        items+=("$dir|$time_text|$mtime")
    done < <(ls -1 "$tries_path" 2>/dev/null)

    if [[ ${#items[@]} -eq 0 ]]; then
        echo "No workspaces found in $tries_path"
        create_new_workspace "$tries_path" "$search_term"
        return $?
    fi

    # Sort by recency (mtime descending)
    local -a sorted_items=()
    while IFS= read -r item; do
        sorted_items+=("$item")
    done < <(
        for item in "${items[@]}"; do
            echo "$item"
        done | sort -t'|' -k3 -rn
    )

    # Prepare fzf options
    local fzf_opts=(
        "--preview=echo {}"
        "--preview-window=right:30%"
        "--no-sort"
        "--with-nth=1"
    )

    # If search term provided, use it as initial input
    if [[ -n "$search_term" ]]; then
        fzf_opts+=("--query=$search_term")
    fi

    # Add option to create new
    local -a display_items=()
    for item in "${sorted_items[@]}"; do
        local name="${item%%|*}"
        local time_text="${item#*|}"
        time_text="${time_text%%|*}"
        display_items+=("$name (${time_text})")
    done

    local date_prefix
    date_prefix=$(date +%Y-%m-%d)
    display_items+=("➕ Create new: $date_prefix-")

    # Use fzf to select
    local selection
    selection=$(
        printf '%s\n' "${display_items[@]}" | fzf "${fzf_opts[@]}" 2>/dev/tty
    ) || return 1

    # Extract directory name from selection
    if [[ "$selection" == *"Create new"* ]]; then
        create_new_workspace "$tries_path" "$search_term"
        return $?
    fi

    # Extract the directory name (remove metadata)
    local dir_name="${selection%% (*}"
    local full_path="$tries_path/$dir_name"

    [[ ! -d "$full_path" ]] && {
        echo "Error: Directory not found: $full_path"
        return 1
    }

    # Change to the directory and spawn a shell
    if cd "$full_path" 2>/dev/null; then
        # Successfully changed directory - spawn a new shell
        "${SHELL:-/bin/bash}"
        return 0
    else
        echo "Error: Failed to change to directory: $full_path"
        return 1
    fi
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    main "$@"
fi
