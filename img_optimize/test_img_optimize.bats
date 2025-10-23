#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp img_optimize.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1

    # Mock magick/convert command by creating a fake executable in PATH
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    # Clean up temporary directory (trap will also handle this)
    rm -rf "$TEST_TEMP_DIR"
}

create_mock_imagemagick() {
    cat > "$MOCK_BIN_DIR/magick" << 'EOF'
#!/bin/bash
# Mock ImageMagick command
input_file="$1"
output_file="${@: -1}"

case "$1" in
    *)
        # Simulate image optimization by copying input to output with slightly smaller size
        if [[ -f "$input_file" ]]; then
            # Create output file that's 70% of input size
            input_size=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file" 2>/dev/null)
            new_size=$((input_size * 7 / 10))
            dd if=/dev/zero of="$output_file" bs=1 count="$new_size" 2>/dev/null
            exit 0
        fi
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_BIN_DIR/magick"
}

create_test_image() {
    local filename="$1"
    local size="${2:-1024}"
    # Create a dummy file of specified size
    dd if=/dev/zero of="$filename" bs=1 count="$size" 2>/dev/null
}

@test "help option displays usage information" {
    create_mock_imagemagick
    run bash img_optimize.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Optimize images for size"* ]]
}

@test "short help option displays usage information" {
    create_mock_imagemagick
    run bash img_optimize.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "missing imagemagick dependency causes failure" {
    # Don't create mock magick command, and use isolated PATH with basic shell utilities
    run env PATH="$MOCK_BIN_DIR:/usr/bin:/bin" bash img_optimize.sh test.jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required dependencies"* ]]
    [[ "$output" == *"ImageMagick"* ]]
}

@test "no input files displays error" {
    create_mock_imagemagick
    run bash img_optimize.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"No input files or directories specified"* ]]
}

@test "invalid quality parameter displays error" {
    create_mock_imagemagick
    create_test_image "test.jpg"
    run bash img_optimize.sh --quality 150 test.jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Quality must be between 1 and 100"* ]]
}

@test "quality parameter below minimum displays error" {
    create_mock_imagemagick
    create_test_image "test.jpg"
    run bash img_optimize.sh --quality 0 test.jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Quality must be between 1 and 100"* ]]
}

@test "non-numeric quality parameter displays error" {
    create_mock_imagemagick
    create_test_image "test.jpg"
    run bash img_optimize.sh --quality abc test.jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Quality must be between 1 and 100"* ]]
}

@test "nonexistent file displays error" {
    create_mock_imagemagick
    run bash img_optimize.sh nonexistent.jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Path not found"* ]]
}

@test "optimize single jpg file" {
    create_mock_imagemagick
    create_test_image "vacation-selfie.jpg" 2048
    run bash img_optimize.sh vacation-selfie.jpg
    [ "$status" -eq 0 ]
    [[ "$output" == *"Optimizing images with quality: 85"* ]]
    [[ "$output" == *"✓ vacation-selfie.jpg"* ]]
    [[ "$output" == *"Processed: 1 images"* ]]
    [[ "$output" == *"saved"* ]]
    # Check that optimized file was created
    [ -f "vacation-selfie.optimized.jpg" ]
}

@test "optimize single png file" {
    create_mock_imagemagick
    create_test_image "logo.png" 1024
    run bash img_optimize.sh logo.png
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ logo.png"* ]]
    [ -f "logo.optimized.png" ]
}

@test "optimize with custom quality parameter" {
    create_mock_imagemagick
    create_test_image "photo.jpg" 2048
    run bash img_optimize.sh --quality 90 photo.jpg
    [ "$status" -eq 0 ]
    [[ "$output" == *"Optimizing images with quality: 90"* ]]
    [[ "$output" == *"✓ photo.jpg"* ]]
}

@test "optimize multiple files" {
    create_mock_imagemagick
    create_test_image "cat-meme.jpg" 2048
    create_test_image "dog-photo.png" 1024
    run bash img_optimize.sh cat-meme.jpg dog-photo.png
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ cat-meme.jpg"* ]]
    [[ "$output" == *"✓ dog-photo.png"* ]]
    [[ "$output" == *"Processed: 2 images"* ]]
    [ -f "cat-meme.optimized.jpg" ]
    [ -f "dog-photo.optimized.png" ]
}

@test "optimize directory recursively" {
    create_mock_imagemagick
    mkdir -p photos/summer
    create_test_image "photos/beach.jpg" 2048
    create_test_image "photos/summer/sunset.png" 1024
    run bash img_optimize.sh photos/
    [ "$status" -eq 0 ]
    [[ "$output" == *"Processing directory: photos/"* ]]
    [[ "$output" == *"✓ photos/beach.jpg"* ]]
    [[ "$output" == *"✓ photos/summer/sunset.png"* ]]
    [[ "$output" == *"Processed: 2 images"* ]]
    [ -f "photos/beach.optimized.jpg" ]
    [ -f "photos/summer/sunset.optimized.png" ]
}

@test "skip already optimized files" {
    create_mock_imagemagick
    create_test_image "photo.optimized.jpg" 1024
    run bash img_optimize.sh photo.optimized.jpg
    [ "$status" -eq 0 ]
    [[ "$output" == *"Processed: 0 images"* ]]
}

@test "skip unsupported file types" {
    create_mock_imagemagick
    create_test_image "document.pdf" 1024
    run bash img_optimize.sh document.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping unsupported file"* ]]
    [[ "$output" == *"Processed: 0 images"* ]]
}

@test "mixed files and directories" {
    create_mock_imagemagick
    create_test_image "logo.png" 1024
    mkdir -p vacation
    create_test_image "vacation/beach.jpg" 2048
    run bash img_optimize.sh logo.png vacation/
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ logo.png"* ]]
    [[ "$output" == *"Processing directory: vacation/"* ]]
    [[ "$output" == *"✓ vacation/beach.jpg"* ]]
    [[ "$output" == *"Processed: 2 images"* ]]
}

@test "supports case-insensitive file extensions" {
    create_mock_imagemagick
    create_test_image "PHOTO.JPG" 2048
    create_test_image "image.PNG" 1024
    mkdir -p images
    mv PHOTO.JPG images/
    mv image.PNG images/
    run bash img_optimize.sh images/
    [ "$status" -eq 0 ]
    [[ "$output" == *"Processed: 2 images"* ]]
}

@test "displays size statistics correctly" {
    create_mock_imagemagick
    create_test_image "photo.jpg" 10000
    run bash img_optimize.sh photo.jpg
    [ "$status" -eq 0 ]
    [[ "$output" == *"→"* ]]
    [[ "$output" == *"saved"* ]]
    [[ "$output" == *"%"* ]]
    [[ "$output" == *"Total size:"* ]]
    [[ "$output" == *"Total saved:"* ]]
}
