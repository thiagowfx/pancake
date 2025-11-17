#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYWRIGHT_SCRIPT="$SCRIPT_DIR/aws_login_headless_playwright.py"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Fully automated AWS SSO login using headless browser automation.

OPTIONS:
    -h, --help              Show this help message and exit
    --profile PROFILE       AWS profile name (default: default)
    --op-item ITEM          Retrieve SSO password from 1Password (requires 'op' CLI)
                            Can be an item name/ID or secret reference (op://...)
    --op-account ACCOUNT    1Password account to use (default: uses current session)
    --username USERNAME     AWS SSO username/email (if required by your IdP)
    --no-headless           Run browser in visible mode for debugging

DESCRIPTION:
    This script automates AWS SSO login without browser interaction. It uses
    Playwright to control a headless Chrome browser that fills in credentials
    and completes the authentication flow.

    The script performs these steps:
    1. Starts AWS SSO login and captures the verification URL
    2. Optionally retrieves SSO password from 1Password
    3. Launches headless browser to automate the login form
    4. Waits for authentication to complete

PREREQUISITES:
    - AWS CLI v2 must be installed
    - uv must be installed (handles Python and Playwright automatically)
    - Optional: 1Password CLI ('op') for automatic password retrieval

EXAMPLES:
    $0                                                 Login with interactive password prompt (default profile)
    $0 --profile production                            Login to specific AWS profile
    $0 --op-item TACO42BURRITO88SALSA99                Login using item name from 1Password
    $0 --op-item "op://Employee/AWS/password"          Login using secret reference from 1Password
    $0 --profile prod --op-item AWS --op-account work  Login to prod profile with 1Password
    $0 --username joe@example.com                      Login with username pre-filled
    $0 --no-headless                                   Login with visible browser for debugging

EXIT CODES:
    0    Successfully authenticated to AWS SSO
    1    Error occurred during authentication
EOF
}

parse_args() {
    aws_profile="default"
    op_item=""
    op_account=""
    username=""
    headless_flag="--headless"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --profile)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --profile requires an argument"
                    exit 1
                fi
                aws_profile="$2"
                shift 2
                ;;
            --op-item)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --op-item requires an argument"
                    exit 1
                fi
                op_item="$2"
                shift 2
                ;;
            --op-account)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --op-account requires an argument"
                    exit 1
                fi
                op_account="$2"
                shift 2
                ;;
            --username)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --username requires an argument"
                    exit 1
                fi
                username="$2"
                shift 2
                ;;
            --no-headless)
                headless_flag="--no-headless"
                shift
                ;;
            -*)
                echo "Error: Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                echo "Error: Unexpected argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "aws"
        "uv"
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
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi

    # Check if Playwright script exists
    if [[ ! -f "$PLAYWRIGHT_SCRIPT" ]]; then
        echo "Error: Playwright automation script not found at: $PLAYWRIGHT_SCRIPT"
        exit 1
    fi
}

get_sso_password() {
    local password=""

    if [[ -n "$op_item" ]]; then
        echo "Retrieving SSO password from 1Password..." >&2

        local op_cmd
        # Check if using secret reference format (op://...)
        if [[ "$op_item" == op://* ]]; then
            # Use 'op read' for secret references
            op_cmd="op read \"$op_item\""
            if [[ -n "$op_account" ]]; then
                op_cmd="op --account \"$op_account\" read \"$op_item\""
            fi
        else
            # Use 'op item get' for item names/IDs
            op_cmd="op item get \"$op_item\" --fields password"
            if [[ -n "$op_account" ]]; then
                op_cmd="op --account \"$op_account\" item get \"$op_item\" --fields password"
            fi
        fi

        password=$(eval "$op_cmd" 2>&1)

        if [[ -z "$password" ]] || [[ "$password" == *"ERROR"* ]] || [[ "$password" == *"error"* ]]; then
            echo "" >&2
            echo "Error: Failed to retrieve password from 1Password." >&2
            echo "$password" >&2
            exit 1
        fi
    else
        echo -n "Enter your AWS SSO password: " >&2
        read -rs password
        echo "" >&2

        if [[ -z "$password" ]]; then
            echo "Error: Password cannot be empty" >&2
            exit 1
        fi
    fi

    echo "$password"
}

start_aws_sso_login() {
    echo "Initiating AWS SSO login for profile: $AWS_PROFILE" >&2

    # Create temporary file for AWS SSO output
    local temp_file
    temp_file=$(mktemp)

    # Start AWS SSO login in background, redirect output to temp file
    aws sso login --profile "$AWS_PROFILE" --no-browser > "$temp_file" 2>&1 &
    local aws_pid=$!

    # Wait for URL to appear in output (with timeout)
    local verification_url=""
    local timeout=20  # Total timeout in half-seconds (10 seconds)
    local elapsed=0

    while [[ -z "$verification_url" ]] && [[ $elapsed -lt $timeout ]]; do
        if [[ -f "$temp_file" ]]; then
            verification_url=$(grep -Eo 'https://[^ ]+' "$temp_file" 2>/dev/null | head -1)
        fi
        if [[ -z "$verification_url" ]]; then
            sleep 0.5
            elapsed=$((elapsed + 1))
        fi
    done

    # Check if we got the URL
    if [[ -z "$verification_url" ]]; then
        # Check if process already exited (might be already logged in)
        if ! kill -0 "$aws_pid" 2>/dev/null; then
            wait "$aws_pid"
            local exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                rm -f "$temp_file"
                echo "✓ Already logged in to AWS SSO" >&2
                exit 0
            fi
        fi

        echo "Error: Could not extract verification URL from AWS SSO login output" >&2
        echo "Output:" >&2
        cat "$temp_file" >&2
        rm -f "$temp_file"
        kill "$aws_pid" 2>/dev/null || true
        exit 1
    fi

    echo "Verification URL: $verification_url" >&2

    # Clean up temp file
    rm -f "$temp_file"

    # Output only the URL to stdout (this is captured by caller)
    echo "$verification_url"

    # Keep AWS process running in background
    # It will automatically complete when browser authentication succeeds
}

run_playwright_automation() {
    local verification_url="$1"
    local password="$2"

    echo "Launching headless browser automation..."

    # Build uvx command with inline script dependencies
    # Password is passed via stdin for security (not visible in process list)
    local uvx_cmd=(
        "uvx"
        "--from" "playwright"
        "--with" "playwright"
        "python"
        "$PLAYWRIGHT_SCRIPT"
        "$verification_url"
        "--password-stdin"
    )

    if [[ -n "$username" ]]; then
        uvx_cmd+=("--username" "$username")
    fi

    uvx_cmd+=("$headless_flag")

    # First time setup: ensure Playwright browser is installed
    if [[ ! -d "$HOME/.cache/ms-playwright" ]] && [[ ! -d "$HOME/Library/Caches/ms-playwright" ]]; then
        echo "First-time setup: installing Playwright browser..."
        if ! uvx --from playwright playwright install chromium --with-deps 2>/dev/null; then
            echo "Note: Browser installation may require manual setup"
            echo "If script fails, run: uvx --from playwright playwright install chromium"
        fi
    fi

    # Pass password via stdin to prevent exposure in process list
    if echo "$password" | "${uvx_cmd[@]}"; then
        echo ""
        echo "✓ Successfully authenticated to AWS SSO"
        echo ""
        echo "AWS profile '$AWS_PROFILE' is now logged in."
        return 0
    else
        echo ""
        echo "✗ Failed to authenticate to AWS SSO"
        return 1
    fi
}

main() {
    parse_args "$@"

    # Set AWS_PROFILE from parsed value
    AWS_PROFILE="$aws_profile"

    check_dependencies

    local password
    if ! password=$(get_sso_password); then
        exit 1
    fi

    local verification_url
    if ! verification_url=$(start_aws_sso_login); then
        exit 1
    fi

    if ! run_playwright_automation "$verification_url" "$password"; then
        exit 1
    fi
}

main "$@"
