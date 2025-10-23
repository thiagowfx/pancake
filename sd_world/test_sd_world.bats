#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp sd_world.sh "$TEST_TEMP_DIR/"

    # Mock bin directory for fake commands
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    # Clean up temporary directory (trap will also handle this)
    rm -rf "$TEST_TEMP_DIR"
}

create_mock_uname() {
    local os="$1"
    cat > "$MOCK_BIN_DIR/uname" << EOF
#!/bin/bash
echo "$os"
EOF
    chmod +x "$MOCK_BIN_DIR/uname"
}

create_mock_command() {
    local cmd="$1"
    local behavior="${2:-success}"

    cat > "$MOCK_BIN_DIR/$cmd" << EOF
#!/bin/bash
case "$behavior" in
    "success")
        echo "Mock $cmd executed successfully"
        exit 0
        ;;
    "fail")
        echo "Mock $cmd failed"
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_BIN_DIR/$cmd"
}

@test "help option displays usage information" {
    run bash "$TEST_TEMP_DIR/sd_world.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Perform a full system upgrade"* ]]
    [[ "$output" == *"OPTIONS:"* ]]
    [[ "$output" == *"EXAMPLES:"* ]]
}

@test "short help option displays usage information" {
    run bash "$TEST_TEMP_DIR/sd_world.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Perform a full system upgrade"* ]]
}

@test "unsupported operating system shows error" {
    create_mock_uname "FreeBSD"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported operating system: FreeBSD"* ]]
}

@test "linux system with no package managers" {
    create_mock_uname "Linux"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Detected Linux system"* ]]
    [[ "$output" == *"No package managers found"* ]]
}

@test "linux system with successful apk upgrade" {
    create_mock_uname "Linux"
    create_mock_command "apk" "success"
    create_mock_command "doas" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected Linux system"* ]]
    [[ "$output" == *"Upgrading Alpine (apk)..."* ]]
    [[ "$output" == *"✓ Alpine (apk) upgrade completed successfully"* ]]
    [[ "$output" == *"Successfully upgraded: 1/1 package managers"* ]]
    [[ "$output" == *"All package managers upgraded successfully!"* ]]
}

@test "linux system with successful pacman upgrade" {
    create_mock_uname "Linux"
    create_mock_command "pacman" "success"
    create_mock_command "sudo" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected Linux system"* ]]
    [[ "$output" == *"Upgrading Arch (pacman)..."* ]]
    [[ "$output" == *"✓ Arch (pacman) upgrade completed successfully"* ]]
    [[ "$output" == *"Successfully upgraded: 1/1 package managers"* ]]
}

@test "linux system with successful apt upgrade" {
    create_mock_uname "Linux"
    create_mock_command "apt" "success"
    create_mock_command "sudo" "success"

    # Create /usr/bin/apt to simulate Debian/Ubuntu system
    mkdir -p "$TEST_TEMP_DIR/usr/bin"
    touch "$TEST_TEMP_DIR/usr/bin/apt"

    # Mock the file existence check
    cat > "$MOCK_BIN_DIR/test_apt_check.sh" << 'EOF'
#!/bin/bash
# Override the apt detection logic for testing
export PATH="/tmp/claude/test_temp/bin:/usr/bin:$PATH"
EOF

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected Linux system"* ]]
}

@test "linux system with failed package manager" {
    create_mock_uname "Linux"
    create_mock_command "apk" "fail"
    create_mock_command "doas" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗ Alpine (apk) upgrade failed"* ]]
    [[ "$output" == *"Some package managers failed to upgrade"* ]]
}

@test "linux system with multiple package managers mixed results" {
    create_mock_uname "Linux"
    create_mock_command "apk" "success"
    create_mock_command "pacman" "fail"
    create_mock_command "doas" "success"
    create_mock_command "sudo" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✓ Alpine (apk) upgrade completed successfully"* ]]
    [[ "$output" == *"✗ Arch (pacman) upgrade failed"* ]]
    [[ "$output" == *"Successfully upgraded: 1/2 package managers"* ]]
    [[ "$output" == *"Some package managers failed to upgrade"* ]]
}

@test "macos system with no package managers" {
    create_mock_uname "Darwin"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Detected macOS system"* ]]
    [[ "$output" == *"No package managers found"* ]]
}

@test "macos system with successful homebrew upgrade" {
    create_mock_uname "Darwin"
    create_mock_command "brew" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected macOS system"* ]]
    [[ "$output" == *"Upgrading Homebrew..."* ]]
    [[ "$output" == *"✓ Homebrew upgrade completed successfully"* ]]
    [[ "$output" == *"Successfully upgraded: 1/1 package managers"* ]]
}

@test "macos system with successful mas upgrade" {
    create_mock_uname "Darwin"
    create_mock_command "mas" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Upgrading Mac App Store..."* ]]
    [[ "$output" == *"✓ Mac App Store upgrade completed successfully"* ]]
}

@test "macos system with successful system updates" {
    create_mock_uname "Darwin"
    create_mock_command "softwareupdate" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Upgrading System Updates..."* ]]
    [[ "$output" == *"✓ System Updates upgrade completed successfully"* ]]
}

@test "macos system with all package managers successful" {
    create_mock_uname "Darwin"
    create_mock_command "brew" "success"
    create_mock_command "mas" "success"
    create_mock_command "softwareupdate" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected macOS system"* ]]
    [[ "$output" == *"✓ Homebrew upgrade completed successfully"* ]]
    [[ "$output" == *"✓ Mac App Store upgrade completed successfully"* ]]
    [[ "$output" == *"✓ System Updates upgrade completed successfully"* ]]
    [[ "$output" == *"Successfully upgraded: 3/3 package managers"* ]]
    [[ "$output" == *"All package managers upgraded successfully!"* ]]
}

@test "macos system with mixed results" {
    create_mock_uname "Darwin"
    create_mock_command "brew" "success"
    create_mock_command "mas" "fail"
    create_mock_command "softwareupdate" "success"

    run bash "$TEST_TEMP_DIR/sd_world.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✓ Homebrew upgrade completed successfully"* ]]
    [[ "$output" == *"✗ Mac App Store upgrade failed"* ]]
    [[ "$output" == *"✓ System Updates upgrade completed successfully"* ]]
    [[ "$output" == *"Successfully upgraded: 2/3 package managers"* ]]
    [[ "$output" == *"Some package managers failed to upgrade"* ]]
}