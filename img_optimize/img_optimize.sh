#!/bin/bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS] IMAGE|DIRECTORY...

Optimize images for size while maintaining quality. Supports JPEG, PNG, WebP, and GIF formats.

OPTIONS:
    -h, --help           Show this help message and exit
    -q, --quality NUM    Set quality level (1-100, default: 85)

DESCRIPTION:
    Optimizes one or more image files using ImageMagick. Creates new files with
    the '.optimized' suffix (e.g., photo.jpg becomes photo.optimized.jpg).

    If a directory is provided, recursively processes all supported images within it.

    The script strips metadata and applies lossy compression to reduce file size
    while maintaining good visual quality.

PREREQUISITES:
    - ImageMagick must be installed ('magick' or 'convert' command)

EXAMPLES:
    $0 vacation-selfie.jpg
    $0 --quality 90 cat-meme.png
    $0 photos/summer-2024/
    $0 logo.png banner.jpg downloads/

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

    # Update global counters
    TOTAL_ORIGINAL=$((TOTAL_ORIGINAL + original_size))
    TOTAL_NEW=$((TOTAL_NEW + new_size))
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
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
        # Process directory recursively
        echo "Processing directory: $path"
        while IFS= read -r -d '' file; do
            optimize_image "$file"
        done < <(find "$path" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) -print0)
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

    # Global counters
    TOTAL_ORIGINAL=0
    TOTAL_NEW=0
    PROCESSED_COUNT=0

    # Process each argument
    for arg in "$@"; do
        process_path "$arg"
    done

    echo ""
    echo "Summary:"
    echo "Processed: $PROCESSED_COUNT images"
    if [[ $PROCESSED_COUNT -gt 0 ]]; then
        local total_saved=$((TOTAL_ORIGINAL - TOTAL_NEW))
        local total_percent=0
        if [[ $TOTAL_ORIGINAL -gt 0 ]]; then
            total_percent=$(( (total_saved * 100) / TOTAL_ORIGINAL ))
        fi
        echo "Total size: $(format_size "$TOTAL_ORIGINAL") → $(format_size "$TOTAL_NEW")"
        echo "Total saved: $(format_size "$total_saved") (${total_percent}%)"
    fi
}

main "$@"
