#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [REPO ...]

List open GitHub pull requests where your review is requested.

The complement of friendly_ping: instead of "who's blocking me?", this
answers "who am I blocking?"

OPTIONS:
    -h, --help               Show this help message and exit
    --json                   Output raw JSON
    --slack                  Output as Slack mrkdwn (for pasting into Slack)
    --include-draft          Include draft PRs (excluded by default)
    --include-teams           Include PRs where review was requested via team (excluded by default)
    -o, --org ORG            Filter PRs to a specific organization
    --created-before WHEN    Only show PRs created before WHEN (YYYY-MM-DD or relative like "60 days")
    --created-after WHEN     Only show PRs created after WHEN (YYYY-MM-DD or relative like "60 days")
    -q, --quiet              Exit 0 if PRs exist, 1 if none (no output)

ARGUMENTS:
    REPO                     Filter by specific repositories (e.g. helm/helm tulip/terraform)

PREREQUISITES:
    - gh (GitHub CLI) must be installed and authenticated
    - jq must be installed for JSON processing

EXAMPLES:
    $cmd                                  List PRs awaiting your review
    $cmd --json                           Dump raw JSON for scripting
    $cmd --json | jq '.[].title'          List just titles
    $cmd --slack                          Output Slack mrkdwn for pasting
    $cmd --slack | pbcopy                 Copy Slack-formatted summary
    $cmd -o helm                          Only show PRs from the helm org
    $cmd --created-before "7 days"        Only show PRs older than 7 days
    $cmd --created-after 2025-01-01       Only show PRs created after a date
    $cmd helm/helm tulip/terraform        Only show PRs from specific repos
    $cmd --include-teams                       Include team-based review requests
    $cmd -q && echo "reviews pending"     Check if you have reviews pending

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

    if [[ "$when" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$when"
        return 0
    fi

    local num unit
    if [[ "$when" =~ ^([0-9]+)\ +(day|week|month|year)s?$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        echo "Error: invalid date format. Use YYYY-MM-DD or relative format like '60 days'" >&2
        return 1
    fi

    local days=0
    case "$unit" in
        day) days=$num ;;
        week) days=$((num * 7)) ;;
        month) days=$((num * 30)) ;;
        year) days=$((num * 365)) ;;
    esac

    local result
    if date --version &>/dev/null 2>&1; then
        result=$(date -d "$days days ago" +%Y-%m-%d)
    else
        result=$(date -v-"${days}"d +%Y-%m-%d)
    fi

    echo "$result"
}

fetch_prs() {
    local include_draft="$1"
    local include_team="$2"

    local query_str="review-requested:@me is:pr is:open"
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
                        author {
                            login
                        }
                        repository {
                            nameWithOwner
                        }
                        reviewRequests(first: 20) {
                            nodes {
                                requestedReviewer {
                                    ... on User { login }
                                    ... on Team { name }
                                    __typename
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
        author: (.author.login // "unknown"),
        repo: .repository.nameWithOwner,
        ci: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
        hasDirectRequest: ([.reviewRequests.nodes[].requestedReviewer | select(.__typename == "User")] | length > 0)
    }]'

    if [[ "$include_team" != "true" ]]; then
        jq_filter="${jq_filter} | [.[] | select(.hasDirectRequest)]"
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

render_plain() {
    local prs="$1"
    local use_color="$2"

    local total
    total=$(echo "$prs" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No reviews pending."
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
            local number title is_draft ci author created_at age
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            is_draft=$(echo "$pr" | jq -r '.isDraft')
            ci=$(echo "$pr" | jq -r '.ci')
            author=$(echo "$pr" | jq -r '.author')
            created_at=$(echo "$pr" | jq -r '.createdAt')
            age=$(format_age "$created_at")

            # Truncate title
            local max_title=60
            local display_title="$title"
            if [[ ${#display_title} -gt $max_title ]]; then
                display_title="${display_title:0:$((max_title - 3))}..."
            fi

            local draft_indicator=""
            if [[ "$is_draft" == "true" ]]; then
                draft_indicator=" [draft]"
            fi

            printf '  #%-5s ' "$number"
            printf '%-63s ' "${display_title}${draft_indicator}"
            format_ci "$ci" "$use_color"
            printf ' %4s  <- %s\n' "$age" "$author"
        done < <(echo "$repo_prs" | jq -c '.[]')
        echo ""
    done < <(echo "$prs" | jq -r '[.[].repo] | unique | .[]')

    echo "$total review(s) pending."
}

render_slack() {
    local prs="$1"

    local total
    total=$(echo "$prs" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No reviews pending."
        return 1
    fi

    echo "$prs" | jq -r '
        def ci_emoji:
            {"SUCCESS":":large_green_circle:","FAILURE":":red_circle:","ERROR":":red_circle:","PENDING":":large_yellow_circle:"}[.] // ":white_circle:";
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
            "\u2022 " + $ci_e +
            " " +
            (if .isDraft then "[draft] " else "" end) +
            "<\(.url)|#\(.number) \(.title)>" +
            " \u00b7 " + (.createdAt | age) +
            " \u00b7 by " + .author
        ),
        ""
    '

    echo "_${total} review(s) pending._"
}

main() {
    local include_draft=false
    local include_team=false
    local json_output=false
    local slack_output=false
    local quiet=false
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
            --include-draft)
                include_draft=true
                shift
                ;;
            --include-teams)
                include_team=true
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

    local prs
    prs=$(fetch_prs "$include_draft" "$include_team")

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
        echo "No reviews pending."
        exit 1
    fi

    local use_color=false
    if [[ -t 1 ]]; then
        use_color=true
    fi
    render_plain "$prs" "$use_color"
}

main "$@"
