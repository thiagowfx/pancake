#!/bin/bash
set -uo pipefail

# set -e is intentionally omitted to allow the script to continue running and
# attempt all upgrades, even if some fail. This allows for a comprehensive
# summary of successes and failures at the end.

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Perform a full system upgrade across different operating systems and package managers.

OPTIONS:
    -h, --help    Show this help message and exit

DESCRIPTION:
    This script detects the current operating system and available package managers,
    then performs comprehensive system upgrades. It handles multiple package managers
    gracefully and provides a summary of upgrade results.

    Supported systems and package managers:
    - Linux: Alpine (apk), Arch (pacman), Debian/Ubuntu (apt), Flatpak, Nix (nix-env)
    - macOS: Homebrew (brew), Mac App Store (mas), System Updates (softwareupdate)
    - Cross-platform: Claude Code, myrepos, sd_world_corp

EXAMPLES:
    $0              Upgrade all available package managers
    $0 --help       Show this help

EXIT CODES:
    0    All available package managers upgraded successfully
    1    Some package managers failed to upgrade or none were found
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Track current upgrade for diagnostics
CURRENT_UPGRADE=""

# Global counters for diagnostics
total_managers=0
successful_managers=0
failed_managers=0
failed_list=()

cleanup_and_exit() {
    # Kill any running background jobs first
    for job in $(jobs -p 2>/dev/null); do
        kill -TERM "$job" 2>/dev/null || kill -KILL "$job" 2>/dev/null
    done

    echo ""

    if [[ -n "$CURRENT_UPGRADE" ]]; then
        log_warning "Interrupted during $CURRENT_UPGRADE upgrade"
    fi
    log_warning "Script interrupted by user"

    # Print diagnostics if we've processed any managers
    if [[ $total_managers -gt 0 ]]; then
        echo ""
        log "Interrupt Summary:"
        echo "Processed: $total_managers package managers"
        echo "Successful: $successful_managers"
        echo "Failed: $failed_managers"

        if [[ ${#failed_list[@]} -gt 0 ]]; then
            echo "Failed upgrades: ${failed_list[*]}"
        fi

        local skipped=$((total_managers - successful_managers - failed_managers))
        if [[ $skipped -gt 0 ]]; then
            echo "Interrupted/Skipped: $skipped"
        fi
    fi

    exit 130
}


# Signal handler for script-level interrupts
trap 'cleanup_and_exit' SIGINT

log() {
    echo "$(tput bold)$(tput setaf 4)$*$(tput sgr0)"  # Bold blue
}

log_success() {
    echo "$(tput bold)$(tput setaf 2)✓ $*$(tput sgr0)"  # Bold green
}

log_error() {
    echo "$(tput bold)$(tput setaf 1)✗ $*$(tput sgr0)"  # Bold red
}

log_warning() {
    echo "$(tput bold)$(tput setaf 3)⚠ $*$(tput sgr0)"  # Bold yellow
}

run_upgrade() {
    local manager_name="$1"
    shift
    local cmd=("$@")

    CURRENT_UPGRADE="$manager_name"
    log "Upgrading $manager_name..."

    # Create a temporary file to capture output
    local temp_output
    temp_output=$(mktemp)

    # Run the command in background to maintain control, showing output in real-time via tee
    eval "${cmd[*]}" 2>&1 | tee "$temp_output" &
    local cmd_pid=$!

    # Wait for the command to complete, allowing interrupts
    if wait "$cmd_pid"; then
        # Success - output already shown via tee
        rm -f "$temp_output"
        log_success "$manager_name upgrade completed successfully"
        CURRENT_UPGRADE=""
        return 0
    else
        local exit_code=$?

        if [[ $exit_code -eq 130 ]] || [[ $exit_code -ge 128 ]]; then
            # Interrupted by signal - clean up and show diagnostics
            rm -f "$temp_output"
            echo ""
            log_warning "$manager_name upgrade interrupted"
            CURRENT_UPGRADE=""
            cleanup_and_exit
        else
            # Command failed - output already shown via tee
            rm -f "$temp_output"
            log_error "$manager_name upgrade failed"
            CURRENT_UPGRADE=""
            return 1
        fi
    fi
}

check_and_run() {
    local check_cmd="$1"
    local manager_name="$2"
    shift 2
    local upgrade_cmd=("$@")

    if command -v "$check_cmd" >/dev/null 2>&1; then
        if run_upgrade "$manager_name" "${upgrade_cmd[@]}"; then
            return 0
        else
            local exit_code=$?
            if [[ $exit_code -eq 130 ]]; then
                return 130  # Interrupted
            fi
            return 1
        fi
    else
        return 2  # Not available
    fi
}

handle_upgrade_result() {
    local manager_name="$1"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        successful_managers=$((successful_managers + 1))
    elif [[ $exit_code -eq 1 ]]; then
        failed_managers=$((failed_managers + 1))
        failed_list+=("$manager_name")
    elif [[ $exit_code -eq 130 ]]; then
        # Interrupted - skip this manager but continue
        log_warning "Skipped $manager_name due to interrupt"
    fi

    [[ $exit_code -ne 2 ]] && total_managers=$((total_managers + 1))
    echo ""  # Add spacing between upgrades
}

main() {
    log "Starting system upgrade..."
    echo ""

    case "$(uname)" in
        Linux)
            log "Detected Linux system"
            echo ""

            # Alpine Linux
            check_and_run "apk" "Alpine (apk)" doas apk update && doas apk upgrade
            handle_upgrade_result "Alpine (apk)"

            # Arch Linux
            check_and_run "pacman" "Arch (pacman)" sudo pacman -Syu --noconfirm
            handle_upgrade_result "Arch (pacman)"

            # Debian/Ubuntu
            check_and_run "apt" "Debian/Ubuntu (apt)" sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
            handle_upgrade_result "Debian/Ubuntu (apt)"

            # Flatpak
            check_and_run "flatpak" "Flatpak" flatpak update -y
            handle_upgrade_result "Flatpak"

            # Nix
            check_and_run "nix-channel" "Nix" nix-channel --update && nix-env -u
            handle_upgrade_result "Nix"
            ;;

        Darwin)
            log "Detected macOS system"
            echo ""

            # Homebrew
            check_and_run "brew" "Homebrew" brew upgrade && brew upgrade --fetch-HEAD && brew cleanup
            handle_upgrade_result "Homebrew"

            # Mac App Store
            check_and_run "mas" "Mac App Store" mas upgrade
            handle_upgrade_result "Mac App Store"

            # System Updates
            check_and_run "softwareupdate" "System Updates" softwareupdate --install --safari-only
            handle_upgrade_result "System Updates"
            ;;

        *)
            log_error "Unsupported operating system: $(uname)"
            exit 1
            ;;
    esac

    # Cross-platform tools (run after OS-specific upgrades)
    check_and_run "claude" "Claude Code" claude update
    handle_upgrade_result "Claude Code"

    check_and_run "mr" "myrepos" "cd ~ && mr --stats update"
    handle_upgrade_result "myrepos"

    check_and_run "sd_world_corp" "sd_world_corp" sd_world_corp
    handle_upgrade_result "sd_world_corp"

    echo ""
    log "Upgrade Summary:"
    echo "Successfully upgraded: $successful_managers/$total_managers package managers"

    if [[ ${#failed_list[@]} -gt 0 ]]; then
        echo "Failed upgrades: ${failed_list[*]}"
    fi

    if [[ $total_managers -eq 0 ]]; then
        log_error "No package managers found on this system."
        exit 1
    elif [[ $successful_managers -eq $total_managers ]]; then
        log_success "All package managers upgraded successfully!"
        exit 0
    else
        log_error "Some package managers failed to upgrade."
        exit 1
    fi
}

main "$@"
