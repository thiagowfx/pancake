#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Run a command in the background and exit cleanly.

Starts a command in the background in a tmux session, allowing the shell to exit
immediately without waiting for the command to complete. Sessions can be re-attached
at any time.

Supports pipes, logical operators, and other shell features by passing commands
as quoted strings.

USAGE:
    $cmd [--no-log] COMMAND [ARGS...]
    $cmd [--no-log] "SHELL COMMAND"
    $cmd --list
    $cmd --attach SESSION_ID
    $cmd --kill SESSION_ID

OPTIONS:
    -h, --help          Show this help message and exit
    --no-log            Send output to /dev/null instead of logging
    --list              List all active spawn sessions
    --attach SESSION_ID Attach to an existing spawn session
    --kill SESSION_ID   Kill a spawn session

EXAMPLES:
    Simple command:
        $cmd sleep 3600

    Command with arguments:
        $cmd echo "Hello World"

    Pipe (pass as quoted string):
        $cmd "echo hello | tr a-z A-Z"

    List active sessions:
        $cmd --list

    Attach to a session:
        $cmd --attach spawn-sleep-a1b2c3d4

EXIT CODES:
    0    Command started successfully or operation completed
    1    Invalid arguments or setup failed
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "tmux"
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

get_session_dir() {
    echo "${HOME}/.cache/spawn"
}

generate_session_id() {
    local cmd_name=$1
    # Sanitize command name: take basename, remove special chars, truncate to 16 chars
    cmd_name=$(basename "$cmd_name" | sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-16)
    # Generate a short unique session ID with command name
    echo "spawn-${cmd_name}-$(openssl rand -hex 3)"
}

list_sessions() {
    local session_dir
    session_dir=$(get_session_dir)

    if [[ ! -d "$session_dir" ]]; then
        echo "No spawn sessions found."
        return 0
    fi

    local sessions=()
    while IFS= read -r session_file; do
        local session_id status
        session_id=$(basename "$session_file" .session)
        status=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -q "^${session_id}$" && echo "running" || echo "exited")

        if [[ "$status" == "running" ]]; then
            sessions+=("$session_id")
        fi
    done < <(find "$session_dir" -maxdepth 1 -name "*.session" -type f 2>/dev/null)

    if [[ ${#sessions[@]} -eq 0 ]]; then
        echo "No active spawn sessions."
        return 0
    fi

    echo "Active spawn sessions:"
    printf '%s\n' "${sessions[@]}" | sort
}

attach_session() {
    local session_id=$1

    if ! tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -q "^${session_id}$"; then
        echo "Error: Session '$session_id' not found or already exited" >&2
        return 1
    fi

    tmux attach-session -t "$session_id"
}

kill_session() {
    local session_id=$1
    local session_dir
    session_dir=$(get_session_dir)

    if tmux kill-session -t "$session_id" 2>/dev/null; then
        rm -f "${session_dir}/${session_id}.session"
        echo "Killed session: $session_id"
        return 0
    else
        echo "Error: Session '$session_id' not found" >&2
        return 1
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
            --list)
                list_sessions
                exit 0
                ;;
            --attach)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --attach requires a session ID" >&2
                    exit 1
                fi
                attach_session "$2"
                exit $?
                ;;
            --kill)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --kill requires a session ID" >&2
                    exit 1
                fi
                kill_session "$2"
                exit $?
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

    # Create session directory
    local session_dir
    session_dir=$(get_session_dir)
    if ! mkdir -p "$session_dir" 2>/dev/null; then
        echo "Error: Failed to create session directory: $session_dir" >&2
        exit 1
    fi

    # Generate unique session ID based on command name
    local session_id
    session_id=$(generate_session_id "${command_args[0]}")

    # Set up output destination
    local output_dest
    if [[ "$no_log" == true ]]; then
        output_dest="/dev/null"
    else
        local timestamp
        timestamp=$(date +%s)
        output_dest="${session_dir}/${session_id}-${timestamp}.log"
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

    # Create a marker file for this session
    touch "${session_dir}/${session_id}.session"

    # Start the command in a new tmux session with explicit window name
    # Use tee to log output while displaying it in the pane
    local pane_cmd
    if [[ "$output_dest" == "/dev/null" ]]; then
        pane_cmd="bash -c '$cmd_string'"
    else
        pane_cmd="bash -c '$cmd_string' 2>&1 | tee '$output_dest'"
    fi
    tmux new-session -d -s "$session_id" -n "$session_id" -c "$PWD" "$pane_cmd"
    # Disable automatic window renaming at session level
    tmux set-option -t "$session_id" allow-rename off

    echo "Started session: $session_id"
    echo "Attach with: spawn --attach $session_id"

    exit 0
}

main "$@"
