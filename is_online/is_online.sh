#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Check if internet connectivity is available by making HTTP requests to
reliable endpoints.

This tool uses generate_204 endpoints (services that return HTTP 204 No
Content) to verify that DNS, TCP, and HTTP are all functioning correctly.
It's more reliable than simple ping tests for detecting real internet access.

OPTIONS:
    -h, --help       Show this help message and exit
    -q, --quiet      Suppress output (useful for scripts)
    -t, --timeout N  Set connection timeout in seconds (default: 5)

PREREQUISITES:
    - curl must be installed

EXAMPLES:
    $cmd                    Check connectivity with default settings
    $cmd --quiet            Check silently (exit code only)
    $cmd --timeout 10       Use 10-second timeout
    if $cmd -q; then        Use in conditional
        echo "We're online!"
    fi

EXIT CODES:
    0    Internet is available
    1    Internet is not available or error occurred
EOF
}

check_dependencies() {
    local required_deps=(
        "curl"
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

is_online() {
    local timeout="${1:-5}"

    # Primary endpoint: Google's generate_204
    # Fallback endpoints if primary fails
    local endpoints=(
        "https://www.google.com/generate_204"
        "https://connectivitycheck.gstatic.com/generate_204"
        "https://cloudflare.com/cdn-cgi/trace"
    )

    for endpoint in "${endpoints[@]}"; do
        if curl -sf \
            --max-time "$timeout" \
            --connect-timeout "$timeout" \
            -o /dev/null \
            -w "%{http_code}" \
            "$endpoint" | grep -qE '^(200|204)$'; then
            return 0
        fi
    done

    return 1
}

main() {
    local quiet=false
    local timeout=5

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -t|--timeout)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --timeout requires a value"
                    exit 1
                fi
                timeout="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    check_dependencies

    if is_online "$timeout"; then
        if [[ "$quiet" == false ]]; then
            echo "✓ Online"
        fi
        exit 0
    else
        if [[ "$quiet" == false ]]; then
            echo "✗ Offline"
        fi
        exit 1
    fi
}

main "$@"
