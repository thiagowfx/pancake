#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TITLE] [MESSAGE...]

Send desktop notifications across Linux and macOS platforms.

ARGUMENTS:
    TITLE           Notification title (default: "Notification")
    MESSAGE...      One or more message arguments (joined with spaces)
                    (default: current timestamp)

OPTIONS:
    -h, --help      Show this help message and exit

DESCRIPTION:
    Cross-platform desktop notification tool that works on both Linux and
    macOS. On Linux, it uses notify-send. On macOS, it uses osascript with
    JXA (JavaScript for Automation).

    All arguments after the title are concatenated with spaces to form
    the notification message.

EXAMPLES:
    $0                                  Send notification with defaults
    $0 "Build Complete"                 Send with custom title
    $0 "Deploy" "Production is live"    Send with title and description
    $0 "Coffee Time" "☕"                Unicode works too
    $0 Build complete in 42 seconds     Multiple args form the message

EXIT CODES:
    0    Notification sent successfully
    1    Failed to send notification (no supported method available)
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

json_escape() {
    local input="$1"
    # Escape backslashes first, then quotes, then newlines
    printf '%s' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

send_notification() {
    local title="${1:-Notification}"
    local description="${2:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

    # Try notify-send (Linux)
    if command -v notify-send &> /dev/null; then
        if notify-send --expire-time=5000 "$title" "$description" 2>/dev/null; then
            return 0
        fi
    fi

    # Try osascript (macOS)
    if command -v osascript &> /dev/null; then
        # Use JXA (JavaScript for Automation)
        local escaped_title
        local escaped_description
        escaped_title=$(json_escape "$title")
        escaped_description=$(json_escape "$description")

        local js_script
        js_script=$(cat <<EOF
var app = Application.currentApplication();
app.includeStandardAdditions = true;
app.displayNotification("$escaped_description", {
    withTitle: "$escaped_title"
});
EOF
)
        if osascript -l JavaScript -e "$js_script" 2>/dev/null; then
            return 0
        fi
    fi

    echo "Error: Cannot send notifications. No supported notification system found." >&2
    echo "Linux: Install libnotify-bin (notify-send)" >&2
    echo "macOS: osascript should be available by default" >&2
    return 1
}

main() {
    local title="${1:-}"
    local description=""

    # If we have more than one argument, join all but the first as the description
    if [[ $# -gt 1 ]]; then
        shift
        description="$*"
    fi

    send_notification "$title" "$description"
}

main "$@"
