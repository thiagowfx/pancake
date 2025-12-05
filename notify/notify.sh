#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [TITLE] [MESSAGE...]

Send desktop notifications across Linux and macOS platforms.

Cross-platform desktop notification tool that works on both Linux and macOS.
On Linux, it uses notify-send. On macOS, it uses osascript with JXA
(JavaScript for Automation). All arguments after the title are concatenated
with spaces to form the notification message.

ARGUMENTS:
    TITLE           Notification title (default: "Notification")
    MESSAGE...      One or more message arguments (joined with spaces)
                    (default: current timestamp)

OPTIONS:
    -h, --help      Show this help message and exit
    -p, --persistent  Keep notification on screen until dismissed
    -s, --sound [SOUND]  Play a sound with the notification
                         SOUND: Optional sound name (default: Glass)
                         macOS: Basso, Blow, Bottle, Frog, Funk, Glass, Hero,
                                Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
                         Linux: Uses paplay or aplay if available

EXAMPLES:
    $cmd                                  Send notification with defaults
    $cmd "Build Complete"                 Send with custom title
    $cmd "Deploy" "Production is live"    Send with title and description
    $cmd "Coffee Time" "☕"                Unicode works too
    $cmd Build complete in 42 seconds     Multiple args form the message
    $cmd -p "Critical Alert"              Persistent notification
    $cmd --persistent "Error" "Fix ASAP"  Persistent with title and message
    $cmd -s "Build Complete"              Notification with default sound
    $cmd -s Hero "Deploy Done"            Notification with Hero sound
    $cmd --sound Ping "Test" "Success"    Notification with Ping sound
    $cmd -ps Basso "Alert"                Persistent notification with sound

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

play_sound() {
    local sound_name="${1:-Glass}"

    # Try afplay (macOS)
    if command -v afplay &> /dev/null; then
        local sound_path="/System/Library/Sounds/${sound_name}.aiff"
        if [[ -f "$sound_path" ]]; then
            afplay "$sound_path" &>/dev/null &
            return 0
        else
            echo "Warning: Sound '$sound_name' not found at $sound_path" >&2
            return 1
        fi
    fi

    # Try paplay (Linux - PulseAudio)
    if command -v paplay &> /dev/null; then
        # Use a default system sound if available
        local sound_path="/usr/share/sounds/freedesktop/stereo/message.oga"
        if [[ -f "$sound_path" ]]; then
            paplay "$sound_path" &>/dev/null &
            return 0
        fi
    fi

    # Try aplay (Linux - ALSA)
    if command -v aplay &> /dev/null; then
        local sound_path="/usr/share/sounds/alsa/Front_Center.wav"
        if [[ -f "$sound_path" ]]; then
            aplay "$sound_path" &>/dev/null &
            return 0
        fi
    fi

    return 1
}

send_notification() {
    local title="${1:-Notification}"
    local description="${2:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
    local persistent="${3:-false}"

    # Try notify-send (Linux)
    if command -v notify-send &> /dev/null; then
        if [[ "$persistent" == "true" ]]; then
            # expire-time=0 means the notification stays until dismissed
            if notify-send --expire-time=0 "$title" "$description" 2>/dev/null; then
                return 0
            fi
        else
            if notify-send --expire-time=5000 "$title" "$description" 2>/dev/null; then
                return 0
            fi
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
        if [[ "$persistent" == "true" ]]; then
            # Use display alert for persistent notifications (modal dialog)
            js_script=$(cat <<EOF
var app = Application.currentApplication();
app.includeStandardAdditions = true;
app.activate();
app.displayAlert("$escaped_title", {
    message: "$escaped_description"
});
EOF
)
        else
            # Use display notification for regular notifications
            js_script=$(cat <<EOF
var app = Application.currentApplication();
app.includeStandardAdditions = true;
app.displayNotification("$escaped_description", {
    withTitle: "$escaped_title"
});
EOF
)
        fi
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
    local persistent="false"
    local play_sound_flag="false"
    local sound_name="Glass"
    local title=""
    local description=""

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--persistent)
                persistent="true"
                shift
                ;;
            -s|--sound)
                play_sound_flag="true"
                shift
                # Check if next argument is a sound name (not a flag, single word, no spaces)
                if [[ $# -gt 0 && ! "$1" =~ ^- && ! "$1" =~ [[:space:]] ]]; then
                    # Only treat as sound name if the file actually exists
                    if [[ -f "/System/Library/Sounds/${1}.aiff" ]]; then
                        sound_name="$1"
                        shift
                    fi
                fi
                ;;
            -ps|-sp)
                # Combined flags: persistent + sound
                persistent="true"
                play_sound_flag="true"
                shift
                # Check for sound name after combined flag (single word, file exists)
                if [[ $# -gt 0 && ! "$1" =~ [[:space:]] && -f "/System/Library/Sounds/${1}.aiff" ]]; then
                    sound_name="$1"
                    shift
                fi
                ;;
            *)
                # First non-flag argument is the title
                if [[ -z "$title" ]]; then
                    title="$1"
                    shift
                    # Rest of arguments form the description
                    description="$*"
                    break
                fi
                ;;
        esac
    done

    send_notification "$title" "$description" "$persistent"

    if [[ "$play_sound_flag" == "true" ]]; then
        play_sound "$sound_name"
    fi
}

main "$@"
