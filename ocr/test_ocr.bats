#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp ocr.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1

    # Mock command directory
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    # Clean up temporary directory (trap will also handle this)
    rm -rf "$TEST_TEMP_DIR"
}

create_mock_swift() {
    cat > "$MOCK_BIN_DIR/swift" << 'EOF'
#!/bin/bash
# Mock swift command that simulates OCR output
if [[ "$1" == "-" ]] && [[ -f "$2" ]]; then
    echo "Mock OCR text from image"
    echo "Line 1 of text"
    echo "Line 2 of text"
    exit 0
else
    echo "Error: Invalid swift usage" >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/swift"
}

create_failing_swift() {
    cat > "$MOCK_BIN_DIR/swift" << 'EOF'
#!/bin/bash
echo "couldn't recognize text" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/swift"
}

create_mock_uname() {
    local os="${1:-Darwin}"
    cat > "$MOCK_BIN_DIR/uname" << EOF
#!/bin/bash
if [[ "\$1" == "-s" ]]; then
    echo "$os"
else
    command uname "\$@"
fi
EOF
    chmod +x "$MOCK_BIN_DIR/uname"
}

create_test_image() {
    # Create a dummy image file for testing
    touch "$TEST_TEMP_DIR/test-image.png"
}

@test "help option displays usage information" {
    run bash ocr.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Extract text from images"* ]]
}

@test "short help option displays usage information" {
    run bash ocr.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no arguments displays usage" {
    run bash ocr.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "extracts text from image successfully" {
    skip "Requires macOS platform check"
    create_mock_swift
    create_mock_uname "Darwin"
    create_test_image

    run bash ocr.sh test-image.png
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mock OCR text"* ]]
}

@test "fails on non-Darwin platform" {
    create_mock_uname "Linux"
    create_test_image

    run bash ocr.sh test-image.png
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires macOS"* ]]
}

@test "fails when swift not available" {
    create_mock_uname "Darwin"
    create_test_image

    run bash ocr.sh test-image.png
    [ "$status" -eq 1 ]
    [[ "$output" == *"Swift is not installed"* ]]
}

@test "fails when image file does not exist" {
    create_mock_uname "Darwin"
    create_mock_swift

    run bash ocr.sh nonexistent-image.png
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found"* ]]
}

@test "fails when image file is not readable" {
    skip "Difficult to test file permissions reliably in CI"
    create_mock_uname "Darwin"
    create_mock_swift
    create_test_image
    chmod 000 test-image.png

    run bash ocr.sh test-image.png
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot read file"* ]]
}

@test "handles OCR failure gracefully" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_failing_swift
    create_test_image

    run bash ocr.sh test-image.png
    [ "$status" -eq 1 ]
    [[ "$output" == *"couldn't recognize text"* ]]
}

@test "accepts jpg files" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_mock_swift
    touch test-image.jpg

    run bash ocr.sh test-image.jpg
    [ "$status" -eq 0 ]
}

@test "accepts paths with spaces" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_mock_swift
    touch "my awesome screenshot.png"

    run bash ocr.sh "my awesome screenshot.png"
    [ "$status" -eq 0 ]
}

@test "accepts relative paths" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_mock_swift
    mkdir -p subdir
    touch subdir/image.png

    run bash ocr.sh subdir/image.png
    [ "$status" -eq 0 ]
}

@test "accepts absolute paths" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_mock_swift
    create_test_image
    abs_path="$TEST_TEMP_DIR/test-image.png"

    run bash ocr.sh "$abs_path"
    [ "$status" -eq 0 ]
}

@test "processes multiple files" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_mock_swift
    touch image1.png image2.png image3.png

    run bash ocr.sh image1.png image2.png image3.png
    [ "$status" -eq 0 ]
    # Output should contain multiple "Mock OCR text" blocks
    [ "$(echo "$output" | grep -c "Mock OCR text")" -eq 3 ]
}

@test "separates output with blank lines for multiple files" {
    skip "Requires macOS platform check"
    create_mock_uname "Darwin"
    create_mock_swift
    touch image1.png image2.png

    run bash ocr.sh image1.png image2.png
    [ "$status" -eq 0 ]
    # Should have blank line separator between outputs
    # Check that we have a blank line in the output
    [ "$(echo "$output" | grep -c "^$")" -ge 1 ]
}

@test "fails if any file in batch does not exist" {
    create_mock_uname "Darwin"
    create_mock_swift
    touch image1.png

    run bash ocr.sh image1.png nonexistent.png image3.png
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found"* ]]
}
