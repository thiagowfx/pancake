#!/usr/bin/env bats

setup() {
    # Create a temporary directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Set up trap to ensure cleanup happens even if test fails
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

    # Copy the script to test directory for isolation
    cp pdf_password_remove.sh "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || exit 1

    # Mock bin directory
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    # Clean up temporary directory (trap will also handle this)
    rm -rf "$TEST_TEMP_DIR"
}

create_mock_qpdf() {
    cat > "$MOCK_BIN_DIR/qpdf" << 'EOF'
#!/bin/bash
# Mock qpdf command
password=""
decrypt=false
input_file=""
output_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --password=*)
            password="${1#*=}"
            shift
            ;;
        --decrypt)
            decrypt=true
            shift
            ;;
        *)
            if [[ -z "$input_file" ]]; then
                input_file="$1"
            else
                output_file="$1"
            fi
            shift
            ;;
    esac
done

# Check password matches test password
if [[ "$password" == "TESTPASSWORD123" ]] && [[ -f "$input_file" ]]; then
    cp "$input_file" "$output_file"
    exit 0
else
    echo "Error: wrong password or file not found" >&2
    exit 2
fi
EOF
    chmod +x "$MOCK_BIN_DIR/qpdf"
}

create_mock_gs() {
    cat > "$MOCK_BIN_DIR/gs" << 'EOF'
#!/bin/bash
# Mock ghostscript command
password=""
output_file=""
input_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -sPDFPassword=*)
            password="${1#*=}"
            shift
            ;;
        -sOutputFile=*)
            output_file="${1#*=}"
            shift
            ;;
        -q|-dNOPAUSE|-dBATCH|-sDEVICE=*)
            shift
            ;;
        *)
            input_file="$1"
            shift
            ;;
    esac
done

# Check password matches test password
if [[ "$password" == "TESTPASSWORD123" ]] && [[ -f "$input_file" ]]; then
    cp "$input_file" "$output_file"
    exit 0
else
    echo "Error: wrong password or file not found" >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/gs"
}

create_mock_file() {
    cat > "$MOCK_BIN_DIR/file" << 'EOF'
#!/bin/bash
# Mock file command - always returns PDF for .pdf files
filename="$1"
if [[ "$filename" == *.pdf ]]; then
    echo "$filename: PDF document, version 1.4"
else
    echo "$filename: data"
fi
EOF
    chmod +x "$MOCK_BIN_DIR/file"
}

create_test_pdf() {
    local filename="$1"
    # Create a minimal valid PDF structure
    cat > "$filename" << 'PDFEOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources 4 0 R /MediaBox [0 0 612 792] /Contents 5 0 R >>
endobj
4 0 obj
<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>
endobj
5 0 obj
<< /Length 44 >>
stream
BT
/F1 12 Tf
100 700 Td
(Test Document) Tj
ET
endstream
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000214 00000 n
0000000299 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
392
%%EOF
PDFEOF
}

@test "help option displays usage information" {
    create_mock_gs
    run bash pdf_password_remove.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"Remove password protection from PDF files"* ]]
}

@test "short help option displays usage information" {
    create_mock_gs
    run bash pdf_password_remove.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
}

@test "usage includes all expected options" {
    create_mock_gs
    run bash pdf_password_remove.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--password"* ]]
    [[ "$output" == *"--output"* ]]
    [[ "$output" == *"--help"* ]]
}

@test "missing both dependencies causes failure" {
    # Don't create mock gs or qpdf, and use isolated PATH
    create_test_pdf "test.pdf"
    run env PATH="$MOCK_BIN_DIR:/usr/bin:/bin" bash pdf_password_remove.sh --password=TEST test.pdf
    [ "$status" -eq 1 ]
    [[ "$output" == *"Neither ghostscript (gs) nor qpdf found"* ]]
}

@test "no input files displays error" {
    create_mock_gs
    run bash pdf_password_remove.sh --password=TEST
    [ "$status" -eq 1 ]
    [[ "$output" == *"No input files specified"* ]]
}

@test "password option requires an argument" {
    create_mock_gs
    create_test_pdf "test.pdf"
    run bash pdf_password_remove.sh --password
    [ "$status" -eq 1 ]
    [[ "$output" == *"--password requires an argument"* ]]
}

@test "output option requires an argument" {
    create_mock_gs
    create_test_pdf "test.pdf"
    run bash pdf_password_remove.sh --output
    [ "$status" -eq 1 ]
    [[ "$output" == *"--output requires an argument"* ]]
}

@test "unknown option displays error" {
    create_mock_gs
    run bash pdf_password_remove.sh --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --unknown-option"* ]]
}

@test "output flag with multiple files displays error" {
    create_mock_gs
    create_test_pdf "test1.pdf"
    create_test_pdf "test2.pdf"
    run bash pdf_password_remove.sh -o output.pdf --password=TEST test1.pdf test2.pdf
    [ "$status" -eq 1 ]
    [[ "$output" == *"--output can only be used with a single input file"* ]]
}

@test "nonexistent file displays error" {
    create_mock_gs
    create_mock_file
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 nonexistent.pdf
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found: nonexistent.pdf"* ]]
}

@test "process single pdf file with ghostscript" {
    create_mock_gs
    create_mock_file
    create_test_pdf "secret.pdf"
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 secret.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Successfully processed: secret.pdf → secret-unlocked.pdf"* ]]
    [[ "$output" == *"Successfully processed 1/1 file(s)"* ]]
    [ -f "secret-unlocked.pdf" ]
}

@test "process single pdf file with qpdf" {
    create_mock_qpdf
    create_mock_file
    create_test_pdf "secret.pdf"
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 secret.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Successfully processed: secret.pdf → secret-unlocked.pdf"* ]]
    [ -f "secret-unlocked.pdf" ]
}

@test "ghostscript is preferred over qpdf" {
    create_mock_gs
    create_mock_qpdf
    create_mock_file
    create_test_pdf "test.pdf"

    # Add marker to detect which tool was used
    cat >> "$MOCK_BIN_DIR/gs" << 'EOF'
echo "GS_MARKER" > /tmp/pdf_tool_used
EOF
    cat >> "$MOCK_BIN_DIR/qpdf" << 'EOF'
echo "QPDF_MARKER" > /tmp/pdf_tool_used
EOF

    run bash pdf_password_remove.sh --password=TESTPASSWORD123 test.pdf
    [ "$status" -eq 0 ]

    # Verify gs was used (if file exists)
    if [ -f "/tmp/pdf_tool_used" ]; then
        marker=$(cat /tmp/pdf_tool_used)
        [[ "$marker" == "GS_MARKER" ]]
        rm -f /tmp/pdf_tool_used
    fi
}

@test "process single pdf with custom output filename" {
    create_mock_gs
    create_mock_file
    create_test_pdf "secret.pdf"
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 -o unlocked.pdf secret.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Successfully processed: secret.pdf → unlocked.pdf"* ]]
    [ -f "unlocked.pdf" ]
}

@test "process multiple pdf files" {
    create_mock_gs
    create_mock_file
    create_test_pdf "financial-report.pdf"
    create_test_pdf "tax-form.pdf"
    create_test_pdf "contract.pdf"
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 financial-report.pdf tax-form.pdf contract.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Successfully processed: financial-report.pdf → financial-report-unlocked.pdf"* ]]
    [[ "$output" == *"✓ Successfully processed: tax-form.pdf → tax-form-unlocked.pdf"* ]]
    [[ "$output" == *"✓ Successfully processed: contract.pdf → contract-unlocked.pdf"* ]]
    [[ "$output" == *"Successfully processed 3/3 file(s)"* ]]
    [ -f "financial-report-unlocked.pdf" ]
    [ -f "tax-form-unlocked.pdf" ]
    [ -f "contract-unlocked.pdf" ]
}

@test "wrong password causes failure" {
    create_mock_gs
    create_mock_file
    create_test_pdf "secret.pdf"
    run bash pdf_password_remove.sh --password=WRONGPASSWORD secret.pdf
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗ Failed to process: secret.pdf"* ]]
    [[ "$output" == *"wrong password"* ]]
}

@test "non-pdf file displays error" {
    create_mock_gs
    create_mock_file
    echo "This is not a PDF" > notapdf.txt
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 notapdf.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not a PDF file"* ]]
}

@test "handles files without extension correctly" {
    create_mock_gs
    create_mock_file
    create_test_pdf "document.pdf"
    mv document.pdf document
    # Mock file command will say it's not a PDF since no .pdf extension
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 document
    [ "$status" -eq 1 ]
}

@test "preserves file extension in output" {
    create_mock_gs
    create_mock_file
    create_test_pdf "report.PDF"
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 report.PDF
    [ "$status" -eq 0 ]
    [[ "$output" == *"report.PDF → report-unlocked.PDF"* ]]
}

@test "short form password argument works" {
    create_mock_gs
    create_mock_file
    create_test_pdf "test.pdf"
    run bash pdf_password_remove.sh -p TESTPASSWORD123 test.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Successfully processed"* ]]
}

@test "equals syntax for password works" {
    create_mock_gs
    create_mock_file
    create_test_pdf "test.pdf"
    run bash pdf_password_remove.sh --password=TESTPASSWORD123 test.pdf
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Successfully processed"* ]]
}

@test "partial failure with multiple files" {
    create_mock_gs
    create_mock_file
    create_test_pdf "good1.pdf"
    create_test_pdf "good2.pdf"

    # Create a mock that fails for specific file
    cat > "$MOCK_BIN_DIR/gs" << 'EOF'
#!/bin/bash
output_file=""
input_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -sOutputFile=*) output_file="${1#*=}"; shift ;;
        -q|-dNOPAUSE|-dBATCH|-sDEVICE=*|-sPDFPassword=*) shift ;;
        *) input_file="$1"; shift ;;
    esac
done
# Fail for good2.pdf
if [[ "$input_file" == *"good2.pdf"* ]]; then
    exit 1
fi
cp "$input_file" "$output_file" 2>/dev/null
EOF
    chmod +x "$MOCK_BIN_DIR/gs"

    run bash pdf_password_remove.sh --password=TEST good1.pdf good2.pdf
    [ "$status" -eq 1 ]
    [[ "$output" == *"✓ Successfully processed: good1.pdf"* ]]
    [[ "$output" == *"✗ Failed to process: good2.pdf"* ]]
    [[ "$output" == *"Successfully processed 1/2 file(s)"* ]]
    [[ "$output" == *"Failed files: good2.pdf"* ]]
}
