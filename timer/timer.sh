#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS] DURATION

Count down for a specified duration and notify when complete.

ARGUMENTS:
    DURATION        Time to wait (accepts sleep format: 5, 5s, 5m, 5h, etc.)

OPTIONS:
    -h, --help      Show this help message and exit
    -s, --silent    Skip audio notification (desktop notification only)

DESCRIPTION:
    Simple countdown timer that waits for the specified duration and then
    alerts you with an optional audio cue and desktop notification.

    The DURATION argument uses the same format as the sleep command:
    - Numbers without suffix are interpreted as seconds
    - Suffix 's' for seconds, 'm' for minutes, 'h' for hours, 'd' for days
    - You can combine multiple values: "1h 30m" or "90s"

EXAMPLES:
    $0 5                    Wait 5 seconds
    $0 5m                   Wait 5 minutes
    $0 1h                   Wait 1 hour
    $0 90s                  Wait 90 seconds (1.5 minutes)
    $0 1h 30m               Wait 1.5 hours
    $0 --silent 10m         Wait 10 minutes without audio
    $0 -s 300               Wait 300 seconds (5 minutes) without audio

EXIT CODES:
    0    Timer completed successfully
    1    Invalid arguments or timer interrupted
EOF
}

play_sound() {
    # Try to play a system sound - platform dependent
    if command -v afplay &> /dev/null; then
        # macOS - use a built-in system sound
        afplay /System/Library/Sounds/Glass.aiff 2>/dev/null || true
    elif command -v paplay &> /dev/null; then
        # Linux (PulseAudio) - try to play a system sound
        paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true
    elif command -v aplay &> /dev/null; then
        # Linux (ALSA) - try to play a system sound
        aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || true
    fi
    # If no sound system is available or sound fails, just continue silently
}

format_duration() {
    local duration="$1"
    echo "${duration// /}"
}

main() {
    local silent=false
    local duration=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -s|--silent)
                silent=true
                shift
                ;;
            --)
                # End of options marker
                shift
                duration="$*"
                break
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                echo "Run '$0 --help' for usage information." >&2
                exit 1
                ;;
            *)
                # Collect all remaining arguments as the duration
                duration="$*"
                break
                ;;
        esac
    done

    # Validate duration argument
    if [[ -z "$duration" ]]; then
        echo "Error: DURATION argument is required" >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    # Validate that sleep accepts this duration format
    # Use a basic regex check for common invalid patterns
    if [[ "$duration" =~ ^-.*$ ]] || [[ "$duration" =~ [^0-9smhd\ \.] ]]; then
        echo "Error: Invalid duration format: $duration" >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    local formatted_duration
    formatted_duration=$(format_duration "$duration")

    echo "Timer started for $formatted_duration..."

    # Actually sleep for the duration
    sleep "$duration"

    echo "Timer complete!"

    # Play sound unless silent mode is enabled
    if [[ "$silent" == false ]]; then
        play_sound
    fi

    # Send desktop notification
    local notify_script
    notify_script="$(dirname "$0")/../notify/notify.sh"

    # Try to find notify script in common locations
    if [[ ! -x "$notify_script" ]]; then
        # Try to find it in PATH
        notify_script=$(command -v notify.sh 2>/dev/null || echo "")
    fi

    if [[ -n "$notify_script" ]] && [[ -x "$notify_script" ]]; then
        "$notify_script" "Timer complete" "$formatted_duration" 2>/dev/null || true
    else
        echo "Note: Desktop notification not available (notify.sh not found)" >&2
    fi
}

main "$@"
