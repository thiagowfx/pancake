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
    -o, --org ORG   Limit status visibility to specific organization
    -h, --help      Show this help message and exit

ENVIRONMENT:
    GITHUB_TOKEN    GitHub Personal Access Token (required)

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

CLEAR_STATUS=0
ORG_NAME=""

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--clear)
            CLEAR_STATUS=1
            shift
            ;;
        -o|--org)
            ORG_NAME="${2:-}"
            if [[ -z "$ORG_NAME" ]]; then
                echo "Error: --org requires an organization name"
                exit 1
            fi
            shift 2
            ;;
        -*)
            echo "Error: Unknown option ${1}"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

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

get_org_id() {
    local org_name="$1"

    local query
    query=$(jq -n --arg org "$org_name" --arg login "$org_name" \
        '{query: "query { organization(login: \($login | @json)) { id } }"}')

    local response
    response=$(curl -s -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$query" \
        https://api.github.com/graphql)

    # Check for errors
    if echo "$response" | jq -e '.errors' &>/dev/null; then
        echo "Error: Failed to look up organization '$org_name'"
        echo "$response" | jq '.'
        exit 1
    fi

    # Extract and return the organization ID
    echo "$response" | jq -r '.data.organization.id'
}

emoji_shorthand_to_unicode() {
    local shorthand="$1"

    # If not in shorthand format, return as-is
    if ! [[ "$shorthand" =~ ^:[a-z_]+:$ ]]; then
        echo "$shorthand"
        return 0
    fi

    # Convert common emoji shorthands
    case "$shorthand" in
        # keep-sorted start
        :+1:) echo "👍" ;;
        :-1:) echo "👎" ;;
        :airplane:) echo "✈️" ;;
        :airplane_arriving:) echo "🛬" ;;
        :airplane_departing:) echo "🛫" ;;
        :balloon:) echo "🎈" ;;
        :beach:) echo "🏖️" ;;
        :beach_with_umbrella:) echo "🏖️" ;;
        :bed:) echo "🛏️" ;;
        :blue_heart:) echo "💙" ;;
        :camping:) echo "🏕️" ;;
        :christmas_tree:) echo "🎄" ;;
        :confetti_ball:) echo "🎊" ;;
        :fire:) echo "🔥" ;;
        :gift:) echo "🎁" ;;
        :green_heart:) echo "💚" ;;
        :grinning:) echo "😀" ;;
        :heart:) echo "❤️" ;;
        :house_with_garden:) echo "🏡" ;;
        :juggling_person:) echo "🤹" ;;
        :mountain:) echo "⛰️" ;;
        :muscle:) echo "💪" ;;
        :ok_hand:) echo "👌" ;;
        :partying_face:) echo "🥳" ;;
        :person_cartwheeling:) echo "🤸" ;;
        :pray:) echo "🙏" ;;
        :purple_heart:) echo "💜" ;;
        :raising_hand:) echo "🙋" ;;
        :relaxed:) echo "☺️" ;;
        :rocket:) echo "🚀" ;;
        :sailboat:) echo "⛵" ;;
        :santa:) echo "🎅" ;;
        :sleeping:) echo "😴" ;;
        :smile:) echo "😄" ;;
        :sparkles:) echo "✨" ;;
        :star:) echo "⭐" ;;
        :sun:) echo "☀️" ;;
        :sunny:) echo "☀️" ;;
        :surfing:) echo "🏄" ;;
        :surfing_woman:) echo "🏄‍♀️" ;;
        :swimming:) echo "🏊" ;;
        :swimming_woman:) echo "🏊‍♀️" ;;
        :tada:) echo "🎉" ;;
        :tent:) echo "⛺" ;;
        :thumbsdown:) echo "👎" ;;
        :thumbsup:) echo "👍" ;;
        :wave:) echo "👋" ;;
        :yellow_heart:) echo "💛" ;;
        :zzz:) echo "💤" ;;
        # keep-sorted end
        *) echo "$shorthand" ;;
    esac
}

build_graphql_query() {
    local expiration="${1:-}"
    local emoji="${2:-}"
    local message="${3:-}"
    local org_id="${4:-}"

    local status_emoji=""
    local status_message=""

    if [[ -n "$emoji" ]]; then
        status_emoji=$(emoji_shorthand_to_unicode "$emoji")
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

    # Build optional org visibility field
    local org_field=""
    if [[ -n "$org_id" ]]; then
        org_field=", organizationId: \"$org_id\""
    fi

    # Build GraphQL with optional expiration and busy indicator
    local graphql_query
    if [[ -n "$expiration" ]]; then
        graphql_query="mutation { changeUserStatus(input: {emoji: $status_emoji, message: $full_message, expiresAt: \"${expiration}T23:59:59Z\", limitedAvailability: true$org_field}) { clientMutationId } }"
    else
        graphql_query="mutation { changeUserStatus(input: {emoji: $status_emoji, message: $full_message, limitedAvailability: true$org_field}) { clientMutationId } }"
    fi

    jq -n --arg q "$graphql_query" '{query: $q}'
}

main() {
    check_dependencies

    # Check for GitHub token
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "Error: GITHUB_TOKEN environment variable not set"
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
            -H "Authorization: Bearer $GITHUB_TOKEN" \
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
    shift 1 || true
    shift 1 || true

    # Parse remaining arguments, looking for --org
    local message=""
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -o|--org)
                ORG_NAME="${2:-}"
                if [[ -z "$ORG_NAME" ]]; then
                    echo "Error: --org requires an organization name"
                    exit 1
                fi
                shift 2
                ;;
            *)
                if [[ -z "$message" ]]; then
                    message="$1"
                else
                    message="$message $1"
                fi
                shift
                ;;
        esac
    done

    validate_date "$date"

    # Look up org ID if provided
    local org_id=""
    if [[ -n "$ORG_NAME" ]]; then
        echo "Looking up organization '$ORG_NAME'..."
        org_id=$(get_org_id "$ORG_NAME")
        if [[ -z "$org_id" ]] || [[ "$org_id" == "null" ]]; then
            echo "Error: Organization '$ORG_NAME' not found"
            exit 1
        fi
    fi

    echo "Setting GitHub status to OOO until $date..."

    # Build the GraphQL mutation
    local query
    query=$(build_graphql_query "$date" "$emoji" "$message" "$org_id")

    # Send the request
    local response
    response=$(curl -s -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
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
        # Convert emoji for display
        local display_emoji
        display_emoji=$(emoji_shorthand_to_unicode "$emoji")
        echo "  Status: $display_emoji $message"
    fi
}

main "$@"
