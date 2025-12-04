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
    -u, --user USER         Filter PRs created by USER (defaults to current git user.name)
    --involves USER         Filter PRs where USER is a reviewer or assignee
    -q, --quiet             Suppress output and only exit with status code
    -j, --json              Output results as JSON
    -o, --org ORG           Filter results to only show PRs from a specific organization
    --created-before WHEN   Only show PRs created before WHEN (YYYY-MM-DD or relative like "60 days")
    --created-after WHEN    Only show PRs created after WHEN (YYYY-MM-DD or relative like "60 days")
    -d, --detailed          Fetch detailed PR info including reviewers and assignees (slower)
    -g, --group-by FIELD    Group results by 'repo', 'user', 'reviewer', or 'assignee' (default: repo)
    --include-approved      Include approved PRs in results (only effective with --detailed; skipped by default)

ARGUMENTS:
    REPO                    Optional repository names to filter by (e.g. thiagowfx/.dotfiles thiagowfx/pre-commit-hooks)

PREREQUISITES:
    - gh (GitHub CLI) - preferred, or curl as fallback
    - jq must be installed for JSON processing

EXAMPLES:
    $cmd                                                List all your open PRs (excluding approved)
    $cmd --user alice                                   List all open PRs created by user 'alice'
    $cmd --involves alice --detailed                    List PRs where alice is a reviewer or assignee
    $cmd --detailed                                     List PRs with reviewer and assignee info
    $cmd --include-approved                             Include approved PRs in results
    $cmd --org helm                                     List your open PRs only in helm/* repos
    $cmd --created-before 2024-12-01                    List PRs created before 2024-12-01
    $cmd --created-after "60 days"                      List PRs created after 60 days ago
    $cmd --created-before 2024-12-01 --created-after "1 week"  Combine date filters
    $cmd --group-by reviewer --detailed                 Group PRs by reviewer with details
    $cmd --group-by assignee --detailed                 Group PRs by assignee with details
    $cmd --org helm --created-before "1 week"           Combine filters
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
    local involves_user="$5"
    local created_before="$6"
    local created_after="$7"
    local detailed="$8"
    local group_by="$9"
    local include_approved="${10}"
    shift 10
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

                # Fetch review decision, assignees, and approvers
                local review_decision assignees reviewers approvers
                review_decision=$(gh pr view "$number" --repo "$repo" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo 'null')

                # Skip if overall PR is approved and we're grouping by repo (not by person)
                if [[ "$include_approved" != "true" && "$review_decision" == "APPROVED" && "$group_by" == "repo" ]]; then
                    continue
                fi

                assignees=$(gh pr view "$number" --repo "$repo" --json assignees --jq '.assignees' 2>/dev/null || echo '[]')
                reviewers=$(gh pr view "$number" --repo "$repo" --json reviewRequests --jq '.reviewRequests' 2>/dev/null || echo '[]')

                # Fetch who has approved the PR (for person-based grouping)
                approvers=$(gh pr view "$number" --repo "$repo" --json reviews --jq '[.reviews[] | select(.state == "APPROVED") | .author.login]' 2>/dev/null || echo '[]')

                prs_with_details+=("{\"title\":\"$title\",\"html_url\":\"$url\",\"repository_url\":\"https://api.github.com/repos/$repo\",\"assignees\":$assignees,\"reviewRequests\":$reviewers,\"approvers\":$approvers}")
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

        # Filter by involves user if specified (reviewer or assignee)
        if [[ -n "$involves_user" ]]; then
            response=$(echo "$response" | jq "[.[] | select(
                (.reviewRequests // [] | map(.login) | index(\"$involves_user\")) or
                (.assignees // [] | map(.login) | index(\"$involves_user\"))
            )]")
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

        # Filter by creation date if specified
        if [[ -n "$created_before" ]]; then
            response=$(echo "$response" | jq "[.[] | select(.created_at <= \"${created_before}T23:59:59Z\")]")
        fi
        if [[ -n "$created_after" ]]; then
            response=$(echo "$response" | jq "[.[] | select(.created_at >= \"${created_after}T00:00:00Z\")]")
        fi

        if [[ "$output_format" == "json" ]]; then
            echo "$response" | jq '.'
        else
            case "$group_by" in
                user)
                    format_pr_output_by_user "$response" "$include_approved"
                    ;;
                reviewer)
                    format_pr_output_by_reviewer "$response" "$include_approved"
                    ;;
                assignee)
                    format_pr_output_by_assignee "$response" "$include_approved"
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

        # Filter by involves user if specified (reviewer or assignee)
        if [[ -n "$involves_user" ]]; then
            response=$(echo "$response" | jq "{total_count: (.items | map(select(
                (.requested_reviewers // [] | map(.login) | index(\"$involves_user\")) or
                (.assignees // [] | map(.login) | index(\"$involves_user\"))
            )) | length), items: (.items | map(select(
                (.requested_reviewers // [] | map(.login) | index(\"$involves_user\")) or
                (.assignees // [] | map(.login) | index(\"$involves_user\"))
            )))}")
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

        # Filter by creation date if specified
        if [[ -n "$created_before" ]]; then
            response=$(echo "$response" | jq "{total_count: (.items | map(select(.created_at <= \"${created_before}T23:59:59Z\")) | length), items: (.items | map(select(.created_at <= \"${created_before}T23:59:59Z\")))}")
        fi
        if [[ -n "$created_after" ]]; then
            response=$(echo "$response" | jq "{total_count: (.items | map(select(.created_at >= \"${created_after}T00:00:00Z\")) | length), items: (.items | map(select(.created_at >= \"${created_after}T00:00:00Z\")))}")
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
    local include_approved="$2"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    # Group by unique reviewers and display PRs for each reviewer
    # Skip PRs where the reviewer has already approved (unless --include-approved)
    echo "$response" | jq -r 'reduce (.[] | select(.reviewRequests and (.reviewRequests | length) > 0)) as $pr (
        {};
        reduce ($pr.reviewRequests | .[] | select(.login) | .login) as $reviewer (
            .;
            if ("'"$include_approved"'" == "true" or ($pr.approvers // [] | index($reviewer) | not)) then
                .[$reviewer] += [$pr]
            else
                .
            end
        )
    ) |
    to_entries | sort_by(.key) | .[] |
    select(.value | length > 0) |
    .key + "\n" +
    (.value | map(
        "  \(.title)\n  \(.html_url // "N/A") (\(.repository_url | split("/") | .[-2:] | join("/")))" +
        (if .assignees and (.assignees | length) > 0 then "\n  Assigned to: " + (.assignees | map(.login | select(.)) | join(", ")) else "" end)
    ) | join("\n\n")) + "\n"'
}

format_pr_output_by_assignee() {
    local response="$1"
    local include_approved="$2"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    # Group by unique assignees and display PRs for each assignee
    # Skip PRs where the assignee has already approved (unless --include-approved)
    echo "$response" | jq -r 'reduce (.[] | select(.assignees and (.assignees | length) > 0)) as $pr (
        {};
        reduce ($pr.assignees | .[] | select(.login) | .login) as $assignee (
            .;
            if ("'"$include_approved"'" == "true" or ($pr.approvers // [] | index($assignee) | not)) then
                .[$assignee] += [$pr]
            else
                .
            end
        )
    ) |
    to_entries | sort_by(.key) | .[] |
    select(.value | length > 0) |
    .key + "\n" +
    (.value | map(
        "  \(.title)\n  \(.html_url // "N/A") (\(.repository_url | split("/") | .[-2:] | join("/")))" +
        (if .reviewRequests and (.reviewRequests | length) > 0 then "\n  Requested reviewers: " + (.reviewRequests | map(.login | select(.)) | join(", ")) else "" end)
    ) | join("\n\n")) + "\n"'
}

format_pr_output_by_user() {
    local response="$1"
    local include_approved="$2"
    local total
    total=$(echo "$response" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "No open PRs found."
        return 0
    fi

    # Group by unique users (reviewers and assignees combined) and display PRs for each user
    # Skip PRs where the user has already approved (unless --include-approved)
    echo "$response" | jq -r 'reduce .[] as $pr (
        {};
        reduce (
            ([$pr.reviewRequests // [] | .[] | select(.login) | .login] + [$pr.assignees // [] | .[] | select(.login) | .login] | unique) | .[]
        ) as $user (
            .;
            if ("'"$include_approved"'" == "true" or ($pr.approvers // [] | index($user) | not)) then
                .[$user] += [$pr]
            else
                .
            end
        )
    ) |
    to_entries | sort_by(.key) | .[] |
    select(.value | length > 0) |
    .key + "\n" +
    (.value | map(
        "  \(.title)\n  \(.html_url // "N/A") (\(.repository_url | split("/") | .[-2:] | join("/")))" +
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
    local involves_user=""
    local created_before=""
    local created_after=""
    local detailed=false
    local group_by=""
    local include_approved=false
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
            --involves)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --involves requires a value" >&2
                    exit 1
                fi
                involves_user="$2"
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
            --include-approved)
                include_approved=true
                shift
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

    # Validate that certain options require --detailed
    if [[ "$detailed" != "true" ]]; then
        if [[ "$group_by" == "user" || "$group_by" == "reviewer" || "$group_by" == "assignee" ]]; then
            echo "Error: --group-by user/reviewer/assignee requires --detailed flag" >&2
            exit 1
        fi
        if [[ -n "$involves_user" ]]; then
            echo "Error: --involves requires --detailed flag" >&2
            exit 1
        fi
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
        fetch_open_prs "$user" "$output_format" "$method" "$org_filter" "$involves_user" "$created_before" "$created_after" "$detailed" "$group_by" "$include_approved" "${positional_args[@]}" > /dev/null
    else
        fetch_open_prs "$user" "$output_format" "$method" "$org_filter" "$involves_user" "$created_before" "$created_after" "$detailed" "$group_by" "$include_approved" "${positional_args[@]}"
    fi
}

main "$@"
