#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

TUI dashboard for your open GitHub pull requests.

Displays PRs grouped by repository with CI status, review state, draft
indicator, and age. Launches an interactive TUI when gum is available,
with a plain-text fallback.

OPTIONS:
    -h, --help           Show this help message and exit
    --no-tui             Force non-interactive output
    --include-draft      Include draft PRs (excluded by default)
    --include-approved   Include approved PRs (excluded by default)
    --json               Output raw JSON
    --refresh SECS       Auto-refresh interval in seconds (default: 300)
    -q, --quiet          Exit 0 if PRs exist, 1 if none (no output)

PREREQUISITES:
    - gh (GitHub CLI) must be installed and authenticated
    - jq must be installed for JSON processing
    - gum is optional (for interactive TUI)

EXAMPLES:
    $cmd                     Launch interactive dashboard
    $cmd --no-tui            Print plain-text table
    $cmd --include-draft     Show draft PRs too
    $cmd --json              Dump raw JSON for scripting
    $cmd -q && echo "PRs!"   Check if you have open PRs
    $cmd --json | jq '.[].title'

EXIT CODES:
    0    PRs found (or help shown)
    1    No PRs found, or error occurred
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "gh"
        "jq"
        # keep-sorted end
    )
    local missing_deps=()

    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: missing required dependencies: ${missing_deps[*]}" >&2
        exit 1
    fi
}

fetch_prs() {
    local include_draft="$1"
    local include_approved="$2"

    local query_str="author:@me is:pr is:open"
    if [[ "$include_draft" != "true" ]]; then
        query_str="$query_str -is:draft"
    fi

    local raw
    # shellcheck disable=SC2016
    raw=$(gh api graphql -f query_str="$query_str" -f query='
    query($query_str: String!) {
        search(query: $query_str, type: ISSUE, first: 100) {
            edges {
                node {
                    ... on PullRequest {
                        number
                        title
                        url
                        createdAt
                        isDraft
                        reviewDecision
                        repository {
                            nameWithOwner
                        }
                        reviewRequests(first: 10) {
                            nodes {
                                requestedReviewer {
                                    ... on User { login }
                                    ... on Team { name }
                                }
                            }
                        }
                        commits(last: 1) {
                            nodes {
                                commit {
                                    statusCheckRollup {
                                        state
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }')

    local jq_filter='[.data.search.edges[].node | {
        number,
        title,
        url,
        createdAt,
        isDraft,
        reviewDecision,
        repo: .repository.nameWithOwner,
        reviewers: [.reviewRequests.nodes[]
            | .requestedReviewer
            | select(. != null)
            | (.login // .name)
            | select(. != null)],
        ci: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE")
    }]'

    if [[ "$include_approved" != "true" ]]; then
        jq_filter="${jq_filter} | [.[] | select(.reviewDecision != \"APPROVED\")]"
    fi

    echo "$raw" | jq "$jq_filter"
}

format_age() {
    local created_at="$1"
    local now
    now=$(date +%s)

    local created
    if date --version &>/dev/null 2>&1; then
        created=$(date -d "$created_at" +%s)
    else
        created=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S%z" "$created_at" +%s 2>/dev/null || echo "$now")
    fi

    local diff=$(( now - created ))
    if [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60))m"
    elif [[ $diff -lt 86400 ]]; then
        echo "$((diff / 3600))h"
    elif [[ $diff -lt 604800 ]]; then
        echo "$((diff / 86400))d"
    elif [[ $diff -lt 2592000 ]]; then
        echo "$((diff / 604800))w"
    else
        echo "$((diff / 2592000))mo"
    fi
}

format_ci() {
    local ci="$1"
    local use_color="$2"

    if [[ "$use_color" == "true" ]]; then
        case "$ci" in
            SUCCESS)  printf '\033[32m pass \033[0m' ;;
            FAILURE|ERROR) printf '\033[31m fail \033[0m' ;;
            PENDING)  printf '\033[33m pend \033[0m' ;;
            *)        printf '\033[90m  --  \033[0m' ;;
        esac
    else
        case "$ci" in
            SUCCESS)  printf ' pass ' ;;
            FAILURE|ERROR) printf ' fail ' ;;
            PENDING)  printf ' pend ' ;;
            *)        printf '  --  ' ;;
        esac
    fi
}

format_review() {
    local review="$1"
    local use_color="$2"

    if [[ "$use_color" == "true" ]]; then
        case "$review" in
            APPROVED)         printf '\033[32mapproved\033[0m' ;;
            CHANGES_REQUESTED) printf '\033[31mchanges \033[0m' ;;
            REVIEW_REQUIRED)  printf '\033[33mpending \033[0m' ;;
            *)                printf '\033[90m   --   \033[0m' ;;
        esac
    else
        case "$review" in
            APPROVED)         printf 'approved' ;;
            CHANGES_REQUESTED) printf 'changes ' ;;
            REVIEW_REQUIRED)  printf 'pending ' ;;
            *)                printf '   --   ' ;;
        esac
    fi
}

format_line() {
    local number="$1"
    local title="$2"
    local is_draft="$3"
    local ci="$4"
    local review="$5"
    local reviewers="$6"
    local age="$7"
    local use_color="$8"

    # Truncate title
    local max_title=72
    local display_title="$title"
    if [[ ${#display_title} -gt $max_title ]]; then
        display_title="${display_title:0:$((max_title - 3))}..."
    fi

    local draft_tag=""
    if [[ "$is_draft" == "true" ]]; then
        if [[ "$use_color" == "true" ]]; then
            draft_tag="\033[90m[draft]\033[0m "
        else
            draft_tag="[draft] "
        fi
    fi

    local ci_str
    ci_str=$(format_ci "$ci" "$use_color")

    local review_str
    review_str=$(format_review "$review" "$use_color")

    local reviewer_str=""
    if [[ -n "$reviewers" && "$reviewers" != "null" ]]; then
        reviewer_str=" <- $reviewers"
    fi

    printf "  #%-5s %-${max_title}s %b %s  %s  %3s%s" \
        "$number" "$display_title" "$draft_tag" "$ci_str" "$review_str" "$age" "$reviewer_str"
}

ci_emoji() {
    case "$1" in
        SUCCESS)       printf '🟢' ;;
        FAILURE|ERROR) printf '🔴' ;;
        PENDING)       printf '🟡' ;;
        *)             printf '  ' ;;
    esac
}

review_emoji() {
    case "$1" in
        APPROVED)          printf '✅' ;;
        CHANGES_REQUESTED) printf '🔴' ;;
        REVIEW_REQUIRED)   printf '👀' ;;
        *)                 printf '  ' ;;
    esac
}

build_lines() {
    local prs="$1"

    _lines=()
    _urls=()

    while IFS= read -r repo; do
        local repo_prs
        repo_prs=$(echo "$prs" | jq -c "[.[] | select(.repo == \"$repo\")]")

        while IFS= read -r pr; do
            local number title url ci review is_draft
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            url=$(echo "$pr" | jq -r '.url')
            ci=$(echo "$pr" | jq -r '.ci')
            review=$(echo "$pr" | jq -r '.reviewDecision // ""')
            is_draft=$(echo "$pr" | jq -r '.isDraft')

            # Truncate title if needed (keep at least 72 chars visible)
            local max_title=72
            local display_title="$title"
            if [[ ${#display_title} -gt $max_title ]]; then
                display_title="${display_title:0:$((max_title - 3))}..."
            fi

            local line
            line=$(printf "%s %s %-22s #%-5s %s" \
                "$(ci_emoji "$ci")" "$(review_emoji "$review")" \
                "$repo" "$number" "$display_title")
            _lines+=("$line")
            _urls+=("$url")
        done < <(echo "$repo_prs" | jq -c '.[]')
    done < <(echo "$prs" | jq -r '[.[].repo] | unique | .[]')
}

render_interactive() {
    local include_draft="$1"
    local include_approved="$2"
    local refresh_interval="$3"

    local prs last_fetch=0

    while true; do
        local now
        now=$(date +%s)

        # Refresh data if stale
        if [[ $(( now - last_fetch )) -ge $refresh_interval ]]; then
            local tmpfile
            tmpfile=$(mktemp)
            gum spin --spinner dot --title "Fetching PRs..." -- \
                bash -c "$(declare -f fetch_prs); fetch_prs '$include_draft' '$include_approved' > '$tmpfile'"
            prs=$(cat "$tmpfile")
            rm -f "$tmpfile"
            last_fetch=$(date +%s)
            build_lines "$prs"
        fi

        if [[ ${#_lines[@]} -eq 0 ]]; then
            echo "No open PRs found."
            return 1
        fi

        local refresh_label=">> Refresh <<"
        local selected
        local legend="CI: 🟢pass 🔴fail 🟡pending  Review: ✅ok 🔴changes 👀pending"
        local header="$legend"
        if [[ "$refresh_interval" -gt 0 ]]; then
            header="${header}  [refresh: $((refresh_interval / 60))m]"
        fi
        selected=$(printf "%s\n" "$refresh_label" "${_lines[@]}" | gum filter --header "$header") || return 0

        if [[ -z "$selected" ]]; then
            return 0
        fi

        if [[ "$selected" == "$refresh_label" ]]; then
            last_fetch=0
            continue
        fi

        # Find matching URL
        local i
        for i in "${!_lines[@]}"; do
            if [[ "${_lines[$i]}" == "$selected" ]]; then
                local action
                action=$(gum choose \
                    "Open in browser" \
                    "Copy URL" \
                    "View details" \
                    "Quit") || continue

                case "$action" in
                    "Open in browser")
                        if command -v open &>/dev/null; then
                            open "${_urls[$i]}"
                        elif command -v xdg-open &>/dev/null; then
                            xdg-open "${_urls[$i]}"
                        else
                            echo "${_urls[$i]}"
                        fi
                        ;;
                    "Copy URL")
                        if command -v pbcopy &>/dev/null; then
                            echo -n "${_urls[$i]}" | pbcopy
                            echo "Copied: ${_urls[$i]}"
                        elif command -v xclip &>/dev/null; then
                            echo -n "${_urls[$i]}" | xclip -selection clipboard
                            echo "Copied: ${_urls[$i]}"
                        else
                            echo "${_urls[$i]}"
                        fi
                        ;;
                    "View details")
                        gh pr view "${_urls[$i]}" || echo "Error: failed to fetch PR details" >&2
                        ;;
                    "Quit"|"")
                        return 0
                        ;;
                esac
                break
            fi
        done
    done
}

render_plain() {
    local prs="$1"
    local use_color="$2"

    local total
    total=$(echo "$prs" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 1
    fi

    while IFS= read -r repo; do
        if [[ "$use_color" == "true" ]]; then
            printf '\033[1;35m%s\033[0m\n' "$repo"
        else
            echo "$repo"
        fi

        local repo_prs
        repo_prs=$(echo "$prs" | jq -c "[.[] | select(.repo == \"$repo\")]")

        while IFS= read -r pr; do
            local number title is_draft ci review reviewers_str created_at age
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            is_draft=$(echo "$pr" | jq -r '.isDraft')
            ci=$(echo "$pr" | jq -r '.ci')
            review=$(echo "$pr" | jq -r '.reviewDecision // ""')
            reviewers_str=$(echo "$pr" | jq -r '.reviewers | if length > 0 then join(", ") else "" end')
            created_at=$(echo "$pr" | jq -r '.createdAt')
            age=$(format_age "$created_at")

            format_line "$number" "$title" "$is_draft" "$ci" "$review" "$reviewers_str" "$age" "$use_color"
            echo ""
        done < <(echo "$repo_prs" | jq -c '.[]')
        echo ""
    done < <(echo "$prs" | jq -r '[.[].repo] | unique | .[]')

    echo "$total open PR(s)."
}

main() {
    local no_tui=false
    local include_draft=false
    local include_approved=false
    local json_output=false
    local quiet=false
    local refresh_interval=300

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --no-tui)
                no_tui=true
                shift
                ;;
            --include-draft)
                include_draft=true
                shift
                ;;
            --include-approved)
                include_approved=true
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            --refresh)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --refresh requires a value" >&2
                    exit 1
                fi
                refresh_interval="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -*)
                echo "Error: unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                echo "Error: unexpected argument: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done

    check_dependencies

    # Decide TUI vs plain
    local use_tui=false
    if [[ "$no_tui" != true ]] && [[ -t 1 ]] && command -v gum &>/dev/null; then
        use_tui=true
    fi

    if [[ "$use_tui" == true ]]; then
        render_interactive "$include_draft" "$include_approved" "$refresh_interval"
    else
        local prs
        prs=$(fetch_prs "$include_draft" "$include_approved")

        local count
        count=$(echo "$prs" | jq 'length')

        if [[ "$quiet" == true ]]; then
            [[ "$count" -gt 0 ]]
            exit $?
        fi

        if [[ "$json_output" == true ]]; then
            echo "$prs" | jq '.'
            [[ "$count" -gt 0 ]]
            exit $?
        fi

        if [[ "$count" -eq 0 ]]; then
            echo "No open PRs found."
            exit 1
        fi

        local use_color=false
        if [[ -t 1 ]]; then
            use_color=true
        fi
        render_plain "$prs" "$use_color"
    fi
}

main "$@"
