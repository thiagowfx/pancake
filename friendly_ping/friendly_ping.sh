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

ARGUMENTS:
    REPO                    Optional repository names to filter by (e.g. tulip/terraform tulip/kiwi)

PREREQUISITES:
    - gh (GitHub CLI) - preferred, or curl as fallback
    - jq must be installed for JSON processing

EXAMPLES:
    $cmd                                                List all your open PRs
    $cmd --user alice                                   List all open PRs from user 'alice'
    $cmd --org helm                                     List your open PRs only in helm/* repos
    $cmd --since 2024-12-01                             List PRs created before 2024-12-01
    $cmd --since "60 days"                              List PRs created 60+ days ago
    $cmd thiagowfx/.dotfiles thiagowfx/pre-commit-hooks List PRs only from specific repos
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
    shift 5
    local -a repos=("$@")

    if [[ -z "$user" ]]; then
        echo "Error: GitHub username not provided and git user.name not configured" >&2
        exit 1
    fi

    local response

    if [[ "$method" == "gh" ]]; then
        # Use gh CLI - it handles authentication automatically
        if ! response=$(gh search prs --author="$user" --state=open --json title,url,repository,createdAt); then
            echo "Error: Failed to fetch PRs from GitHub CLI" >&2
            exit 1
        fi

        # Convert gh output to API-like format for consistent output
        response=$(echo "$response" | jq '[.[] | {title: .title, html_url: .url, repository_url: ("https://api.github.com/repos/" + .repository.nameWithOwner), created_at: .createdAt}]')

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
            format_pr_output_gh "$response"
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
            (.prs | map("  \(.title)\n  \(.html_url)") | join("\n\n")) +
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
            (.prs | map("  \(.title)\n  \(.html_url)") | join("\n\n")) +
            "\n") |
        join("\n")'
}

main() {
    local user=""
    local output_format="text"
    local quiet=false
    local org_filter=""
    local since_date=""
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
        fetch_open_prs "$user" "$output_format" "$method" "$org_filter" "$since_date" "${positional_args[@]}" > /dev/null
    else
        fetch_open_prs "$user" "$output_format" "$method" "$org_filter" "$since_date" "${positional_args[@]}"
    fi
}

main "$@"
