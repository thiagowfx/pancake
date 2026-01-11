#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] IMAGE|DIRECTORY...

Optimize images for size while maintaining quality. Supports JPEG, PNG, WebP, and GIF formats.

Optimizes one or more image files using ImageMagick. Creates new files with
the '.optimized' suffix (e.g., photo.jpg becomes photo.optimized.jpg). If a
directory is provided, recursively processes all supported images within it.
The script strips metadata and applies lossy compression to reduce file size
while maintaining good visual quality.

OPTIONS:
    -h, --help           Show this help message and exit
    -q, --quality NUM    Set quality level (1-100, default: 85)

PREREQUISITES:
    - ImageMagick must be installed ('magick' or 'convert' command)

EXAMPLES:
    $cmd vacation-selfie.jpg
    $cmd --quality 90 cat-meme.png
    $cmd photos/summer-2024/
    $cmd logo.png banner.jpg downloads/

EXIT CODES:
    0    All images optimized successfully
    1    Error occurred during processing
EOF
}

# Default settings
QUALITY=85

# Parse arguments
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -q|--quality)
            QUALITY="$2"
            shift 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Reset positional parameters
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    set -- "${POSITIONAL_ARGS[@]}"
else
    set --
fi

check_dependencies() {
    # Try both 'magick' (v7) and 'convert' (v6) commands
    if ! command -v magick &> /dev/null && ! command -v convert &> /dev/null; then
        echo "Error: Missing required dependencies: ImageMagick (magick or convert)"
        echo "Install ImageMagick via: brew install imagemagick"
        exit 1
    fi
}

get_file_size() {
    local file="$1"
    # Try GNU stat first, then BSD stat
    if stat -c%s "$file" 2>/dev/null; then
        return
    elif stat -f%z "$file" 2>/dev/null; then
        return
    else
        echo "0"
    fi
}

format_size() {
    local size=$1
    if [[ $size -lt 1024 ]]; then
        echo "${size}B"
    elif [[ $size -lt 1048576 ]]; then
        echo "$(( size / 1024 ))KB"
    else
        echo "$(( size / 1048576 ))MB"
    fi
}

optimize_image() {
    local input_file="$1"
    local basename="${input_file%.*}"
    local extension="${input_file##*.}"
    local output_file="${basename}.optimized.${extension}"

    # Skip if already optimized
    if [[ "$input_file" == *".optimized."* ]]; then
        return 0
    fi

    # Get original size
    local original_size
    original_size=$(get_file_size "$input_file")

    # Optimize using ImageMagick
    local magick_cmd="magick"
    if ! command -v magick &> /dev/null; then
        magick_cmd="convert"
    fi

    if ! "$magick_cmd" "$input_file" -strip -quality "$QUALITY" "$output_file" 2>/dev/null; then
        echo "✗ Failed to optimize: $input_file"
        return 1
    fi

    # Get new size and calculate savings
    local new_size
    new_size=$(get_file_size "$output_file")
    local saved=$((original_size - new_size))
    local percent=0
    if [[ $original_size -gt 0 ]]; then
        percent=$(( (saved * 100) / original_size ))
    fi

    echo "✓ $input_file"
    echo "  $(format_size "$original_size") → $(format_size "$new_size") (saved $(format_size "$saved"), ${percent}%)"

    # Atomically update summary file for concurrent operations
    echo "$original_size $new_size" >> "$SUMMARY_FILE"
}

process_path() {
    local path="$1"

    if [[ -f "$path" ]]; then
        # Process single file if it's a supported image format
        local ext="${path##*.}"
        ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        case "$ext" in
            jpg|jpeg|png|webp|gif)
                optimize_image "$path"
                ;;
            *)
                echo "Skipping unsupported file: $path"
                ;;
        esac
    elif [[ -d "$path" ]]; then
        # Process directory recursively in parallel
        echo "Processing directory: $path"

        # Determine the number of CPU cores for parallel processing
        local num_cores
        if command -v nproc &> /dev/null; then
            num_cores=$(nproc)
        elif command -v sysctl &> /dev/null; then
            num_cores=$(sysctl -n hw.ncpu)
        else
            num_cores=4 # Default to 4 cores if unable to determine
        fi

        # Use xargs to process files in parallel. The shell function and relevant
        # variables must be exported to be available in subshells.
        find "$path" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) -print0 | \
            xargs -0 -P "$num_cores" -I {} bash -c 'optimize_image "$@"' _ {}
    else
        echo "Error: Path not found: $path"
        exit 1
    fi
}

main() {
    check_dependencies

    # Validate quality parameter
    if [[ ! "$QUALITY" =~ ^[0-9]+$ ]] || [[ "$QUALITY" -lt 1 ]] || [[ "$QUALITY" -gt 100 ]]; then
        echo "Error: Quality must be between 1 and 100"
        exit 1
    fi

    # Check if we have any arguments
    if [[ $# -eq 0 ]]; then
        echo "Error: No input files or directories specified"
        usage
        exit 1
    fi

    echo "Optimizing images with quality: $QUALITY"
    echo ""

    # Create a temporary file to store results for summary calculation.
    # This approach avoids race conditions when running in parallel.
    SUMMARY_FILE=$(mktemp)
    trap 'rm -f "$SUMMARY_FILE"' EXIT

    # Export variables and functions needed by parallel subshells
    export QUALITY
    export SUMMARY_FILE
    export -f get_file_size
    export -f format_size
    export -f optimize_image

    # Process each argument
    for arg in "$@"; do
        process_path "$arg"
    done

    # Calculate and display summary from the results file
    local total_original=0
    local total_new=0
    local processed_count=0

    # Ensure file has content before reading
    if [[ -s "$SUMMARY_FILE" ]]; then
        while read -r original_size new_size; do
            total_original=$((total_original + original_size))
            total_new=$((total_new + new_size))
            processed_count=$((processed_count + 1))
        done < "$SUMMARY_FILE"
    fi

    echo ""
    echo "Summary:"
    echo "Processed: $processed_count images"
    if [[ $processed_count -gt 0 ]]; then
        local total_saved=$((total_original - total_new))
        local total_percent=0
        if [[ $total_original -gt 0 ]]; then
            total_percent=$(( (total_saved * 100) / total_original ))
        fi
        echo "Total size: $(format_size "$total_original") → $(format_size "$total_new")"
        echo "Total saved: $(format_size "$total_saved") (${total_percent}%)"
    fi
}

main "$@"
