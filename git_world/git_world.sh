#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Tidy up a git repository by fetching, pruning remotes, and cleaning up stale
local branches and worktrees.

Performs the following steps in order:
  1. Fetch all remotes
  2. Prune stale remote-tracking references
  3. Delete local branches whose upstream is gone
  4. Clean up stale worktrees (if any exist)

OPTIONS:
    -h, --help    Show this help message and exit

EXAMPLES:
    $cmd              Clean up the current git repository
    $cmd --help       Show this help

EXIT CODES:
    0    Cleanup completed (even if some branches could not be deleted)
    1    Not in a git repository or fatal error
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

main() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: not in a git repository"
        exit 1
    fi

    echo "Fetching all remotes..."
    git fetch --all --prune

    echo "Pruning unreachable objects..."
    git prune

    echo "Deleting local branches with gone upstreams..."
    git branch -vv | awk '/: gone]/{print $1}' | while IFS= read -r branch; do
        git branch -D "$branch" 2>/dev/null && echo "  Deleted branch: $branch" || echo "  Could not delete branch: $branch"
    done

    if git worktree list --porcelain | grep -q '^worktree '; then
        echo "Cleaning up stale worktrees..."
        git wt world 2>/dev/null || true
    fi

    echo "Done."
}

main "$@"
