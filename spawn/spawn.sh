#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Run a command in the background and exit cleanly.

Starts a command in the background with nohup, allowing the shell to exit
immediately without waiting for the command to complete. By default, output is
logged to ~/.cache/spawn/. Use --no-log to discard output instead.

Supports pipes, logical operators, and other shell features by passing commands
as quoted strings.

USAGE:
    $cmd [--no-log] COMMAND [ARGS...]
    $cmd [--no-log] "SHELL COMMAND"

OPTIONS:
    -h, --help    Show this help message and exit
    --no-log      Send output to /dev/null instead of logging

EXAMPLES:
    Simple command:
        $cmd sleep 3600

    Command with arguments:
        $cmd echo "Hello World"

    Pipe (pass as quoted string):
        $cmd "echo hello | tr a-z A-Z"

    Logical operators:
        $cmd "echo first && echo second"
        $cmd "test -f /config || echo missing"

    Complex shell code:
        $cmd "for i in 1 2 3; do echo \$i; done"

EXIT CODES:
    0    Command started successfully in the background
    1    Invalid arguments or setup failed
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "nohup"
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

main() {
    check_dependencies

    local no_log=false
    local command_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --no-log)
                no_log=true
                shift
                ;;
            --)
                # Explicit separator - everything after this is the command
                shift
                command_args+=("$@")
                break
                ;;
            -*)
                # Unknown option
                echo "Error: Unknown option: $1" >&2
                exit 1
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
        echo "Error: No command specified" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi

    # Set up output destination
    local output_dest
    if [[ "$no_log" == true ]]; then
        output_dest="/dev/null"
    else
        # Create log directory if it doesn't exist
        local log_dir
        log_dir="${HOME}/.cache/spawn"
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            echo "Error: Failed to create log directory: $log_dir" >&2
            exit 1
        fi

        # Generate log filename with timestamp
        local cmd_name
        cmd_name=$(basename "${command_args[0]}")
        local timestamp
        timestamp=$(date +%s)
        output_dest="${log_dir}/${cmd_name}-${timestamp}.log"
    fi

    # If there's only one argument and it contains shell metacharacters,
    # treat it as a shell command. Otherwise, build the command normally.
    local cmd_string=""
    local has_operators=false

    if [[ ${#command_args[@]} -eq 1 ]]; then
        case "${command_args[0]}" in
            *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*)
                has_operators=true
                ;;
        esac
    fi

    if [[ "$has_operators" == true ]]; then
        # Single argument with shell operators - pass directly to bash
        cmd_string="${command_args[0]}"
    else
        # Multiple arguments or no operators - quote each argument properly
        for arg in "${command_args[@]}"; do
            if [[ -z "$cmd_string" ]]; then
                cmd_string=$(printf '%q' "$arg")
            else
                cmd_string+=" "
                cmd_string+=$(printf '%q' "$arg")
            fi
        done
    fi

    # Start the command in the background with nohup through bash
    nohup bash -c "$cmd_string" > "$output_dest" 2>&1 &

    exit 0
}

main "$@"
