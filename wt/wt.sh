#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [COMMAND] [OPTIONS]

Manage git worktrees with ease.

When invoked without arguments, launches interactive TUI (requires gum).

COMMANDS:
     tui                     Launch interactive TUI dashboard
     add [branch] [path]     Create new worktree from default branch (auto-generates branch if omitted)
                             Aliases: new, create
                             Options: [--current-branch|-c] to start from current branch instead
     co <pr-number>          Checkout a PR in a new worktree
                              Aliases: checkout, pr co, pr checkout
     list                    List all worktrees
                             Aliases: ls, xl
     remove [path|branch]    Remove worktree by path or branch name (current if omitted)
                             Aliases: rm, del, delete, bd
                             Options: [--force]
     move [worktree] [dest]  Move worktree to new location (interactive if omitted)
                             Aliases: mv
                             Options: [--no-cd]
                             For main worktree: extracts branch to new worktree
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
     --no-cd                 Stay in current directory after creating worktree (use with 'add' command)
     --current-branch, -c    Start new worktree from current branch instead of default (use with 'add' command)
     --force, -f             Force remove worktree (use with 'remove' command)

PREREQUISITES:
    - Git 2.5+ with worktree support
    - gum (https://github.com/charmbracelet/gum) for TUI mode
    - GitHub CLI (gh) for 'co' command only

ENVIRONMENT:
    WT_NO_TUI=1              Disable automatic TUI launch (show help instead)

EXAMPLES:
     $cmd                                 Launch interactive TUI (if gum installed)
     $cmd tui                             Explicitly launch TUI
     $cmd add                              Auto-generate branch name and cd to it
     $cmd add --no-cd                      Auto-generate branch name, stay in current directory
     $cmd add --current-branch feature-x    Create worktree starting from current branch
     $cmd add feature-x                    Create worktree in .worktrees/feature-x and cd to it
     $cmd add --no-cd feature-x            Create worktree in .worktrees/feature-x, stay in current directory
     $cmd add feature-x ~/work/proj-x      Create worktree in specific path and cd to it
     $cmd co 42                            Checkout PR #42 in new worktree and cd to it
     $cmd co --no-cd 42                    Checkout PR #42 without changing directory
     $cmd pr co 42                         Same as 'co 42' (matches gh CLI interface)
     $cmd list                             Show all worktrees
     $cmd remove                           Remove current worktree and cd to main
     $cmd remove feature-x                 Remove worktree by branch name
     $cmd remove ../feature-x              Remove worktree by path
     $cmd remove --force feature-x         Force remove worktree with unstaged changes
     $cmd prune                            Clean up stale worktree data
     $cmd world                            Clean up worktrees for merged branches
     $cmd move                             Interactive selection with fzf
     $cmd move feature-x                   Move worktree to auto-generated path
     $cmd move feature-x ~/work/new-loc    Move worktree to specific path
     $cmd move --no-cd feature-x           Move without changing directory
     $cmd cd                               Interactive selection with fzf
     $cmd cd feature-x                     Change to worktree by exact branch name
     $cmd cd feature                       Partial match (uses fzf if multiple)
     $cmd cd '*bug*'                       Glob pattern match
     $cmd cd -                             Change to main worktree
     cd "\$($cmd goto)"                    Interactive selection with fzf (goto variant)
     cd "\$($cmd goto feature-x)"          Change to worktree by exact branch name (goto variant)

NOTES:
    - By default, 'add' creates new branches from the default branch (main/master)
    - Use --current-branch to start from the current branch instead
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

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        exit 1
    fi
}

get_repo_root() {
    git rev-parse --show-toplevel
}

get_main_worktree() {
    git worktree list --porcelain | awk '/^worktree / {print substr($0, 10); exit}'
}

add_to_exclude() {
    local repo_root="$1"
    local exclude_file="$repo_root/.git/info/exclude"
    local exclude_pattern=".worktrees"

    mkdir -p "$(dirname "$exclude_file")"

    if [[ ! -f "$exclude_file" ]]; then
        cat > "$exclude_file" << 'EOF'
# This file excludes patterns from git
# See also .gitignore
EOF
    fi

    if ! grep -q "^${exclude_pattern}$" "$exclude_file"; then
        echo "$exclude_pattern" >> "$exclude_file"
    fi
}

generate_branch_name() {
    local username=""

    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$remote_url" == *"github.com"* ]] && command -v gh &>/dev/null; then
        username=$(gh api user --jq '.login' 2>/dev/null || echo "")
    fi

    if [[ -z "$username" ]]; then
        username=$(git config user.name | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    fi

    if [[ -z "$username" ]]; then
        username=$(whoami)
    fi

    local word1 word2
    if [[ -f /usr/share/dict/words ]]; then
        word1=$(grep -E '^[a-z]{4,8}$' /usr/share/dict/words | shuf -n 1)
        word2=$(grep -E '^[a-z]{4,8}$' /usr/share/dict/words | shuf -n 1)
    else
        word1=$(openssl rand -hex 3)
        word2=$(openssl rand -hex 3)
    fi

    echo "${username}/${word1}-${word2}"
}

get_default_branch() {
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    if [[ -z "$default_branch" ]]; then
        if git rev-parse --verify origin/main >/dev/null 2>&1; then
            default_branch="main"
        elif git rev-parse --verify origin/master >/dev/null 2>&1; then
            default_branch="master"
        else
            default_branch=$(git branch --show-current)
        fi
    fi

    echo "$default_branch"
}

# =============================================================================
# CLI COMMANDS
# =============================================================================

cmd_add() {
    local branch=""
    local path=""
    local do_cd=true
    local from_current=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cd)
                do_cd=false
                shift
                ;;
            --current-branch|-c)
                from_current=true
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

    if [[ -z "$branch" ]]; then
        branch=$(generate_branch_name)
        echo "Auto-generated branch name: $branch"
    fi

    if [[ -z "$path" ]]; then
        local repo_root
        repo_root=$(git rev-parse --show-toplevel)
        local dir_name
        dir_name=$(echo "$branch" | tr '/' '-')
        path="$repo_root/.worktrees/$dir_name"

        add_to_exclude "$repo_root"
    fi

    local base_branch
    if [[ "$from_current" == true ]]; then
        base_branch=$(git branch --show-current)
        echo "Starting from current branch: $base_branch"
    else
        base_branch=$(get_default_branch)
        echo "Starting from default branch: $base_branch"
    fi

    echo "Creating worktree for '$branch' at: $path"

    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        git worktree add "$path" "$branch"
    elif git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "refs/heads/$branch$"; then
        git worktree add "$path" -b "$branch" "origin/$branch"
    else
        git worktree add "$path" -b "$branch" "$base_branch"
    fi

    echo "✓ Worktree created successfully"
    echo "  Branch: $branch"
    echo ""
    echo -e "\033[1;36m→ $path\033[0m"

    if [[ "$do_cd" == true ]]; then
        echo ""
        echo "Changing directory to: $path"
        cd "$path" || exit 1
        exec "$SHELL"
    fi
}

cmd_list() {
    echo "Git worktrees:"
    echo ""

    local main_worktree
    main_worktree=$(get_main_worktree)

    git worktree list | while IFS= read -r line; do
        local path
        path=$(echo "$line" | awk '{print $1}')

        if [[ "$path" == "$main_worktree/.worktrees/"* ]]; then
            local repo_label="[repo]"
            if [[ -t 1 ]]; then
                repo_label=$'\033[36m[repo]\033[0m'
            fi
            local short_path
            short_path="${repo_label}/.worktrees/$(basename "$path")"
            echo "${line/$path/$short_path}"
        else
            echo "$line"
        fi
    done
}

cmd_remove() {
    local path=""
    local force=false

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
        local current_dir
        current_dir=$(pwd)
        local main_worktree
        main_worktree=$(get_main_worktree)

        if [[ "$current_dir" == "$main_worktree" ]]; then
            if command -v fzf &> /dev/null; then
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

                local selected
                selected=$(printf "%s\n" "${worktrees[@]}" | awk -F'|' '{printf "%-50s %s\n", $2, $1}' | fzf --prompt="Select worktree to remove: " --height=40% --reverse)

                if [[ -z "$selected" ]]; then
                    echo "Aborted"
                    exit 0
                fi

                path=$(echo "$selected" | awk '{print $NF}')
            else
                echo "Error: Not in a worktree. Specify a path to remove."
                echo "Usage: $(basename "$0") remove [--force] [path]"
                echo "Tip: Install fzf for interactive selection from main worktree"
                exit 1
            fi
        fi

        if [[ -z "$path" ]]; then
            local worktree_root
            worktree_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

            if [[ -n "$worktree_root" ]] && git worktree list --porcelain | grep -q "^worktree ${worktree_root}$"; then
                path="$worktree_root"
                echo "Removing current worktree: $path"
                echo "Changing directory to main worktree: $main_worktree"
                cd "$main_worktree" || exit 1

                local branch
                branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo "")

                if [[ "$force" == true ]]; then
                    git worktree remove --force "$path"
                else
                    git worktree remove "$path"
                fi
                echo "✓ Worktree removed successfully"

                if [[ -n "$branch" ]] && git rev-parse --verify "$branch" >/dev/null 2>&1; then
                    main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
                    if [[ "$branch" != "$main_branch" ]]; then
                        git branch -D "$branch" 2>/dev/null || true
                    fi
                fi

                exec "$SHELL"
            else
                echo "Error: Not in a worktree. Specify a path to remove."
                echo "Usage: $(basename "$0") remove [--force] [path]"
                exit 1
            fi
        fi
    fi

    if [[ -n "$path" ]]; then
        if [[ ! -d "$path" ]]; then
            local resolved_path=""
            local wt_path=""
            local wt_branch=""

            while IFS= read -r line; do
                if [[ "$line" == worktree* ]]; then
                    wt_path="${line#worktree }"
                elif [[ "$line" == branch* ]]; then
                    wt_branch="${line#branch }"
                    wt_branch="${wt_branch#refs/heads/}"
                elif [[ -z "$line" ]] && [[ -n "$wt_path" ]]; then
                    if [[ "$wt_branch" == "$path" ]]; then
                        resolved_path="$wt_path"
                        break
                    fi
                    wt_path=""
                    wt_branch=""
                fi
            done < <(git worktree list --porcelain && echo)

            if [[ -n "$resolved_path" ]]; then
                echo "Resolved branch '$path' to worktree: $resolved_path"
                path="$resolved_path"
            fi
        fi

        echo "Removing worktree at: $path"

        local branch
        branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo "")

        if [[ "$force" == true ]]; then
            git worktree remove --force "$path"
        else
            git worktree remove "$path"
        fi
        echo "✓ Worktree removed successfully"

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

cmd_move() {
    local worktree=""
    local dest=""
    local do_cd=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cd)
                do_cd=false
                shift
                ;;
            *)
                if [[ -z "$worktree" ]]; then
                    worktree="$1"
                elif [[ -z "$dest" ]]; then
                    dest="$1"
                else
                    echo "Error: Too many arguments"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    local main_worktree
    main_worktree=$(get_main_worktree)

    local repo_root
    repo_root=$(get_repo_root)

    if [[ -z "$worktree" ]]; then
        if ! command -v fzf &> /dev/null; then
            echo "Error: fzf is required for interactive selection"
            echo "Usage: $(basename "$0") move [--no-cd] <worktree> [dest]"
            exit 1
        fi

        local -a worktrees=()
        local wt_path=""
        local branch=""

        while IFS= read -r line; do
            if [[ "$line" == worktree* ]]; then
                wt_path="${line#worktree }"
            elif [[ "$line" == branch* ]]; then
                branch="${line#branch }"
                branch="${branch#refs/heads/}"
            elif [[ -z "$line" ]] && [[ -n "$wt_path" ]]; then
                if [[ "$wt_path" == "$main_worktree" ]]; then
                    worktrees+=("$wt_path|$branch|(main)")
                else
                    worktrees+=("$wt_path|$branch")
                fi
                wt_path=""
                branch=""
            fi
        done < <(git worktree list --porcelain && echo)

        if [[ ${#worktrees[@]} -eq 0 ]]; then
            echo "Error: No worktrees found"
            exit 1
        fi

        local selected
        selected=$(printf "%s\n" "${worktrees[@]}" | awk -F'|' '{if (NF==3) printf "%-50s %s %s\n", $2, $1, $3; else printf "%-50s %s\n", $2, $1}' | fzf --prompt="Select worktree to move: " --height=40% --reverse)

        if [[ -z "$selected" ]]; then
            echo "Aborted"
            exit 0
        fi

        worktree=$(echo "$selected" | awk '{print $2}')
    fi

    local worktree_path="$worktree"
    local worktree_branch=""

    if [[ ! -d "$worktree" ]]; then
        local wt_path=""
        local wt_branch=""

        while IFS= read -r line; do
            if [[ "$line" == worktree* ]]; then
                wt_path="${line#worktree }"
            elif [[ "$line" == branch* ]]; then
                wt_branch="${line#branch }"
                wt_branch="${wt_branch#refs/heads/}"
            elif [[ -z "$line" ]] && [[ -n "$wt_path" ]]; then
                if [[ "$wt_branch" == "$worktree" ]]; then
                    worktree_path="$wt_path"
                    worktree_branch="$wt_branch"
                    break
                fi
                wt_path=""
                wt_branch=""
            fi
        done < <(git worktree list --porcelain && echo)

        if [[ -z "$worktree_branch" ]]; then
            echo "Error: No worktree found for '$worktree'"
            exit 1
        fi
    else
        worktree_branch=$(git -C "$worktree_path" symbolic-ref --short HEAD 2>/dev/null || echo "")
    fi

    if [[ "$worktree_path" == "$main_worktree" ]]; then
        local default_branch
        default_branch=$(get_default_branch)

        if [[ "$worktree_branch" == "$default_branch" ]]; then
            echo "Error: Main worktree is already on default branch ($default_branch)"
            echo "Nothing to extract"
            exit 1
        fi

        echo "Extracting branch from main worktree: $worktree_branch"
        echo "Main worktree will switch to: $default_branch"

        if [[ -z "$dest" ]]; then
            dest="$repo_root/.worktrees/$(echo "$worktree_branch" | tr '/' '-')"
            echo "Auto-generated destination: $dest"
        fi

        dest="${dest/#\~/$HOME}"

        if [[ "$dest" != /* ]]; then
            dest="$repo_root/$dest"
        fi

        echo "New path: $dest"

        mkdir -p "$(dirname "$dest")"

        if [[ "$dest" == "$repo_root/.worktrees/"* ]]; then
            add_to_exclude "$repo_root"
        fi

        echo "Switching main worktree to $default_branch..."
        git -C "$main_worktree" checkout "$default_branch"

        echo "Creating new worktree..."
        git worktree add "$dest" "$worktree_branch"

        echo ""
        echo "✓ Extracted branch: $worktree_branch"
        echo "  New worktree: $dest"
        echo "  Main worktree now on: $default_branch"

        if [[ "$do_cd" == true ]]; then
            echo ""
            echo "Changing directory to: $dest"
            cd "$dest" || exit 1
            exec "$SHELL"
        fi
        exit 0
    fi

    echo "Moving worktree: $worktree_branch"
    echo "Current path: $worktree_path"

    if [[ -z "$dest" ]]; then
        local auto_name
        auto_name=$(generate_branch_name)
        dest="$repo_root/.worktrees/$(echo "$auto_name" | tr '/' '-')"
        echo "Auto-generated destination: $dest"
    fi

    dest="${dest/#\~/$HOME}"

    if [[ "$dest" != /* ]]; then
        dest="$repo_root/$dest"
    fi

    if [[ "$dest" == "$worktree_path" ]]; then
        echo "Error: Source and destination are the same"
        exit 1
    fi

    echo "New path: $dest"

    mkdir -p "$(dirname "$dest")"

    if [[ "$dest" == "$repo_root/.worktrees/"* ]]; then
        add_to_exclude "$repo_root"
    fi

    git worktree move "$worktree_path" "$dest"

    echo ""
    echo "✓ Moved worktree: $worktree_branch"
    echo "  From: $worktree_path"
    echo "  To:   $dest"

    if [[ "$do_cd" == true ]]; then
        echo ""
        echo "Changing directory to: $dest"
        cd "$dest" || exit 1
        exec "$SHELL"
    fi
}

cmd_goto() {
    local query="${1:-}"

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
            all_worktrees+=("$path|$branch")

            if [[ -n "$query" ]]; then
                if [[ "$branch" == "$query" ]] || [[ "$path" == "$query" ]]; then
                    exact_matches+=("$path|$branch")
                else
                    # shellcheck disable=SC2053
                    if [[ "$branch" == $query ]] || [[ "$path" == $query ]]; then
                        glob_matches+=("$path|$branch")
                    elif [[ "$branch" == *"$query"* ]] || [[ "$path" == *"$query"* ]]; then
                        partial_matches+=("$path|$branch")
                    fi
                fi
            fi

            path=""
            branch=""
        fi
    done < <(git worktree list --porcelain && echo)

    local -a all_matches=()
    if [[ -n "$query" ]]; then
        [[ ${#exact_matches[@]} -gt 0 ]] && all_matches+=("${exact_matches[@]}")
        [[ ${#glob_matches[@]} -gt 0 ]] && all_matches+=("${glob_matches[@]}")
        [[ ${#partial_matches[@]} -gt 0 ]] && all_matches+=("${partial_matches[@]}")
    else
        all_matches=("${all_worktrees[@]}")
    fi

    if [[ ${#all_matches[@]} -eq 0 ]]; then
        echo "Error: No worktree found matching '$query'" >&2
        exit 1
    elif [[ ${#all_matches[@]} -eq 1 ]]; then
        echo "${all_matches[0]%%|*}"
    else
        if command -v fzf &> /dev/null; then
            local selected
            selected=$(printf "%s\n" "${all_matches[@]}" | awk -F'|' '{printf "%-50s %s\n", $2, $1}' | fzf --prompt="Select worktree: " --height=40% --reverse)

            if [[ -z "$selected" ]]; then
                echo "Error: No worktree selected" >&2
                exit 1
            fi

            echo "$selected" | awk '{print $NF}'
        else
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

    if [[ "$query" == "-" ]]; then
        target_path=$(get_main_worktree)
    else
        target_path=$(cmd_goto "$query")
    fi

    if [[ -z "$target_path" ]]; then
        exit 1
    fi

    echo "Changing directory to: $target_path"
    cd "$target_path" || exit 1
    exec "$SHELL"
}

cmd_co() {
    local pr_number=""
    local no_cd=false

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

    if ! command -v gh &> /dev/null; then
        echo "Error: 'gh' (GitHub CLI) is required for this command"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi

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

    local repo_root
    repo_root=$(get_repo_root)
    local dir_name
    dir_name=$(echo "$pr_branch" | tr '/' '-')
    local path="$repo_root/.worktrees/$dir_name"

    add_to_exclude "$repo_root"

    if git worktree list --porcelain | grep -q "^worktree ${path}$"; then
        echo "Worktree already exists at: $path"

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

    git worktree add --detach "$path" || {
        echo "Error: Failed to create worktree"
        exit 1
    }

    cd "$path" || {
        echo "Error: Failed to change to worktree directory"
        git worktree remove "$path" 2>/dev/null || true
        exit 1
    }

    if ! gh pr checkout "$pr_number" -b "$pr_branch" 2>/dev/null; then
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

    cd "$repo_root" || exit 1

    echo ""
    echo "✓ Worktree created successfully"
    echo "  Branch: $pr_branch"
    echo "  Path: $path"

    if [[ "$no_cd" == false ]]; then
        echo ""
        echo "Changing directory to: $path"
        cd "$path" || exit 1
        exec "$SHELL"
    fi
}

cmd_world() {
    echo "Cleaning up worktrees and merged branches..."
    echo ""

    echo "Fetching from remotes and pruning..."
    git fetch --all --prune || {
        echo "Error: Failed to fetch from remotes"
        exit 1
    }
    echo ""

    local main_worktree
    main_worktree=$(get_main_worktree)

    local -a worktrees_to_remove=()
    local -a branches_to_delete=()
    local path=""
    local branch=""
    local current_dir
    current_dir=$(pwd)

    while IFS= read -r line; do
         if [[ "$line" == worktree* ]]; then
             if [[ -n "$path" ]] && [[ -n "$branch" ]] && [[ "$path" != "$main_worktree" ]]; then
                 local upstream
                 upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")

                 if [[ -n "$upstream" ]]; then
                     if ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
                         worktrees_to_remove+=("$path|$branch|upstream-gone")
                     fi
                 fi
             fi

             path="${line#worktree }"
             branch=""
         elif [[ "$line" == branch* ]]; then
             branch="${line#branch }"
             branch="${branch#refs/heads/}"
         fi
     done < <(git worktree list --porcelain && echo)

    local main_branch
    main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "master")

    local -a protected_branches=("main" "master")

    while IFS= read -r branch; do
         [[ -z "$branch" ]] && continue
         [[ "$branch" == "$main_branch" ]] && continue
         [[ "$branch" == "HEAD"* ]] && continue

         local is_protected=false
         for protected in "${protected_branches[@]}"; do
             if [[ "$branch" == "$protected" ]]; then
                 is_protected=true
                 break
             fi
         done
         [[ "$is_protected" == true ]] && continue

         if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
             continue
         fi

         local upstream
         upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "$branch@{u}" 2>/dev/null || echo "")
         if [[ -n "$upstream" ]] && ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
             branches_to_delete+=("$branch|upstream-gone")
             continue
         fi

         if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
             if [[ -z "$upstream" ]] || [[ "$upstream" != "origin/"* ]]; then
                 local commits_ahead
                 commits_ahead=$(git rev-list --count "$main_branch..$branch" 2>/dev/null || echo "0")
                 if [[ "$commits_ahead" -eq 0 ]]; then
                     branches_to_delete+=("$branch|no-remote")
                     continue
                 fi
             fi
         fi

         if git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
             local commits_ahead
             commits_ahead=$(git rev-list --count "$main_branch..$branch" 2>/dev/null || echo "1")
             local commits_behind
             commits_behind=$(git rev-list --count "$branch..$main_branch" 2>/dev/null || echo "0")

             if [[ "$commits_ahead" -eq 0 ]] && [[ "$commits_behind" -gt 0 ]]; then
                 branches_to_delete+=("$branch|merged")
             fi
         fi
     done < <(git branch --format='%(refname:short)')

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
        echo "Skipping cleanup (running in non-interactive mode)"
    fi

    if [[ "$should_proceed" == true ]] && [[ "$need_cd" == true ]]; then
        echo ""
        echo "Current directory is in a worktree to be removed"
        echo "Changing to main worktree: $main_worktree"
        cd "$main_worktree" || exit 1
    fi

    if [[ "$should_proceed" == true ]]; then
        echo ""

        for entry in "${worktrees_to_remove[@]:-}"; do
            IFS='|' read -r wt_path wt_branch _ <<< "$entry"
            [[ -z "$wt_path" ]] && continue
            echo "Removing worktree: $wt_branch"
            git worktree remove "$wt_path" 2>/dev/null || git worktree remove --force "$wt_path"
        done

        for entry in "${branches_to_delete[@]}"; do
            IFS='|' read -r branch reason <<< "$entry"
            echo "Deleting branch: $branch ($reason)"
            if [[ "$reason" == "no-remote" || "$reason" == "upstream-gone" ]]; then
                git branch -D "$branch" 2>/dev/null || true
            else
                git branch -d "$branch"
            fi
        done

        echo ""
        echo "✓ Cleanup complete"
    fi

    if [[ "$need_cd" == true ]]; then
        exec "$SHELL"
    fi
}

# =============================================================================
# TUI FUNCTIONS
# =============================================================================

clear_input_buffer() {
    while read -t 0 -n 1 2>/dev/null; do :; done
}

get_worktree_status() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        echo "missing"
        return
    fi

    local git_dir
    git_dir=$(git -C "$path" rev-parse --git-dir 2>/dev/null)

    if [[ -f "$git_dir/MERGE_HEAD" ]]; then
        echo "merging"
        return
    fi

    if [[ -d "$git_dir/rebase-merge" ]] || [[ -d "$git_dir/rebase-apply" ]]; then
        echo "rebasing"
        return
    fi

    if [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
        echo "cherry-picking"
        return
    fi

    if [[ -f "$git_dir/REVERT_HEAD" ]]; then
        echo "reverting"
        return
    fi

    if [[ -f "$git_dir/BISECT_LOG" ]]; then
        echo "bisecting"
        return
    fi

    local changes
    changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$changes" -gt 0 ]]; then
        echo "$changes changes"
    else
        echo "clean"
    fi
}

get_worktree_ahead_behind() {
    local path="$1"
    local branch="$2"

    if [[ -z "$branch" ]] || [[ ! -d "$path" ]]; then
        echo ""
        return
    fi

    local upstream
    upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")

    if [[ -z "$upstream" ]]; then
        echo ""
        return
    fi

    local ahead behind
    ahead=$(git -C "$path" rev-list --count "@{u}..HEAD" 2>/dev/null || echo "0")
    behind=$(git -C "$path" rev-list --count "HEAD..@{u}" 2>/dev/null || echo "0")

    if [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
        echo "↑$ahead ↓$behind"
    elif [[ "$ahead" -gt 0 ]]; then
        echo "↑$ahead"
    elif [[ "$behind" -gt 0 ]]; then
        echo "↓$behind"
    else
        echo "synced"
    fi
}

collect_worktrees() {
    local -n result=$1
    local path="" branch="" is_bare=""

    while IFS= read -r line; do
        if [[ "$line" == worktree* ]]; then
            path="${line#worktree }"
        elif [[ "$line" == branch* ]]; then
            branch="${line#branch }"
            branch="${branch#refs/heads/}"
        elif [[ "$line" == "bare" ]]; then
            is_bare="true"
        elif [[ -z "$line" ]] && [[ -n "$path" ]]; then
            if [[ "$is_bare" != "true" ]]; then
                result+=("$path|$branch")
            fi
            path=""
            branch=""
            is_bare=""
        fi
    done < <(git worktree list --porcelain && echo)
}

show_dashboard() {
    local current_worktree="$1"
    local -a worktrees=()
    collect_worktrees worktrees

    if [[ ${#worktrees[@]} -eq 0 ]]; then
        gum style --foreground 208 "No worktrees found."
        return
    fi

    local main_worktree
    main_worktree=$(get_main_worktree)

    gum style --bold --foreground 212 "Git Worktrees"
    echo ""

    local max_branch_len=0
    local max_path_len=0
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"
        [[ ${#branch} -gt $max_branch_len ]] && max_branch_len=${#branch}

        local display_path="$path"
        if [[ "$path" == "$main_worktree/.worktrees/"* ]]; then
            display_path="[repo]/.worktrees/$(basename "$path")"
        elif [[ "$path" == "$main_worktree" ]]; then
            display_path="[repo] (main)"
        fi
        [[ ${#display_path} -gt $max_path_len ]] && max_path_len=${#display_path}
    done

    printf "  %-${max_branch_len}s  %-${max_path_len}s  %-15s  %s\n" "BRANCH" "PATH" "STATUS" "SYNC"
    echo ""

    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"

        local display_path="$path"
        if [[ "$path" == "$main_worktree/.worktrees/"* ]]; then
            display_path="[repo]/.worktrees/$(basename "$path")"
        elif [[ "$path" == "$main_worktree" ]]; then
            display_path="[repo] (main)"
        fi

        local status
        status=$(get_worktree_status "$path")
        local sync
        sync=$(get_worktree_ahead_behind "$path" "$branch")

        local marker=" "
        if [[ "$path" == "$current_worktree" ]]; then
            marker="→"
        fi

        printf "%s %-${max_branch_len}s  %-${max_path_len}s  %-15s  %s\n" \
            "$marker" "$branch" "$display_path" "$status" "$sync"
    done
}

tui_action_new_worktree() {
    gum style --bold --foreground 212 "New Worktree"
    echo ""

    local source
    source=$(gum choose \
        "From default branch" \
        "From current branch" \
        "From specific branch" \
        --header "Start from:")

    local base_branch=""
    case "$source" in
        "From default branch")
            base_branch=$(get_default_branch)
            ;;
        "From current branch")
            base_branch=$(git branch --show-current)
            ;;
        "From specific branch")
            local branches
            branches=$(git branch -a --format='%(refname:short)' | sort -u)
            base_branch=$(echo "$branches" | gum filter --header "Select base branch:")
            [[ -z "$base_branch" ]] && return 1
            ;;
        *)
            return 1
            ;;
    esac

    gum style --foreground 245 "Base branch: $base_branch"
    echo ""

    local auto_branch
    auto_branch=$(generate_branch_name)
    local new_branch
    new_branch=$(gum input --value "$auto_branch" --header "New branch name:")

    if [[ -z "$new_branch" ]]; then
        gum style --foreground 208 "Branch name required"
        return 1
    fi

    local repo_root
    repo_root=$(get_repo_root)
    local auto_path
    auto_path="$repo_root/.worktrees/$(echo "$new_branch" | tr '/' '-')"
    local worktree_path
    worktree_path=$(gum input --value "$auto_path" --header "Worktree path:")

    if [[ -z "$worktree_path" ]]; then
        worktree_path="$auto_path"
    fi

    worktree_path="${worktree_path/#\~/$HOME}"

    if [[ "$worktree_path" != /* ]]; then
        worktree_path="$repo_root/$worktree_path"
    fi

    if [[ "$worktree_path" == "$repo_root/.worktrees/"* ]]; then
        add_to_exclude "$repo_root"
    fi

    gum spin --spinner dot --title "Creating worktree..." -- \
        git worktree add -b "$new_branch" "$worktree_path" "$base_branch"

    gum style --foreground 2 "✓ Created worktree: $new_branch"
    echo "  Path: $worktree_path"
    echo ""

    if gum confirm "Open in new shell?"; then
        cd "$worktree_path" && exec "$SHELL"
    fi
}

tui_action_checkout_branch() {
    gum style --bold --foreground 212 "Check Out Branch"
    echo ""

    local branches
    branches=$(git branch -a --format='%(refname:short)' | grep -v '^origin/HEAD' | sort -u)

    local selected
    selected=$(echo "$branches" | gum filter --header "Select branch:")

    if [[ -z "$selected" ]]; then
        return 1
    fi

    local branch="$selected"
    branch="${branch#origin/}"

    local -a worktrees=()
    collect_worktrees worktrees

    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path existing_branch <<< "$entry"
        if [[ "$existing_branch" == "$branch" ]]; then
            gum style --foreground 208 "Branch already has a worktree: $path"
            echo ""
            if gum confirm "Switch to existing worktree?"; then
                cd "$path" && exec "$SHELL"
            fi
            return 0
        fi
    done

    local repo_root
    repo_root=$(get_repo_root)
    local auto_path
    auto_path="$repo_root/.worktrees/$(echo "$branch" | tr '/' '-')"

    gum style --foreground 245 "Creating worktree for: $branch"
    echo ""

    local worktree_path
    worktree_path=$(gum input --value "$auto_path" --header "Worktree path:")

    if [[ -z "$worktree_path" ]]; then
        worktree_path="$auto_path"
    fi

    worktree_path="${worktree_path/#\~/$HOME}"

    if [[ "$worktree_path" != /* ]]; then
        worktree_path="$repo_root/$worktree_path"
    fi

    if [[ "$worktree_path" == "$repo_root/.worktrees/"* ]]; then
        add_to_exclude "$repo_root"
    fi

    gum spin --spinner dot --title "Creating worktree..." -- \
        git worktree add "$worktree_path" "$branch"

    gum style --foreground 2 "✓ Created worktree: $branch"
    echo "  Path: $worktree_path"
    echo ""

    if gum confirm "Open in new shell?"; then
        cd "$worktree_path" && exec "$SHELL"
    fi
}

tui_action_checkout_pr() {
    gum style --bold --foreground 212 "Check Out PR"
    echo ""

    if ! command -v gh &>/dev/null; then
        gum style --foreground 196 "Error: GitHub CLI (gh) is required"
        echo "Install: https://cli.github.com/"
        return 1
    fi

    local pr_number
    pr_number=$(gum input --placeholder "42" --header "PR number:")

    if [[ -z "$pr_number" ]]; then
        return 1
    fi

    gum style --foreground 245 "Fetching PR #${pr_number}..."

    local pr_branch
    if ! pr_branch=$(gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>&1); then
        gum style --foreground 196 "Error: Failed to fetch PR"
        echo "$pr_branch"
        return 1
    fi

    gum style --foreground 245 "Branch: $pr_branch"
    echo ""

    local repo_root
    repo_root=$(get_repo_root)
    local path
    path="$repo_root/.worktrees/$(echo "$pr_branch" | tr '/' '-')"

    add_to_exclude "$repo_root"

    if git worktree list --porcelain | grep -q "^worktree ${path}$"; then
        gum style --foreground 208 "Worktree already exists: $path"
        echo ""
        if gum confirm "Switch to existing worktree?"; then
            cd "$path" && exec "$SHELL"
        fi
        return 0
    fi

    gum spin --spinner dot --title "Creating worktree..." -- \
        git worktree add --detach "$path"

    cd "$path" || {
        gum style --foreground 196 "Error: Failed to enter worktree"
        git worktree remove "$path" 2>/dev/null || true
        return 1
    }

    if ! gh pr checkout "$pr_number" -b "$pr_branch" 2>/dev/null; then
        gum style --foreground 245 "Fetching PR ref directly..."
        if ! git fetch origin "pull/${pr_number}/head:${pr_branch}"; then
            gum style --foreground 196 "Error: Failed to fetch PR"
            cd "$repo_root" || true
            git worktree remove "$path" 2>/dev/null || true
            return 1
        fi
        git checkout "$pr_branch" || {
            gum style --foreground 196 "Error: Failed to checkout"
            cd "$repo_root" || true
            git worktree remove "$path" 2>/dev/null || true
            return 1
        }
    fi

    cd "$repo_root" || return 1

    gum style --foreground 2 "✓ Created worktree: $pr_branch"
    echo "  Path: $path"
    echo ""

    if gum confirm "Open in new shell?"; then
        cd "$path" && exec "$SHELL"
    fi
}

tui_action_select_worktree() {
    local action="$1"
    local current_worktree="$2"

    local -a worktrees=()
    collect_worktrees worktrees

    if [[ ${#worktrees[@]} -eq 0 ]]; then
        gum style --foreground 208 "No worktrees found"
        return 1
    fi

    local main_worktree
    main_worktree=$(get_main_worktree)

    local -a options=()
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"
        local display_path="$path"
        if [[ "$path" == "$main_worktree/.worktrees/"* ]]; then
            display_path="[repo]/.worktrees/$(basename "$path")"
        elif [[ "$path" == "$main_worktree" ]]; then
            display_path="[repo] (main)"
        fi
        options+=("$branch|$display_path|$path")
    done

    local header=""
    case "$action" in
        cd) header="Switch to worktree:" ;;
        open) header="Open in editor:" ;;
        diff) header="Show diff for:" ;;
        remove) header="Remove worktree:" ;;
    esac

    local selected
    selected=$(printf "%s\n" "${options[@]}" | awk -F'|' '{printf "%-40s %s\n", $1, $2}' | gum filter --header "$header")

    if [[ -z "$selected" ]]; then
        return 1
    fi

    local selected_branch
    selected_branch=$(echo "$selected" | awk '{print $1}')

    local selected_path=""
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"
        if [[ "$branch" == "$selected_branch" ]]; then
            selected_path="$path"
            break
        fi
    done

    case "$action" in
        cd)
            cd "$selected_path" && exec "$SHELL"
            ;;
        open)
            local editor="${EDITOR:-${VISUAL:-code}}"
            "$editor" "$selected_path"
            ;;
        diff)
            gum style --bold --foreground 212 "Diff: $selected_branch"
            echo ""
            git -C "$selected_path" diff --stat
            echo ""
            if gum confirm "Show full diff?"; then
                git -C "$selected_path" diff | gum pager
            fi
            ;;
        remove)
            if [[ "$selected_path" == "$main_worktree" ]]; then
                gum style --foreground 196 "Cannot remove main worktree"
                return 1
            fi

            gum style --foreground 208 "Remove worktree: $selected_branch"
            echo "  Path: $selected_path"
            echo ""

            if ! gum confirm "Are you sure?"; then
                return 0
            fi

            local in_worktree=false
            if [[ "$current_worktree" == "$selected_path"* ]]; then
                in_worktree=true
            fi

            gum spin --spinner dot --title "Removing worktree..." -- \
                git worktree remove "$selected_path"

            local main_branch
            main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
            if [[ "$selected_branch" != "$main_branch" ]] && [[ "$selected_branch" != "main" ]] && [[ "$selected_branch" != "master" ]]; then
                git branch -D "$selected_branch" 2>/dev/null || true
            fi

            gum style --foreground 2 "✓ Removed: $selected_branch"

            if [[ "$in_worktree" == true ]]; then
                echo ""
                gum style --foreground 245 "Returning to main worktree..."
                cd "$main_worktree" && exec "$SHELL"
            fi
            ;;
    esac
}

tui_action_move_worktree() {
    local -a worktrees=()
    collect_worktrees worktrees

    if [[ ${#worktrees[@]} -eq 0 ]]; then
        gum style --foreground 208 "No worktrees found"
        return 1
    fi

    local main_worktree
    main_worktree=$(get_main_worktree)
    local repo_root
    repo_root=$(get_repo_root)

    local -a options=()
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"
        local display_path="$path"
        local suffix=""
        if [[ "$path" == "$main_worktree/.worktrees/"* ]]; then
            display_path="[repo]/.worktrees/$(basename "$path")"
        elif [[ "$path" == "$main_worktree" ]]; then
            display_path="[repo]"
            suffix=" (main)"
        fi
        options+=("$branch|$display_path$suffix|$path")
    done

    local selected
    selected=$(printf "%s\n" "${options[@]}" | awk -F'|' '{printf "%-40s %s\n", $1, $2}' | gum filter --header "Select worktree to move:")

    if [[ -z "$selected" ]]; then
        return 1
    fi

    local selected_branch
    selected_branch=$(echo "$selected" | awk '{print $1}')

    local selected_path=""
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"
        if [[ "$branch" == "$selected_branch" ]]; then
            selected_path="$path"
            break
        fi
    done

    if [[ "$selected_path" == "$main_worktree" ]]; then
        local default_branch
        default_branch=$(get_default_branch)

        if [[ "$selected_branch" == "$default_branch" ]]; then
            gum style --foreground 208 "Main worktree is on default branch ($default_branch)"
            echo "Nothing to extract."
            return 1
        fi

        gum style --bold --foreground 212 "Extract from Main Worktree"
        echo ""
        gum style --foreground 245 "Branch: $selected_branch"
        gum style --foreground 245 "Main will switch to: $default_branch"
        echo ""

        local auto_dest
        auto_dest="$repo_root/.worktrees/$(echo "$selected_branch" | tr '/' '-')"
        local new_path
        new_path=$(gum input --value "$auto_dest" --header "New path:")

        if [[ -z "$new_path" ]]; then
            new_path="$auto_dest"
        fi

        new_path="${new_path/#\~/$HOME}"
        if [[ "$new_path" != /* ]]; then
            new_path="$repo_root/$new_path"
        fi

        if ! gum confirm "Extract branch to new worktree?"; then
            return 0
        fi

        mkdir -p "$(dirname "$new_path")"
        if [[ "$new_path" == "$repo_root/.worktrees/"* ]]; then
            add_to_exclude "$repo_root"
        fi

        gum spin --spinner dot --title "Switching main to $default_branch..." -- \
            git -C "$main_worktree" checkout "$default_branch"

        gum spin --spinner dot --title "Creating new worktree..." -- \
            git worktree add "$new_path" "$selected_branch"

        gum style --foreground 2 "✓ Extracted: $selected_branch"
        echo "  New path: $new_path"
        echo ""

        if gum confirm "Open in new shell?"; then
            cd "$new_path" && exec "$SHELL"
        fi
        return 0
    fi

    gum style --foreground 245 "Moving: $selected_branch"
    gum style --foreground 245 "Current path: $selected_path"
    echo ""

    local auto_name
    auto_name=$(generate_branch_name)
    local auto_dest
    auto_dest="$repo_root/.worktrees/$(echo "$auto_name" | tr '/' '-')"

    local new_path
    local used_auto_path=false
    new_path=$(gum input --placeholder "$auto_dest" --header "New path (Enter for auto):")

    if [[ -z "$new_path" ]]; then
        new_path="$auto_dest"
        used_auto_path=true
    fi

    new_path="${new_path/#\~/$HOME}"

    if [[ "$new_path" != /* ]]; then
        new_path="$repo_root/$new_path"
    fi

    if [[ "$new_path" == "$selected_path" ]]; then
        gum style --foreground 208 "Source and destination are the same"
        return 1
    fi

    gum style --foreground 245 "New path: $new_path"
    echo ""

    if ! gum confirm "Move worktree to this location?"; then
        return 0
    fi

    mkdir -p "$(dirname "$new_path")"

    if [[ "$new_path" == "$repo_root/.worktrees/"* ]]; then
        add_to_exclude "$repo_root"
    fi

    gum spin --spinner dot --title "Moving worktree..." -- \
        git worktree move "$selected_path" "$new_path"

    gum style --foreground 2 "✓ Moved worktree: $selected_branch"
    echo "  From: $selected_path"
    echo "  To:   $new_path"
    echo ""

    if gum confirm "Rename branch?"; then
        local suggested_name
        if [[ "$used_auto_path" == true ]]; then
            suggested_name="$auto_name"
        else
            suggested_name=$(basename "$new_path")
        fi

        local new_branch
        new_branch=$(gum input --value "$suggested_name" --header "New branch name:")

        if [[ -n "$new_branch" ]] && [[ "$new_branch" != "$selected_branch" ]]; then
            git branch -m "$selected_branch" "$new_branch"
            gum style --foreground 2 "✓ Renamed branch: $selected_branch → $new_branch"
            selected_branch="$new_branch"
        fi
    fi

    if gum confirm "Open in new shell?"; then
        cd "$new_path" && exec "$SHELL"
    fi
}

tui_action_cleanup() {
    gum style --bold --foreground 212 "Clean Worktrees"
    echo ""

    gum spin --spinner dot --title "Fetching from remotes..." -- \
        git fetch --all --prune

    local -a worktrees=()
    collect_worktrees worktrees

    local main_worktree
    main_worktree=$(get_main_worktree)
    local default_branch
    default_branch=$(get_default_branch)

    local -a stale=()
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"

        [[ "$path" == "$main_worktree" ]] && continue
        [[ -z "$branch" ]] && continue

        local upstream
        upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")

        if [[ -n "$upstream" ]] && ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
            stale+=("$branch (upstream gone)|$path")
            continue
        fi

        if git merge-base --is-ancestor "$branch" "$default_branch" 2>/dev/null; then
            local ahead
            ahead=$(git rev-list --count "$default_branch..$branch" 2>/dev/null || echo "1")
            if [[ "$ahead" -eq 0 ]]; then
                stale+=("$branch (merged)|$path")
            fi
        fi
    done

    if [[ ${#stale[@]} -eq 0 ]]; then
        gum style --foreground 2 "✓ No stale worktrees found"
        return 0
    fi

    gum style --foreground 208 "Found ${#stale[@]} stale worktree(s):"
    echo ""

    local -a options=()
    for entry in "${stale[@]}"; do
        IFS='|' read -r label path <<< "$entry"
        options+=("$label")
    done

    local -a to_remove=()
    mapfile -t to_remove < <(printf "%s\n" "${options[@]}" | gum choose --no-limit --header "Select worktrees to remove:")

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        gum style --foreground 245 "Nothing selected"
        return 0
    fi

    for label in "${to_remove[@]}"; do
        local branch
        branch=$(echo "$label" | cut -d'(' -f1 | xargs)

        for entry in "${stale[@]}"; do
            if [[ "$entry" == "$label|"* ]]; then
                local path
                path="${entry#*|}"

                git worktree remove "$path" 2>/dev/null || \
                    git worktree remove --force "$path"
                local main_branch
                main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
                if [[ "$branch" != "$main_branch" ]] && [[ "$branch" != "main" ]] && [[ "$branch" != "master" ]]; then
                    git branch -D "$branch" 2>/dev/null || true
                fi

                gum style --foreground 2 "✓ Removed: $branch"
                break
            fi
        done
    done
}

tui_main_menu() {
    local original_worktree
    original_worktree=$(pwd -P)
    cd "$(get_main_worktree)"
    while true; do
        clear
        show_dashboard "$original_worktree"
        echo ""

        local editor="${EDITOR:-${VISUAL:-code}}"
        local editor_label="Open in $editor..."

        local action
        action=$(gum choose \
            "New worktree..." \
            "Check out branch..." \
            "Check out PR..." \
            "Switch to worktree..." \
            "$editor_label" \
            "Show diff..." \
            "Move worktree..." \
            "Remove worktree..." \
            "Clean" \
            "Refresh" \
            "Quit")

        case "$action" in
            "New worktree...")
                tui_action_new_worktree
                ;;
            "Check out branch...")
                tui_action_checkout_branch || continue
                ;;
            "Check out PR...")
                tui_action_checkout_pr || continue
                ;;
            "Switch to worktree...")
                tui_action_select_worktree cd "$original_worktree" && continue
                ;;
            "$editor_label")
                tui_action_select_worktree open "$original_worktree" && continue
                ;;
            "Show diff...")
                tui_action_select_worktree diff "$original_worktree" || continue
                ;;
            "Move worktree...")
                tui_action_move_worktree || continue
                ;;
            "Remove worktree...")
                tui_action_select_worktree remove "$original_worktree" || continue
                ;;
            "Clean")
                tui_action_cleanup
                ;;
            "Refresh")
                continue
                ;;
            "Quit"|"")
                exit 0
                ;;
        esac

        echo ""
        gum input --placeholder "Press Enter to continue..." > /dev/null 2>&1 || true
    done
}

cmd_tui() {
    if ! command -v gum &> /dev/null; then
        echo "Error: 'gum' is required for TUI mode"
        echo "Install: https://github.com/charmbracelet/gum#installation"
        exit 1
    fi

    check_git_repo
    tui_main_menu
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
        usage
        exit 0
    fi

    if [[ $# -eq 0 ]]; then
        if [[ "${WT_NO_TUI:-}" == "1" ]] || [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
            usage
            exit 0
        fi

        if command -v gum &> /dev/null; then
            check_git_repo
            tui_main_menu
            exit 0
        else
            echo "TUI requires 'gum'. Install: https://github.com/charmbracelet/gum#installation"
            echo ""
            usage
            exit 0
        fi
    fi

    if ! command -v git &> /dev/null; then
        echo "Error: git is required"
        exit 1
    fi

    check_git_repo

    local command="$1"
    shift

    case "$command" in
        tui)
            cmd_tui
            ;;
        add|new|create)
            cmd_add "$@"
            ;;
        co|checkout)
            cmd_co "$@"
            ;;
        pr)
            local pr_subcommand="${1:-}"
            shift || true
            case "$pr_subcommand" in
                co|checkout)
                    cmd_co "$@"
                    ;;
                *)
                    echo "Error: Unknown pr subcommand '$pr_subcommand'"
                    echo "Usage: $(basename "$0") pr co <pr-number>"
                    exit 1
                    ;;
            esac
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
        move|mv)
            cmd_move "$@"
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
