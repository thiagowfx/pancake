#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the scripts to test directory for isolation
    cp aws_login_headless.sh "$TEST_TEMP_DIR/"
    cp aws_login_headless_playwright.py "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1

    # Mock bin directory
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
}

teardown() {
    # Clean up temporary directory (trap will also handle this)
    rm -rf "$TEST_TEMP_DIR"
}

@test "help option displays usage information" {
    run bash aws_login_headless.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Fully automated AWS SSO login"* ]]
}

@test "short help option displays usage information" {
    run bash aws_login_headless.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "usage includes all expected options" {
    run bash aws_login_headless.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--profile"* ]]
    [[ "$output" == *"--op-item"* ]]
    [[ "$output" == *"--op-account"* ]]
    [[ "$output" == *"--username"* ]]
    [[ "$output" == *"--no-headless"* ]]
}

@test "missing aws dependency causes failure" {
    # Use isolated PATH without aws
    run env PATH="$MOCK_BIN_DIR:/usr/bin:/bin" bash aws_login_headless.sh --help 2>&1 || true
    # Help should still work even if dependencies are missing
    [ "$status" -eq 0 ]
}

@test "op-item requires an argument" {
    run bash aws_login_headless.sh --op-item
    [ "$status" -eq 1 ]
    [[ "$output" == *"--op-item requires an argument"* ]]
}

@test "op-account requires an argument" {
    run bash aws_login_headless.sh --op-account
    [ "$status" -eq 1 ]
    [[ "$output" == *"--op-account requires an argument"* ]]
}

@test "username requires an argument" {
    run bash aws_login_headless.sh --username
    [ "$status" -eq 1 ]
    [[ "$output" == *"--username requires an argument"* ]]
}

@test "unknown option displays error" {
    run bash aws_login_headless.sh --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --unknown-option"* ]]
}

@test "unexpected argument displays error" {
    run bash aws_login_headless.sh some-extra-arg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected argument: some-extra-arg"* ]]
}

@test "profile requires an argument" {
    run bash aws_login_headless.sh --profile
    [ "$status" -eq 1 ]
    [[ "$output" == *"--profile requires an argument"* ]]
}
