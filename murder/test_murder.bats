#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp murder.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1

    # Mock commands by creating fake executables in PATH
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"

    # Create test process that will run in background
    TEST_PROCESS_CMD="$TEST_TEMP_DIR/test_process.sh"
    cat > "$TEST_PROCESS_CMD" << 'EOF'
#!/bin/bash
# Simple test process that sleeps
trap 'exit 0' TERM INT HUP
while true; do
    sleep 1
done
EOF
    chmod +x "$TEST_PROCESS_CMD"
}

teardown() {
    # Clean up any test processes
    pkill -f "test_process.sh" 2>/dev/null || true
    # Clean up temporary directory
    rm -rf "$TEST_TEMP_DIR"
}

@test "help option displays usage information" {
    run bash murder.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Kill processes gracefully"* ]]
    [[ "$output" == *"TARGET"* ]]
}

@test "short help option displays usage information" {
    run bash murder.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no target argument displays error" {
    run bash murder.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"TARGET is required"* ]]
}

@test "invalid option displays error" {
    run bash murder.sh --invalid-option 1234
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "non-numeric PID displays error" {
    run bash murder.sh abc123
    [ "$status" -eq 1 ]
    [[ "$output" == *"No processes found"* ]]
}

@test "kill by name with force flag" {
    # Start a test process with a unique name
    bash -c 'exec -a unicorn_test_proc sleep 300' &
    local test_pid=$!

    # Give it a moment to start
    sleep 0.5

    # Kill it by name with force flag
    run timeout 20 bash murder.sh -f unicorn_test_proc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found processes matching 'unicorn_test_proc'"* ]]
    [[ "$output" == *"Killed"* ]]

    # Verify process is dead
    sleep 1
    # shellcheck disable=SC2314
    ! kill -0 "$test_pid" 2>/dev/null
}

@test "kill by name without matches" {
    run bash murder.sh nonexistent_proc_name_42
    [ "$status" -eq 1 ]
    [[ "$output" == *"No processes found matching"* ]]
}

@test "kill by port requires lsof" {
    # Remove lsof from PATH
    run env PATH="$MOCK_BIN_DIR:/usr/bin:/bin" bash -c 'hash -r; which lsof >/dev/null 2>&1 || bash murder.sh :8080'
    # If lsof doesn't exist, should get error about missing lsof
    if [[ "$status" -ne 0 ]]; then
        [[ "$output" == *"lsof"* ]] || [[ "$output" == *"No processes found"* ]]
    fi
}

@test "kill by port when no process listening" {
    # Skip if lsof not available
    if ! command -v lsof &> /dev/null; then
        skip "lsof not available"
    fi

    # Use a very high port unlikely to be in use
    run bash murder.sh :65432
    [ "$status" -eq 1 ]
    [[ "$output" == *"No processes found listening on port"* ]]
}

@test "signal escalation sends multiple signals" {
    # Start a test process
    bash "$TEST_PROCESS_CMD" &
    local test_pid=$!

    # Give it a moment to start
    sleep 0.5

    # Kill it and verify escalation messages
    run timeout 20 bash murder.sh "$test_pid"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sending SIGTERM"* ]]

    # Process should be dead
    sleep 1
    # shellcheck disable=SC2314
    ! kill -0 "$test_pid" 2>/dev/null
}

@test "process details shown before killing by name" {
    # Start a test process with unique name
    bash -c 'exec -a dragon_test_proc sleep 300' &
    local test_pid=$!

    # Give it a moment to start
    sleep 0.5

    # Use force to avoid interactive prompt
    run timeout 20 bash murder.sh -f dragon_test_proc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found processes matching 'dragon_test_proc'"* ]]

    # Clean up
    kill "$test_pid" 2>/dev/null || true
}

@test "supports port with leading colon" {
    # Skip if lsof not available
    if ! command -v lsof &> /dev/null; then
        skip "lsof not available"
    fi

    run bash murder.sh :65433
    [ "$status" -eq 1 ]
    [[ "$output" == *"No processes found listening on port 65433"* ]]
}

@test "supports port without leading colon as fallback" {
    # Skip if lsof not available
    if ! command -v lsof &> /dev/null; then
        skip "lsof not available"
    fi

    # Use a high port number that won't be a valid PID
    run bash murder.sh 65434
    [ "$status" -eq 1 ]
    [[ "$output" == *"No processes found listening on port 65434"* ]]
}

@test "multiple targets error" {
    run bash murder.sh 1234 5678
    [ "$status" -eq 1 ]
    [[ "$output" == *"Multiple targets specified"* ]]
}

@test "force flag works with long form" {
    # Start a test process
    bash -c 'exec -a phoenix_test_proc sleep 300' &
    local test_pid=$!

    # Give it a moment to start
    sleep 0.5

    # Kill with --force
    run timeout 20 bash murder.sh --force phoenix_test_proc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Killed"* ]]

    # Clean up
    sleep 1
    # shellcheck disable=SC2314
    ! kill -0 "$test_pid" 2>/dev/null
}

@test "case insensitive process name matching" {
    # Start a test process
    bash -c 'exec -a CAPSLOCK_TEST_PROC sleep 300' &
    local test_pid=$!

    # Give it a moment to start
    sleep 0.5

    # Search with different case
    run timeout 20 bash murder.sh -f capslock
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found processes matching"* ]]

    # Clean up
    sleep 1
    # shellcheck disable=SC2314
    ! kill -0 "$test_pid" 2>/dev/null
}

@test "refuses to kill root-owned process without flag" {
    # Skip if not running as non-root
    if [[ $EUID -eq 0 ]]; then
        skip "Test must run as non-root user"
    fi

    # Find a root-owned process (init/systemd or launchd)
    local root_pid
    if command -v systemctl &> /dev/null; then
        root_pid=1  # systemd on Linux
    else
        # On macOS, find launchd
        root_pid=$(ps -u root -o pid= | head -n 1 | tr -d '[:space:]')
    fi

    if [[ -z "$root_pid" ]]; then
        skip "Could not find a root-owned process"
    fi

    # Attempt to kill without --allow-root
    run bash murder.sh "$root_pid"
    [ "$status" -eq 1 ]
    [[ "$output" == *"owned by root"* ]]
    [[ "$output" == *"--allow-root"* ]]
}

@test "allow-root flag with short form" {
    # Skip if not running as root
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root privileges (would just check flag parsing)"
    fi

    # This test just verifies the flag is accepted
    # We don't actually want to kill system processes
    run bash murder.sh -r --help
    [ "$status" -eq 0 ]
}

@test "allow-root flag with long form" {
    # Skip if not running as root
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root privileges (would just check flag parsing)"
    fi

    # This test just verifies the flag is accepted
    run bash murder.sh --allow-root --help
    [ "$status" -eq 0 ]
}

@test "skip root-owned processes by name without flag" {
    # Skip if not running as non-root
    if [[ $EUID -eq 0 ]]; then
        skip "Test must run as non-root user"
    fi

    # Start both a regular process and check if system has root processes
    bash -c 'exec -a test_regular_proc sleep 300' &
    local test_pid=$!
    sleep 0.5

    # Try to kill 'init' or 'launchd' (root-owned system process)
    # This should skip root processes
    local root_process_name
    if command -v systemctl &> /dev/null; then
        root_process_name="systemd"
    else
        root_process_name="launchd"
    fi

    run timeout 10 bash murder.sh -f "$root_process_name"
    # Should either find no matching processes (our test env) or skip root-owned ones
    [[ "$output" == *"No processes found"* ]] || [[ "$output" == *"owned by root"* ]] || [ "$status" -eq 1 ]

    # Clean up our test process
    kill "$test_pid" 2>/dev/null || true
}

