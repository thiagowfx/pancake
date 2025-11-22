#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS] TARGET

Kill processes gracefully using escalating signals.

ARGUMENTS:
    TARGET    Process identifier - can be:
              - PID (e.g., 1234)
              - Name (e.g., node)
              - Port (e.g., :8080 or 8080)

OPTIONS:
    -h, --help    Show this help message and exit
    -f, --force   Skip confirmation prompts

DESCRIPTION:
    This script terminates processes using an escalating signal strategy:
    1. SIGTERM (15) - graceful shutdown, 3s wait
    2. SIGINT (2)  - interrupt, 3s wait
    3. SIGHUP (1)  - hangup, 4s wait
    4. SIGKILL (9) - force kill

    When killing by name or port, the script shows matching processes
    and asks for confirmation before terminating each one (unless -f is used).

PREREQUISITES:
    - Standard Unix utilities: ps, kill, lsof (for port-based killing)

EXAMPLES:
    $0 1234           Kill process with PID 1234
    $0 node           Kill all processes named 'node'
    $0 :8080          Kill process listening on port 8080
    $0 -f python      Kill all python processes without confirmation
    $0 --help         Show this help

EXIT CODES:
    0    Successfully killed target process(es)
    1    Error occurred or no processes found
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "kill"
        "ps"
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

is_process_alive() {
    local pid=$1
    kill -0 "$pid" 2>/dev/null
}

kill_with_escalation() {
    local pid=$1
    local signals=(15 2 1 9)
    local waits=(3 3 4 0)
    local signal_names=("TERM" "INT" "HUP" "KILL")

    for i in "${!signals[@]}"; do
        if ! is_process_alive "$pid"; then
            return 0
        fi

        local sig=${signals[$i]}
        local wait_time=${waits[$i]}
        local sig_name=${signal_names[$i]}

        echo "  Sending SIG${sig_name} (${sig}) to PID ${pid}..."
        kill -"$sig" "$pid" 2>/dev/null || true

        if [[ $wait_time -gt 0 ]]; then
            sleep "$wait_time"
        fi
    done

    if is_process_alive "$pid"; then
        echo "  Failed to kill PID ${pid}"
        return 1
    fi

    echo "  Successfully killed PID ${pid}"
    return 0
}

kill_by_pid() {
    local pid=$1

    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid PID: $pid"
        return 1
    fi

    if ! is_process_alive "$pid"; then
        echo "Error: Process $pid does not exist or already terminated"
        return 1
    fi

    # Prevent self-termination
    if [[ "$pid" -eq $$ ]]; then
        echo "Error: Cannot kill self (PID $$)"
        return 1
    fi

    echo "Killing process $pid..."
    kill_with_escalation "$pid"
}

kill_by_name() {
    local name=$1
    local force=$2
    local pids
    local killed=0

    # Get PIDs matching the name, excluding this script's process
    # Using ps with grep for compatibility across systems (pgrep behavior varies)
    # shellcheck disable=SC2009
    pids=$(ps -eo pid,comm | grep -i "$name" | grep -v "^[[:space:]]*$$[[:space:]]" | awk '{print $1}' || true)

    if [[ -z "$pids" ]]; then
        echo "No processes found matching: $name"
        return 1
    fi

    echo "Found processes matching '$name':"
    ps -p "${pids//$'\n'/,}" -o pid,ppid,user,comm,args 2>/dev/null || true
    echo

    while IFS= read -r pid; do
        if [[ -z "$pid" ]]; then
            continue
        fi

        # Skip self
        if [[ "$pid" -eq $$ ]]; then
            continue
        fi

        local cmd
        cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")

        if [[ "$force" != "true" ]]; then
            echo -n "Kill PID $pid ($cmd)? [y/N] "
            read -r response </dev/tty
            case "$response" in
                [yY]|[yY][eE][sS]|[yY][aA][sS])
                    kill_with_escalation "$pid" && killed=$((killed + 1))
                    ;;
                *)
                    echo "  Skipped PID $pid"
                    ;;
            esac
        else
            kill_with_escalation "$pid" && killed=$((killed + 1))
        fi
    done <<< "$pids"

    if [[ $killed -eq 0 ]]; then
        echo "No processes were killed"
        return 1
    fi

    echo "Killed $killed process(es)"
    return 0
}

kill_by_port() {
    local port=$1
    local force=$2

    # Remove leading colon if present
    port=${port#:}

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid port number: $port"
        return 1
    fi

    if ! command -v lsof &> /dev/null; then
        echo "Error: 'lsof' is required for port-based killing but not found"
        return 1
    fi

    local pids
    pids=$(lsof -ti ":$port" 2>/dev/null || true)

    if [[ -z "$pids" ]]; then
        echo "No processes found listening on port $port"
        return 1
    fi

    echo "Found processes listening on port $port:"
    ps -p "${pids//$'\n'/,}" -o pid,ppid,user,comm,args 2>/dev/null || true
    echo

    local killed=0
    while IFS= read -r pid; do
        if [[ -z "$pid" ]]; then
            continue
        fi

        # Skip self
        if [[ "$pid" -eq $$ ]]; then
            continue
        fi

        local cmd
        cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")

        if [[ "$force" != "true" ]]; then
            echo -n "Kill PID $pid ($cmd) on port $port? [y/N] "
            read -r response </dev/tty
            case "$response" in
                [yY]|[yY][eE][sS]|[yY][aA][sS])
                    kill_with_escalation "$pid" && killed=$((killed + 1))
                    ;;
                *)
                    echo "  Skipped PID $pid"
                    ;;
            esac
        else
            kill_with_escalation "$pid" && killed=$((killed + 1))
        fi
    done <<< "$pids"

    if [[ $killed -eq 0 ]]; then
        echo "No processes were killed"
        return 1
    fi

    echo "Killed $killed process(es)"
    return 0
}

main() {
    local force=false
    local target=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -*)
                echo "Error: Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target=$1
                else
                    echo "Error: Multiple targets specified"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$target" ]]; then
        echo "Error: TARGET is required"
        usage
        exit 1
    fi

    check_dependencies

    # Determine target type and dispatch
    if [[ "$target" =~ ^:?[0-9]+$ ]] && [[ "$target" =~ : ]]; then
        # Port (starts with colon)
        kill_by_port "$target" "$force"
    elif [[ "$target" =~ ^[0-9]+$ ]]; then
        # Could be PID or port - check if process exists
        if is_process_alive "$target"; then
            kill_by_pid "$target"
        else
            # Try as port
            kill_by_port "$target" "$force"
        fi
    else
        # Name
        kill_by_name "$target" "$force"
    fi
}

main "$@"
