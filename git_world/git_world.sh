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

setup_colors() {
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        bold=$(tput bold 2>/dev/null) || bold=""
        green=$(tput setaf 2 2>/dev/null) || green=""
        red=$(tput setaf 1 2>/dev/null) || red=""
        cyan=$(tput setaf 6 2>/dev/null) || cyan=""
        reset=$(tput sgr0 2>/dev/null) || reset=""
    else
        bold="" green="" red="" cyan="" reset=""
    fi
}

main() {
    setup_colors

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "${red}Error: not in a git repository${reset}"
        exit 1
    fi

    echo "${bold}${cyan}Fetching all remotes...${reset}"
    git fetch --all --prune

    echo "${bold}${cyan}Pruning unreachable objects...${reset}"
    git prune

    echo "${bold}${cyan}Deleting local branches with gone upstreams...${reset}"
    git branch -vv | awk '/: gone]/{print $1}' | while IFS= read -r branch; do
        if git branch -D "$branch" 2>/dev/null; then
            echo "  ${green}✓ Deleted branch: $branch${reset}"
        else
            echo "  ${red}✗ Could not delete branch: $branch${reset}"
        fi
    done

    if git worktree list --porcelain | grep -q '^worktree '; then
        echo "${bold}${cyan}Cleaning up stale worktrees...${reset}"
        git wt world 2>/dev/null || true
    fi

    echo "${bold}${green}Done.${reset}"
}

main "$@"
