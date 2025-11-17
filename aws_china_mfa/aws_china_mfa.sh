#!/usr/bin/env bash
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
    -h, --help              Show this help message and exit
    --op-item ITEM_ID       Retrieve MFA token from 1Password item (requires 'op' CLI)
    --op-account ACCOUNT    1Password account to use (default: uses current session)

DESCRIPTION:
    This script can be sourced or executed with eval to set AWS session credentials.
    It prompts for an MFA token (or retrieves it from 1Password), retrieves temporary
    session credentials, and exports them as environment variables.

    When sourced: exports variables directly to your current shell
    When executed: prints export commands to stdout

PREREQUISITES:
    - AWS CLI must be installed and configured
    - 'jq' must be installed for JSON parsing
    - AWS profile must have MFA device configured
    - Optional: 1Password CLI ('op') for automatic MFA token retrieval

EXAMPLES:
    source $0                                  Use default profile ($DEFAULT_AWS_PROFILE)
    source $0 my-china-profile                 Use custom profile
    source $0 --op-item xyz123                 Use 1Password item for MFA token
    source $0 --op-item xyz123 --op-account my-account  Use specific 1Password account
    eval "\$($0)"                              Execute with eval (default profile)
    eval "\$($0 my-china-profile)"             Execute with eval (custom profile)
    $0 --help                                  Show this help

NOTES:
    - Session credentials are valid for $SESSION_DURATION seconds (24 hours)
    - Exported variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, AWS_PROFILE

EXIT CODES:
    0    Credentials successfully exported
    1    Error occurred during authentication
EOF
}

parse_args() {
    op_item=""
    op_account=""
    aws_profile=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                return 0 2>/dev/null || exit 0
                ;;
            --op-item)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --op-item requires an argument" >&2
                    usage
                    return 1 2>/dev/null || exit 1
                fi
                op_item="$2"
                shift 2
                ;;
            --op-account)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --op-account requires an argument" >&2
                    usage
                    return 1 2>/dev/null || exit 1
                fi
                op_account="$2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                usage
                return 1 2>/dev/null || exit 1
                ;;
            *)
                if [[ -z "$aws_profile" ]]; then
                    aws_profile="$1"
                else
                    echo "Error: Unexpected argument: $1" >&2
                    usage
                    return 1 2>/dev/null || exit 1
                fi
                shift
                ;;
        esac
    done

    aws_profile="${aws_profile:-$DEFAULT_AWS_PROFILE}"
}

# Initialize global variables
op_item=""
op_account=""
aws_profile=""

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

    # Check for 'op' if 1Password integration is requested
    if [[ -n "$op_item" ]]; then
        if ! command -v "op" &> /dev/null; then
            missing_deps+=("op")
        fi
    fi

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

get_mfa_token() {
    local token=""

    if [[ -n "$op_item" ]]; then
        echo "Retrieving MFA token from 1Password..." >&2

        local op_cmd="op item get \"$op_item\" --otp"
        if [[ -n "$op_account" ]]; then
            op_cmd="op --account \"$op_account\" item get \"$op_item\" --otp"
        fi

        token=$(eval "$op_cmd" 2>&1)

        if [[ -z "$token" ]] || [[ "$token" == *"ERROR"* ]] || [[ "$token" == *"error"* ]]; then
            echo "" >&2
            echo "Error: Failed to retrieve MFA token from 1Password." >&2
            echo "$token" >&2
            return 1
        fi
    else
        echo -n "Enter the MFA token code for your AWS China account: " >&2
        read -r token

        if [[ -z "$token" ]]; then
            echo "Error: MFA token cannot be empty" >&2
            return 1
        fi
    fi

    echo "$token"
}

main() {
    parse_args "$@"
    check_dependencies

    if [[ $sourced -eq 0 ]]; then
        echo "Note: Script is being executed. To apply credentials, run:" >&2
        echo "  eval \"\$($0 $aws_profile)\"" >&2
        echo "" >&2
    fi

    echo "Using AWS profile: $aws_profile" >&2

    local token
    if ! token=$(get_mfa_token) || [[ -z "$token" ]]; then
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

    echo "" >&2
    echo "✓ Successfully authenticated to AWS China" >&2
    echo "" >&2

    if [[ $sourced -eq 1 ]]; then
        echo "Exported AWS credentials:" >&2
        echo "" >&2
        env | grep '^AWS_' | sort >&2
    else
        # Execution mode
        if [[ -t 1 ]]; then
            # stdout is a terminal (not piped to eval)
            echo "Copy and paste the export commands above to apply credentials." >&2
        else
            # stdout is piped (eval mode)
            echo "Exported AWS credentials:" >&2
            echo "" >&2
            echo "  AWS_PROFILE=$aws_profile" >&2
            echo "  AWS_ACCESS_KEY_ID=$access_key" >&2
            echo "  AWS_SECRET_ACCESS_KEY=$secret_key" >&2
            echo "  AWS_SESSION_TOKEN=$session_token" >&2
        fi
    fi
}

main "$@"
