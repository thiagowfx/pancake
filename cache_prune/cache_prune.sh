#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Free up disk space by pruning old and unused cache data from various tools.

By default, runs in dry-run mode (shows what would be cleaned without actually
cleaning). Use --execute to actually perform the cleanup.

This script safely removes old and unused cache data from Docker (dangling
images, unused containers, volumes, networks, build cache), pre-commit (old
hook environments not used recently), Homebrew (old formula versions and cached
downloads), Helm (cached chart repositories and archives), Terraform (cached
provider plugins), npm (package cache), pip (Python package cache), Go (build
cache and module cache), Yarn (package cache), Bundler/Ruby (gem cache), and
Git (garbage collection on repositories in common directories). The script
gracefully skips any tools that are not installed on your system.

OPTIONS:
    -h, --help       Show this help message and exit
    -x, --execute    Actually perform cleanup (default is dry-run)
    -y, --yes        Skip confirmation prompt and proceed automatically
    -v, --verbose    Show detailed output during operations

PREREQUISITES:
    At least one of the following tools must be installed:
    - Docker CLI ('docker')
    - pre-commit ('pip install pre-commit')
    - Homebrew ('brew')
    - Helm ('helm')
    - Terraform ('terraform')
    - npm ('npm')
    - pip ('pip' or 'pip3')
    - Go ('go')
    - Yarn ('yarn')
    - Bundler ('bundle')
    - Git ('git')

EXAMPLES:
    $cmd                    Preview what would be cleaned (dry-run)
    $cmd --execute          Run interactively with confirmation for each cache
    $cmd -x -y              Execute cleanup without prompts
    $cmd -v                 Verbose dry-run preview

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
        # If brew cleanup -n found nothing, there's nothing to clean
        echo "minimal"
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

# Check if Helm is available and has cache
check_helm() {
    if ! command -v helm &> /dev/null; then
        return 1
    fi

    # Check for Helm cache directories
    local cache_dir="${HOME}/.cache/helm"
    local config_dir="${HOME}/.config/helm"

    # Check if cache directory exists and has content
    if [[ -d "$cache_dir" ]] && [[ "$(find "$cache_dir" -type f 2>/dev/null | head -1)" ]]; then
        return 0
    fi

    # Check if config directory has repository cache
    if [[ -d "$config_dir/repository" ]] && [[ "$(find "$config_dir/repository" -type f 2>/dev/null | head -1)" ]]; then
        return 0
    fi

    return 1
}

# Get estimated Helm cache size
get_helm_size() {
    local total_size=0
    local cache_dir="${HOME}/.cache/helm"
    local config_dir="${HOME}/.config/helm"

    if [[ -d "$cache_dir" ]]; then
        local cache_size
        cache_size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
        total_size=$((total_size + cache_size))
    fi

    if [[ -d "$config_dir/repository" ]]; then
        local repo_size
        repo_size=$(du -sk "$config_dir/repository" 2>/dev/null | awk '{print $1}')
        total_size=$((total_size + repo_size))
    fi

    if [[ "$total_size" -gt 0 ]]; then
        if [[ "$total_size" -lt 1024 ]]; then
            echo "${total_size}KB"
        else
            echo "$((total_size / 1024))MB"
        fi
    else
        echo "minimal"
    fi
}

# Prune Helm cache
prune_helm() {
    local cache_dir="${HOME}/.cache/helm"
    local config_dir="${HOME}/.config/helm"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would remove Helm cache directories:"
        if [[ "$VERBOSE" == true ]]; then
            if [[ -d "$cache_dir" ]]; then
                echo "    ${cache_dir}"
                find "$cache_dir" -type f 2>/dev/null || true
            fi
            if [[ -d "$config_dir/repository" ]]; then
                echo "    ${config_dir}/repository"
                find "$config_dir/repository" -type f 2>/dev/null || true
            fi
        fi
        local count
        count=$(find "$cache_dir" "$config_dir/repository" -type f 2>/dev/null | wc -l)
        echo "    $count cached file(s)"
        return 0
    fi

    # Remove Helm cache directory
    if [[ -d "$cache_dir" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            echo "  Removing Helm cache: ${cache_dir}"
            rm -rf "$cache_dir"
        else
            rm -rf "$cache_dir" 2>/dev/null || true
        fi
    fi

    # Remove Helm repository cache
    if [[ -d "$config_dir/repository" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            echo "  Removing Helm repository cache: ${config_dir}/repository"
            rm -rf "$config_dir/repository"
        else
            rm -rf "$config_dir/repository" 2>/dev/null || true
        fi
    fi

    echo "  Helm cache cleaned"
}

# Check if Terraform is available and has cache
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        return 1
    fi

    local cache_dir="${HOME}/.terraform.d/plugin-cache"
    if [[ ! -d "$cache_dir" ]]; then
        return 1
    fi

    # Check if there's anything to clean
    if [[ ! "$(find "$cache_dir" -type f 2>/dev/null)" ]]; then
        return 1
    fi

    return 0
}

# Get estimated Terraform cache size
get_terraform_size() {
    local cache_dir="${HOME}/.terraform.d/plugin-cache"
    local size
    if [[ -d "$cache_dir" ]]; then
        size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
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

# Prune Terraform cache
prune_terraform() {
    local cache_dir="${HOME}/.terraform.d/plugin-cache"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would remove plugin cache directory: ${cache_dir}"
        if [[ "$VERBOSE" == true ]]; then
            find "$cache_dir" -type f 2>/dev/null || true
        fi
        local count
        count=$(find "$cache_dir" -type f 2>/dev/null | wc -l)
        echo "    $count cached provider(s)"
        return 0
    fi

    # Remove the entire plugin cache directory
    if [[ "$VERBOSE" == true ]]; then
        echo "  Removing Terraform plugin cache: ${cache_dir}"
        rm -rf "$cache_dir"
    else
        rm -rf "$cache_dir" 2>/dev/null || true
    fi

    echo "  Terraform cache cleaned"
}

# Check if npm is available and has cache
check_npm() {
    if ! command -v npm &> /dev/null; then
        return 1
    fi

    # Check if npm cache directory exists and has content
    local cache_dir
    cache_dir=$(npm config get cache 2>/dev/null)
    if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
        return 1
    fi

    # Check if there's anything to clean
    if [[ ! "$(find "$cache_dir" -type f 2>/dev/null | head -1)" ]]; then
        return 1
    fi

    return 0
}

# Get estimated npm cache size
get_npm_size() {
    local cache_dir
    cache_dir=$(npm config get cache 2>/dev/null)
    local size
    if [[ -d "$cache_dir" ]]; then
        size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
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

# Prune npm cache
prune_npm() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: npm cache clean --force"
        if [[ "$VERBOSE" == true ]]; then
            npm cache verify 2>/dev/null || true
        fi
        return 0
    fi

    if [[ "$VERBOSE" == true ]]; then
        npm cache clean --force
    else
        npm cache clean --force &> /dev/null
    fi

    echo "  npm cache cleaned"
}

# Check if pip is available and has cache
check_pip() {
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        return 1
    fi

    # Try to get cache directory
    local cache_dir
    if command -v pip3 &> /dev/null; then
        cache_dir=$(pip3 cache dir 2>/dev/null)
    elif command -v pip &> /dev/null; then
        cache_dir=$(pip cache dir 2>/dev/null)
    fi

    if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
        return 1
    fi

    # Check if there's anything to clean
    if [[ ! "$(find "$cache_dir" -type f 2>/dev/null | head -1)" ]]; then
        return 1
    fi

    return 0
}

# Get estimated pip cache size
get_pip_size() {
    local cache_dir
    if command -v pip3 &> /dev/null; then
        cache_dir=$(pip3 cache dir 2>/dev/null)
    elif command -v pip &> /dev/null; then
        cache_dir=$(pip cache dir 2>/dev/null)
    fi

    local size
    if [[ -d "$cache_dir" ]]; then
        size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
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

# Prune pip cache
prune_pip() {
    local pip_cmd="pip"
    if command -v pip3 &> /dev/null; then
        pip_cmd="pip3"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: ${pip_cmd} cache purge"
        if [[ "$VERBOSE" == true ]]; then
            ${pip_cmd} cache info 2>/dev/null || true
        fi
        return 0
    fi

    if [[ "$VERBOSE" == true ]]; then
        ${pip_cmd} cache purge
    else
        ${pip_cmd} cache purge &> /dev/null
    fi

    echo "  pip cache cleaned"
}

# Check if Go is available and has cache
check_go() {
    if ! command -v go &> /dev/null; then
        return 1
    fi

    # Check if there's anything in the build cache or module cache
    local build_cache
    local mod_cache
    build_cache=$(go env GOCACHE 2>/dev/null)
    mod_cache=$(go env GOMODCACHE 2>/dev/null)

    if [[ -z "$build_cache" && -z "$mod_cache" ]]; then
        return 1
    fi

    # Check if either cache has content
    if [[ -d "$build_cache" ]] && [[ "$(find "$build_cache" -type f 2>/dev/null | head -1)" ]]; then
        return 0
    fi
    if [[ -d "$mod_cache" ]] && [[ "$(find "$mod_cache" -type f 2>/dev/null | head -1)" ]]; then
        return 0
    fi

    return 1
}

# Get estimated Go cache size
get_go_size() {
    local build_cache
    local mod_cache
    build_cache=$(go env GOCACHE 2>/dev/null)
    mod_cache=$(go env GOMODCACHE 2>/dev/null)

    local total_size=0
    if [[ -d "$build_cache" ]]; then
        local build_size
        build_size=$(du -sk "$build_cache" 2>/dev/null | awk '{print $1}')
        total_size=$((total_size + build_size))
    fi
    if [[ -d "$mod_cache" ]]; then
        local mod_size
        mod_size=$(du -sk "$mod_cache" 2>/dev/null | awk '{print $1}')
        total_size=$((total_size + mod_size))
    fi

    if [[ "$total_size" -gt 0 ]]; then
        if [[ "$total_size" -lt 1024 ]]; then
            echo "${total_size}KB"
        else
            echo "$((total_size / 1024))MB"
        fi
    else
        echo "minimal"
    fi
}

# Prune Go cache
prune_go() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: go clean -cache -modcache"
        if [[ "$VERBOSE" == true ]]; then
            local build_cache
            local mod_cache
            build_cache=$(go env GOCACHE 2>/dev/null)
            mod_cache=$(go env GOMODCACHE 2>/dev/null)
            echo "  Build cache: ${build_cache}"
            echo "  Module cache: ${mod_cache}"
        fi
        return 0
    fi

    if [[ "$VERBOSE" == true ]]; then
        go clean -cache -modcache
    else
        go clean -cache -modcache &> /dev/null
    fi

    echo "  Go cache cleaned"
}

# Check if Yarn is available and has cache
check_yarn() {
    if ! command -v yarn &> /dev/null; then
        return 1
    fi

    # Get Yarn cache directory
    local cache_dir
    cache_dir=$(yarn cache dir 2>/dev/null)
    if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
        return 1
    fi

    # Check if there's anything to clean
    if [[ ! "$(find "$cache_dir" -type f 2>/dev/null | head -1)" ]]; then
        return 1
    fi

    return 0
}

# Get estimated Yarn cache size
get_yarn_size() {
    local cache_dir
    cache_dir=$(yarn cache dir 2>/dev/null)
    local size
    if [[ -d "$cache_dir" ]]; then
        size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
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

# Prune Yarn cache
prune_yarn() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: yarn cache clean"
        if [[ "$VERBOSE" == true ]]; then
            yarn cache dir 2>/dev/null || true
        fi
        return 0
    fi

    if [[ "$VERBOSE" == true ]]; then
        yarn cache clean
    else
        yarn cache clean &> /dev/null
    fi

    echo "  Yarn cache cleaned"
}

# Check if Bundler is available and has cache
check_bundler() {
    if ! command -v bundle &> /dev/null; then
        return 1
    fi

    # Check for gem cache directory
    local cache_dir="${HOME}/.bundle/cache"
    if [[ -d "$cache_dir" ]] && [[ "$(find "$cache_dir" -type f 2>/dev/null | head -1)" ]]; then
        return 0
    fi

    # Also check for system gem cache if gem is available
    if command -v gem &> /dev/null; then
        local gem_cache
        gem_cache=$(gem environment gemdir 2>/dev/null)
        if [[ -n "$gem_cache" ]] && [[ -d "$gem_cache/cache" ]]; then
            if [[ "$(find "$gem_cache/cache" -type f 2>/dev/null | head -1)" ]]; then
                return 0
            fi
        fi
    fi

    return 1
}

# Get estimated Bundler cache size
get_bundler_size() {
    local total_size=0
    local cache_dir="${HOME}/.bundle/cache"

    if [[ -d "$cache_dir" ]]; then
        local size
        size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
        total_size=$((total_size + size))
    fi

    # Also check gem cache
    if command -v gem &> /dev/null; then
        local gem_cache
        gem_cache=$(gem environment gemdir 2>/dev/null)
        if [[ -n "$gem_cache" ]] && [[ -d "$gem_cache/cache" ]]; then
            local gem_size
            gem_size=$(du -sk "$gem_cache/cache" 2>/dev/null | awk '{print $1}')
            total_size=$((total_size + gem_size))
        fi
    fi

    if [[ "$total_size" -gt 0 ]]; then
        if [[ "$total_size" -lt 1024 ]]; then
            echo "${total_size}KB"
        else
            echo "$((total_size / 1024))MB"
        fi
    else
        echo "minimal"
    fi
}

# Prune Bundler cache
prune_bundler() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: bundle clean --force (if in project with Gemfile)"
        if command -v gem &> /dev/null; then
            echo "  Would run: gem cleanup"
        fi
        if [[ "$VERBOSE" == true ]]; then
            local cache_dir="${HOME}/.bundle/cache"
            if [[ -d "$cache_dir" ]]; then
                echo "  Bundle cache: ${cache_dir}"
            fi
        fi
        return 0
    fi

    # Clean gem cache
    if command -v gem &> /dev/null; then
        if [[ "$VERBOSE" == true ]]; then
            gem cleanup
        else
            gem cleanup &> /dev/null || true
        fi
    fi

    # Clean bundle cache if available
    local cache_dir="${HOME}/.bundle/cache"
    if [[ -d "$cache_dir" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            echo "  Removing bundle cache: ${cache_dir}"
            rm -rf "$cache_dir"
        else
            rm -rf "$cache_dir" 2>/dev/null || true
        fi
    fi

    echo "  Bundler/Ruby cache cleaned"
}

# Check if Git is available and can benefit from garbage collection
check_git() {
    if ! command -v git &> /dev/null; then
        return 1
    fi

    # Look for git repositories in common locations
    local common_dirs=("${HOME}/Workspace" "${HOME}/workspace" "${HOME}/Projects" "${HOME}/projects" "${HOME}/Code" "${HOME}/code" "${HOME}/repos" "${HOME}/src")
    local found_repos=false

    for dir in "${common_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if find "$dir" -maxdepth 3 -name .git -type d 2>/dev/null | head -1 | grep -q .; then
                found_repos=true
                break
            fi
        fi
    done

    if [[ "$found_repos" == false ]]; then
        return 1
    fi

    return 0
}

# Get estimated Git reclaimable space
get_git_size() {
    # It's hard to estimate git gc savings without running it
    # Return a generic message
    echo "varies"
}

# Prune Git repositories
prune_git() {
    local common_dirs=("${HOME}/Workspace" "${HOME}/workspace" "${HOME}/Projects" "${HOME}/projects" "${HOME}/Code" "${HOME}/code" "${HOME}/repos" "${HOME}/src")

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would run: git gc on repositories in common directories"
        if [[ "$VERBOSE" == true ]]; then
            for dir in "${common_dirs[@]}"; do
                if [[ -d "$dir" ]]; then
                    find "$dir" -maxdepth 3 -name .git -type d 2>/dev/null | while read -r git_dir; do
                        local repo_dir
                        repo_dir=$(dirname "$git_dir")
                        echo "    Found repo: ${repo_dir}"
                    done
                fi
            done
        fi
        return 0
    fi

    local repos_cleaned=0
    for dir in "${common_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -maxdepth 3 -name .git -type d 2>/dev/null | while read -r git_dir; do
                local repo_dir
                repo_dir=$(dirname "$git_dir")
                if [[ "$VERBOSE" == true ]]; then
                    echo "  Running git gc in: ${repo_dir}"
                    (cd "$repo_dir" && git gc --auto) || true
                else
                    (cd "$repo_dir" && git gc --auto &> /dev/null) || true
                fi
                repos_cleaned=$((repos_cleaned + 1))
            done
        fi
    done

    echo "  Git garbage collection completed"
}

# Prompt for confirmation for a specific tool
confirm_tool() {
    local tool_name="$1"

    if [[ "$AUTO_YES" == true ]]; then
        return 0
    fi

    # Read from /dev/tty to ensure we get user input from terminal
    # (stdin might be redirected in the calling loop)
    local response=""
    if [[ -r /dev/tty ]]; then
        read -r -p "Clean ${tool_name} cache? [y/N] " response < /dev/tty
    else
        # If /dev/tty is not available, default to no
        return 1
    fi

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
        echo "- Docker not available or not running"
    fi

    # Check pre-commit
    if check_precommit; then
        tools_found=$((tools_found + 1))
        local precommit_size
        precommit_size=$(get_precommit_size)
        echo "✓ pre-commit cache found (~${precommit_size})"
        tools_info="${tools_info}pre-commit|pre-commit gc + remove old environments (30+ days)|${precommit_size}\n"
    else
        echo "- pre-commit cache not found"
    fi

    # Check Homebrew
    if check_homebrew; then
        tools_found=$((tools_found + 1))
        local brew_size
        brew_size=$(get_homebrew_size)
        echo "✓ Homebrew cache found (~${brew_size})"
        tools_info="${tools_info}homebrew|brew cleanup --prune=all|${brew_size}\n"
    else
        echo "- Homebrew not available"
    fi

    # Check Helm
    if check_helm; then
        tools_found=$((tools_found + 1))
        local helm_size
        helm_size=$(get_helm_size)
        echo "✓ Helm cache found (~${helm_size})"
        tools_info="${tools_info}helm|rm -rf ~/.cache/helm and ~/.config/helm/repository|${helm_size}\n"
    else
        echo "- Helm cache not available"
    fi

    # Check Terraform
    if check_terraform; then
        tools_found=$((tools_found + 1))
        local terraform_size
        terraform_size=$(get_terraform_size)
        echo "✓ Terraform cache found (~${terraform_size})"
        tools_info="${tools_info}terraform|rm -rf ~/.terraform.d/plugin-cache|${terraform_size}\n"
    else
        echo "- Terraform cache not available"
    fi

    # Check npm
    if check_npm; then
        tools_found=$((tools_found + 1))
        local npm_size
        npm_size=$(get_npm_size)
        echo "✓ npm cache found (~${npm_size})"
        tools_info="${tools_info}npm|npm cache clean --force|${npm_size}\n"
    else
        echo "- npm cache not available"
    fi

    # Check pip
    if check_pip; then
        tools_found=$((tools_found + 1))
        local pip_size
        pip_size=$(get_pip_size)
        echo "✓ pip cache found (~${pip_size})"
        tools_info="${tools_info}pip|pip cache purge|${pip_size}\n"
    else
        echo "- pip cache not available"
    fi

    # Check Go
    if check_go; then
        tools_found=$((tools_found + 1))
        local go_size
        go_size=$(get_go_size)
        echo "✓ Go cache found (~${go_size})"
        tools_info="${tools_info}go|go clean -cache -modcache|${go_size}\n"
    else
        echo "- Go cache not available"
    fi

    # Check Yarn
    if check_yarn; then
        tools_found=$((tools_found + 1))
        local yarn_size
        yarn_size=$(get_yarn_size)
        echo "✓ Yarn cache found (~${yarn_size})"
        tools_info="${tools_info}yarn|yarn cache clean|${yarn_size}\n"
    else
        echo "- Yarn cache not available"
    fi

    # Check Bundler
    if check_bundler; then
        tools_found=$((tools_found + 1))
        local bundler_size
        bundler_size=$(get_bundler_size)
        echo "✓ Bundler/Ruby cache found (~${bundler_size})"
        tools_info="${tools_info}bundler|gem cleanup + remove bundle cache|${bundler_size}\n"
    else
        echo "- Bundler/Ruby cache not available"
    fi

    # Check Git
    if check_git; then
        tools_found=$((tools_found + 1))
        local git_size
        git_size=$(get_git_size)
        echo "✓ Git repositories found (can run garbage collection)"
        tools_info="${tools_info}git|git gc on repositories in common directories|${git_size}\n"
    else
        echo "- Git repositories not found in common directories"
    fi

    echo ""

    # Exit if no tools found
    if [[ $tools_found -eq 0 ]]; then
        echo "No supported tools found. Install at least one of: Docker, pre-commit, Homebrew, Helm, Terraform, npm, pip, Go, Yarn, Bundler, or Git."
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
                    helm)
                        echo "Pruning Helm cache..."
                        prune_helm
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    terraform)
                        echo "Pruning Terraform cache..."
                        prune_terraform
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    npm)
                        echo "Pruning npm cache..."
                        prune_npm
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    pip)
                        echo "Pruning pip cache..."
                        prune_pip
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    go)
                        echo "Pruning Go cache..."
                        prune_go
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    yarn)
                        echo "Pruning Yarn cache..."
                        prune_yarn
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    bundler)
                        echo "Pruning Bundler/Ruby cache..."
                        prune_bundler
                        cleaned_count=$((cleaned_count + 1))
                        echo ""
                        ;;
                    git)
                        echo "Running Git garbage collection..."
                        prune_git
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
