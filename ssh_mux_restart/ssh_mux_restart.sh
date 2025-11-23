#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Restart SSH multiplexed connections to refresh authentication credentials.

This script finds and terminates SSH multiplexed control master processes ([mux]
connections). This is useful when SSH authentication becomes stale, particularly
after SAML SSO enforcement or when 1Password SSH agent credentials need
refreshing. By default, only SSH multiplexed connections are killed. Use the
--restart-1password flag to additionally restart the 1Password SSH agent.

OPTIONS:
    -h, --help              Show this help message and exit
    --restart-1password     Also restart the 1Password SSH agent

PREREQUISITES:
    - Standard Unix tools (pgrep, pkill)
    - 1Password app (macOS) if using --restart-1password flag

EXAMPLES:
    $cmd                          Kill SSH multiplexed connections
    $cmd --restart-1password      Kill connections and restart 1Password agent
    $cmd --help                   Show this help

EXIT CODES:
    0    All operations completed successfully
    1    Failed to find or kill processes, or dependencies missing
    2    Partial success (some operations failed)

REFERENCES:
    - https://perrotta.dev/2025/10/github-the-organization-has-enabled-or-enforced-saml-sso/
    - https://perrotta.dev/2025/05/1password-ssh-agent-error/
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "pgrep"
        "pkill"
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
        exit 1
    fi
}

kill_ssh_mux_connections() {
    echo "Finding SSH multiplexed connections..."

    # Find SSH multiplexed control master processes
    local mux_pids
    mux_pids=$(pgrep -fl 'ssh.*\[mux\]' | awk '{print $1}' || true)

    if [[ -z "$mux_pids" ]]; then
        echo "No SSH multiplexed connections found."
        return 0
    fi

    echo "Found SSH multiplexed connections:"
    pgrep -afl 'ssh.*\[mux\]' | while IFS= read -r line; do
        echo "  $line"
    done

    echo "Killing SSH multiplexed connections..."
    local kill_count=0
    local total_count=0

    while IFS= read -r pid; do
        if [[ -n "$pid" ]]; then
            total_count=$((total_count + 1))
            if kill "$pid" 2>/dev/null; then
                echo "✓ Killed SSH mux process: $pid"
                kill_count=$((kill_count + 1))
            else
                echo "✗ Failed to kill SSH mux process: $pid" >&2
            fi
        fi
    done <<< "$mux_pids"

    echo "Killed $kill_count/$total_count SSH multiplexed connections."

    if [[ $kill_count -eq $total_count ]]; then
        return 0
    else
        return 2
    fi
}

restart_1password_agent() {
    echo ""
    echo "Restarting 1Password application..."

    # Check if 1Password is running
    local onepassword_pid
    onepassword_pid=$(pgrep -x "1Password" || true)

    if [[ -z "$onepassword_pid" ]]; then
        echo "1Password is not currently running."
        return 0
    fi

    echo "Found 1Password process: $onepassword_pid"

    # Quit 1Password gracefully
    echo "Quitting 1Password..."
    if osascript -e 'quit app "1Password"' 2>/dev/null; then
        echo "✓ 1Password quit successfully"

        # Wait a moment for it to fully quit
        sleep 2

        # Restart 1Password
        echo "Starting 1Password..."
        if open -a "1Password" 2>/dev/null; then
            echo "✓ 1Password started successfully"
            echo "1Password SSH agent is now ready for use."
        else
            echo "✗ Failed to start 1Password" >&2
            return 2
        fi
    else
        echo "✗ Failed to quit 1Password gracefully" >&2
        return 2
    fi

    return 0
}

main() {
    local restart_1password=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --restart-1password)
                restart_1password=true
                shift
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Use --help for usage information." >&2
                exit 1
                ;;
        esac
    done

    check_dependencies

    local exit_code=0

    # Kill SSH multiplexed connections
    if ! kill_ssh_mux_connections; then
        exit_code=$?
    fi

    # Optionally restart 1Password agent
    if [[ "$restart_1password" == true ]]; then
        if ! restart_1password_agent; then
            exit_code=2
        fi
    fi

    echo ""
    if [[ $exit_code -eq 0 ]]; then
        echo "All operations completed successfully!"
    elif [[ $exit_code -eq 2 ]]; then
        echo "Some operations failed. Check output above for details." >&2
    fi

    exit "$exit_code"
}

main "$@"
