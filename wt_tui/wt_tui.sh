#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Interactive TUI for managing git worktrees.

Provides a visual dashboard to view, create, and manage git worktrees.
Inspired by conductor.build.

OPTIONS:
    -h, --help    Show this help message and exit

PREREQUISITES:
    - Git 2.5+ with worktree support
    - gum (https://github.com/charmbracelet/gum)
    - GitHub CLI (gh) for PR checkout feature

EXAMPLES:
    $cmd              Launch the TUI
    $cmd --help       Show this help

EXIT CODES:
    0    Success
    1    Error occurred
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "git"
        "gum"
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
        echo "Install gum: https://github.com/charmbracelet/gum#installation"
        exit 1
    fi
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

generate_branch_name() {
    local username=""

    # Try GitHub username first (if origin is GitHub and gh is available)
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$remote_url" == *"github.com"* ]] && command -v gh &>/dev/null; then
        username=$(gh api user --jq '.login' 2>/dev/null || echo "")
    fi

    # Fallback to git config user.name
    if [[ -z "$username" ]]; then
        username=$(git config user.name | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    fi

    # Fallback to system username
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

add_to_exclude() {
    local repo_root="$1"
    local exclude_file="$repo_root/.git/info/exclude"
    local exclude_pattern=".worktrees"

    mkdir -p "$(dirname "$exclude_file")"

    if [[ ! -f "$exclude_file" ]]; then
        echo "# git ls-files --others --exclude-from=.git/info/exclude" > "$exclude_file"
    fi

    if ! grep -q "^${exclude_pattern}$" "$exclude_file"; then
        echo "$exclude_pattern" >> "$exclude_file"
    fi
}

get_worktree_status() {
    local path="$1"
    local status=""

    if [[ ! -d "$path" ]]; then
        echo "missing"
        return
    fi

    local changes
    changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$changes" -gt 0 ]]; then
        status="$changes changes"
    else
        status="clean"
    fi

    echo "$status"
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

    local header
    header=$(printf "  %-40s %-30s %-15s %-12s" "BRANCH" "PATH" "STATUS" "SYNC")
    gum style --foreground 245 "$header"

    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"

        local short_path
        if [[ "$path" == "$main_worktree" ]]; then
            short_path="(main)"
            branch="${branch:-$(get_default_branch)}"
        else
            short_path=$(basename "$path")
        fi

        local status
        status=$(get_worktree_status "$path")

        local sync
        sync=$(get_worktree_ahead_behind "$path" "$branch")

        local status_color="32"
        if [[ "$status" == *"changes"* ]]; then
            status_color="33"
        elif [[ "$status" == "missing" ]]; then
            status_color="31"
        fi

        local marker="  "
        if [[ "$path" == "$current_worktree" ]]; then
            marker="→ "
        fi

        printf "%s%-40s %-30s \033[%sm%-15s\033[0m %-12s\n" "$marker" "$branch" "$short_path" "$status_color" "$status" "$sync"
    done
}

action_new_worktree() {
    gum style --bold --foreground 212 "Create New Worktree"
    echo ""

    local from_branch
    from_branch=$(gum choose --header "Start from:" "Default branch ($(get_default_branch))" "Current branch" "Specific branch")

    local base_branch
    case "$from_branch" in
        "Default"*)
            base_branch=$(get_default_branch)
            ;;
        "Current"*)
            base_branch=$(git branch --show-current)
            ;;
        "Specific"*)
            base_branch=$(git branch --format='%(refname:short)' | gum filter --placeholder "Select branch...")
            ;;
    esac

    local branch_name
    local auto_name
    auto_name=$(generate_branch_name)
    branch_name=$(gum input --placeholder "$auto_name" --header "Branch name (Enter for auto):")

    if [[ -z "$branch_name" ]]; then
        branch_name="$auto_name"
    fi

    local repo_root
    repo_root=$(get_repo_root)
    local dir_name
    dir_name=$(echo "$branch_name" | tr '/' '-')
    local path="$repo_root/.worktrees/$dir_name"

    add_to_exclude "$repo_root"

    gum spin --spinner dot --title "Creating worktree..." -- \
        git worktree add "$path" -b "$branch_name" "$base_branch" 2>/dev/null || \
        git worktree add "$path" "$branch_name" 2>/dev/null || \
        git worktree add "$path" -b "$branch_name" "origin/$base_branch"

    gum style --foreground 2 "✓ Created worktree: $branch_name"
    echo "  Path: $path"

    if gum confirm "Open in new shell?"; then
        cd "$path" && exec "$SHELL"
    fi
}

action_checkout_pr() {
    if ! command -v gh &> /dev/null; then
        gum style --foreground 1 "Error: GitHub CLI (gh) is required for PR checkout"
        return 1
    fi

    gum style --bold --foreground 212 "Checkout Pull Request"
    echo ""

    local pr_number
    pr_number=$(gum input --placeholder "42" --header "PR number:")

    if [[ -z "$pr_number" ]]; then
        gum style --foreground 1 "Aborted"
        return 1
    fi

    local pr_info
    pr_info=$(gh pr view "$pr_number" --json headRefName,title 2>/dev/null) || {
        gum style --foreground 1 "Error: Could not fetch PR #$pr_number"
        return 1
    }

    local branch_name
    branch_name=$(echo "$pr_info" | jq -r '.headRefName')
    local title
    title=$(echo "$pr_info" | jq -r '.title')

    gum style --foreground 245 "PR #$pr_number: $title"
    gum style --foreground 245 "Branch: $branch_name"
    echo ""

    local repo_root
    repo_root=$(get_repo_root)
    local dir_name
    dir_name=$(echo "$branch_name" | tr '/' '-')
    local path="$repo_root/.worktrees/$dir_name"

    add_to_exclude "$repo_root"

    gum spin --spinner dot --title "Fetching PR..." -- \
        gh pr checkout "$pr_number" --detach

    git worktree add "$path" -b "$branch_name" FETCH_HEAD 2>/dev/null || \
        git worktree add "$path" "$branch_name" 2>/dev/null || {
        gum style --foreground 1 "Error: Could not create worktree"
        return 1
    }

    gum style --foreground 2 "✓ Created worktree for PR #$pr_number"
    echo "  Path: $path"

    if gum confirm "Open in new shell?"; then
        cd "$path" && exec "$SHELL"
    fi
}

action_select_worktree() {
    local action="$1"
    local current_path="$2"
    local -a worktrees=()
    collect_worktrees worktrees

    if [[ ${#worktrees[@]} -eq 0 ]]; then
        gum style --foreground 208 "No worktrees found."
        return 1
    fi

    local repo_root
    repo_root=$(get_main_worktree)

    local -a options=()
    local current_option=""
    for entry in "${worktrees[@]}"; do
        IFS='|' read -r path branch <<< "$entry"
        local status
        status=$(get_worktree_status "$path")
        local short_path="${path/#$repo_root/.}"
        local option="$branch ($status) -> $short_path"
        if [[ "$path" == "$current_path" ]]; then
            current_option="→ $option"
        else
            options+=("  $option")
        fi
    done

    if [[ -n "$current_option" ]]; then
        options=("$current_option" "${options[@]}")
    fi

    local selected
    selected=$(printf "%s\n" "${options[@]}" | gum filter --placeholder "Select worktree...")

    if [[ -z "$selected" ]]; then
        return 1
    fi

    local selected_path
    selected_path="${selected##*-> }"
    selected_path="${selected_path/#./$repo_root}"

    case "$action" in
        cd)
            cd "$selected_path" && exec "$SHELL"
            ;;
        open)
            local editor="${EDITOR:-${VISUAL:-code}}"
            if command -v "$editor" &> /dev/null; then
                "$editor" "$selected_path"
            else
                gum style --foreground 1 "Editor not found: $editor"
            fi
            ;;
        diff)
            git -C "$selected_path" diff
            gum input --placeholder "Press Enter to continue..."
            ;;
        remove)
            local branch
            branch=$(echo "$selected" | cut -d'(' -f1 | xargs)

            if ! gum confirm "Remove worktree '$branch'?"; then
                return 0
            fi

            local main_worktree
            main_worktree=$(get_main_worktree)

            if [[ "$selected_path" == "$main_worktree" ]]; then
                gum style --foreground 1 "Cannot remove main worktree"
                return 1
            fi

            git worktree remove "$selected_path" 2>/dev/null || \
                git worktree remove --force "$selected_path"

            # Delete the branch if it exists and is not the main branch
            if [[ -n "$branch" ]] && git rev-parse --verify "$branch" >/dev/null 2>&1; then
                local main_branch
                main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
                if [[ "$branch" != "$main_branch" ]] && [[ "$branch" != "main" ]] && [[ "$branch" != "master" ]]; then
                    git branch -D "$branch" 2>/dev/null || true
                fi
            fi

            gum style --foreground 2 "✓ Removed worktree: $branch"

            cd "$(get_main_worktree)"
            ;;
    esac
}

action_cleanup() {
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
                # Delete the branch if it's not a protected branch
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

main_menu() {
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
            "Checkout PR..." \
            "Switch to worktree..." \
            "$editor_label" \
            "Show diff..." \
            "Remove worktree..." \
            "Clean" \
            "Refresh" \
            "Quit")

        case "$action" in
            "New worktree...")
                action_new_worktree
                ;;
            "Checkout PR...")
                action_checkout_pr
                ;;
            "Switch to worktree...")
                action_select_worktree cd "$original_worktree"
                ;;
            "$editor_label")
                action_select_worktree open "$original_worktree"
                ;;
            "Show diff...")
                action_select_worktree diff "$original_worktree"
                ;;
            "Remove worktree...")
                action_select_worktree remove "$original_worktree"
                ;;
            "Clean")
                action_cleanup
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

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    check_dependencies
    check_git_repo
    main_menu
}

main "$@"
