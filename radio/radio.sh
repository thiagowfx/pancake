#!/usr/bin/env bash
set -euo pipefail

# Station definitions
# Format: "station_id|name|url"
declare -a STATIONS=(
    "defcon|DEF CON Radio - Music for hacking|https://ice4.somafm.com/defcon-64-aac"
    "lofi|Lo-fi hip hop beats|https://live.hunter.fm/lofi_low"
    "trance|HBR1 Trance|http://ubuntu.hbr1.com:19800/trance.ogg"
    "salsa|Latina Salsa|https://latinasalsa.ice.infomaniak.ch/latinasalsa.mp3"
    "kfai|KFAI (Minneapolis community radio)|https://kfai.broadcasttool.stream/kfai-1"
)

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [station]

Stream internet radio stations using available media players.

OPTIONS:
    -h, --help        Show this help message and exit
    -l, --list        List all available stations
    -f, --foreground  Run in foreground (default is background)

STATIONS:
    defcon        DEF CON Radio - Music for hacking
    lofi          Lo-fi hip hop beats
    trance        HBR1 Trance
    salsa         Latina Salsa
    kfai          KFAI (Minneapolis community radio)

    If no station is specified, a random station will be selected.

DESCRIPTION:
    A simple radio player that streams from various internet radio stations.
    Automatically detects and uses available media players (mpv, vlc, ffplay, mplayer).

    By default, the player runs in background mode and you can close the terminal.
    The process is named 'radio-<station>' for easy identification.
    Use 'pkill -f radio-defcon' or 'murder radio' to stop playback.

PREREQUISITES:
    - At least one of: mpv, vlc, ffplay (ffmpeg), or mplayer

EXAMPLES:
    $0                  Stream a random station in background
    $0 defcon           Stream DEF CON Radio in background
    $0 -f lofi          Stream lo-fi hip hop in foreground
    $0 --list           Show all available stations
    pkill -f radio      Stop all radio streams
    murder radio        Stop all radio streams (if murder is installed)

EXIT CODES:
    0    Successfully started streaming
    1    Invalid station or no media player available
EOF
}

list_stations() {
    echo "Available stations:"
    echo
    for station in "${STATIONS[@]}"; do
        IFS='|' read -r id name url <<< "$station"
        printf "  %-12s  %s\n" "$id" "$name"
    done
}

find_media_player() {
    # Try media players in order of preference
    local players=("mpv" "vlc" "ffplay" "mplayer")

    for player in "${players[@]}"; do
        if command -v "$player" &> /dev/null; then
            echo "$player"
            return 0
        fi
    done

    return 1
}

get_player_args() {
    local player="$1"
    local url="$2"

    case "$player" in
        mpv)
            echo "--really-quiet" "$url"
            ;;
        vlc)
            echo "-I" "dummy" "--quiet" "$url"
            ;;
        ffplay)
            echo "-nodisp" "-autoexit" "-loglevel" "quiet" "$url"
            ;;
        mplayer)
            echo "-really-quiet" "$url"
            ;;
    esac
}

get_random_station() {
    local random_index=$((RANDOM % ${#STATIONS[@]}))
    local station="${STATIONS[$random_index]}"
    IFS='|' read -r id name url <<< "$station"
    echo "$id"
}

main() {
    local background=true
    local station=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--list)
                list_stations
                exit 0
                ;;
            -f|--foreground)
                background=false
                shift
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                echo "Run '$0 --help' for usage information" >&2
                exit 1
                ;;
            *)
                station="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$station" ]]; then
        station=$(get_random_station)
        echo "No station specified, randomly selected: $station"
    fi

    # Find available media player
    local player
    if ! player=$(find_media_player); then
        echo "Error: No media player found" >&2
        echo "Install one of: mpv, vlc, ffmpeg (ffplay), or mplayer" >&2
        echo "macOS: brew install mpv" >&2
        echo "Linux: sudo apt install mpv (or equivalent)" >&2
        exit 1
    fi

    # Find station URL
    local url=""
    local found=false
    for entry in "${STATIONS[@]}"; do
        IFS='|' read -r id name station_url <<< "$entry"
        if [[ "$id" == "$station" ]]; then
            url="$station_url"
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then
        echo "Error: Unknown station '$station'" >&2
        echo "Run '$0 --list' to see available stations" >&2
        exit 1
    fi

    # Get player-specific arguments
    local -a args
    read -ra args <<< "$(get_player_args "$player" "$url")"

    if [[ "$background" == true ]]; then
        echo "Starting $station radio in background using $player..."
        echo "Stop with: pkill -f radio-$station"

        # Create a wrapper script with 'radio-' in the name for easy identification
        local wrapper_script="/tmp/radio-$station-$$"
        cat > "$wrapper_script" << EOF
#!/bin/bash
exec -a "radio-$station" "$player" ${args[@]}
EOF
        chmod +x "$wrapper_script"

        nohup "$wrapper_script" >/dev/null 2>&1 &
        disown

        # Clean up wrapper script after a delay
        (sleep 2 && rm -f "$wrapper_script") &
    else
        echo "Streaming $station radio using $player..."
        echo "Press Ctrl+C to stop"
        exec -a "radio-$station" "$player" "${args[@]}"
    fi
}

main "$@"
