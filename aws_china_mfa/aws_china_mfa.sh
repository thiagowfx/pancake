#!/bin/bash
# shellcheck disable=SC2317
set -euo pipefail

readonly DEFAULT_AWS_PROFILE="china"
readonly SESSION_DURATION=86400

usage() {
    cat << EOF
Usage: source $0 [OPTIONS] [AWS_PROFILE]

Authenticate to AWS China using MFA and export temporary session credentials in the current shell.

POSITIONAL ARGUMENTS:
    AWS_PROFILE    AWS profile name (default: $DEFAULT_AWS_PROFILE)

OPTIONS:
    -h, --help    Show this help message and exit

DESCRIPTION:
    This script must be sourced (not executed) to export AWS session credentials
    to your current shell environment. It prompts for an MFA token, retrieves
    temporary session credentials, and exports them as environment variables.

PREREQUISITES:
    - AWS CLI must be installed and configured
    - 'jq' must be installed for JSON parsing
    - AWS profile must have MFA device configured

EXAMPLES:
    source $0                  Use default profile ($DEFAULT_AWS_PROFILE)
    source $0 my-china-profile Use custom profile
    source $0 --help           Show this help

NOTES:
    - Session credentials are valid for $SESSION_DURATION seconds (24 hours)
    - This script must be sourced to export variables to your shell
    - Exported variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, AWS_PROFILE

EXIT CODES:
    0    Credentials successfully exported
    1    Error occurred during authentication
EOF
}

# Check if script is being sourced
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced -eq 0 ]]; then
    echo "Error: Do not invoke this script directly; instead, run 'source $0'"
    exit 1
fi

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
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi
}

main() {
    check_dependencies

    export AWS_PROFILE="${1:-$DEFAULT_AWS_PROFILE}"
    echo "Using AWS profile: $AWS_PROFILE"

    echo -n "Enter the MFA token code for your AWS China account: "
    read -r token

    if [[ -z "$token" ]]; then
        echo "Error: MFA token cannot be empty"
        return 1
    fi

    echo "Retrieving MFA device ARN..."
    local mfa_arn
    mfa_arn="$(aws iam --profile "$AWS_PROFILE" get-user --output text --query User.Arn | sed 's|:user/|:mfa/|')"

    if [[ -z "$mfa_arn" ]]; then
        echo "Error: Could not retrieve MFA device ARN"
        return 1
    fi

    echo "Requesting session token..."
    local credentials
    credentials="$(aws --profile "$AWS_PROFILE" sts get-session-token --serial-number "$mfa_arn" --token-code "$token" --duration-seconds $SESSION_DURATION)"

    if [[ -z "$credentials" ]]; then
        echo "Error: Failed to retrieve session token"
        return 1
    fi

    AWS_ACCESS_KEY_ID=$(echo "$credentials" | jq -r '.Credentials.AccessKeyId')
    AWS_SECRET_ACCESS_KEY=$(echo "$credentials" | jq -r '.Credentials.SecretAccessKey')
    AWS_SESSION_TOKEN=$(echo "$credentials" | jq -r '.Credentials.SessionToken')

    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN

    if [[ -z "$AWS_SESSION_TOKEN" ]] || [[ "$AWS_SESSION_TOKEN" == "null" ]]; then
        echo "Error: Failed to extract session token from credentials"
        return 1
    fi

    echo ""
    echo "✓ Successfully authenticated to AWS China"
    echo ""
    echo "Exported AWS credentials:"
    env | grep '^AWS_' | sort
}

main "$@"

# TODO #1: 1password integration: extract MFA directly from 1Password.
# TODO #2: make it work with both source and execution
