#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [COMMAND] [OPTIONS]

Manage git worktrees with ease.

COMMANDS:
    add [branch] [path]     Create new worktree (auto-generates branch if omitted)
                            Aliases: new, create
    list                    List all worktrees
                            Aliases: ls
    remove [path]           Remove worktree (current if no path given)
                            Aliases: rm, del, delete
    prune                   Remove stale worktree administrative files
    goto [pattern]          Print path to worktree (interactive with fzf if no pattern)
    cd [pattern]            Change to worktree directory in new shell
    help                    Show this help message

OPTIONS:
    -h, --help              Show this help message and exit
    --no-cd                 Skip changing directory after creating worktree

PREREQUISITES:
    - Git 2.5+ with worktree support

EXAMPLES:
    $cmd add                              Auto-generate branch name and cd to it
    $cmd add feature-x                    Create worktree in ../feature-x and cd to it
    $cmd add --no-cd feature-x            Create worktree without changing directory
    $cmd add feature-x ~/work/proj-x      Create worktree in specific path
    $cmd list                             Show all worktrees
    $cmd remove                           Remove current worktree and cd to main
    $cmd remove ../feature-x              Remove specific worktree
    $cmd prune                            Clean up stale worktree data
    $cmd cd                               Interactive selection with fzf
    $cmd cd feature-x                     Change to worktree by exact branch name
    $cmd cd feature                       Partial match (uses fzf if multiple)
    $cmd cd '*bug*'                       Glob pattern match
    cd "\$($cmd goto)"                    Interactive selection with fzf (goto variant)
    cd "\$($cmd goto feature-x)"          Change to worktree by exact branch name (goto variant)

NOTES:
    - By default, 'add' changes directory to the new worktree (use --no-cd to skip)
    - By default, 'remove' without args removes current worktree and cds to main
    - When no branch is given, auto-generates name: username/word1-word2
    - When no path is given, worktrees are created as siblings to the main repo
    - The 'goto' command outputs the path for use with command substitution
    - The 'cd' command spawns a new shell in the worktree directory
    - Both 'goto' and 'cd' match by branch name or path (exact, glob, or partial)
    - When multiple matches exist, fzf provides interactive selection (if installed)
    - Branch names can be new or existing branches

EXIT CODES:
    0    Success
    1    Error occurred
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "git"
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

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        exit 1
    fi
}

generate_branch_name() {
    # Generate branch name: username/word1-word2
    local username
    username=$(git config user.name | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

    # Fallback to system username if git user.name not set
    if [[ -z "$username" ]]; then
        username=$(whoami)
    fi

    # Generate random words from /usr/share/dict/words if available
    local word1 word2
    if [[ -f /usr/share/dict/words ]]; then
        word1=$(grep -E '^[a-z]{4,8}$' /usr/share/dict/words | shuf -n 1)
        word2=$(grep -E '^[a-z]{4,8}$' /usr/share/dict/words | shuf -n 1)
    else
        # Fallback to random hex if dict not available
        word1=$(openssl rand -hex 3)
        word2=$(openssl rand -hex 3)
    fi

    echo "${username}/${word1}-${word2}"
}

cmd_add() {
    local branch=""
    local path=""
    local no_cd=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cd)
                no_cd=true
                shift
                ;;
            *)
                if [[ -z "$branch" ]]; then
                    branch="$1"
                elif [[ -z "$path" ]]; then
                    path="$1"
                else
                    echo "Error: Too many arguments"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Auto-generate branch name if not provided
    if [[ -z "$branch" ]]; then
        branch=$(generate_branch_name)
        echo "Auto-generated branch name: $branch"
    fi

    # If no path specified, create as sibling to main repo
    if [[ -z "$path" ]]; then
        local repo_root
        repo_root=$(git rev-parse --show-toplevel)
        local parent_dir
        parent_dir=$(dirname "$repo_root")
        # Use sanitized branch name for directory (replace / with -)
        local dir_name
        dir_name=$(echo "$branch" | tr '/' '-')
        path="$parent_dir/$dir_name"
    fi

    echo "Creating worktree for '$branch' at: $path"

    # Check if branch exists remotely or locally
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        # Branch exists, check it out
        git worktree add "$path" "$branch"
    elif git ls-remote --heads origin "$branch" | grep -q "$branch"; then
        # Branch exists on remote, track it
        git worktree add "$path" -b "$branch" "origin/$branch"
    else
        # New branch
        git worktree add "$path" -b "$branch"
    fi

    echo "✓ Worktree created successfully"
    echo "  Branch: $branch"
    echo "  Path: $path"

    # Change directory to the new worktree unless --no-cd is specified
    if [[ "$no_cd" == false ]]; then
        echo ""
        echo "Changing directory to: $path"
        cd "$path" || exit 1
        exec "$SHELL"
    fi
}

cmd_list() {
    echo "Git worktrees:"
    echo ""
    git worktree list
}

cmd_remove() {
    local path="${1:-}"

    if [[ -z "$path" ]]; then
        # If no path provided, check if we're in a worktree
        local current_dir
        current_dir=$(pwd)
        local main_worktree
        main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10); exit}')

        if [[ "$current_dir" == "$main_worktree" ]]; then
            echo "Error: Cannot remove main worktree. Specify a path to remove."
            echo "Usage: $(basename "$0") remove <path>"
            exit 1
        fi

        # Check if current directory is a worktree
        if git worktree list --porcelain | grep -q "^worktree ${current_dir}$"; then
            path="$current_dir"
            echo "Removing current worktree: $path"
            echo "Changing directory to main worktree: $main_worktree"
            cd "$main_worktree" || exit 1
            git worktree remove "$path"
            echo "✓ Worktree removed successfully"
            exec "$SHELL"
        else
            echo "Error: Not in a worktree. Specify a path to remove."
            echo "Usage: $(basename "$0") remove <path>"
            exit 1
        fi
    else
        echo "Removing worktree at: $path"
        git worktree remove "$path"
        echo "✓ Worktree removed successfully"
    fi
}

cmd_prune() {
    echo "Pruning stale worktree data..."
    git worktree prune -v
    echo "✓ Prune completed"
}

cmd_goto() {
    local query="${1:-}"

    # Collect all worktrees with their branches and paths
    local -a exact_matches=()
    local -a glob_matches=()
    local -a partial_matches=()
    local -a all_worktrees=()

    local path=""
    local branch=""

    while IFS= read -r line; do
        if [[ "$line" == worktree* ]]; then
            path="${line#worktree }"
        elif [[ "$line" == branch* ]]; then
            branch="${line#branch }"
            branch="${branch#refs/heads/}"
        elif [[ -z "$line" ]] && [[ -n "$path" ]]; then
            # Empty line marks end of worktree entry
            all_worktrees+=("$path|$branch")

            # If query provided, process matches
            if [[ -n "$query" ]]; then
                # Match against branch name and path

                # Exact match
                if [[ "$branch" == "$query" ]] || [[ "$path" == "$query" ]]; then
                    exact_matches+=("$path|$branch")
                else
                    # Glob match (intentionally unquoted for pattern matching)
                    # shellcheck disable=SC2053
                    if [[ "$branch" == $query ]] || [[ "$path" == $query ]]; then
                        glob_matches+=("$path|$branch")
                    # Partial/substring match
                    elif [[ "$branch" == *"$query"* ]] || [[ "$path" == *"$query"* ]]; then
                        partial_matches+=("$path|$branch")
                    fi
                fi
            fi

            # Reset for next worktree
            path=""
            branch=""
        fi
    done < <(git worktree list --porcelain && echo)

    # Combine matches in priority order
    local -a all_matches=()
    if [[ -n "$query" ]]; then
        [[ ${#exact_matches[@]} -gt 0 ]] && all_matches+=("${exact_matches[@]}")
        [[ ${#glob_matches[@]} -gt 0 ]] && all_matches+=("${glob_matches[@]}")
        [[ ${#partial_matches[@]} -gt 0 ]] && all_matches+=("${partial_matches[@]}")
    else
        # No query - show all worktrees
        all_matches=("${all_worktrees[@]}")
    fi

    # Handle match results
    if [[ ${#all_matches[@]} -eq 0 ]]; then
        echo "Error: No worktree found matching '$query'" >&2
        exit 1
    elif [[ ${#all_matches[@]} -eq 1 ]]; then
        # Single match - return the path
        echo "${all_matches[0]%%|*}"
    else
        # Multiple matches or no query - use fzf if available
        if command -v fzf &> /dev/null; then
            local selected
            selected=$(printf "%s\n" "${all_matches[@]}" | awk -F'|' '{printf "%-50s %s\n", $2, $1}' | fzf --prompt="Select worktree: " --height=40% --reverse)

            if [[ -z "$selected" ]]; then
                echo "Error: No worktree selected" >&2
                exit 1
            fi

            # Extract path from selection (it's at the end after spaces)
            echo "$selected" | awk '{print $NF}'
        else
            # No fzf available
            if [[ -z "$query" ]]; then
                echo "Error: fzf is required for interactive selection" >&2
                echo "Usage: $(basename "$0") goto <branch|pattern>" >&2
                echo "Tip: Install fzf for interactive selection without a pattern" >&2
            else
                echo "Error: Multiple worktrees match '$query':" >&2
                echo "" >&2
                for match in "${all_matches[@]}"; do
                    IFS='|' read -r path branch <<< "$match"
                    echo "  $branch -> $path" >&2
                done
                echo "" >&2
                echo "Tip: Install fzf for interactive selection" >&2
            fi
            exit 1
        fi
    fi
}

cmd_cd() {
    local query="${1:-}"

    # Use cmd_goto to find the target path
    local target_path
    target_path=$(cmd_goto "$query")

    if [[ -z "$target_path" ]]; then
        exit 1
    fi

    echo "Changing directory to: $target_path"
    cd "$target_path" || exit 1
    exec "$SHELL"
}

main() {
    check_dependencies

    # Handle help flags at global level
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]] || [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    check_git_repo

    local command="${1:-}"
    shift || true

    case "$command" in
        add|new|create)
            cmd_add "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        remove|rm|del|delete)
            cmd_remove "$@"
            ;;
        prune)
            cmd_prune "$@"
            ;;
        goto)
            cmd_goto "$@"
            ;;
        cd)
            cmd_cd "$@"
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
