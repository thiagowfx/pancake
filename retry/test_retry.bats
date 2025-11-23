#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp retry.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1

    # Create a counter file for tracking attempts
    COUNTER_FILE="$TEST_TEMP_DIR/counter"
    export COUNTER_FILE
    echo "0" > "$COUNTER_FILE"

    # Mock command directory
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    # Clean up temporary directory (trap will also handle this)
    rm -rf "$TEST_TEMP_DIR"
}

create_mock_success() {
    cat > "$MOCK_BIN_DIR/mock_success" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/mock_success"
}

create_mock_fail_then_succeed() {
    local fail_count="${1:-2}"
    cat > "$MOCK_BIN_DIR/mock_fail_then_succeed" << EOF
#!/bin/bash
COUNTER_FILE="${COUNTER_FILE}"
count=\$(cat "\$COUNTER_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNTER_FILE"
if [[ "\$count" -lt $fail_count ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/mock_fail_then_succeed"
}

create_mock_always_fail() {
    cat > "$MOCK_BIN_DIR/mock_always_fail" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/mock_always_fail"
}

@test "help option displays usage information" {
    run bash retry.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Execute a command repeatedly until it succeeds"* ]]
}

@test "short help option displays usage information" {
    run bash retry.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no arguments shows error" {
    run bash retry.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: No command specified"* ]]
}

@test "immediately successful command exits with 0" {
    create_mock_success
    run timeout 5s bash retry.sh mock_success
    [ "$status" -eq 0 ]
}

@test "command succeeds after retries" {
    create_mock_fail_then_succeed 3
    run timeout 5s bash retry.sh -i 0.1 mock_fail_then_succeed
    [ "$status" -eq 0 ]
    count=$(cat "$COUNTER_FILE")
    [ "$count" -eq 3 ]
}

@test "verbose mode shows attempt messages" {
    create_mock_fail_then_succeed 2
    run timeout 5s bash retry.sh -v -i 0.1 mock_fail_then_succeed
    [ "$status" -eq 0 ]
    [[ "$output" == *"Attempt 1:"* ]]
    [[ "$output" == *"Failed, retrying"* ]]
    [[ "$output" == *"Success after"* ]]
}

@test "max attempts limit is respected" {
    create_mock_always_fail
    run timeout 5s bash retry.sh -i 0.1 -m 3 mock_always_fail
    [ "$status" -eq 125 ]
}

@test "max attempts with verbose shows limit reached" {
    create_mock_always_fail
    run timeout 5s bash retry.sh -v -i 0.1 -m 2 mock_always_fail
    [ "$status" -eq 125 ]
    [[ "$output" == *"Max attempts (2) reached"* ]]
}

@test "timeout limit is respected" {
    create_mock_always_fail
    run bash retry.sh -i 0.2 -t 1 mock_always_fail
    [ "$status" -eq 124 ]
}

@test "timeout with verbose shows timeout reached" {
    create_mock_always_fail
    run bash retry.sh -v -i 0.2 -t 1 mock_always_fail
    [ "$status" -eq 124 ]
    [[ "$output" == *"Timeout"* ]]
}

@test "custom interval is used" {
    create_mock_fail_then_succeed 2
    start=$(date +%s)
    run bash retry.sh -i 1 mock_fail_then_succeed
    end=$(date +%s)
    elapsed=$((end - start))
    [ "$status" -eq 0 ]
    # Should take at least 1 second (one retry with 1s interval)
    [ "$elapsed" -ge 1 ]
}

@test "both max attempts and timeout work together" {
    create_mock_always_fail
    # Timeout will hit first (1 second vs ~3 attempts at 0.5s each)
    run bash retry.sh -i 0.5 -m 10 -t 1 mock_always_fail
    [ "$status" -eq 124 ]
}

@test "invalid interval shows error" {
    create_mock_success
    run bash retry.sh -i invalid mock_success
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --interval must be a positive number"* ]]
}

@test "negative interval shows error" {
    create_mock_success
    run bash retry.sh -i -1 mock_success
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --interval must be a positive number"* ]]
}

@test "invalid max attempts shows error" {
    create_mock_success
    run bash retry.sh -m invalid mock_success
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --max-attempts must be a non-negative integer"* ]]
}

@test "invalid timeout shows error" {
    create_mock_success
    run bash retry.sh -t invalid mock_success
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --timeout must be a non-negative integer"* ]]
}

@test "unknown option shows error" {
    create_mock_success
    run bash retry.sh --unknown mock_success
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Unknown option: --unknown"* ]]
}

@test "command with arguments works" {
    run timeout 5s bash retry.sh -i 0.1 test -f retry.sh
    [ "$status" -eq 0 ]
}

@test "command with multiple arguments works" {
    echo "test" > test.txt
    run timeout 5s bash retry.sh -i 0.1 grep -q test test.txt
    [ "$status" -eq 0 ]
}

@test "interval flag without value shows error" {
    create_mock_success
    run bash retry.sh -i
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --interval requires a value"* ]]
}

@test "max attempts flag without value shows error" {
    create_mock_success
    run bash retry.sh -m
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --max-attempts requires a value"* ]]
}

@test "timeout flag without value shows error" {
    create_mock_success
    run bash retry.sh -t
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --timeout requires a value"* ]]
}

@test "zero max attempts means unlimited" {
    create_mock_fail_then_succeed 5
    run timeout 5s bash retry.sh -i 0.1 -m 0 mock_fail_then_succeed
    [ "$status" -eq 0 ]
}

@test "decimal interval works" {
    create_mock_fail_then_succeed 2
    run timeout 5s bash retry.sh -i 0.25 mock_fail_then_succeed
    [ "$status" -eq 0 ]
}

@test "verbose mode shows correct attempt count on success" {
    create_mock_fail_then_succeed 4
    run timeout 5s bash retry.sh -v -i 0.1 mock_fail_then_succeed
    [ "$status" -eq 0 ]
    [[ "$output" == *"Success after 4 attempt(s)"* ]]
}

@test "double dash separator works" {
    run timeout 5s bash retry.sh -v -- echo "test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test"* ]]
}

@test "double dash allows command with dashes" {
    run timeout 5s bash retry.sh -i 0.1 -- test -f retry.sh
    [ "$status" -eq 0 ]
}

@test "double dash with options after it" {
    create_mock_success
    run timeout 5s bash retry.sh -m 3 -- mock_success --fake-flag
    [ "$status" -eq 0 ]
}
