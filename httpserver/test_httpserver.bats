#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp httpserver.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1
}

@test "help option displays usage information" {
    run bash httpserver.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"HTTP server"* ]]
}

@test "help with -h flag" {
    run bash httpserver.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "detects available HTTP server tool" {
    # This test verifies the script can find at least one tool
    # We mock the execution to prevent actually starting a server

    # Create a mock that just exits immediately
    cat > mock_server.sh << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x mock_server.sh

    # The script should detect one of the available tools
    run timeout 1 bash httpserver.sh 9999 || true
    # Should start trying to launch a server
    [[ "$output" == *"Starting HTTP server"* ]]
}

@test "invalid port number shows error" {
    run bash httpserver.sh abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid port"* ]]
}

@test "shows default port in output" {
    run timeout 1 bash httpserver.sh || true
    [[ "$output" == *"8000"* ]]
}

@test "shows custom port in output" {
    run timeout 1 bash httpserver.sh 3000 || true
    [[ "$output" == *"3000"* ]]
}

@test "shows current directory being served" {
    run timeout 1 bash httpserver.sh || true
    [[ "$output" == *"Serving directory:"* ]]
}

@test "shows access URL" {
    run timeout 1 bash httpserver.sh 4200 || true
    [[ "$output" == *"http://localhost:4200"* ]]
}
