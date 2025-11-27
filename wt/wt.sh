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
    list                    List all worktrees
    remove <path>           Remove worktree at path
    prune                   Remove stale worktree administrative files
    goto <branch>           Print path to worktree for branch (useful for cd)
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
    $cmd remove ../feature-x              Remove worktree
    $cmd prune                            Clean up stale worktree data
    cd "\$($cmd goto feature-x)"          Change to worktree directory

NOTES:
    - By default, 'add' changes directory to the new worktree (use --no-cd to skip)
    - When no branch is given, auto-generates name: username/word1-word2
    - When no path is given, worktrees are created as siblings to the main repo
    - The 'goto' command returns the absolute path to help with shell navigation
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
        echo "Error: Path required"
        echo "Usage: $(basename "$0") remove <path>"
        exit 1
    fi

    echo "Removing worktree at: $path"
    git worktree remove "$path"
    echo "✓ Worktree removed successfully"
}

cmd_prune() {
    echo "Pruning stale worktree data..."
    git worktree prune -v
    echo "✓ Prune completed"
}

cmd_goto() {
    local branch="${1:-}"

    if [[ -z "$branch" ]]; then
        echo "Error: Branch name required" >&2
        echo "Usage: $(basename "$0") goto <branch>" >&2
        exit 1
    fi

    # Parse worktree list to find matching branch
    local worktree_path
    worktree_path=$(git worktree list --porcelain | awk -v branch="$branch" '
        /^worktree / { path = substr($0, 10) }
        /^branch / {
            current_branch = substr($0, 8)
            gsub(/^refs\/heads\//, "", current_branch)
            if (current_branch == branch) {
                print path
                exit
            }
        }
    ')

    if [[ -z "$worktree_path" ]]; then
        echo "Error: No worktree found for branch '$branch'" >&2
        exit 1
    fi

    echo "$worktree_path"
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
        add)
            cmd_add "$@"
            ;;
        list)
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
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
