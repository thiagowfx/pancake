#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [REPO ...]

List all open GitHub pull requests created by you that are awaiting review.

Displays PRs grouped by repository, making it easy to see which of your
contributions still need attention from maintainers.

OPTIONS:
    -h, --help              Show this help message and exit
    -u, --user USER         GitHub username (defaults to current git user.name)
    -q, --quiet             Suppress output and only exit with status code
    -j, --json              Output results as JSON
    -o, --org ORG           Filter results to only show PRs from a specific organization
    -s, --since WHEN        Only show PRs created before WHEN (YYYY-MM-DD or relative like "60 days")
    -d, --detailed          Fetch detailed PR info including reviewers and assignees (slower)
    -g, --group-by FIELD    Group results by 'repo', 'user', 'reviewer', or 'assignee' (default: repo)

ARGUMENTS:
    REPO                    Optional repository names to filter by (e.g. thiagowfx/.dotfiles thiagowfx/pre-commit-hooks)

PREREQUISITES:
    - gh (GitHub CLI) - preferred, or curl as fallback
    - jq must be installed for JSON processing

EXAMPLES:
    $cmd                                                List all your open PRs
    $cmd --user alice                                   List all open PRs from user 'alice'
    $cmd --detailed                                     List PRs with reviewer and assignee info
    $cmd --org helm                                     List your open PRs only in helm/* repos
    $cmd --since 2024-12-01                             List PRs created before 2024-12-01
    $cmd --since "60 days"                              List PRs created 60+ days ago
    $cmd --group-by reviewer --detailed                 Group PRs by reviewer with details
    $cmd --group-by assignee --detailed                 Group PRs by assignee with details
    $cmd --org helm --since "1 week"                    Combine filters
    $cmd --json                                         Output results in JSON format
    $cmd -q && echo "You have open PRs" || echo "No open PRs"

ENVIRONMENT:
    GITHUB_TOKEN              Optional: GitHub API token for higher rate limits

EXIT CODES:
    0    Success (may or may not have open PRs)
    1    Error occurred
EOF
}

check_dependencies() {
    local missing_deps=()

    # jq is always required
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    # gh or curl is required (at least one)
    if ! command -v gh &> /dev/null && ! command -v curl &> /dev/null; then
        missing_deps+=("gh or curl")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        exit 1
    fi
}

get_method() {
    # Prefer gh, fall back to curl
    if command -v gh &> /dev/null; then
        echo "gh"
    elif command -v curl &> /dev/null; then
        echo "curl"
    else
        echo ""
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
        echo "Error: Invalid date format. Use YYYY-MM-DD or relative format like '60 days'" >&2
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

get_github_username() {
    local method="$1"

    # If using gh, get the authenticated user
    if [[ "$method" == "gh" ]]; then
        gh api user --jq '.login' 2>/dev/null || echo ""
    else
        # Try to get from git config
        local username
        username=$(git config --global user.name 2>/dev/null || echo "")

        if [[ -n "$username" ]]; then
            # Extract the first part if it contains spaces (First Last -> First)
            echo "${username%% *}"
        else
            echo ""
        fi
    fi
}

fetch_open_prs() {
    local user="$1"
    local output_format="$2"
    local method="$3"
    local org_filter="$4"
    local since_date="$5"
    local detailed="$6"
    local group_by="$7"
    shift 7
    local -a repos=("$@")

    if [[ -z "$user" ]]; then
        echo "Error: GitHub username not provided and git user.name not configured" >&2
        exit 1
    fi

    local response

    if [[ "$method" == "gh" ]]; then
        # Use gh CLI - it handles authentication automatically
        if ! response=$(gh search prs --author="$user" --state=open --json number,title,url,repository); then
            echo "Error: Failed to fetch PRs from GitHub CLI" >&2
            exit 1
        fi

        if [[ "$detailed" == "true" ]]; then
            # Fetch detailed data including reviewers and assignees for each PR
            # Note: This requires individual API calls, making it slower
            local -a prs_with_details=()
            while IFS= read -r line; do
                local number repo title url
                number=$(echo "$line" | jq -r '.number')
                repo=$(echo "$line" | jq -r '.repository.nameWithOwner')
                title=$(echo "$line" | jq -r '.title')
                url=$(echo "$line" | jq -r '.url')

                local assignees reviewers
                assignees=$(gh pr view "$number" --repo "$repo" --json assignees --jq '.assignees' 2>/dev/null || echo '[]')
                reviewers=$(gh pr view "$number" --repo "$repo" --json reviewRequests --jq '.reviewRequests' 2>/dev/null || echo '[]')

                prs_with_details+=("{\"title\":\"$title\",\"html_url\":\"$url\",\"repository_url\":\"https://api.github.com/repos/$repo\",\"assignees\":$assignees,\"reviewRequests\":$reviewers}")
            done < <(echo "$response" | jq -c '.[]')

            # Combine all into a single JSON array
            response=$(printf '[%s]' "$(IFS=','; echo "${prs_with_details[*]}")")
        else
            # Convert to standard format - no detailed reviewer/assignee data
            response=$(echo "$response" | jq '[.[] | {
                title: .title,
                html_url: .url,
                repository_url: ("https://api.github.com/repos/" + .repository.nameWithOwner),
                number: .number,
                repo: .repository.nameWithOwner,
                assignees: [],
                reviewRequests: []
            }]')
        fi

        # Filter by organization if specified
        if [[ -n "$org_filter" ]]; then
            response=$(echo "$response" | jq "[.[] | select(.repository_url | contains(\"/${org_filter}/\"))]")
        fi

        # Filter by specific repositories if specified
        if [[ ${#repos[@]} -gt 0 ]]; then
            local repo_filter
            repo_filter=$(IFS='|'; echo "${repos[*]}")
            response=$(echo "$response" | jq "[.[] | select(.repository_url | test(\"/(${repo_filter})$\"))]")
        fi

        # Filter by creation date if specified (show PRs created BEFORE this date)
        if [[ -n "$since_date" ]]; then
            response=$(echo "$response" | jq "[.[] | select(.created_at <= \"${since_date}T23:59:59Z\")]")
        fi

        if [[ "$output_format" == "json" ]]; then
            echo "$response" | jq '.'
        else
            case "$group_by" in
                user)
                    format_pr_output_by_user "$response"
                    ;;
                reviewer)
                    format_pr_output_by_reviewer "$response"
                    ;;
                assignee)
                    format_pr_output_by_assignee "$response"
                    ;;
                repo|"")
                    format_pr_output_gh "$response"
                    ;;
            esac
        fi
    else
        # Fallback to curl + GitHub API
        local api_url="https://api.github.com/search/issues?q=author:${user}+is:pr+is:open&sort=created&order=desc&per_page=100"
        local curl_opts=(
            -s
            -H "Accept: application/vnd.github.v3+json"
        )

        # Use GitHub token if available
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            curl_opts+=(-H "Authorization: token ${GITHUB_TOKEN}")
        fi

        response=$(curl "${curl_opts[@]}" "$api_url")

        # Check for API errors
        if echo "$response" | jq -e '.message' &>/dev/null; then
            local error_msg
            error_msg=$(echo "$response" | jq -r '.message')
            echo "Error: GitHub API error: $error_msg" >&2
            exit 1
        fi

        # Filter by organization if specified
        if [[ -n "$org_filter" ]]; then
            response=$(echo "$response" | jq "{total_count: (.items | map(select(.repository_url | contains(\"/${org_filter}/\"))) | length), items: (.items | map(select(.repository_url | contains(\"/${org_filter}/\"))))}")
        fi

        # Filter by specific repositories if specified
        if [[ ${#repos[@]} -gt 0 ]]; then
            local repo_filter
            repo_filter=$(IFS='|'; echo "${repos[*]}")
            response=$(echo "$response" | jq "{total_count: (.items | map(select(.repository_url | test(\"/(${repo_filter})$\"))) | length), items: (.items | map(select(.repository_url | test(\"/(${repo_filter})$\"))))}")
        fi

        # Filter by creation date if specified (show PRs created BEFORE this date)
        if [[ -n "$since_date" ]]; then
            response=$(echo "$response" | jq "{total_count: (.items | map(select(.created_at <= \"${since_date}T23:59:59Z\")) | length), items: (.items | map(select(.created_at <= \"${since_date}T23:59:59Z\")))}")
        fi

        if [[ "$output_format" == "json" ]]; then
            echo "$response" | jq '.'
        else
            format_pr_output "$response"
        fi
    fi
}

format_pr_output() {
    local response="$1"
    local total
    total=$(echo "$response" | jq '.total_count')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    echo "$response" | jq -r '.items | group_by(.repository_url | split("/") | .[-2:] | join("/")) |
        map({repo: .[0].repository_url | split("/") | .[-2:] | join("/"), prs: .}) |
        map("\(.repo)\n" +
            (.prs | map(
                "  \(.title)\n  \(.html_url)" +
                (if (.requested_reviewers | length) > 0 then "\n  Reviewers: \(.requested_reviewers | map(.login) | join(\", \"))" else "" end) +
                (if (.assignees | length) > 0 then "\n  Assignees: \(.assignees | map(.login) | join(\", \"))" else "" end)
            ) | join("\n\n")) +
            "\n") |
        join("\n")'
}

format_pr_output_gh() {
    local response="$1"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    echo "$response" | jq -r 'group_by(.repository_url | split("/") | .[-2:] | join("/")) |
        map({repo: .[0].repository_url | split("/") | .[-2:] | join("/"), prs: .}) |
        map("\(.repo)\n" +
            (.prs | map(
                "  \(.title)\n  \(.html_url)" +
                (if .reviewRequests and (.reviewRequests | length) > 0 then "\n  Reviewers: " + (.reviewRequests | map(.login) | join(", ")) else "" end) +
                (if .assignees and (.assignees | length) > 0 then "\n  Assignees: " + (.assignees | map(.login) | join(", ")) else "" end)
            ) | join("\n\n")) +
            "\n") |
        join("\n")'
}

format_pr_output_by_reviewer() {
    local response="$1"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    # Group by unique reviewers and display PRs for each reviewer
    echo "$response" | jq -r 'reduce (.[] | select(.reviewRequests and (.reviewRequests | length) > 0)) as $pr (
        {};
        reduce ($pr.reviewRequests | .[] | .login) as $reviewer (
            .;
            .[$reviewer] += [$pr]
        )
    ) |
    to_entries | sort_by(.key) | .[] |
    .key + "\n" +
    (.value | map(
        "  \(.title)\n  \(.html_url) (\(.repository_url | split("/") | .[-2:] | join("/")))" +
        (if .assignees and (.assignees | length) > 0 then "\n  Assigned to: " + (.assignees | map(.login) | join(", ")) else "" end)
    ) | join("\n\n")) + "\n"'
}

format_pr_output_by_assignee() {
    local response="$1"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    # Group by unique assignees and display PRs for each assignee
    echo "$response" | jq -r 'reduce (.[] | select(.assignees and (.assignees | length) > 0)) as $pr (
        {};
        reduce ($pr.assignees | .[] | .login) as $assignee (
            .;
            .[$assignee] += [$pr]
        )
    ) |
    to_entries | sort_by(.key) | .[] |
    .key + "\n" +
    (.value | map(
        "  \(.title)\n  \(.html_url) (\(.repository_url | split("/") | .[-2:] | join("/")))" +
        (if .reviewRequests and (.reviewRequests | length) > 0 then "\n  Requested reviewers: " + (.reviewRequests | map(.login) | join(", ")) else "" end)
    ) | join("\n\n")) + "\n"'
}

format_pr_output_by_user() {
    local response="$1"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    # Group by unique users (reviewers and assignees combined) and display PRs for each user
    echo "$response" | jq -r 'reduce .[] as $pr (
        {};
        reduce (
            ([$pr.reviewRequests // [] | .[] | .login] + [$pr.assignees // [] | .[] | .login] | unique) | .[]
        ) as $user (
            .;
            .[$user] += [$pr]
        )
    ) |
    to_entries | sort_by(.key) | .[] |
    .key + "\n" +
    (.value | map(
        "  \(.title)\n  \(.html_url) (\(.repository_url | split("/") | .[-2:] | join("/")))" +
        (
            (if .reviewRequests and (.reviewRequests | length) > 0 then "Reviewer" else "" end) +
            (if .assignees and (.assignees | length) > 0 then (if .reviewRequests and (.reviewRequests | length) > 0 then " + Assignee" else "Assignee" end) else "" end) |
            if . != "" then "\n  Role: " + . else "" end
        )
    ) | join("\n\n")) + "\n"'
}

main() {
    local user=""
    local output_format="text"
    local quiet=false
    local org_filter=""
    local since_date=""
    local detailed=false
    local group_by=""
    local -a positional_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -u|--user)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --user requires a value" >&2
                    exit 1
                fi
                user="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -j|--json)
                output_format="json"
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
            -s|--since)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --since requires a value" >&2
                    exit 1
                fi
                if ! since_date=$(parse_since_date "$2"); then
                    exit 1
                fi
                shift 2
                ;;
            -d|--detailed)
                detailed=true
                shift
                ;;
            -g|--group-by)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --group-by requires a value (repo, user, reviewer, or assignee)" >&2
                    exit 1
                fi
                if [[ "$2" != "repo" && "$2" != "repository" && "$2" != "user" && "$2" != "reviewer" && "$2" != "assignee" ]]; then
                    echo "Error: --group-by must be 'repo', 'repository', 'user', 'reviewer', or 'assignee'" >&2
                    exit 1
                fi
                # Normalize "repository" to "repo"
                if [[ "$2" == "repository" ]]; then
                    group_by="repo"
                else
                    group_by="$2"
                fi
                shift 2
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                # Collect positional arguments (repository names)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    check_dependencies

    # Validate that --group-by user/reviewer/assignee requires --detailed
    if [[ "$group_by" == "user" || "$group_by" == "reviewer" || "$group_by" == "assignee" ]] && [[ "$detailed" != "true" ]]; then
        echo "Error: --group-by user/reviewer/assignee requires --detailed flag" >&2
        exit 1
    fi

    # Get the preferred method (gh or curl)
    local method
    method=$(get_method)

    # Get username if not provided
    if [[ -z "$user" ]]; then
        user=$(get_github_username "$method")
    fi

    if [[ -z "$user" ]]; then
        echo "Error: Could not determine GitHub username. Please use --user option." >&2
        exit 1
    fi

    if [[ "$quiet" == true ]]; then
        fetch_open_prs "$user" "$output_format" "$method" "$org_filter" "$since_date" "$detailed" "$group_by" "${positional_args[@]}" > /dev/null
    else
        fetch_open_prs "$user" "$output_format" "$method" "$org_filter" "$since_date" "$detailed" "$group_by" "${positional_args[@]}"
    fi
}

main "$@"
