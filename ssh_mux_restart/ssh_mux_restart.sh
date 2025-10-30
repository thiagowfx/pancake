#!/bin/bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Restart SSH multiplexed connections to refresh authentication credentials.

OPTIONS:
    -h, --help              Show this help message and exit
    --restart-1password     Also restart the 1Password SSH agent

DESCRIPTION:
    This script finds and terminates SSH multiplexed control master processes
    ([mux] connections). This is useful when SSH authentication becomes stale,
    particularly after SAML SSO enforcement or when 1Password SSH agent
    credentials need refreshing.

    By default, only SSH multiplexed connections are killed. Use the
    --restart-1password flag to additionally restart the 1Password SSH agent.

PREREQUISITES:
    - Standard Unix tools (pgrep, pkill)
    - 1Password CLI ('op') if using --restart-1password flag

EXAMPLES:
    $0                          Kill SSH multiplexed connections
    $0 --restart-1password      Kill connections and restart 1Password agent
    $0 --help                   Show this help

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
    echo "Restarting 1Password SSH agent..."

    if ! command -v op &> /dev/null; then
        echo "Error: 1Password CLI ('op') not found. Install it to use --restart-1password flag." >&2
        return 1
    fi

    # Find and kill the 1Password SSH agent process
    local agent_pids
    agent_pids=$(pgrep -f "1Password.*ssh-agent" || true)

    if [[ -n "$agent_pids" ]]; then
        echo "Found 1Password SSH agent processes:"
        pgrep -af "1Password.*ssh-agent" | while IFS= read -r line; do
            echo "  $line"
        done

        echo "Killing 1Password SSH agent..."
        while IFS= read -r pid; do
            if [[ -n "$pid" ]]; then
                if kill "$pid" 2>/dev/null; then
                    echo "✓ Killed 1Password agent process: $pid"
                else
                    echo "✗ Failed to kill 1Password agent process: $pid" >&2
                fi
            fi
        done <<< "$agent_pids"

        echo "1Password SSH agent will restart automatically on next use."
    else
        echo "No 1Password SSH agent processes found."
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
