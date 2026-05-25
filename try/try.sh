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
    -h, --help         Show this help message and exit
    -l, --list         List all workspaces and exit
    -p, --path PATH    Set base path for workspaces (default: ~/workspace/tries)
    -d, --delete NAME  Delete a workspace matching NAME

FEATURES:
    - Interactive directory selection with fuzzy search
    - Automatic date-prefixed directories
    - Recency scoring for recent workspaces
    - Create new workspaces on the fly
    - Quick create with + prefix
    - Quick delete with - prefix (uses trash if available, else prompts)

EXAMPLES:
    $cmd                 Open interactive selector
    $cmd react           Filter for react-related workspaces
    $cmd +myproject      Create workspace named myproject
    $cmd + myproject     Create workspace named myproject (space-separated)
    $cmd +               Create workspace with random name
    $cmd -myproject      Delete workspace matching myproject
    $cmd --delete react  Delete workspace matching react
    $cmd -p ~/projects   Use custom workspace path
    $cmd -l              List all workspaces

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

list_workspaces() {
    local tries_path="$1"

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
        return 0
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

    # Display items with formatting
    printf "%-40s %s\n" "WORKSPACE" "ACCESSED"
    printf "%-40s %s\n" "$(printf '=%.0s' {1..40})" "$(printf '=%.0s' {1..15})"
    for item in "${sorted_items[@]}"; do
        local name="${item%%|*}"
        local time_text="${item#*|}"
        time_text="${time_text%%|*}"
        printf "%-40s %s\n" "$name" "$time_text"
    done
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
        # Record in zoxide if available
        if command -v zoxide &> /dev/null; then
            zoxide add "$full_path"
        fi
        # Successfully changed directory - spawn a new shell
        "${SHELL:-/bin/bash}"
        return 0
    else
        echo "Error: Failed to change to directory: $full_path"
        return 1
    fi
}

delete_workspace() {
    local tries_path="$1"
    local search_term="$2"

    if [[ -z "$search_term" ]]; then
        echo "Error: --delete requires a workspace name"
        return 1
    fi

    # Collect candidates by substring match
    local -a matches=()
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        [[ "$dir" == .* ]] && continue
        [[ ! -d "$tries_path/$dir" ]] && continue
        if [[ "$dir" == *"$search_term"* ]]; then
            matches+=("$dir")
        fi
    done < <(ls -1 "$tries_path" 2>/dev/null)

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "Error: no workspace matches '$search_term' in $tries_path"
        return 1
    fi

    local target
    if [[ ${#matches[@]} -eq 1 ]]; then
        target="${matches[0]}"
    else
        # Multiple matches - let user pick
        local fzf_opts=(
            "--prompt=Delete> "
            "--preview=echo {}"
            "--preview-window=right:30%"
            "--no-sort"
            "--query=$search_term"
        )
        target=$(
            printf '%s\n' "${matches[@]}" | fzf "${fzf_opts[@]}" 2>/dev/tty
        ) || return 1
        [[ -z "$target" ]] && return 1
    fi

    local full_path="$tries_path/$target"

    # Defensive: ensure resolved path stays inside tries_path
    local resolved
    resolved=$(cd "$full_path" 2>/dev/null && pwd) || {
        echo "Error: cannot resolve $full_path"
        return 1
    }
    if [[ "$resolved" != "$tries_path"/* ]]; then
        echo "Error: refusing to delete path outside $tries_path: $resolved"
        return 1
    fi

    # Warn if caller's CWD is inside the workspace being deleted - the parent
    # shell will be left in a stale directory (we can't cd it from here).
    local caller_pwd="${PWD:-}"
    if [[ -n "$caller_pwd" && ( "$caller_pwd" == "$resolved" || "$caller_pwd" == "$resolved"/* ) ]]; then
        echo "Warning: your shell is inside $resolved - cd elsewhere before/after to avoid a stale CWD"
    fi

    if command -v trash &> /dev/null; then
        trash "$full_path" || return 1
        echo "Trashed: $full_path"
    else
        local confirm
        read -r -p "Delete $full_path? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$full_path" || return 1
            echo "Deleted: $full_path"
        else
            echo "Aborted."
            return 1
        fi
    fi

    # Keep zoxide in sync
    if command -v zoxide &> /dev/null; then
        zoxide remove "$full_path" 2>/dev/null || true
    fi
}

main() {
    check_dependencies

    local tries_path="${TRY_PATH:-$HOME/workspace/tries}"
    local search_term=""
    local list_mode=false
    local delete_name=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -l | --list)
                list_mode=true
                shift
                ;;
            -p | --path)
                tries_path="$2"
                shift 2
                ;;
            -d | --delete)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: $1 requires a workspace name"
                    exit 1
                fi
                delete_name="$2"
                shift 2
                ;;
            +)
                # Handle "+ name" syntax (space-separated)
                shift
                search_term="+${1:-}"
                shift || true
                ;;
            -*)
                # -NAME shorthand for deletion (parallels +NAME for creation)
                delete_name="${1#-}"
                shift
                ;;
            *)
                search_term="$1"
                shift
                ;;
        esac
    done

    mkdir -p "$tries_path"
    tries_path=$(cd "$tries_path" && pwd)

    # If --list mode, display workspaces and exit
    if [[ "$list_mode" == true ]]; then
        list_workspaces "$tries_path"
        exit $?
    fi

    # If delete requested, run delete flow and exit
    if [[ -n "$delete_name" ]]; then
        delete_workspace "$tries_path" "$delete_name"
        exit $?
    fi

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

    # If search term provided, check for matches
    local selection
    if [[ -n "$search_term" ]]; then
        # Filter items matching the search term (exclude "Create new" line)
        local -a filtered_items=()
        while IFS= read -r item; do
            [[ "$item" == *"Create new"* ]] && continue
            filtered_items+=("$item")
        done < <(printf '%s\n' "${display_items[@]}" | grep -i "$search_term")

        # If exactly one match, select it automatically
        if [[ ${#filtered_items[@]} -eq 1 ]]; then
            selection="${filtered_items[0]}"
            echo "Found workspace: $selection"
        elif [[ ${#filtered_items[@]} -gt 1 ]]; then
            # Multiple matches, use fzf to pick one
            local fzf_opts=(
                "--preview=echo {}"
                "--preview-window=right:30%"
                "--no-sort"
                "--with-nth=1"
                "--query=$search_term"
            )
            selection=$(
                printf '%s\n' "${display_items[@]}" | fzf "${fzf_opts[@]}" 2>/dev/tty
            ) || return 1
        else
            # No matches - create workspace with the search term name
            echo "No matching workspace found. Creating new workspace: $search_term"
            create_new_workspace "$tries_path" "$search_term"
            return $?
        fi
    else
        # No search term, use fzf normally
        local fzf_opts=(
            "--preview=echo {}"
            "--preview-window=right:30%"
            "--no-sort"
            "--with-nth=1"
        )
        selection=$(
            printf '%s\n' "${display_items[@]}" | fzf "${fzf_opts[@]}" 2>/dev/tty
        ) || return 1
    fi

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
        # Record in zoxide if available
        if command -v zoxide &> /dev/null; then
            zoxide add "$full_path"
        fi
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
