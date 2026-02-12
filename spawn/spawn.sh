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
    $cmd --list-all
    $cmd --attach SESSION_ID
    $cmd --kill SESSION_ID

OPTIONS:
    -h, --help          Show this help message and exit
    --no-log            Send output to /dev/null instead of logging
    --list              List active spawn sessions started from the current directory
    --list-all          List all active spawn sessions regardless of directory
    --attach SESSION_ID Attach to an existing spawn session
    --kill SESSION_ID   Kill a spawn session

EXAMPLES:
    Simple command:
        $cmd sleep 3600

    Command with arguments:
        $cmd echo "Hello World"

    Pipe (pass as quoted string):
        $cmd "echo hello | tr a-z A-Z"

    List active sessions (current directory):
        $cmd --list

    List all active sessions:
        $cmd --list-all

    Attach to a session:
        $cmd --attach spawn-sleep-a1b2c3d4

EXIT CODES:
    0    Command started successfully or operation completed
    1    Invalid arguments or setup failed
EOF
}

has_tmux() {
    command -v tmux &> /dev/null
}

get_session_dir() {
    echo "${HOME}/.cache/spawn"
}

generate_session_id() {
    local -a args=("$@")
    local cmd_name
    local args_str=""

    # Get the command name
    cmd_name=$(basename "${args[0]}" | sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-10)

    # Build a string from meaningful arguments (skip flags and options)
    local i
    for ((i = 1; i < ${#args[@]}; i++)); do
        local arg="${args[i]}"
        # Skip options that start with -
        if [[ ! "$arg" =~ ^- ]]; then
            # Sanitize the argument
            arg=$(echo "$arg" | sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-8)
            if [[ -n "$args_str" ]]; then
                args_str="${args_str}-${arg}"
            else
                args_str="$arg"
            fi
        fi
    done

    # Combine command and arguments
    if [[ -n "$args_str" ]]; then
        cmd_name="${cmd_name}-${args_str}"
    fi

    # Truncate total to 30 chars before random suffix
    cmd_name=$(echo "$cmd_name" | cut -c1-30)

    # Generate a short unique session ID with command name and arguments
    echo "spawn-${cmd_name}-$(openssl rand -hex 3)"
}

list_sessions() {
    local filter_dir="${1:-}"
    local session_dir
    session_dir=$(get_session_dir)

    if [[ ! -d "$session_dir" ]]; then
        echo "No spawn sessions found."
        return 0
    fi

    local sessions=()
    while IFS= read -r session_file; do
        local session_id
        session_id=$(basename "$session_file" .session)

        if ! tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -q "^${session_id}$"; then
            continue
        fi

        if [[ -n "$filter_dir" ]]; then
            local stored_dir
            stored_dir=$(head -1 "$session_file" 2>/dev/null)
            if [[ "$stored_dir" != "$filter_dir" ]]; then
                continue
            fi
        fi

        sessions+=("$session_id")
    done < <(find "$session_dir" -maxdepth 1 -name "*.session" -type f 2>/dev/null)

    if [[ ${#sessions[@]} -eq 0 ]]; then
        if [[ -n "$filter_dir" ]]; then
            echo "No active spawn sessions in $filter_dir."
        else
            echo "No active spawn sessions."
        fi
        return 0
    fi

    echo "Active spawn sessions:"
    printf '%s\n' "${sessions[@]}" | sort
}

attach_session() {
    local session_id=$1

    if ! tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -q "^${session_id}$"; then
        echo "Error: Session '$session_id' not found or already exited" >&2
        echo "" >&2
        list_sessions >&2
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

spawn_with_nohup() {
    local no_log=$1
    shift
    local command_args=("$@")

    # Set up output destination
    local output_dest
    if [[ "$no_log" == true ]]; then
        output_dest="/dev/null"
    else
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
    echo "Started in background (nohup mode, no re-attachment)"
}

spawn_with_tmux() {
    local no_log=$1
    shift
    local command_args=("$@")

    # Create session directory
    local session_dir
    session_dir=$(get_session_dir)
    if ! mkdir -p "$session_dir" 2>/dev/null; then
        echo "Error: Failed to create session directory: $session_dir" >&2
        exit 1
    fi

    # Generate unique session ID based on command name and arguments
    local session_id
    session_id=$(generate_session_id "${command_args[@]}")

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

    # Create a marker file for this session with the working directory
    echo "$PWD" > "${session_dir}/${session_id}.session"

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
}

main() {
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
                if ! has_tmux; then
                    echo "Error: --list requires tmux (not installed)" >&2
                    exit 1
                fi
                list_sessions "$PWD"
                exit 0
                ;;
            --list-all)
                if ! has_tmux; then
                    echo "Error: --list-all requires tmux (not installed)" >&2
                    exit 1
                fi
                list_sessions
                exit 0
                ;;
            --attach)
                if ! has_tmux; then
                    echo "Error: --attach requires tmux (not installed)" >&2
                    exit 1
                fi
                if [[ $# -lt 2 ]]; then
                    echo "Error: --attach requires a session ID" >&2
                    echo "" >&2
                    list_sessions >&2
                    exit 1
                fi
                attach_session "$2"
                exit $?
                ;;
            --kill)
                if ! has_tmux; then
                    echo "Error: --kill requires tmux (not installed)" >&2
                    exit 1
                fi
                if [[ $# -lt 2 ]]; then
                    echo "Error: --kill requires a session ID" >&2
                    echo "" >&2
                    list_sessions >&2
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

    # Use tmux if available, otherwise fall back to nohup
    if has_tmux; then
        spawn_with_tmux "$no_log" "${command_args[@]}"
    else
        spawn_with_nohup "$no_log" "${command_args[@]}"
    fi

    exit 0
}

main "$@"
