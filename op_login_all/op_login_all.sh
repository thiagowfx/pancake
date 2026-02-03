#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Log into all configured 1Password accounts using the 'op' CLI tool.

This script discovers all 1Password accounts configured on the system and
attempts to sign in to each one. It provides feedback for each login attempt
and a summary at the end.

OPTIONS:
    -h, --help    Show this help message and exit

PREREQUISITES:
    - 1Password CLI ('op') must be installed
    - Accounts must be added using 'op account add'
    - 'jq' must be installed for JSON parsing

EXAMPLES:
    $cmd              Log into all accounts
    $cmd --help       Show this help

EXIT CODES:
    0    All accounts logged in successfully
    1    Some or all accounts failed to log in, or no accounts found
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
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
}

main() {
    check_dependencies

    echo "Logging into all 1Password accounts..."

    local accounts
    accounts=$(op account list --format=json 2>/dev/null | jq -r '.[] | .user_uuid // .shorthand // .url' 2>/dev/null || echo "")

    if [[ -z "$accounts" ]]; then
        echo "No 1Password accounts found. Add accounts first using 'op account add'."
        exit 1
    fi

    local success_count=0
    local total_count=0

    while IFS= read -r account; do
        if [[ -n "$account" ]]; then
            total_count=$((total_count + 1))
            echo "Attempting to sign in to account: $account"

            if op signin --account="$account" --raw >/dev/null 2>&1; then
                echo "✓ Successfully signed in to: $account"
                success_count=$((success_count + 1))
            else
                echo "✗ Failed to sign in to: $account"
            fi
            echo ""
        fi
    done <<< "$accounts"

    echo "Login Summary:"
    echo "Successfully logged in: $success_count/$total_count accounts"

    if [ $success_count -eq $total_count ]; then
        echo "All accounts logged in successfully!"
        exit 0
    else
        echo "Some accounts failed to log in."
        exit 1
    fi
}

main "$@"
