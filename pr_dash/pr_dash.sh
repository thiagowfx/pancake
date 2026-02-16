#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [REPO ...]

TUI dashboard for your open GitHub pull requests.

Displays PRs grouped by repository with CI status, review state, draft
indicator, and age. Launches an interactive TUI when gum is available,
with a plain-text fallback.

OPTIONS:
    -h, --help               Show this help message and exit
    --no-tui                 Force non-interactive output
    --include-draft          Include draft PRs (excluded by default)
    --include-approved       Include approved PRs (excluded by default)
    --json                   Output raw JSON
    --slack                  Output as Slack mrkdwn (for pasting into Slack)
    --refresh SECS           Auto-refresh interval in seconds (default: 300)
    --stale-after DAYS       Hide PRs older than DAYS behind a toggle (default: 28)
    -o, --org ORG            Filter PRs to a specific organization
    --created-before WHEN    Only show PRs created before WHEN (YYYY-MM-DD or relative like "60 days")
    --created-after WHEN     Only show PRs created after WHEN (YYYY-MM-DD or relative like "60 days")
    -q, --quiet              Exit 0 if PRs exist, 1 if none (no output)

ARGUMENTS:
    REPO                     Filter by specific repositories (e.g. helm/helm tulip/terraform)

PREREQUISITES:
    - gh (GitHub CLI) must be installed and authenticated
    - jq must be installed for JSON processing
    - gum is optional (for interactive TUI)

EXAMPLES:
    $cmd                                  Launch interactive dashboard
    $cmd --no-tui                         Print plain-text table
    $cmd --include-draft                  Show draft PRs too
    $cmd --json                           Dump raw JSON for scripting
    $cmd -q && echo "PRs!"                Check if you have open PRs
    $cmd --json | jq '.[].title'
    $cmd --slack                          Output Slack mrkdwn for pasting
    $cmd --slack | pbcopy                 Copy Slack-formatted summary
    $cmd -o helm                          Only show PRs from the helm org
    $cmd --created-before "7 days"        Only show PRs older than 7 days
    $cmd --created-after 2025-01-01       Only show PRs created after a date
    $cmd helm/helm tulip/terraform        Only show PRs from specific repos

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

parse_since_date() {
    local when="$1"

    # If it looks like a date (YYYY-MM-DD), use it as-is
    if [[ "$when" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$when"
        return 0
    fi

    # Try to parse relative dates
    # Extract number and unit from input like "2 days", "1 week", etc.
    local num unit
    if [[ "$when" =~ ^([0-9]+)\ +(day|week|month|year)s?$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        echo "Error: invalid date format. Use YYYY-MM-DD or relative format like '60 days'" >&2
        return 1
    fi

    # Convert unit to days
    local days=0
    case "$unit" in
        day) days=$num ;;
        week) days=$((num * 7)) ;;
        month) days=$((num * 30)) ;;
        year) days=$((num * 365)) ;;
    esac

    # Calculate the date that was N days ago
    # Try GNU date first (Linux), then BSD date (macOS)
    local result
    if date --version &>/dev/null 2>&1; then
        # GNU date
        result=$(date -d "$days days ago" +%Y-%m-%d)
    else
        # BSD date
        result=$(date -v-"${days}"d +%Y-%m-%d)
    fi

    echo "$result"
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

build_line() {
    local pr="$1"

    local number title ci review is_draft repo
    number=$(echo "$pr" | jq -r '.number')
    title=$(echo "$pr" | jq -r '.title')
    ci=$(echo "$pr" | jq -r '.ci')
    review=$(echo "$pr" | jq -r '.reviewDecision // ""')
    is_draft=$(echo "$pr" | jq -r '.isDraft')
    repo=$(echo "$pr" | jq -r '.repo')

    local max_title=72
    local display_title="$title"
    if [[ ${#display_title} -gt $max_title ]]; then
        display_title="${display_title:0:$((max_title - 3))}..."
    fi

    printf "%s %s %-22s #%-5s %s" \
        "$(ci_emoji "$ci")" "$(review_emoji "$review")" \
        "$repo" "$number" "$display_title"
}

build_lines() {
    local prs="$1"
    local stale_days="$2"

    _lines=()
    _urls=()
    _stale_lines=()
    _stale_urls=()

    local stale_secs=$(( stale_days * 86400 ))
    local now
    now=$(date +%s)

    # Ready PRs (CI pass + approved) first, then the rest grouped by repo
    local sorted_prs
    sorted_prs=$(echo "$prs" | jq '[
        ([.[] | select(.ci == "SUCCESS" and .reviewDecision == "APPROVED" and .isDraft != true)] | sort_by(.repo)) +
        ([.[] | select(.ci != "SUCCESS" or .reviewDecision != "APPROVED" or .isDraft == true)] | sort_by(.repo))
    ] | add')

    while IFS= read -r pr; do
        local url created_at created age_secs
        url=$(echo "$pr" | jq -r '.url')
        created_at=$(echo "$pr" | jq -r '.createdAt')

        if date --version &>/dev/null 2>&1; then
            created=$(date -d "$created_at" +%s)
        else
            created=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || echo "$now")
        fi
        age_secs=$(( now - created ))

        local line
        line=$(build_line "$pr")

        if [[ $age_secs -ge $stale_secs ]]; then
            _stale_lines+=("$line")
            _stale_urls+=("$url")
        else
            _lines+=("$line")
            _urls+=("$url")
        fi
    done < <(echo "$sorted_prs" | jq -c '.[]')
}

render_interactive() {
    local include_draft="$1"
    local include_approved="$2"
    local refresh_interval="$3"
    local stale_days="$4"
    local org_filter="$5"
    local created_before="$6"
    local created_after="$7"
    shift 7
    local -a repos=("$@")

    local prs last_fetch=0
    local show_stale=false

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

            # Apply filters
            if [[ -n "$org_filter" ]]; then
                prs=$(echo "$prs" | jq "[.[] | select(.repo | startswith(\"${org_filter}/\"))]")
            fi
            if [[ -n "$created_before" ]]; then
                prs=$(echo "$prs" | jq "[.[] | select(.createdAt <= \"${created_before}T23:59:59Z\")]")
            fi
            if [[ -n "$created_after" ]]; then
                prs=$(echo "$prs" | jq "[.[] | select(.createdAt >= \"${created_after}T00:00:00Z\")]")
            fi
            if [[ ${#repos[@]} -gt 0 ]]; then
                local repo_filter
                repo_filter=$(IFS='|'; echo "${repos[*]}")
                prs=$(echo "$prs" | jq "[.[] | select(.repo | test(\"(${repo_filter})$\"))]")
            fi

            last_fetch=$(date +%s)
            build_lines "$prs" "$stale_days"
        fi

        # Build the visible list
        local visible_lines=("${_lines[@]}")
        local visible_urls=("${_urls[@]}")
        local stale_label=""

        if [[ "$show_stale" == true ]]; then
            visible_lines+=("${_stale_lines[@]}")
            visible_urls+=("${_stale_urls[@]}")
        elif [[ ${#_stale_lines[@]} -gt 0 ]]; then
            stale_label=">> Show ${#_stale_lines[@]} older PRs (>${stale_days}d) <<"
        fi

        if [[ ${#visible_lines[@]} -eq 0 && ${#_stale_lines[@]} -eq 0 ]]; then
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

        local filter_items=("$refresh_label")
        if [[ -n "$stale_label" ]]; then
            filter_items+=("${visible_lines[@]}" "$stale_label")
        else
            filter_items+=("${visible_lines[@]}")
        fi

        selected=$(printf "%s\n" "${filter_items[@]}" | gum filter --header "$header") || return 0

        if [[ -z "$selected" ]]; then
            return 0
        fi

        if [[ "$selected" == "$refresh_label" ]]; then
            last_fetch=0
            show_stale=false
            continue
        fi

        if [[ -n "$stale_label" && "$selected" == "$stale_label" ]]; then
            show_stale=true
            continue
        fi

        # Find matching URL
        local i
        for i in "${!visible_lines[@]}"; do
            if [[ "${visible_lines[$i]}" == "$selected" ]]; then
                local action
                action=$(gum choose \
                    "Open in browser" \
                    "Copy URL" \
                    "View details" \
                    "Quit") || continue

                case "$action" in
                    "Open in browser")
                        if command -v open &>/dev/null; then
                            open "${visible_urls[$i]}"
                        elif command -v xdg-open &>/dev/null; then
                            xdg-open "${visible_urls[$i]}"
                        else
                            echo "${visible_urls[$i]}"
                        fi
                        ;;
                    "Copy URL")
                        if command -v pbcopy &>/dev/null; then
                            echo -n "${visible_urls[$i]}" | pbcopy
                            echo "Copied: ${visible_urls[$i]}"
                        elif command -v xclip &>/dev/null; then
                            echo -n "${visible_urls[$i]}" | xclip -selection clipboard
                            echo "Copied: ${visible_urls[$i]}"
                        else
                            echo "${visible_urls[$i]}"
                        fi
                        ;;
                    "View details")
                        gh pr view "${visible_urls[$i]}" || echo "Error: failed to fetch PR details" >&2
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

render_slack() {
    local prs="$1"

    local total
    total=$(echo "$prs" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 1
    fi

    echo "$prs" | jq -r '
        def ci_emoji:
            {"SUCCESS":":large_green_circle:","FAILURE":":red_circle:","ERROR":":red_circle:","PENDING":":large_yellow_circle:"}[.] // ":white_circle:";
        def review_emoji:
            {"APPROVED":":white_check_mark:","CHANGES_REQUESTED":":x:","REVIEW_REQUIRED":":eyes:"}[.] // "";
        def age:
            ((now - fromdate) / 3600) as $hours |
            if $hours < 1 then "\($hours * 60 | floor)m"
            elif $hours < 24 then "\($hours | floor)h"
            elif $hours < 168 then "\($hours / 24 | floor)d"
            elif $hours < 720 then "\($hours / 168 | floor)w"
            else "\($hours / 720 | floor)mo"
            end;
        group_by(.repo) | .[] |
        "*\(.[0].repo)*",
        (.[] |
            (.ci | ci_emoji) as $ci_e |
            ((.reviewDecision // "") | review_emoji) as $rv_e |
            "\u2022 " + $ci_e +
            (if $rv_e != "" then " " + $rv_e else "" end) +
            " " +
            (if .isDraft then "[draft] " else "" end) +
            "<\(.url)|#\(.number) \(.title)>" +
            " \u00b7 " + (.createdAt | age) +
            (if .reviewers and (.reviewers | length) > 0 then " \u00b7 " + (.reviewers | join(", ")) else "" end)
        ),
        ""
    '

    echo "_${total} open PR(s)._"
}

main() {
    local no_tui=false
    local include_draft=false
    local include_approved=false
    local json_output=false
    local slack_output=false
    local quiet=false
    local refresh_interval=300
    local stale_days=28
    local org_filter=""
    local created_before=""
    local created_after=""
    local -a positional_args=()

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
            --slack)
                slack_output=true
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
            --stale-after)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --stale-after requires a value" >&2
                    exit 1
                fi
                stale_days="$2"
                shift 2
                ;;
            -o|--org)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --org requires a value" >&2
                    exit 1
                fi
                org_filter="$2"
                shift 2
                ;;
            --created-before)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --created-before requires a value" >&2
                    exit 1
                fi
                if ! created_before=$(parse_since_date "$2"); then
                    exit 1
                fi
                shift 2
                ;;
            --created-after)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --created-after requires a value" >&2
                    exit 1
                fi
                if ! created_after=$(parse_since_date "$2"); then
                    exit 1
                fi
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
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    check_dependencies

    # Decide TUI vs plain
    local use_tui=false
    if [[ "$no_tui" != true ]] && [[ "$json_output" != true ]] && [[ "$slack_output" != true ]] && [[ "$quiet" != true ]] && [[ -t 1 ]] && command -v gum &>/dev/null; then
        use_tui=true
    fi

    if [[ "$use_tui" == true ]]; then
        render_interactive "$include_draft" "$include_approved" "$refresh_interval" "$stale_days" \
            "$org_filter" "$created_before" "$created_after" "${positional_args[@]}"
    else
        local prs
        prs=$(fetch_prs "$include_draft" "$include_approved")

        # Apply filters
        if [[ -n "$org_filter" ]]; then
            prs=$(echo "$prs" | jq "[.[] | select(.repo | startswith(\"${org_filter}/\"))]")
        fi
        if [[ -n "$created_before" ]]; then
            prs=$(echo "$prs" | jq "[.[] | select(.createdAt <= \"${created_before}T23:59:59Z\")]")
        fi
        if [[ -n "$created_after" ]]; then
            prs=$(echo "$prs" | jq "[.[] | select(.createdAt >= \"${created_after}T00:00:00Z\")]")
        fi
        if [[ ${#positional_args[@]} -gt 0 ]]; then
            local repo_filter
            repo_filter=$(IFS='|'; echo "${positional_args[*]}")
            prs=$(echo "$prs" | jq "[.[] | select(.repo | test(\"(${repo_filter})$\"))]")
        fi

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

        if [[ "$slack_output" == true ]]; then
            render_slack "$prs"
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
