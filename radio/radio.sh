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
    "rain|Rain sounds for relaxation|http://maggie.torontocast.com:8108/stream"
    "jazz|SomaFM - Jazz|https://ice4.somafm.com/live-64-aac"
    "groovesalad|SomaFM - Groove Salad (ambient/downtempo)|https://ice4.somafm.com/groovesalad-64-aac"
    "ambient|SomaFM - Drone Zone|https://ice4.somafm.com/dronezone-64-aac"
    "indie|SomaFM - Indie Pop Rocks|https://ice4.somafm.com/indiepop-64-aac"
    "bossa|SomaFM - Bossa Beyond|https://ice4.somafm.com/bossa-64-aac"
)

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [station]

Stream internet radio stations using available media players.

A simple radio player that streams from various internet radio stations.
Automatically detects and uses available media players (mpv, vlc, ffplay,
mplayer).

OPTIONS:
    -h, --help        Show this help message and exit
    -l, --list        List all available stations
    -f, --foreground  Run in foreground (default is background)
    -k, --kill [station]  Kill radio processes (all or specific station)
    -b, --burst [N]   Launch N random stations simultaneously (default: 3)

STATIONS:
    defcon        DEF CON Radio - Music for hacking
    lofi          Lo-fi hip hop beats
    trance        HBR1 Trance
    salsa         Latina Salsa
    kfai          KFAI (Minneapolis community radio)
    rain          Rain sounds for relaxation
    jazz          SomaFM - Jazz
    groovesalad   SomaFM - Groove Salad (ambient/downtempo)
    ambient       SomaFM - Drone Zone
    indie         SomaFM - Indie Pop Rocks
    bossa         SomaFM - Bossa Beyond

    If no station is specified, a random station will be selected.

    By default, the player runs in background mode and you can close the terminal.
    The process is named 'radio-<station>' for easy identification.
    Use 'pkill -f radio-defcon' or 'murder radio' to stop playback.

PREREQUISITES:
    - At least one of: mpv, vlc, ffplay (ffmpeg), or mplayer

EXAMPLES:
    $cmd                  Stream a random station in background
    $cmd defcon           Stream DEF CON Radio in background
    $cmd -f lofi          Stream lo-fi hip hop in foreground
    $cmd --list           Show all available stations
    $cmd -k               Kill all existing radio processes
    $cmd -k salsa         Kill only salsa radio processes
    $cmd -b               Launch 3 random stations simultaneously
    $cmd -b 5             Launch 5 random stations simultaneously
    pkill -f radio      Stop all radio streams (alternative)
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

launch_station() {
    local station="$1"
    local player="$2"

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
        return 1
    fi

    # Get player-specific arguments
    local -a args
    read -ra args <<< "$(get_player_args "$player" "$url")"

    echo "Starting $station radio in background using $player..."

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
}

burst_mode() {
    local count="${1:-3}"

    # Validate count is a positive integer
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -eq 0 ]]; then
        echo "Error: Burst count must be a positive integer" >&2
        exit 1
    fi

    # Cap count at total number of stations
    if [[ "$count" -gt "${#STATIONS[@]}" ]]; then
        echo "Warning: Requested $count stations, but only ${#STATIONS[@]} available. Using ${#STATIONS[@]}." >&2
        count="${#STATIONS[@]}"
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

    echo "Launching burst mode: $count random stations..."
    echo

    # Select N unique random stations
    local -a selected_stations=()
    local -a available_indices=()

    # Build array of available indices
    for i in "${!STATIONS[@]}"; do
        available_indices+=("$i")
    done

    # Shuffle and pick first N
    for ((i=0; i<count; i++)); do
        if [[ ${#available_indices[@]} -eq 0 ]]; then
            break
        fi
        local random_pos=$((RANDOM % ${#available_indices[@]}))
        local selected_index="${available_indices[$random_pos]}"
        local station="${STATIONS[$selected_index]}"
        IFS='|' read -r id name url <<< "$station"
        selected_stations+=("$id")
        # Remove selected index from available pool
        unset 'available_indices[$random_pos]'
        available_indices=("${available_indices[@]}")
    done

    # Launch each selected station
    for station in "${selected_stations[@]}"; do
        launch_station "$station" "$player"
        sleep 0.5
    done

    echo
    echo "Burst mode complete: ${#selected_stations[@]} stations launched"
    echo "Stop all with: pkill -f radio"
}

kill_radio_processes() {
    local target_station="${1:-}"

    if [[ -n "$target_station" ]]; then
        echo "Looking for $target_station radio processes..."
    else
        echo "Looking for radio processes..."
    fi

    # Find media player processes streaming from known radio station URLs
    # We match against the station URLs since exec -a doesn't work reliably on macOS
    local pids=()
    for station in "${STATIONS[@]}"; do
        IFS='|' read -r id name url <<< "$station"

        # If target station specified, only match that station
        if [[ -n "$target_station" ]] && [[ "$id" != "$target_station" ]]; then
            continue
        fi

        # Use pgrep -f to match the URL in the command line
        while IFS= read -r pid; do
            if [[ -n "$pid" ]]; then
                pids+=("$pid")
            fi
        done < <(pgrep -f "$url" 2>/dev/null || true)
    done

    if [[ ${#pids[@]} -eq 0 ]]; then
        if [[ -n "$target_station" ]]; then
            echo "No $target_station radio processes found"
        else
            echo "No radio processes found"
        fi
        return 0
    fi

    echo "Found radio processes:"
    ps -p "$(IFS=,; echo "${pids[*]}")" -o pid,comm,args 2>/dev/null || true
    echo

    # Kill each process
    for pid in "${pids[@]}"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Killing process $pid..."
            kill "$pid" 2>/dev/null || true
            sleep 0.5

            # Force kill if still alive
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing process $pid..."
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    done

    if [[ -n "$target_station" ]]; then
        echo "$target_station radio processes terminated"
    else
        echo "All radio processes terminated"
    fi
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
            -k|--kill)
                shift
                # Check if next arg is a station name
                if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
                    kill_radio_processes "$1"
                    exit 0
                else
                    kill_radio_processes
                    exit 0
                fi
                ;;
            -b|--burst)
                shift
                # Check if next arg is a positive integer
                if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                    burst_mode "$1"
                    exit 0
                else
                    burst_mode
                    exit 0
                fi
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
