#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp radio.sh "$TEST_TEMP_DIR/"
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

create_mock_mpv() {
    cat > "$MOCK_BIN_DIR/mpv" << 'EOF'
#!/bin/bash
# Mock mpv command
echo "mpv called with: $*" > /tmp/radio-test-output
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/mpv"
}

create_mock_vlc() {
    cat > "$MOCK_BIN_DIR/vlc" << 'EOF'
#!/bin/bash
# Mock vlc command
echo "vlc called with: $*" > /tmp/radio-test-output
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/vlc"
}

create_mock_ffplay() {
    cat > "$MOCK_BIN_DIR/ffplay" << 'EOF'
#!/bin/bash
# Mock ffplay command
echo "ffplay called with: $*" > /tmp/radio-test-output
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ffplay"
}

create_mock_mplayer() {
    cat > "$MOCK_BIN_DIR/mplayer" << 'EOF'
#!/bin/bash
# Mock mplayer command
echo "mplayer called with: $*" > /tmp/radio-test-output
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/mplayer"
}

@test "help option displays usage information" {
    run bash radio.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Stream internet radio stations"* ]]
    [[ "$output" == *"defcon"* ]]
}

@test "short help option displays usage information" {
    run bash radio.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "list option displays available stations" {
    run bash radio.sh --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available stations:"* ]]
    [[ "$output" == *"defcon"* ]]
    [[ "$output" == *"lofi"* ]]
    [[ "$output" == *"trance"* ]]
    [[ "$output" == *"salsa"* ]]
    [[ "$output" == *"kfai"* ]]
}

@test "short list option displays available stations" {
    run bash radio.sh -l
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available stations:"* ]]
}

@test "no arguments shows error" {
    run bash radio.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: No station specified"* ]]
}

@test "unknown station shows error" {
    create_mock_mpv
    run bash radio.sh tacobell
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Unknown station 'tacobell'"* ]]
}

@test "defcon station streams successfully" {
    create_mock_mpv
    run timeout 1s bash radio.sh defcon || true
    [[ "$output" == *"Streaming defcon radio"* ]]
}

@test "lofi station streams successfully" {
    create_mock_mpv
    run timeout 1s bash radio.sh lofi || true
    [[ "$output" == *"Streaming lofi radio"* ]]
}

@test "trance station streams successfully" {
    create_mock_mpv
    run timeout 1s bash radio.sh trance || true
    [[ "$output" == *"Streaming trance radio"* ]]
}

@test "salsa station streams successfully" {
    create_mock_mpv
    run timeout 1s bash radio.sh salsa || true
    [[ "$output" == *"Streaming salsa radio"* ]]
}

@test "kfai station streams successfully" {
    create_mock_mpv
    run timeout 1s bash radio.sh kfai || true
    [[ "$output" == *"Streaming kfai radio"* ]]
}

@test "error when no media player installed" {
    run bash radio.sh defcon
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: No media player found"* ]]
}

@test "fallback to vlc when mpv not available" {
    create_mock_vlc
    run timeout 1s bash radio.sh defcon || true
    [[ "$output" == *"using vlc"* ]]
}

@test "fallback to ffplay when mpv and vlc not available" {
    create_mock_ffplay
    run timeout 1s bash radio.sh defcon || true
    [[ "$output" == *"using ffplay"* ]]
}

@test "fallback to mplayer when others not available" {
    create_mock_mplayer
    run timeout 1s bash radio.sh defcon || true
    [[ "$output" == *"using mplayer"* ]]
}

@test "prefers mpv when multiple players available" {
    create_mock_mpv
    create_mock_vlc
    create_mock_ffplay
    run timeout 1s bash radio.sh defcon || true
    [[ "$output" == *"using mpv"* ]]
}

@test "background mode is default" {
    create_mock_mpv
    run bash radio.sh defcon
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting defcon radio in background"* ]]
    [[ "$output" == *"Stop with: pkill -f radio-defcon"* ]]
}

@test "foreground mode option works with short flag" {
    create_mock_mpv
    run timeout 1s bash radio.sh -f lofi || true
    [[ "$output" == *"Streaming lofi radio"* ]]
}

@test "foreground mode option works with long flag" {
    create_mock_mpv
    run timeout 1s bash radio.sh --foreground trance || true
    [[ "$output" == *"Streaming trance radio"* ]]
}

@test "unknown option shows error" {
    create_mock_mpv
    run bash radio.sh --invalid defcon
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Unknown option"* ]]
}
