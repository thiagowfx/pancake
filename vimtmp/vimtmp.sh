#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Create a temporary scratch file and open it in your default editor.

OPTIONS:
    -h, --help    Show this help message and exit

DESCRIPTION:
    Creates a temporary file in the system's temporary directory and opens
    it in your preferred text editor (defined by the EDITOR environment
    variable). The file persists after the editor closes, allowing you to
    reference it later in the same session.

    This is useful for quick notes, temporary calculations, or drafting text
    without cluttering your workspace with permanent files.

PREREQUISITES:
    - EDITOR environment variable must be set

EXAMPLES:
    $cmd              Create and edit a scratch file
    $cmd --help       Show this help

EXIT CODES:
    0    Scratch file created and editor launched successfully
    1    EDITOR not set or other error occurred
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

check_dependencies() {
    if [[ -z "${EDITOR:-}" ]]; then
        echo "Error: EDITOR environment variable is not set"
        echo "Set it to your preferred editor, for example:"
        echo "  export EDITOR=vim"
        echo "  export EDITOR=nano"
        echo "  export EDITOR=code"
        exit 1
    fi
}

main() {
    check_dependencies

    local scratch_file
    scratch_file=$(mktemp)

    echo "Opening scratch file: $scratch_file"

    # Launch editor with the scratch file
    $EDITOR "$scratch_file"
}

main "$@"
