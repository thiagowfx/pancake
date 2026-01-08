#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [WATCH_OPTIONS] [--] COMMAND [ARGS...]

Run a command repeatedly using watch, preserving colored output.

Uses unbuffer to maintain color codes through watch's output. Useful for
monitoring git status, test output, or any command with color formatting.

The -- separator is optional. Watch options are recognized and separated
automatically. All options are passed directly to watch(1). See watch(1)
for available options.

EXAMPLES:
    $cmd git st
        Watch git status with colors every 2 seconds

    $cmd -- git st
        Same as above (-- is optional)

    $cmd -n 1 git st
        Watch git status with 1 second interval

    $cmd -n 5 npm test
        Watch test output with 5 second interval

DEPENDENCIES:
    watch    Part of procps-ng
    unbuffer Part of expect package

EOF
}

main() {
    local watch_args=()
    local command_args=()

    # Parse arguments, looking for -- separator or end of watch options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                command_args+=("$@")
                break
                ;;
            -n|--interval|-d|--differences|-t|--no-title|-p|--precise)
                # watch options that take a value
                watch_args+=("$1" "$2")
                shift 2
                ;;
            -*)
                # Other watch options
                watch_args+=("$1")
                shift
                ;;
            *)
                # Non-option argument: assume this is the start of the command
                command_args+=("$@")
                break
                ;;
        esac
    done

    # Check if command was provided
    if [[ ${#command_args[@]} -eq 0 ]]; then
        echo "Error: No command specified"
        echo ""
        usage
        exit 1
    fi

    # Check dependencies
    if ! command -v watch &> /dev/null; then
        echo "Error: watch not found. Install procps-ng."
        exit 1
    fi

    if ! command -v unbuffer &> /dev/null; then
        echo "Error: unbuffer not found. Install expect package."
        exit 1
    fi

    # Run watch with unbuffer and color flag
    watch "${watch_args[@]}" --color -- unbuffer "${command_args[@]}"
}

main "$@"
