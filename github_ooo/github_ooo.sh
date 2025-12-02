#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [DATE] [EMOJI] [MESSAGE...]

Set or clear GitHub status to Out of Office.

This script sets your GitHub user status to out of office, automatically
clearing it at the end of the specified date. Optionally include an emoji
and status message. Requires a GitHub Personal Access Token with 'user'
scope.

ARGUMENTS:
    DATE            End date for OOO status (YYYY-MM-DD format, omit with --clear)
    EMOJI           Optional emoji to display in status
    MESSAGE...      Optional status message (remaining arguments joined)

OPTIONS:
    -c, --clear     Clear the current status immediately
    -h, --help      Show this help message and exit

ENVIRONMENT:
    GITHUB_PAT      GitHub Personal Access Token (required)

EXAMPLES:
    $cmd 2025-12-25                      Set OOO until Christmas
    $cmd 2025-12-25 🏖️                    Add an emoji
    $cmd 2025-12-25 🏖️ "Enjoying the sun"  With message and emoji
    $cmd 2025-12-25 "Away for the holidays"  Message without emoji
    $cmd --clear                         Clear status immediately

EXIT CODES:
    0    Status set/cleared successfully
    1    Missing token, invalid date, or API request failed
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "-c" ]] || [[ "${1:-}" == "--clear" ]]; then
    CLEAR_STATUS=1
    shift || true
else
    CLEAR_STATUS=0
fi

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "curl"
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
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

validate_date() {
    local date="$1"
    # Validate YYYY-MM-DD format and that it's a valid date
    if ! [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: Invalid date format. Use YYYY-MM-DD"
        exit 1
    fi
}

build_graphql_query() {
    local expiration="${1:-}"
    local emoji="${2:-}"
    local message="${3:-}"

    local status_emoji=""
    local status_message=""

    if [[ -n "$emoji" ]]; then
        status_emoji="$emoji"
    fi

    if [[ -n "$message" ]]; then
        status_message="$message"
    fi

    # Build full message, trimming extra spaces
    local full_message
    if [[ -n "$status_emoji" ]] && [[ -n "$status_message" ]]; then
        full_message="$status_emoji $status_message"
    elif [[ -n "$status_emoji" ]]; then
        full_message="$status_emoji"
    elif [[ -n "$status_message" ]]; then
        full_message="$status_message"
    else
        full_message="Out of office"
    fi

    # Escape for JSON
    status_emoji=$(printf '%s' "$status_emoji" | jq -Rs .)
    full_message=$(printf '%s' "$full_message" | jq -Rs .)

    # Build GraphQL with optional expiration
    local graphql_query
    if [[ -n "$expiration" ]]; then
        graphql_query="mutation { changeUserStatus(input: {emoji: $status_emoji, message: $full_message, expiresAt: \"${expiration}T23:59:59Z\"}) { clientMutationId } }"
    else
        graphql_query="mutation { changeUserStatus(input: {emoji: $status_emoji, message: $full_message}) { clientMutationId } }"
    fi

    jq -n --arg q "$graphql_query" '{query: $q}'
}

main() {
    check_dependencies

    # Check for GitHub token
    if [[ -z "${GITHUB_PAT:-}" ]]; then
        echo "Error: GITHUB_PAT environment variable not set"
        exit 1
    fi

    if [[ $CLEAR_STATUS -eq 1 ]]; then
        # Clear status mode
        echo "Clearing GitHub status..."

        # Build the GraphQL mutation without any status
        local query
        query=$(jq -n '{query: "mutation { changeUserStatus(input: {emoji: \"\", message: \"\"}) { clientMutationId } }"}')

        # Send the request
        local response
        response=$(curl -s -X POST \
            -H "Authorization: Bearer $GITHUB_PAT" \
            -H "Content-Type: application/json" \
            -d "$query" \
            https://api.github.com/graphql)

        # Check for errors
        if echo "$response" | jq -e '.errors' &>/dev/null; then
            echo "Error: Failed to clear GitHub status"
            echo "$response" | jq '.'
            exit 1
        fi

        # Also check if we got empty or invalid response
        if ! echo "$response" | jq -e '.data.changeUserStatus' &>/dev/null; then
            echo "Error: Unexpected API response"
            echo "$response" | jq '.'
            exit 1
        fi

        echo "✓ GitHub status cleared"
        return 0
    fi

    # Set status mode
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local date="$1"
    local emoji="${2:-}"
    local message=""

    if [[ $# -gt 2 ]]; then
        shift 2
        message="$*"
    fi

    validate_date "$date"

    echo "Setting GitHub status to OOO until $date..."

    # Build the GraphQL mutation
    local query
    query=$(build_graphql_query "$date" "$emoji" "$message")

    # Send the request
    local response
    response=$(curl -s -X POST \
        -H "Authorization: Bearer $GITHUB_PAT" \
        -H "Content-Type: application/json" \
        -d "$query" \
        https://api.github.com/graphql)

    # Check for errors
    if echo "$response" | jq -e '.errors' &>/dev/null; then
        echo "Error: Failed to set GitHub status"
        echo "$response" | jq '.'
        exit 1
    fi

    # Also check if we got empty or invalid response
    if ! echo "$response" | jq -e '.data.changeUserStatus' &>/dev/null; then
        echo "Error: Unexpected API response"
        echo "$response" | jq '.'
        exit 1
    fi

    echo "✓ GitHub status set to OOO until $date"
    if [[ -n "$emoji" ]] || [[ -n "$message" ]]; then
        echo "  Status: $emoji $message"
    fi
}

main "$@"
