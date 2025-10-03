#!/bin/bash
# shellcheck disable=SC2317
set -uo pipefail

DEFAULT_AWS_PROFILE="${DEFAULT_AWS_PROFILE:-china}"
SESSION_DURATION="${SESSION_DURATION:-86400}"

# Check if script is being sourced
(return 0 2>/dev/null) && sourced=1 || sourced=0

# Only set -e when executed, not when sourced (to avoid exiting user's shell)
if [[ $sourced -eq 0 ]]; then
    set -e
fi

usage() {
    cat << EOF
Usage: source $0 [OPTIONS] [AWS_PROFILE]
   or: eval "\$($0 [OPTIONS] [AWS_PROFILE])"

Authenticate to AWS China using MFA and export temporary session credentials.

POSITIONAL ARGUMENTS:
    AWS_PROFILE    AWS profile name (default: $DEFAULT_AWS_PROFILE)

OPTIONS:
    -h, --help    Show this help message and exit

DESCRIPTION:
    This script can be sourced or executed with eval to set AWS session credentials.
    It prompts for an MFA token, retrieves temporary session credentials, and
    exports them as environment variables.

    When sourced: exports variables directly to your current shell
    When executed: prints export commands to stdout

PREREQUISITES:
    - AWS CLI must be installed and configured
    - 'jq' must be installed for JSON parsing
    - AWS profile must have MFA device configured

EXAMPLES:
    source $0                      Use default profile ($DEFAULT_AWS_PROFILE)
    source $0 my-china-profile     Use custom profile
    eval "\$($0)"                  Execute with eval (default profile)
    eval "\$($0 my-china-profile)" Execute with eval (custom profile)
    $0 --help                      Show this help

NOTES:
    - Session credentials are valid for $SESSION_DURATION seconds (24 hours)
    - Exported variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, AWS_PROFILE

EXIT CODES:
    0    Credentials successfully exported
    1    Error occurred during authentication
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    return 0 2>/dev/null || exit 0
fi

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "aws"
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
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        return 1
    fi
}

set_credentials() {
    local mode="$1"
    local profile="$2"
    local access_key="$3"
    local secret_key="$4"
    local session_token="$5"

    if [[ $mode -eq 1 ]]; then
        # Sourced mode: export directly
        export AWS_PROFILE="$profile"
        export AWS_ACCESS_KEY_ID="$access_key"
        export AWS_SECRET_ACCESS_KEY="$secret_key"
        export AWS_SESSION_TOKEN="$session_token"
    else
        # Execution mode: print export commands
        echo ""
        echo -e "  export AWS_PROFILE='$profile'"
        echo -e "  export AWS_ACCESS_KEY_ID='$access_key'"
        echo -e "  export AWS_SECRET_ACCESS_KEY='$secret_key'"
        echo -e "  export AWS_SESSION_TOKEN='$session_token'"
    fi
}

main() {
    check_dependencies

    local aws_profile="${1:-$DEFAULT_AWS_PROFILE}"

    if [[ $sourced -eq 0 ]]; then
        echo "Note: Script is being executed. To apply credentials, run:" >&2
        echo "  eval \"\$($0 $aws_profile)\"" >&2
        echo "" >&2
    fi

    echo "Using AWS profile: $aws_profile" >&2
    echo -n "Enter the MFA token code for your AWS China account: " >&2

    read -r token

    if [[ -z "$token" ]]; then
        echo "Error: MFA token cannot be empty" >&2
        return 1
    fi

    echo "Retrieving MFA device ARN..." >&2

    local mfa_arn
    mfa_arn="$(aws iam --profile "$aws_profile" get-user --output text --query User.Arn 2>/dev/null | sed 's|:user/|:mfa/|')"

    if [[ -z "$mfa_arn" ]]; then
        echo "Error: Could not retrieve MFA device ARN" >&2
        return 1
    fi

    echo "Requesting session token..." >&2

    local credentials
    if ! credentials=$(aws --profile "$aws_profile" sts get-session-token --serial-number "$mfa_arn" --token-code "$token" --duration-seconds "$SESSION_DURATION" 2>&1); then
        echo "" >&2
        echo "Error: Failed to retrieve session token." >&2
        echo "$credentials" >&2
        return 1
    fi

    local access_key secret_key session_token
    access_key=$(echo "$credentials" | jq -r '.Credentials.AccessKeyId')
    secret_key=$(echo "$credentials" | jq -r '.Credentials.SecretAccessKey')
    session_token=$(echo "$credentials" | jq -r '.Credentials.SessionToken')

    if [[ -z "$session_token" ]] || [[ "$session_token" == "null" ]]; then
        echo "Error: Failed to extract session token from credentials" >&2
        return 1
    fi

    set_credentials "$sourced" "$aws_profile" "$access_key" "$secret_key" "$session_token"

    if [[ $sourced -eq 1 ]]; then
        echo "" >&2
        echo "✓ Successfully authenticated to AWS China" >&2
        echo "" >&2
        echo "Exported AWS credentials:" >&2
        echo "" >&2
        env | grep '^AWS_' | sort >&2
    else
        echo "" >&2
        echo "✓ Successfully authenticated to AWS China" >&2
        echo "" >&2
        echo "Copy and paste the export commands above to apply credentials." >&2
    fi
}

main "$@"

# TODO: 1password integration: extract MFA directly from 1Password.
