#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Free up disk space by pruning old and unused cache data from various tools.

By default, runs in dry-run mode (shows what would be cleaned without actually cleaning).
Use --execute to actually perform the cleanup.

OPTIONS:
    -h, --help       Show this help message and exit
    -x, --execute    Actually perform cleanup (default is dry-run)
    -y, --yes        Skip confirmation prompt and proceed automatically
    -v, --verbose    Show detailed output during operations

DESCRIPTION:
    This script safely removes old and unused cache data from:
    - Docker (dangling images, unused containers, volumes, networks, build cache)
    - pre-commit (old hook environments not used recently)
    - Homebrew (old formula versions and cached downloads)

    The script gracefully skips any tools that are not installed on your system.

PREREQUISITES:
    At least one of the following tools must be installed:
    - Docker CLI ('docker')
    - pre-commit ('pip install pre-commit')
    - Homebrew ('brew')

EXAMPLES:
    $0                    Preview what would be cleaned (dry-run)
    $0 --execute          Run interactively with confirmation for each cache
    $0 -x -y              Execute cleanup without prompts
    $0 -v                 Verbose dry-run preview

EXIT CODES:
    0    Successfully cleaned cache or dry-run completed
    1    No tools found or error occurred
EOF
}

# Parse command-line arguments
DRY_RUN=true
AUTO_YES=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -x|--execute)
            DRY_RUN=false
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
            ;;
    esac
done

# Check if Docker is available and has data to clean
check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        return 1
    fi

    return 0
}

# Get estimated Docker reclaimable space
get_docker_size() {
    local reclaimable
    reclaimable=$(docker system df --format 'table {{.Type}}\t{{.Reclaimable}}' 2>/dev/null | tail -n +2 | awk '{print $NF}' | grep -v '^0B$' | head -1)
    if [[ -n "$reclaimable" && "$reclaimable" != "0B" ]]; then
        echo "$reclaimable"
    else
        echo "unknown"
    fi
}

# Prune Docker cache
prune_docker() {
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$VERBOSE" == true ]]; then
            docker system df
        fi
        echo "  Would prune unused Docker data (dangling images, stopped containers, unused volumes/networks)"
        return 0
    fi

    # Prune Docker system
    if [[ "$VERBOSE" == true ]]; then
        docker system prune -af --volumes
    else
        docker system prune -af --volumes &> /dev/null
    fi

    echo "  Docker cache pruned"
}

# Check if pre-commit is available and has cache
check_precommit() {
    if ! command -v pre-commit &> /dev/null; then
        return 1
    fi

    local cache_dir="${HOME}/.cache/pre-commit"
    if [[ ! -d "$cache_dir" ]]; then
        return 1
    fi

    # Check if there's anything to clean
    if [[ ! "$(find "$cache_dir" -type f 2>/dev/null)" ]]; then
        return 1
    fi

    return 0
}

# Get estimated pre-commit cache size
get_precommit_size() {
    local cache_dir="${HOME}/.cache/pre-commit"
    local size
    if [[ -d "$cache_dir" ]]; then
        # Only count directories that are 30+ days old (what will actually be deleted)
        local old_dirs
        old_dirs=$(find "$cache_dir" -type d -mtime +30 2>/dev/null)
        if [[ -n "$old_dirs" ]]; then
            size=$(echo "$old_dirs" | xargs du -sk 2>/dev/null | awk '{sum+=$1} END {print sum}')
        else
            size=0
        fi

        if [[ -n "$size" && "$size" -gt 0 ]]; then
            if [[ "$size" -lt 1024 ]]; then
                echo "${size}KB"
            else
                echo "$((size / 1024))MB"
            fi
        else
            echo "minimal"
        fi
    else
        echo "unknown"
    fi
}

# Prune pre-commit cache
prune_precommit() {
    local cache_dir="${HOME}/.cache/pre-commit"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would clean pre-commit cache:"
        if [[ "$VERBOSE" == true ]]; then
            find "$cache_dir" -type d -mtime +30 2>/dev/null || true
        fi
        local count
        count=$(find "$cache_dir" -type d -mtime +30 2>/dev/null | wc -l)
        echo "    $count old environments (30+ days)"
        return 0
    fi

    # Clean old hook environments (30+ days old)
    if [[ "$VERBOSE" == true ]]; then
        echo "  Removing old pre-commit environments (30+ days)..."
        find "$cache_dir" -type d -mtime +30 -print -exec rm -rf {} + 2>/dev/null || true
    else
        find "$cache_dir" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    fi

    # Clean pre-commit gc
    if [[ "$VERBOSE" == true ]]; then
        pre-commit gc
    else
        pre-commit gc &> /dev/null || true
    fi

    echo "  pre-commit cache cleaned"
}

# Check if Homebrew is available
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        return 1
    fi

    return 0
}

# Get estimated Homebrew cache size
get_homebrew_size() {
    local cache_info
    # Get cache size from brew cleanup --dry-run output
    cache_info=$(brew cleanup -n --prune=all 2>&1 | grep -E 'free up|would be freed|would remove' | head -1)
    if [[ -n "$cache_info" ]]; then
        # Try to extract size from the output
        local size
        size=$(echo "$cache_info" | grep -oE '[0-9]+(\.[0-9]+)?[KMGT]?B' | head -1)
        if [[ -n "$size" ]]; then
            echo "$size"
        else
            echo "some space"
        fi
    else
        # Fallback: check cache directory size
        local cache_dir
        cache_dir=$(brew --cache 2>/dev/null)
        if [[ -d "$cache_dir" ]]; then
            local size_kb
            size_kb=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
            if [[ -n "$size_kb" && "$size_kb" -gt 0 ]]; then
                if [[ "$size_kb" -lt 1024 ]]; then
                    echo "${size_kb}KB"
                else
                    echo "$((size_kb / 1024))MB"
                fi
            else
                echo "unknown"
            fi
        else
            echo "unknown"
        fi
    fi
}

# Prune Homebrew cache
prune_homebrew() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: brew cleanup --prune=all"
        if [[ "$VERBOSE" == true ]]; then
            brew cleanup -n --prune=all 2>/dev/null || true
        fi
        return 0
    fi

    if [[ "$VERBOSE" == true ]]; then
        brew cleanup --prune=all
    else
        brew cleanup --prune=all &> /dev/null
    fi

    echo "  Homebrew cache cleaned"
}

# Prompt for confirmation for a specific tool
confirm_tool() {
    local tool_name="$1"

    if [[ "$AUTO_YES" == true ]]; then
        return 0
    fi

    # Read from /dev/tty to ensure we get user input from terminal
    # (stdin might be redirected in the calling loop)
    read -r -p "Clean ${tool_name} cache? [y/N] " response < /dev/tty
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

main() {
    echo "cache_prune - Free up disk space by removing old and unused caches"
    echo ""

    # Track which tools are available
    local tools_found=0
    local tools_info=""

    # Check Docker
    if check_docker; then
        tools_found=$((tools_found + 1))
        local docker_size
        docker_size=$(get_docker_size)
        echo "✓ Docker cache found (~${docker_size} reclaimable)"
        tools_info="${tools_info}docker|docker system prune -af --volumes|${docker_size}\n"
    else
        if [[ "$VERBOSE" == true ]]; then
            echo "  Docker not available or not running"
        fi
    fi

    # Check pre-commit
    if check_precommit; then
        tools_found=$((tools_found + 1))
        local precommit_size
        precommit_size=$(get_precommit_size)
        echo "✓ pre-commit cache found (~${precommit_size})"
        tools_info="${tools_info}pre-commit|pre-commit gc + remove old environments (30+ days)|${precommit_size}\n"
    else
        if [[ "$VERBOSE" == true ]]; then
            echo "  pre-commit cache not found"
        fi
    fi

    # Check Homebrew
    if check_homebrew; then
        tools_found=$((tools_found + 1))
        local brew_size
        brew_size=$(get_homebrew_size)
        echo "✓ Homebrew cache found (~${brew_size})"
        tools_info="${tools_info}homebrew|brew cleanup --prune=all|${brew_size}\n"
    else
        if [[ "$VERBOSE" == true ]]; then
            echo "  Homebrew not available"
        fi
    fi

    echo ""

    # Exit if no tools found
    if [[ $tools_found -eq 0 ]]; then
        echo "No supported tools found. Install Docker, pre-commit, or Homebrew to use this script."
        exit 1
    fi

    # Show what can be cleaned
    if [[ "$DRY_RUN" == true ]]; then
        echo "DRY RUN: Showing what would be deleted without actually deleting"
        echo ""
    fi

    # Track if any caches were cleaned
    local cleaned_count=0

    # Process each available tool
    while IFS='|' read -r tool_name tool_command tool_size; do
        if [[ -n "$tool_name" ]]; then
            echo "${tool_name}:"
            echo "  Command: ${tool_command}"
            echo "  Estimated space: ~${tool_size}"
            echo ""

            # Ask for confirmation for this specific tool
            if confirm_tool "$tool_name"; then
                case $tool_name in
                    docker)
                        echo "Pruning Docker cache..."
                        prune_docker
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    pre-commit)
                        echo "Pruning pre-commit cache..."
                        prune_precommit
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    homebrew)
                        echo "Pruning Homebrew cache..."
                        prune_homebrew
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                esac
            else
                echo "Skipping ${tool_name} cache."
                echo ""
            fi
        fi
    done < <(echo -e "$tools_info")

    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry run completed. No changes were made."
    elif [[ $cleaned_count -eq 0 ]]; then
        echo "No caches were cleaned."
    else
        echo "Cache cleanup completed successfully. Cleaned ${cleaned_count} cache(s)."
    fi
}

main "$@"
