#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND [ARGS...]

Execute a command repeatedly until it succeeds (exits with code 0).

OPTIONS:
    -h, --help                 Show this help message and exit
    -i, --interval SECONDS     Wait time between retries (default: 0.5)
    -m, --max-attempts COUNT   Maximum number of attempts (default: unlimited)
    -t, --timeout SECONDS      Maximum total time to retry (default: unlimited)
    -v, --verbose              Show detailed output for each retry attempt

DESCRIPTION:
    Runs the specified command repeatedly until it exits successfully
    (exit code 0). Useful for waiting on transient failures or for
    services to become available.

    Both --max-attempts and --timeout can be specified together. The
    script will stop at whichever limit is reached first.

EXAMPLES:
    $0 curl -s http://localhost:8080/health
        Retry curl until server responds

    $0 -i 2 -m 10 ping -c 1 example.com
        Retry ping up to 10 times with 2 second intervals

    $0 -t 30 -v ssh user@host echo connected
        Retry SSH for 30 seconds with verbose output

    $0 -i 1 -m 5 -t 10 test -f /tmp/ready
        Stop after 5 attempts OR 10 seconds, whichever comes first

    $0 -v -- command-with-dashes --flag
        Use -- to explicitly separate retry options from command

EXIT CODES:
    0    Command succeeded
    1    Invalid arguments or limits exceeded
    124  Timeout reached (when --timeout is specified)
    125  Max attempts reached (when --max-attempts is specified)
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "sleep"
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

    local interval=0.5
    local max_attempts=0
    local timeout=0
    local verbose=false
    local command_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -i|--interval)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --interval requires a value"
                    exit 1
                fi
                interval="$2"
                shift 2
                ;;
            -m|--max-attempts)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --max-attempts requires a value"
                    exit 1
                fi
                max_attempts="$2"
                shift 2
                ;;
            -t|--timeout)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --timeout requires a value"
                    exit 1
                fi
                timeout="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --)
                # Explicit separator - everything after this is the command
                shift
                command_args+=("$@")
                break
                ;;
            -*)
                # Unknown option - might be for the command, treat as start of command
                command_args+=("$@")
                break
                ;;
            *)
                # First non-option argument - start of command
                command_args+=("$@")
                break
                ;;
        esac
    done

    # Validate command
    if [[ ${#command_args[@]} -eq 0 ]]; then
        echo "Error: No command specified"
        echo ""
        usage
        exit 1
    fi

    # Validate numeric arguments
    if ! [[ "$interval" =~ ^[0-9]+\.?[0-9]*$ ]] || (( $(echo "$interval <= 0" | bc -l) )); then
        echo "Error: --interval must be a positive number"
        exit 1
    fi

    if ! [[ "$max_attempts" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-attempts must be a non-negative integer"
        exit 1
    fi

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        echo "Error: --timeout must be a non-negative integer"
        exit 1
    fi

    # Execute retry loop
    local attempt=0
    local start_time
    start_time=$(date +%s)

    while true; do
        attempt=$((attempt + 1))

        if [[ "$verbose" == true ]]; then
            echo "Attempt $attempt: ${command_args[*]}"
        fi

        # Try to execute the command
        if "${command_args[@]}"; then
            if [[ "$verbose" == true ]]; then
                echo "→ Success after $attempt attempt(s)"
            fi
            exit 0
        fi

        # Check max attempts limit
        if [[ "$max_attempts" -gt 0 ]] && [[ "$attempt" -ge "$max_attempts" ]]; then
            if [[ "$verbose" == true ]]; then
                echo "→ Max attempts ($max_attempts) reached"
            fi
            exit 125
        fi

        # Check timeout limit
        if [[ "$timeout" -gt 0 ]]; then
            local current_time
            current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            if [[ "$elapsed" -ge "$timeout" ]]; then
                if [[ "$verbose" == true ]]; then
                    echo "→ Timeout (${timeout}s) reached"
                fi
                exit 124
            fi
        fi

        if [[ "$verbose" == true ]]; then
            echo "→ Failed, retrying in ${interval}s..."
        fi

        sleep "$interval"
    done
}

main "$@"
