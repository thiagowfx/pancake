#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp nato.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1
}

@test "help option displays usage information" {
    run bash nato.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"NATO phonetic alphabet"* ]]
}

@test "converts single word argument" {
    run bash nato.sh hello
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hotel Echo Lima Lima Oscar"* ]]
}

@test "converts multiple arguments" {
    run bash nato.sh hello world
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hotel Echo Lima Lima Oscar"* ]]
    [[ "$output" == *"Whiskey Oscar Romeo Lima Delta"* ]]
}

@test "converts stdin" {
    run bash -c "echo sos | bash nato.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sierra Oscar Sierra"* ]]
}

@test "handles special characters" {
    run bash nato.sh "a b"
    [ "$status" -eq 0 ]
    # "Alfa · Bravo"
    [[ "$output" == *"Alfa · Bravo"* ]]
}

@test "handles numbers" {
    run bash nato.sh 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"One Two Three"* ]]
}

@test "handles mixed case" {
    run bash nato.sh AbCd
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alfa Bravo Charlie Delta"* ]]
}
