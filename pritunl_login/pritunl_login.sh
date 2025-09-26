#!/bin/bash
set -euo pipefail

readonly PRITUNL_CLIENT_PATH="/Applications/Pritunl.app/Contents/Resources/pritunl-client"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <account> <entry_name> <password_ref>

Connect to Pritunl VPN using credentials from 1Password.

POSITIONAL ARGUMENTS:
    account        1Password account name/ID (e.g., 'stark-industries')
    entry_name     Name of the 1Password entry (e.g., 'Pritunl (VPN)')
    password_ref   1Password password reference (e.g., 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password')

OPTIONS:
    -h, --help    Show this help message and exit

DESCRIPTION:
    This script connects to a Pritunl VPN profile using credentials stored in 1Password.
    It retrieves the password and OTP from 1Password, then starts the VPN connection.

PREREQUISITES:
    - Pritunl client must be installed at $PRITUNL_CLIENT_PATH
    - 1Password CLI ('op') must be installed
    - 'jq' must be installed for JSON parsing
    - User must be logged into the specified 1Password account

EXAMPLES:
    $0 stark-industries 'Pritunl (VPN)' 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password'
    $0 --help

EXIT CODES:
    0    VPN connection successful
    1    Error occurred during connection process
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 3 ]]; then
    echo "Error: Expected 3 arguments, got $#"
    echo ""
    usage
    exit 1
fi

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "jq"
        "op"
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

    if [[ ! -x "$PRITUNL_CLIENT_PATH" ]]; then
        echo "Error: Pritunl client not found at $PRITUNL_CLIENT_PATH"
        exit 1
    fi
}

main() {
    local account_name="$1"
    local entry_name="$2"
    local password_ref="$3"

    check_dependencies

    echo "Connecting to Pritunl VPN..."
    echo "Entry: $entry_name"
    echo "Account: $account_name"
    echo ""

    echo "Getting Pritunl profile ID..."
    local profile_id
    profile_id=$("$PRITUNL_CLIENT_PATH" list --json 2>/dev/null | jq -r '.[0].id' 2>/dev/null)

    if [[ -z "$profile_id" || "$profile_id" == "null" ]]; then
        echo "Error: No Pritunl profiles found. Configure a profile first."
        exit 1
    fi

    echo "Using profile ID: $profile_id"

    echo "Retrieving credentials from 1Password..."
    local op_id
    op_id=$(op --account "$account_name" item get "$entry_name" --format json 2>/dev/null | jq -r '.id' 2>/dev/null)

    if [[ -z "$op_id" || "$op_id" == "null" ]]; then
        echo "Error: Could not find 1Password entry '$entry_name' in account '$account_name'"
        exit 1
    fi

    local password
    password=$(op --account "$account_name" read "$password_ref" 2>/dev/null)

    if [[ -z "$password" ]]; then
        echo "Error: Could not retrieve password from '$password_ref'"
        exit 1
    fi

    local otp
    otp=$(op --account "$account_name" item get "$op_id" --totp 2>/dev/null)

    if [[ -z "$otp" ]]; then
        echo "Error: Could not retrieve OTP for entry '$entry_name'"
        exit 1
    fi

    echo "Starting VPN connection..."
    if "$PRITUNL_CLIENT_PATH" start "$profile_id" --password "$password$otp" 2>/dev/null; then
        echo "✓ VPN connection started successfully"
        echo ""
        echo "Current VPN status:"
        "$PRITUNL_CLIENT_PATH" list
        exit 0
    else
        echo "✗ Failed to start VPN connection"
        exit 1
    fi
}

main "$@"
