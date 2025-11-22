#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp vimtmp.sh "$TEST_TEMP_DIR/"
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

create_mock_editor() {
    cat > "$MOCK_BIN_DIR/fake-editor" << 'EOF'
#!/bin/bash
# Mock editor - just touch the file to verify it exists
if [ -f "$1" ]; then
    echo "Editor opened: $1" > /tmp/vimtmp-test-output
    exit 0
else
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/fake-editor"
}

create_failing_editor() {
    cat > "$MOCK_BIN_DIR/fake-editor" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/fake-editor"
}

@test "help option displays usage information" {
    run bash vimtmp.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Create a temporary scratch file"* ]]
}

@test "short help option displays usage information" {
    run bash vimtmp.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "exits with error when EDITOR is not set" {
    unset EDITOR
    run bash vimtmp.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"EDITOR environment variable is not set"* ]]
}

@test "creates scratch file and opens editor" {
    create_mock_editor
    export EDITOR="$MOCK_BIN_DIR/fake-editor"
    run bash vimtmp.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening scratch file:"* ]]
}

@test "scratch file path contains /tmp" {
    create_mock_editor
    export EDITOR="$MOCK_BIN_DIR/fake-editor"
    run bash vimtmp.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/"* ]] || [[ "$output" == *"/var/folders/"* ]]
}

@test "script works with vim as editor" {
    # Mock vim to just exit successfully
    cat > "$MOCK_BIN_DIR/vim" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/vim"
    export EDITOR="vim"
    run bash vimtmp.sh
    [ "$status" -eq 0 ]
}

@test "script works with nano as editor" {
    # Mock nano to just exit successfully
    cat > "$MOCK_BIN_DIR/nano" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/nano"
    export EDITOR="nano"
    run bash vimtmp.sh
    [ "$status" -eq 0 ]
}

@test "script works with code as editor" {
    # Mock code to just exit successfully
    cat > "$MOCK_BIN_DIR/code" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/code"
    export EDITOR="code"
    run bash vimtmp.sh
    [ "$status" -eq 0 ]
}

@test "no extra arguments accepted" {
    create_mock_editor
    export EDITOR="$MOCK_BIN_DIR/fake-editor"
    run bash vimtmp.sh some-arg
    [ "$status" -eq 0 ]
    # Script should work even with extra args (they're ignored)
}
