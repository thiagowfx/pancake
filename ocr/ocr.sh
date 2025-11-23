#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] IMAGE_FILE [IMAGE_FILE...]

Extract text from images using optical character recognition (OCR).

OPTIONS:
    -h, --help    Show this help message and exit

ARGUMENTS:
    IMAGE_FILE    Path to image file(s) to process (jpg, png, etc.)
                  Multiple files can be specified

DESCRIPTION:
    This script extracts text from image files using Apple's Vision framework
    via a Swift helper. The extracted text is printed to standard output,
    making it easy to pipe to other commands or redirect to a file.

    When processing multiple files, each file's output is separated by a blank
    line. Use with xargs to process files from a pipeline.

    The OCR engine automatically detects language, applies language correction,
    and uses accurate recognition settings for best results.

PREREQUISITES:
    - macOS with Swift and Vision framework (macOS 10.15+)

EXAMPLES:
    $cmd screenshot.png
    $cmd receipt.jpg > receipt.txt
    $cmd document.png | pbcopy
    $cmd page1.png page2.png page3.png
    find . -name "*.png" | xargs $cmd

EXIT CODES:
    0    Text extracted successfully from all files
    1    Invalid arguments, missing dependencies, or OCR failed
EOF
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

check_platform() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "Error: This script requires macOS (uses Vision framework)"
        exit 1
    fi
}

check_swift() {
    if ! command -v swift &> /dev/null; then
        echo "Error: Swift is not installed or not in PATH"
        exit 1
    fi
}

validate_image() {
    local image_path="$1"

    if [[ ! -f "$image_path" ]]; then
        echo "Error: File not found: $image_path"
        exit 1
    fi

    if [[ ! -r "$image_path" ]]; then
        echo "Error: Cannot read file: $image_path"
        exit 1
    fi
}

perform_ocr() {
    local image_path="$1"

    swift - "$image_path" << 'SWIFT_CODE'
#!/usr/bin/env swift

import Foundation
import Vision

func die(_ msg: String) -> Never {
    fputs("\(msg)\n", stderr)
    exit(1)
}

if CommandLine.arguments.count != 2 {
    die("usage: ocr /path/to/frosty-the-snowman.jpg")
}

let path = URL(fileURLWithPath: CommandLine.arguments[1])
var recognizeTextRequest = RecognizeTextRequest()
recognizeTextRequest.automaticallyDetectsLanguage = true
recognizeTextRequest.usesLanguageCorrection = true
recognizeTextRequest.recognitionLevel = .accurate

guard let observations = try? await recognizeTextRequest.perform(on: path) else {
    die("couldn't recognize text")
}

for observation in observations {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
SWIFT_CODE
}

main() {
    check_platform
    check_swift

    local first=true
    for image_path in "$@"; do
        validate_image "$image_path"

        # Add blank line separator between files
        if [[ "$first" == false ]]; then
            echo ""
        fi
        first=false

        perform_ocr "$image_path"
    done
}

main "$@"
