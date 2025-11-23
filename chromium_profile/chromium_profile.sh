#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [COMMAND]

Manage and launch Chrome/Chromium browser profiles.

This script helps manage Chrome/Chromium profiles by listing available profiles
and launching the browser with a specific profile. Profiles can be opened by
either their directory name ("Default", "Profile 1") or their display name
("spongebob", "patrick").

COMMANDS:
    list                      List all available profiles (default)
    open <profile> [url...]   Open browser with specified profile and optional URLs

OPTIONS:
    -b, --browser <name>    Specify browser (chrome|chromium|brave)
                            Default: auto-detect first available
    -h, --help              Show this help message and exit

PREREQUISITES:
    - Chrome, Chromium, or Brave browser installed
    - 'jq' must be installed for JSON parsing

EXAMPLES:
    $cmd                                          List all profiles
    $cmd list                                     List all profiles
    $cmd open "Profile 1"                         Open Chrome with Profile 1
    $cmd open spongebob                           Open with spongebob profile
    $cmd open spongebob https://example.com       Open profile with URL
    $cmd open spongebob https://example.com https://example.org
                                                Open profile with multiple URLs
    $cmd -b brave open Default                    Open Brave with Default profile
    $cmd --browser chromium list                  List Chromium profiles

EXIT CODES:
    0    Success
    1    Error (missing dependencies, invalid profile, etc.)
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "jq"
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
        echo "Install with: brew install ${missing_deps[*]}"
        exit 1
    fi
}

get_user_data_dirs() {
    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Darwin)
            echo "chrome|$HOME/Library/Application Support/Google/Chrome"
            echo "chromium|$HOME/Library/Application Support/Chromium"
            echo "brave|$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
            ;;
        Linux)
            echo "chrome|$HOME/.config/google-chrome"
            echo "chromium|$HOME/.config/chromium"
            echo "brave|$HOME/.config/BraveSoftware/Brave-Browser"
            ;;
        *)
            echo "Error: Unsupported operating system: $os_type" >&2
            exit 1
            ;;
    esac
}

detect_browser() {
    local browser_name="${1:-}"
    local browser_id=""
    local user_data_dir=""

    while IFS='|' read -r id data_path; do
        if [[ -n "$browser_name" ]]; then
            # Check if this browser matches the requested one
            if [[ "$id" == *"$browser_name"* ]] || [[ "$data_path" == *"$browser_name"* ]]; then
                if [[ -d "$data_path" ]]; then
                    browser_id="$id"
                    user_data_dir="$data_path"
                    break
                fi
            fi
        else
            # Auto-detect first available browser
            if [[ -d "$data_path" ]]; then
                browser_id="$id"
                user_data_dir="$data_path"
                break
            fi
        fi
    done < <(get_user_data_dirs)

    if [[ -z "$browser_id" ]] || [[ -z "$user_data_dir" ]]; then
        if [[ -n "$browser_name" ]]; then
            echo "Error: Could not find browser '$browser_name'" >&2
        else
            echo "Error: Could not find any supported browser" >&2
        fi
        exit 1
    fi

    echo "$browser_id|$user_data_dir"
}

list_profiles() {
    local user_data_dir="$1"
    local local_state="$user_data_dir/Local State"

    if [[ ! -f "$local_state" ]]; then
        echo "Error: Could not find Local State file at: $local_state" >&2
        exit 1
    fi

    echo "Available profiles in $user_data_dir:"
    echo ""

    # Parse Local State JSON to get profile information
    local profiles
    profiles=$(jq -r '.profile.info_cache | to_entries[] | "\(.key)|\(.value.name // "Unnamed")"' "$local_state" 2>/dev/null || echo "")

    if [[ -z "$profiles" ]]; then
        echo "No profiles found."
        exit 0
    fi

    while IFS='|' read -r dir_name display_name; do
        if [[ -n "$dir_name" ]]; then
            printf "  %-20s %s\n" "$dir_name" "$display_name"
        fi
    done <<< "$profiles"
}

resolve_profile_name() {
    local user_data_dir="$1"
    local profile_input="$2"
    local local_state="$user_data_dir/Local State"

    # First check if it's a direct directory match
    if [[ -d "$user_data_dir/$profile_input" ]]; then
        echo "$profile_input"
        return 0
    fi

    # Try to find by display name
    if [[ -f "$local_state" ]]; then
        local profiles
        profiles=$(jq -r '.profile.info_cache | to_entries[] | "\(.key)|\(.value.name // "Unnamed")"' "$local_state" 2>/dev/null || echo "")

        while IFS='|' read -r dir_name display_name; do
            if [[ -n "$dir_name" ]] && [[ "$display_name" == "$profile_input" ]]; then
                echo "$dir_name"
                return 0
            fi
        done <<< "$profiles"
    fi

    # Profile not found
    return 1
}

launch_browser() {
    local browser_id="$1"
    local profile_dir="$2"
    shift 2
    local urls=("$@")
    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Darwin)
            case "$browser_id" in
                chrome)
                    open -na "Google Chrome" --args --profile-directory="$profile_dir" "${urls[@]}"
                    ;;
                chromium)
                    open -na "Chromium" --args --profile-directory="$profile_dir" "${urls[@]}"
                    ;;
                brave)
                    open -na "Brave Browser" --args --profile-directory="$profile_dir" "${urls[@]}"
                    ;;
            esac
            ;;
        Linux)
            case "$browser_id" in
                chrome)
                    google-chrome --profile-directory="$profile_dir" "${urls[@]}" &>/dev/null &
                    ;;
                chromium)
                    if command -v chromium &>/dev/null; then
                        chromium --profile-directory="$profile_dir" "${urls[@]}" &>/dev/null &
                    else
                        chromium-browser --profile-directory="$profile_dir" "${urls[@]}" &>/dev/null &
                    fi
                    ;;
                brave)
                    if command -v brave &>/dev/null; then
                        brave --profile-directory="$profile_dir" "${urls[@]}" &>/dev/null &
                    else
                        brave-browser --profile-directory="$profile_dir" "${urls[@]}" &>/dev/null &
                    fi
                    ;;
            esac
            ;;
    esac
}

open_profile() {
    local browser_id="$1"
    local user_data_dir="$2"
    local profile_input="$3"
    shift 3
    local urls=("$@")

    # Resolve profile name to directory
    local profile_dir
    if ! profile_dir=$(resolve_profile_name "$user_data_dir" "$profile_input"); then
        echo "Error: Profile not found: $profile_input" >&2
        echo "Run '$0 list' to see available profiles." >&2
        exit 1
    fi

    echo "Opening browser with profile: $profile_dir"
    if [[ ${#urls[@]} -gt 0 ]]; then
        echo "URLs: ${urls[*]}"
    fi
    launch_browser "$browser_id" "$profile_dir" "${urls[@]}"
}

main() {
    check_dependencies

    local browser_name=""
    local command="list"
    local profile_dir=""
    local extra_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -b|--browser)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --browser requires an argument" >&2
                    exit 1
                fi
                browser_name="$2"
                shift 2
                ;;
            list)
                command="list"
                shift
                ;;
            open)
                command="open"
                if [[ $# -lt 2 ]]; then
                    echo "Error: 'open' command requires a profile name" >&2
                    echo "Run '$0 list' to see available profiles." >&2
                    exit 1
                fi
                profile_dir="$2"
                shift 2
                # Collect remaining arguments as URLs or extra args
                while [[ $# -gt 0 ]]; do
                    extra_args+=("$1")
                    shift
                done
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                echo "Run '$0 --help' for usage information." >&2
                exit 1
                ;;
        esac
    done

    # Detect browser
    local browser_info
    browser_info=$(detect_browser "$browser_name")
    local browser_id
    local user_data_dir
    IFS='|' read -r browser_id user_data_dir <<< "$browser_info"

    case "$command" in
        list)
            list_profiles "$user_data_dir"
            ;;
        open)
            open_profile "$browser_id" "$user_data_dir" "$profile_dir" "${extra_args[@]}"
            ;;
    esac
}

main "$@"
