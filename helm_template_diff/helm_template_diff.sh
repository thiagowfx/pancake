#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [HELM_TEMPLATE_ARGS...] [--against BRANCH]

Compare rendered Helm chart output between the current branch and another branch.

This script renders a Helm chart on the current branch (with all staged and
unstaged changes) and compares it against the same chart rendered on another
branch. The comparison is displayed using git-style colored diff output. If
helm template fails on either branch (e.g., due to file size limits or template
errors), the script automatically falls back to comparing the raw chart source
files instead. The script uses git worktree to safely checkout the comparison
branch without affecting your current working directory. After checkout, files
larger than 5MB are automatically removed to prevent helm from failing due to
file size limits.

POSITIONAL ARGUMENTS:
    HELM_TEMPLATE_ARGS    Arguments to pass to 'helm template' command (including chart path)

OPTIONS:
    -h, --help            Show this help message and exit
    --against BRANCH      Branch to compare against (default: auto-detect origin/main or origin/master)

PREREQUISITES:
    - bash 3.x or later (script uses bash-specific features)
    - git (for branch management and diff)
    - helm (for rendering charts)
    - Must be run from within a git repository

EXAMPLES:
    # Compare against auto-detected main/master branch
    $cmd mychart/ --values prod-values.yaml

    # Compare against specific branch
    $cmd mychart/ --values prod-values.yaml --against origin/main

    # Compare with multiple values files
    $cmd charts/api/ -f values.yaml -f overrides.yaml --against feature/config-update

    # Compare with release name and namespace
    $cmd ./chart --namespace default --create-namespace --against main

EXIT CODES:
    0    Success (diff generated, may be empty or non-empty)
    1    Error (missing dependencies, git errors, helm template failures)
EOF
}

check_dependencies() {
    local required_deps=(
        # keep-sorted start
        "git"
        "helm"
        # keep-sorted end
    )
    local missing_deps=()

    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        exit 1
    fi
}

validate_git_repo() {
    if ! git rev-parse --git-dir &> /dev/null; then
        echo "Error: Not in a git repository" >&2
        exit 1
    fi
}

detect_default_branch() {
    # Try origin/main first, then origin/master
    if git rev-parse --verify origin/main &> /dev/null; then
        echo "origin/main"
    elif git rev-parse --verify origin/master &> /dev/null; then
        echo "origin/master"
    else
        echo "Error: Could not auto-detect default branch (tried origin/main and origin/master)" >&2
        exit 1
    fi
}

parse_args() {
    AGAINST_BRANCH=""
    HELM_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --against)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --against requires a branch argument" >&2
                    usage
                    exit 1
                fi
                AGAINST_BRANCH="$2"
                shift 2
                ;;
            *)
                HELM_ARGS+=("$1")
                shift
                ;;
        esac
    done

    # If no --against provided, auto-detect
    if [[ -z "$AGAINST_BRANCH" ]]; then
        AGAINST_BRANCH=$(detect_default_branch)
        echo "Auto-detected comparison branch: $AGAINST_BRANCH" >&2
    fi

    # Validate the branch exists
    if ! git rev-parse --verify "$AGAINST_BRANCH" &> /dev/null; then
        echo "Error: Branch '$AGAINST_BRANCH' does not exist" >&2
        exit 1
    fi
}

convert_to_absolute_paths() {
    local original_dir="$1"
    shift
    local -a args=("$@")
    local -a result=()
    local i=0
    local found_chart_path=false

    while [[ $i -lt ${#args[@]} ]]; do
        local arg="${args[$i]}"

        case "$arg" in
            -f|--values|--set-file|--ca-file|--cert-file|--key-file)
                result+=("$arg")
                i=$((i + 1))
                if [[ $i -lt ${#args[@]} ]]; then
                    local path="${args[$i]}"
                    # Convert relative paths to absolute
                    if [[ "$path" != /* ]]; then
                        path="$original_dir/$path"
                    fi
                    result+=("$path")
                fi
                ;;
            -*)
                # Other flags, keep as-is
                result+=("$arg")
                ;;
            *)
                # Positional argument (likely chart path)
                # Mark the chart path with a special prefix so we can replace it later
                if [[ "$found_chart_path" == false ]]; then
                    found_chart_path=true
                    # Mark this as the chart path
                    result+=("__CHART_PATH__:$arg")
                else
                    # Other positional args, keep as-is
                    result+=("$arg")
                fi
                ;;
        esac
        i=$((i + 1))
    done

    printf '%s\n' "${result[@]}"
}

adjust_chart_path_for_worktree() {
    local original_dir="$1"
    local worktree_dir="$2"
    shift 2
    local -a args=("$@")
    local -a result=()
    local repo_root
    repo_root=$(git rev-parse --show-toplevel)

    for arg in "${args[@]}"; do
        if [[ "$arg" == __CHART_PATH__:* ]]; then
            # Extract the original chart path
            local chart_path="${arg#__CHART_PATH__:}"
            # Convert relative to absolute if needed
            if [[ "$chart_path" != /* ]]; then
                chart_path="$original_dir/$chart_path"
            fi
            # Normalize the path
            chart_path=$(cd "$chart_path" 2>/dev/null && pwd) || chart_path="$original_dir/$chart_path"
            # Get relative path from repo root
            if [[ "$chart_path" == "$repo_root"* ]]; then
                local rel_path="${chart_path#"$repo_root"/}"
                chart_path="$worktree_dir/$rel_path"
            fi
            # If chart is outside repo, use as-is (will likely fail later)
            result+=("$chart_path")
        else
            result+=("$arg")
        fi
    done

    printf '%s\n' "${result[@]}"
}

remove_chart_path_markers() {
    local original_dir="$1"
    shift
    local -a args=("$@")
    local -a result=()

    for arg in "${args[@]}"; do
        if [[ "$arg" == __CHART_PATH__:* ]]; then
            # Remove the marker and convert to absolute path
            local chart_path="${arg#__CHART_PATH__:}"
            if [[ "$chart_path" != /* ]]; then
                chart_path="$original_dir/$chart_path"
            fi
            result+=("$chart_path")
        else
            result+=("$arg")
        fi
    done

    printf '%s\n' "${result[@]}"
}

extract_chart_path() {
    local -a args=("$@")

    for arg in "${args[@]}"; do
        if [[ "$arg" == __CHART_PATH__:* ]]; then
            echo "${arg#__CHART_PATH__:}"
            return 0
        fi
    done

    return 1
}

render_chart() {
    local output_file="$1"
    shift
    local helm_args=("$@")

    if ! helm template "${helm_args[@]}" > "$output_file" 2>&1; then
        echo "Warning: helm template command failed" >&2
        cat "$output_file" >&2
        return 1
    fi
}

fallback_to_source_diff() {
    local original_dir="$1"
    local worktree_dir="$2"
    local chart_path="$3"

    echo "" >&2
    echo "Falling back to source file comparison..." >&2
    echo "" >&2
    echo "Diff of chart source files (current branch vs $AGAINST_BRANCH):" >&2
    echo "" >&2

    # Compute the chart path relative to repo root for both branches
    local chart_relpath
    if [[ "$chart_path" == /* ]]; then
        # Absolute path - make it relative to original_dir if it's under it
        if [[ "$chart_path" == "$original_dir"* ]]; then
            chart_relpath="${chart_path#"$original_dir"/}"
        else
            # Chart is outside the repo, can't compare
            echo "Error: Chart path is outside the repository, cannot compare source files" >&2
            return 1
        fi
    else
        chart_relpath="$chart_path"
    fi

    # Use git diff to compare the chart directory between branches
    # Capture output to check if there's any diff
    local diff_output
    diff_output=$(git diff --color=always "$AGAINST_BRANCH" HEAD -- "$chart_relpath" 2>&1)

    if [[ -z "$diff_output" ]]; then
        echo "No differences found in chart source files." >&2
    else
        printf '%s\n' "$diff_output"
    fi
}

main() {
    check_dependencies
    validate_git_repo

    # Save original directory
    local original_dir
    original_dir=$(pwd)

    # Parse arguments
    parse_args "$@"

    if [[ ${#HELM_ARGS[@]} -eq 0 ]]; then
        echo "Error: No helm template arguments provided" >&2
        usage
        exit 1
    fi

    # Convert relative paths to absolute paths (with chart path marked)
    local -a processed_helm_args
    while IFS= read -r line; do
        processed_helm_args+=("$line")
    done < <(convert_to_absolute_paths "$original_dir" "${HELM_ARGS[@]}")

    # Extract chart path for potential fallback
    local chart_path
    chart_path=$(extract_chart_path "${processed_helm_args[@]}")

    # Prepare args for current branch (remove markers, use original paths)
    local -a current_helm_args
    while IFS= read -r line; do
        current_helm_args+=("$line")
    done < <(remove_chart_path_markers "$original_dir" "${processed_helm_args[@]}")

    # Create temporary directory for worktree
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "${temp_dir:-}"' EXIT

    local current_output="$temp_dir/current.yaml"
    local other_output="$temp_dir/other.yaml"
    local worktree_dir="$temp_dir/worktree"

    # Render current branch
    echo "Rendering chart on current branch..." >&2
    local current_render_success=0
    if render_chart "$current_output" "${current_helm_args[@]}"; then
        current_render_success=1
    fi

    # Create worktree for comparison branch
    echo "Creating temporary worktree for $AGAINST_BRANCH..." >&2
    if ! git worktree add --detach --quiet "$worktree_dir" "$AGAINST_BRANCH" 2>&1; then
        echo "Error: Failed to create git worktree" >&2
        exit 1
    fi
    trap 'git worktree remove --force "${worktree_dir:-}" 2>/dev/null || true; rm -rf "${temp_dir:-}"' EXIT

    # Remove files larger than 5MB to prevent helm errors
    echo "Removing large files (>5MB) to prevent helm errors..." >&2
    (
        cd "$worktree_dir"
        # Find and remove files larger than 5MB
        find . -type f -size +5M -exec rm -f {} \; 2>/dev/null || true
    ) >&2

    # Prepare args for worktree branch (adjust chart path to worktree)
    local -a worktree_helm_args
    while IFS= read -r line; do
        worktree_helm_args+=("$line")
    done < <(adjust_chart_path_for_worktree "$original_dir" "$worktree_dir" "${processed_helm_args[@]}")

    # Render comparison branch (from worktree)
    echo "Rendering chart on $AGAINST_BRANCH..." >&2
    local other_render_success=0
    if render_chart "$other_output" "${worktree_helm_args[@]}"; then
        other_render_success=1
    fi

    # Check if both renders succeeded
    if [[ $current_render_success -eq 1 ]] && [[ $other_render_success -eq 1 ]]; then
        # Both succeeded - show rendered diff
        echo "" >&2
        echo "Diff of rendered output (current branch vs $AGAINST_BRANCH):" >&2
        echo "" >&2

        # Use git diff for consistent output
        # Capture output to check if there's any diff
        local diff_output
        diff_output=$(git diff --no-index --color=always "$other_output" "$current_output" 2>&1 || true)

        if [[ -z "$diff_output" ]]; then
            echo "No differences found in rendered output." >&2
        else
            printf '%s\n' "$diff_output"
        fi
    else
        # At least one render failed - fall back to source diff
        fallback_to_source_diff "$original_dir" "$worktree_dir" "$chart_path"
    fi
}

main "$@"
