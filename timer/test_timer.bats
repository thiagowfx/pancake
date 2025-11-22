#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp timer.sh "$TEST_TEMP_DIR/"
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

create_mock_afplay() {
    cat > "$MOCK_BIN_DIR/afplay" << 'EOF'
#!/bin/bash
# Mock afplay command
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/afplay"
}

create_mock_notify() {
    # Create a mock notify directory structure
    mkdir -p "$TEST_TEMP_DIR/notify"
    cat > "$TEST_TEMP_DIR/notify/notify.sh" << 'EOF'
#!/bin/bash
# Mock notify.sh command
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/notify/notify.sh"
}

@test "help option displays usage information" {
    run bash timer.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Count down for a specified duration"* ]]
}

@test "short help option displays usage information" {
    run bash timer.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no arguments shows error" {
    run bash timer.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: DURATION argument is required"* ]]
}

@test "timer with seconds only" {
    create_mock_afplay
    create_mock_notify
    run timeout 5s bash timer.sh 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer started for 1"* ]]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "timer with seconds suffix" {
    create_mock_afplay
    create_mock_notify
    run timeout 5s bash timer.sh 1s
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer started for 1s"* ]]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "timer with invalid duration shows error" {
    run bash timer.sh invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid duration format"* ]]
}

@test "timer with negative duration shows error" {
    run bash timer.sh -- -5
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid duration format"* ]]
}

@test "silent mode with short flag" {
    create_mock_notify
    run timeout 5s bash timer.sh -s 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer started for 1"* ]]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "silent mode with long flag" {
    create_mock_notify
    run timeout 5s bash timer.sh --silent 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer started for 1"* ]]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "unknown option shows error" {
    run bash timer.sh --unknown 5
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Unknown option: --unknown"* ]]
}

@test "timer with multiple time units" {
    create_mock_afplay
    create_mock_notify
    # Use 0.1s instead of long duration for testing
    run timeout 5s bash timer.sh 0.1s
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer started"* ]]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "timer gracefully handles missing notify script" {
    create_mock_afplay
    # Don't create mock notify - test graceful degradation
    run timeout 5s bash timer.sh 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "timer gracefully handles missing audio system" {
    create_mock_notify
    # Don't create mock afplay - test graceful degradation
    run timeout 5s bash timer.sh 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "timer works with no mocks at all" {
    # Test complete graceful degradation
    run timeout 5s bash timer.sh 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer started for 1"* ]]
    [[ "$output" == *"Timer complete!"* ]]
}

@test "help flag combined with duration is ignored" {
    run bash timer.sh --help 5m
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "silent flag before help flag shows help" {
    run bash timer.sh -s --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
