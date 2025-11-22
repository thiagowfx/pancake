#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp notify.sh "$TEST_TEMP_DIR/"
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

create_mock_notify_send() {
    cat > "$MOCK_BIN_DIR/notify-send" << 'EOF'
#!/bin/bash
# Mock notify-send command
echo "notify-send called with: $*" > /tmp/notify-test-output
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/notify-send"
}

create_mock_osascript() {
    cat > "$MOCK_BIN_DIR/osascript" << 'EOF'
#!/bin/bash
# Mock osascript command
echo "osascript called with: $*" > /tmp/notify-test-output
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/osascript"
}

create_failing_notify_send() {
    cat > "$MOCK_BIN_DIR/notify-send" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/notify-send"
}

@test "help option displays usage information" {
    run bash notify.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Send desktop notifications"* ]]
}

@test "short help option displays usage information" {
    run bash notify.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no arguments sends default notification with notify-send" {
    create_mock_notify_send
    run bash notify.sh
    [ "$status" -eq 0 ]
}

@test "custom title only with notify-send" {
    create_mock_notify_send
    run bash notify.sh "Build Complete"
    [ "$status" -eq 0 ]
}

@test "custom title and description with notify-send" {
    create_mock_notify_send
    run bash notify.sh "Deploy" "Production is live"
    [ "$status" -eq 0 ]
}

@test "falls back to osascript when notify-send unavailable" {
    create_mock_osascript
    run bash notify.sh "Test" "Message"
    [ "$status" -eq 0 ]
}

@test "falls back to osascript when notify-send fails" {
    create_failing_notify_send
    create_mock_osascript
    run bash notify.sh "Test" "Message"
    [ "$status" -eq 0 ]
}

@test "error when no notification system available" {
    # Create failing mocks for both systems
    cat > "$MOCK_BIN_DIR/notify-send" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/notify-send"

    cat > "$MOCK_BIN_DIR/osascript" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/osascript"

    run bash notify.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot send notifications"* ]]
    [[ "$output" == *"No supported notification system"* ]]
}

@test "unicode characters in title" {
    create_mock_notify_send
    run bash notify.sh "Coffee Time ☕"
    [ "$status" -eq 0 ]
}

@test "unicode characters in description" {
    create_mock_notify_send
    run bash notify.sh "Status" "✓ Success"
    [ "$status" -eq 0 ]
}

@test "empty string arguments" {
    create_mock_notify_send
    run bash notify.sh "" ""
    [ "$status" -eq 0 ]
}

@test "special characters in title" {
    create_mock_notify_send
    run bash notify.sh "Build & Deploy"
    [ "$status" -eq 0 ]
}

@test "special characters in description" {
    create_mock_notify_send
    run bash notify.sh "Test" "Status: 100% complete!"
    [ "$status" -eq 0 ]
}

@test "quotes in title" {
    create_mock_notify_send
    run bash notify.sh "User said \"hello\""
    [ "$status" -eq 0 ]
}

@test "quotes in description" {
    create_mock_notify_send
    run bash notify.sh "Quote" "She said \"yes\""
    [ "$status" -eq 0 ]
}

@test "multiple arguments concatenated" {
    create_mock_notify_send
    run bash notify.sh Build complete in 42 seconds
    [ "$status" -eq 0 ]
}

@test "three arguments" {
    create_mock_notify_send
    run bash notify.sh hello world foo
    [ "$status" -eq 0 ]
}

@test "many arguments" {
    create_mock_notify_send
    run bash notify.sh Title arg1 arg2 arg3 arg4 arg5
    [ "$status" -eq 0 ]
}
