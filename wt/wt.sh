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
     co <pr-number>          Checkout a PR in a new worktree
                             Aliases: checkout
     list                    List all worktrees
                             Aliases: ls, xl
     remove [path]           Remove worktree (current if no path given)
                             Aliases: rm, del, delete, bd
                             Options: [--force]
     prune                   Remove stale worktree administrative files
     world                   Delete worktrees with merged/deleted remote branches
                             Aliases: cleanup
     goto [pattern]          Print path to worktree (interactive with fzf if no pattern)
     cd [pattern]            Change to worktree directory in new shell
     cd -                    Change to main worktree
     help                    Show this help message
 NOTES:
     - Worktrees are created in .worktrees directory within the repo when no path specified
     - The .worktrees directory is automatically added to .git/info/exclude

 OPTIONS:
     -h, --help              Show this help message and exit
     --no-cd                 Skip changing directory after creating worktree
     --force, -f             Force remove worktree (use with 'remove' command)

PREREQUISITES:
    - Git 2.5+ with worktree support
    - GitHub CLI (gh) for 'co' command only

EXAMPLES:
     $cmd add                              Auto-generate branch name and cd to it
     $cmd add feature-x                    Create worktree in .worktrees/feature-x and cd to it
     $cmd add --no-cd feature-x            Create worktree without changing directory
     $cmd add feature-x ~/work/proj-x      Create worktree in specific path
     $cmd co 42                            Checkout PR #42 in new worktree and cd to it
     $cmd co --no-cd 42                    Checkout PR #42 without changing directory
     $cmd list                             Show all worktrees
     $cmd remove                           Remove current worktree and cd to main
     $cmd remove ../feature-x              Remove specific worktree
     $cmd remove --force ../feature-x      Force remove worktree with unstaged changes
     $cmd prune                            Clean up stale worktree data
     $cmd world                            Clean up worktrees for merged branches
     $cmd cd                               Interactive selection with fzf
     $cmd cd feature-x                     Change to worktree by exact branch name
     $cmd cd feature                       Partial match (uses fzf if multiple)
     $cmd cd '*bug*'                       Glob pattern match
     $cmd cd -                             Change to main worktree
     cd "\$($cmd goto)"                    Interactive selection with fzf (goto variant)
     cd "\$($cmd goto feature-x)"          Change to worktree by exact branch name (goto variant)

NOTES:
    - By default, 'add' and 'co' change directory to the new worktree (use --no-cd to skip)
    - By default, 'remove' without args removes current worktree and cds to main
    - The 'co' command uses 'gh pr checkout' to fetch PRs (works with open and merged PRs)
    - When no branch is given, auto-generates name: username/word1-word2
    - When no path is given, worktrees are created in .worktrees directory within the repo
    - The 'goto' command outputs the path for use with command substitution
    - The 'cd' command spawns a new shell in the worktree directory
    - Use 'cd -' to quickly return to the main worktree from any feature branch
    - Both 'goto' and 'cd' match by branch name or path (exact, glob, or partial)
    - When multiple matches exist, fzf provides interactive selection (if installed)
    - Branch names can be new or existing branches

RELATED PROJECTS:
    - AutoWT: https://steveasleep.com/autowt/

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

add_to_exclude() {
    local repo_root="$1"
    local exclude_file="$repo_root/.git/info/exclude"
    local exclude_pattern=".worktrees"

    # Ensure .git/info directory exists
    mkdir -p "$(dirname "$exclude_file")"

    # Create exclude file if it doesn't exist
    if [[ ! -f "$exclude_file" ]]; then
        cat > "$exclude_file" << 'EOF'
# This file excludes patterns from git
# See also .gitignore
EOF
    fi

    # Add .worktrees to exclude if not already present
    if ! grep -q "^${exclude_pattern}$" "$exclude_file"; then
        echo "$exclude_pattern" >> "$exclude_file"
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

    # If no path specified, create in .worktrees directory in repo root
    if [[ -z "$path" ]]; then
        local repo_root
        repo_root=$(git rev-parse --show-toplevel)
        # Use sanitized branch name for directory (replace / with -)
        local dir_name
        dir_name=$(echo "$branch" | tr '/' '-')
        path="$repo_root/.worktrees/$dir_name"

        # Ensure .worktrees is in .git/info/exclude
        add_to_exclude "$repo_root"
    fi

    echo "Creating worktree for '$branch' at: $path"

    # Check if branch exists remotely or locally
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        # Branch exists, check it out
        git worktree add "$path" "$branch"
    elif git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
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
        exec "$SHELL" -i
    fi
}

cmd_list() {
    echo "Git worktrees:"
    echo ""
    git worktree list
}

cmd_remove() {
    local path=""
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"
                    shift
                else
                    echo "Error: Too many arguments"
                    exit 1
                fi
                ;;
        esac
    done

    if [[ -z "$path" ]]; then
        # If no path provided, check if we're in a worktree
        local current_dir
        current_dir=$(pwd)
        local main_worktree
        main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10); exit}')

        if [[ "$current_dir" == "$main_worktree" ]]; then
            # We're in the main worktree - use fzf to select which worktree to remove
            if command -v fzf &> /dev/null; then
                # Collect non-main worktrees
                local -a worktrees=()
                local wt_path=""
                local branch=""

                while IFS= read -r line; do
                    if [[ "$line" == worktree* ]]; then
                        wt_path="${line#worktree }"
                    elif [[ "$line" == branch* ]]; then
                        branch="${line#branch }"
                        branch="${branch#refs/heads/}"
                    elif [[ -z "$line" ]] && [[ -n "$wt_path" ]] && [[ "$wt_path" != "$main_worktree" ]]; then
                        worktrees+=("$wt_path|$branch")
                        wt_path=""
                        branch=""
                    fi
                done < <(git worktree list --porcelain && echo)

                if [[ ${#worktrees[@]} -eq 0 ]]; then
                    echo "Error: No other worktrees to remove"
                    exit 1
                fi

                # Use fzf to select a worktree
                local selected
                selected=$(printf "%s\n" "${worktrees[@]}" | awk -F'|' '{printf "%-50s %s\n", $2, $1}' | fzf --prompt="Select worktree to remove: " --height=40% --reverse)

                if [[ -z "$selected" ]]; then
                    echo "Aborted"
                    exit 0
                fi

                # Extract path from selection
                path=$(echo "$selected" | awk '{print $NF}')
            else
                echo "Error: Not in a worktree. Specify a path to remove."
                echo "Usage: $(basename "$0") remove [--force] [path]"
                echo "Tip: Install fzf for interactive selection from main worktree"
                exit 1
            fi
        fi

        # Check if current directory is a worktree (or if we selected one via fzf)
        if [[ -z "$path" ]]; then
            if git worktree list --porcelain | grep -q "^worktree ${current_dir}$"; then
                path="$current_dir"
                echo "Removing current worktree: $path"
                echo "Changing directory to main worktree: $main_worktree"
                cd "$main_worktree" || exit 1

                # Get branch name before removing worktree
                local branch
                branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo "")

                if [[ "$force" == true ]]; then
                    git worktree remove --force "$path"
                else
                    git worktree remove "$path"
                fi
                echo "✓ Worktree removed successfully"

                # Delete the branch if it exists and is not the main branch
                if [[ -n "$branch" ]] && git rev-parse --verify "$branch" >/dev/null 2>&1; then
                    main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
                    if [[ "$branch" != "$main_branch" ]]; then
                        git branch -D "$branch" 2>/dev/null || true
                    fi
                fi

                exec "$SHELL" -i
            else
                echo "Error: Not in a worktree. Specify a path to remove."
                echo "Usage: $(basename "$0") remove [--force] [path]"
                exit 1
            fi
        fi
    fi

    # Remove the selected/specified worktree
    if [[ -n "$path" ]]; then
        echo "Removing worktree at: $path"

        # Get branch name before removing worktree
        local branch
        branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo "")

        if [[ "$force" == true ]]; then
            git worktree remove --force "$path"
        else
            git worktree remove "$path"
        fi
        echo "✓ Worktree removed successfully"

        # Delete the branch if it exists and is not the main branch
        if [[ -n "$branch" ]] && git rev-parse --verify "$branch" >/dev/null 2>&1; then
            local main_branch
            main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
            if [[ "$branch" != "$main_branch" ]]; then
                git branch -D "$branch" 2>/dev/null || true
            fi
        fi
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

    local target_path

    # Handle special case: cd - switches to main worktree
    if [[ "$query" == "-" ]]; then
        target_path=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10); exit}')
    else
        # Use cmd_goto to find the target path
        target_path=$(cmd_goto "$query")
    fi

    if [[ -z "$target_path" ]]; then
        exit 1
    fi

    echo "Changing directory to: $target_path"
    cd "$target_path" || exit 1
    exec "$SHELL" -i
}

cmd_co() {
    local pr_number=""
    local no_cd=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cd)
                no_cd=true
                shift
                ;;
            *)
                if [[ -z "$pr_number" ]]; then
                    pr_number="$1"
                    shift
                else
                    echo "Error: Unknown option '$1'"
                    exit 1
                fi
                ;;
        esac
    done

    if [[ -z "$pr_number" ]]; then
        echo "Error: PR number required"
        echo "Usage: $(basename "$0") co [--no-cd] <pr-number>"
        exit 1
    fi

    # Check if gh is available
    if ! command -v gh &> /dev/null; then
        echo "Error: 'gh' (GitHub CLI) is required for this command"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi

    # Fetch PR information to get the branch name
    echo "Fetching PR #${pr_number} information..."
    local pr_branch
    if ! pr_branch=$(gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>&1); then
        echo "Error: Failed to fetch PR information"
        echo "$pr_branch"
        exit 1
    fi

    if [[ -z "$pr_branch" ]]; then
        echo "Error: Could not determine branch name for PR #${pr_number}"
        exit 1
    fi

    echo "PR #${pr_number} branch: $pr_branch"

    # Determine the worktree path
    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    local dir_name
    dir_name=$(echo "$pr_branch" | tr '/' '-')
    local path="$repo_root/.worktrees/$dir_name"

    # Ensure .worktrees is in .git/info/exclude
    add_to_exclude "$repo_root"

    # Check if worktree already exists
    if git worktree list --porcelain | grep -q "^worktree ${path}$"; then
        echo "Worktree already exists at: $path"

        # Change directory if requested
        if [[ "$no_cd" == false ]]; then
            echo "Changing directory to: $path"
            cd "$path" || exit 1
            exec "$SHELL"
        fi
        exit 0
    fi

    echo "Checking out PR #${pr_number} in new worktree..."
    echo "  Branch: $pr_branch"
    echo "  Path: $path"
    echo ""

    # Create worktree directory with detached HEAD
    git worktree add --detach "$path" || {
        echo "Error: Failed to create worktree"
        exit 1
    }

    # Change to the new worktree and use gh pr checkout
    cd "$path" || {
        echo "Error: Failed to change to worktree directory"
        git worktree remove "$path" 2>/dev/null || true
        exit 1
    }

    # Use gh pr checkout to fetch and checkout the PR
    # Use -b flag to ensure consistent branch naming
    if ! gh pr checkout "$pr_number" -b "$pr_branch" 2>/dev/null; then
        # If gh pr checkout fails (e.g., branch was deleted after merge),
        # fall back to fetching the PR ref directly
        echo "Branch no longer exists, fetching PR ref directly..."
        if ! git fetch origin "pull/${pr_number}/head:${pr_branch}"; then
            echo "Error: Failed to fetch PR #${pr_number}"
            cd "$repo_root" || true
            git worktree remove "$path" 2>/dev/null || true
            exit 1
        fi
        git checkout "$pr_branch" || {
            echo "Error: Failed to checkout branch"
            cd "$repo_root" || true
            git worktree remove "$path" 2>/dev/null || true
            exit 1
        }
    fi

    # Return to original directory
    cd "$repo_root" || exit 1

    echo ""
    echo "✓ Worktree created successfully"
    echo "  Branch: $pr_branch"
    echo "  Path: $path"

    # Change directory to the new worktree unless --no-cd is specified
    if [[ "$no_cd" == false ]]; then
        echo ""
        echo "Changing directory to: $path"
        cd "$path" || exit 1
        exec "$SHELL" -i
    fi
}

cmd_world() {
    echo "Cleaning up worktrees and merged branches..."
    echo ""

    # First, fetch all remotes and prune
    echo "Fetching from remotes and pruning..."
    git fetch --all --prune || {
        echo "Error: Failed to fetch from remotes"
        exit 1
    }
    echo ""

    # Get main worktree path
    local main_worktree
    main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10); exit}')

    # Collect worktrees to remove
    local -a worktrees_to_remove=()
    local -a branches_to_delete=()
    local path=""
    local branch=""
    local current_dir
    current_dir=$(pwd)

    while IFS= read -r line; do
         if [[ "$line" == worktree* ]]; then
             # Process previous worktree if it had a branch
             if [[ -n "$path" ]] && [[ -n "$branch" ]] && [[ "$path" != "$main_worktree" ]]; then
                 # Check if upstream tracking branch is gone
                 local upstream
                 upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")

                 # Only check branches that have an upstream configured
                 if [[ -n "$upstream" ]]; then
                     # Check if upstream is gone (branch was merged/deleted remotely)
                     if ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
                         worktrees_to_remove+=("$path|$branch|upstream-gone")
                     fi
                 fi
             fi

             # Reset and start new worktree entry
             path="${line#worktree }"
             branch=""
         elif [[ "$line" == branch* ]]; then
             branch="${line#branch }"
             branch="${branch#refs/heads/}"
         fi
     done < <(git worktree list --porcelain && echo)

    # Find branches to delete (merged, stale, or with gone upstream)
    local main_branch
    main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "master")

    # Protected branches that should never be deleted
    local -a protected_branches=("main" "master")

    while IFS= read -r branch; do
         # Skip the main branch and empty lines
         [[ -z "$branch" ]] && continue
         [[ "$branch" == "$main_branch" ]] && continue
         [[ "$branch" == "HEAD"* ]] && continue

         # Skip protected branches
         local is_protected=false
         for protected in "${protected_branches[@]}"; do
             if [[ "$branch" == "$protected" ]]; then
                 is_protected=true
                 break
             fi
         done
         [[ "$is_protected" == true ]] && continue

         # Skip branches that don't exist (shouldn't happen, but be safe)
         if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
             continue
         fi

         # Check if upstream tracking branch is gone (deleted on remote)
         local upstream
         upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "$branch@{u}" 2>/dev/null || echo "")
         if [[ -n "$upstream" ]] && ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
             branches_to_delete+=("$branch|upstream-gone")
             continue
         fi

         # Check if corresponding remote branch exists (origin/<branch>)
         # This handles branches that don't have explicit upstream set
         if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
             # Remote branch doesn't exist - check if upstream is a remote
             if [[ -z "$upstream" ]] || [[ "$upstream" != "origin/"* ]]; then
                 # Not tracking a remote - only delete if it has no unique work
                 local commits_ahead
                 commits_ahead=$(git rev-list --count "$main_branch..$branch" 2>/dev/null || echo "0")
                 if [[ "$commits_ahead" -eq 0 ]]; then
                     # No unique commits, safe to delete
                     branches_to_delete+=("$branch|no-remote")
                     continue
                 fi
             fi
         fi

         # Check if branch is merged into main branch AND behind main branch
         # A merged branch should be an ancestor of main AND have commits behind it
         if git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
             # Verify branch has no commits ahead of main
             local commits_ahead
             commits_ahead=$(git rev-list --count "$main_branch..$branch" 2>/dev/null || echo "1")
             # And verify main has commits ahead of branch (not a fresh branch at same commit)
             local commits_behind
             commits_behind=$(git rev-list --count "$branch..$main_branch" 2>/dev/null || echo "0")

             if [[ "$commits_ahead" -eq 0 ]] && [[ "$commits_behind" -gt 0 ]]; then
                 branches_to_delete+=("$branch|merged")
             fi
         fi
     done < <(git branch --format='%(refname:short)')

    # Combine removals
    local total_removals=$((${#worktrees_to_remove[@]} + ${#branches_to_delete[@]}))

    if [[ $total_removals -eq 0 ]]; then
        echo "✓ No worktrees or merged branches to remove"
        exit 0
    fi

    echo "Found $total_removals item(s) to remove:"
    echo ""

    local need_cd=false
    for entry in "${worktrees_to_remove[@]:-}"; do
        IFS='|' read -r wt_path wt_branch reason <<< "$entry"
        [[ -z "$wt_path" ]] && continue
        echo "  - Worktree: $wt_branch ($reason)"

        # Check if we're currently in this worktree
        if [[ "$current_dir" == "$wt_path"* ]]; then
            need_cd=true
        fi
    done

    for entry in "${branches_to_delete[@]}"; do
        IFS='|' read -r branch reason <<< "$entry"
        case "$reason" in
            upstream-gone) echo "  - Branch: $branch (upstream deleted)" ;;
            no-remote) echo "  - Branch: $branch (no remote branch)" ;;
            merged) echo "  - Branch: $branch (merged into $main_branch)" ;;
            *) echo "  - Branch: $branch" ;;
        esac
    done

    echo ""

    # Check if we're in interactive mode (stdin and stderr are both TTYs)
    local should_proceed=false
    if [[ -t 0 ]] && [[ -t 2 ]]; then
        read -p "Remove these items? [y/N] " -n 1 -r -t 30 || {
            echo ""
            echo "Aborted (timeout)"
            exit 0
        }
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            should_proceed=true
        else
            echo "Aborted"
            exit 0
        fi
    else
        # Non-interactive context - skip deletion but continue gracefully
        echo "Skipping cleanup (running in non-interactive mode)"
    fi

    # If we're in a worktree that will be removed, cd to main first
    if [[ "$should_proceed" == true ]] && [[ "$need_cd" == true ]]; then
        echo ""
        echo "Current directory is in a worktree to be removed"
        echo "Changing to main worktree: $main_worktree"
        cd "$main_worktree" || exit 1
    fi

    # Only perform deletions if in interactive mode
    if [[ "$should_proceed" == true ]]; then
        echo ""

        # Remove worktrees
        for entry in "${worktrees_to_remove[@]:-}"; do
            IFS='|' read -r wt_path wt_branch _ <<< "$entry"
            [[ -z "$wt_path" ]] && continue
            echo "Removing worktree: $wt_branch"
            git worktree remove "$wt_path" 2>/dev/null || git worktree remove --force "$wt_path"
        done

        # Delete branches
        for entry in "${branches_to_delete[@]}"; do
            IFS='|' read -r branch reason <<< "$entry"
            echo "Deleting branch: $branch ($reason)"
            # Use -D to force delete for stale branches
            if [[ "$reason" == "no-remote" || "$reason" == "upstream-gone" ]]; then
                git branch -D "$branch" 2>/dev/null || true
            else
                git branch -d "$branch"
            fi
        done

        echo ""
        echo "✓ Cleanup complete"
    fi

    # If we changed directory, exec new shell
    if [[ "$need_cd" == true ]]; then
        exec "$SHELL" -i
    fi
}

main() {
    check_dependencies

    # Handle help flags at global level
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
        usage
        exit 0
    fi

    check_git_repo

    local command="${1:-add}"
    shift || true

    case "$command" in
        add|new|create)
            cmd_add "$@"
            ;;
        co|checkout)
            cmd_co "$@"
            ;;
        list|ls|xl)
            cmd_list "$@"
            ;;
        remove|rm|del|delete|bd)
            cmd_remove "$@"
            ;;
        prune)
            cmd_prune "$@"
            ;;
        world|cleanup)
            cmd_world "$@"
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
