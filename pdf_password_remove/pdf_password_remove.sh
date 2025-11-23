#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Remove password protection from PDF files.

Remove password protection from one or more PDF files, creating unlocked
versions. Requires the existing password. By default, outputs files with
'-unlocked' suffix. Use -o to specify a custom output filename (single file
only).

USAGE:
    pdf_password_remove [OPTIONS] FILE...

OPTIONS:
    -h, --help              Show this help message
    -p, --password=PASS     Provide password (will prompt if not given)
    -o, --output=FILE       Output filename (single file only)

PREREQUISITES:
    - ghostscript (gs, preferred) or qpdf must be installed
      macOS:   brew install ghostscript
               brew install qpdf
      Linux:   apt/dnf/pacman install ghostscript or qpdf

EXAMPLES:
    Remove password with interactive prompt:
        pdf_password_remove secret.pdf

    Process multiple files:
        pdf_password_remove financial-report.pdf tax-form.pdf passport.pdf

    Provide password via command line:
        pdf_password_remove --password=BANANA42SPLIT secret.pdf

    Custom output filename:
        pdf_password_remove -o unlocked.pdf secret.pdf

    Combine options:
        pdf_password_remove -p PIZZA69SLICE -o clean.pdf document.pdf

EXIT CODES:
    0    All files processed successfully
    1    Error occurred (missing dependencies, wrong password, etc.)
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

check_dependencies() {
  # Check for either ghostscript or qpdf
  if ! command -v gs &>/dev/null && ! command -v qpdf &>/dev/null; then
    echo "Error: Neither ghostscript (gs) nor qpdf found" >&2
    echo "Install one of them:" >&2
    echo "  macOS:   brew install ghostscript (or: brew install qpdf)" >&2
    echo "  Linux:   apt/dnf/pacman install ghostscript (or: qpdf)" >&2
    exit 1
  fi
}

get_pdf_tool() {
  # Prefer ghostscript, fall back to qpdf
  if command -v gs &>/dev/null; then
    echo "gs"
  elif command -v qpdf &>/dev/null; then
    echo "qpdf"
  fi
}

parse_args() {
  PASSWORD=""
  OUTPUT_FILE=""
  INPUT_FILES=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--password)
        if [[ -n "${2:-}" ]]; then
          PASSWORD="$2"
          shift 2
        else
          echo "Error: --password requires an argument" >&2
          exit 1
        fi
        ;;
      --password=*)
        PASSWORD="${1#*=}"
        shift
        ;;
      -o|--output)
        if [[ -n "${2:-}" ]]; then
          OUTPUT_FILE="$2"
          shift 2
        else
          echo "Error: --output requires an argument" >&2
          exit 1
        fi
        ;;
      --output=*)
        OUTPUT_FILE="${1#*=}"
        shift
        ;;
      -*)
        echo "Error: Unknown option: $1" >&2
        echo "Use -h or --help for usage information." >&2
        exit 1
        ;;
      *)
        INPUT_FILES+=("$1")
        shift
        ;;
    esac
  done

  # Validate arguments
  if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
    echo "Error: No input files specified" >&2
    echo "Use -h or --help for usage information." >&2
    exit 1
  fi

  if [[ -n "$OUTPUT_FILE" ]] && [[ ${#INPUT_FILES[@]} -gt 1 ]]; then
    echo "Error: --output can only be used with a single input file" >&2
    exit 1
  fi
}

get_password() {
  if [[ -z "$PASSWORD" ]]; then
    # Prompt for password interactively
    read -rs -p "Enter PDF password: " PASSWORD
    echo >&2
    if [[ -z "$PASSWORD" ]]; then
      echo "Error: Password cannot be empty" >&2
      exit 1
    fi
  fi
}

process_pdf() {
  local input_file="$1"
  local output_file="$2"
  local password="$3"

  if [[ ! -f "$input_file" ]]; then
    echo "Error: File not found: $input_file" >&2
    return 1
  fi

  if [[ ! -r "$input_file" ]]; then
    echo "Error: File not readable: $input_file" >&2
    return 1
  fi

  # Check if file is actually a PDF
  if ! file "$input_file" | grep -q "PDF"; then
    echo "Error: Not a PDF file: $input_file" >&2
    return 1
  fi

  # Use available tool to remove password
  local tool
  tool="$(get_pdf_tool)"

  local success=false
  if [[ "$tool" == "qpdf" ]]; then
    if qpdf --password="$password" --decrypt "$input_file" "$output_file" 2>/dev/null; then
      success=true
    fi
  elif [[ "$tool" == "gs" ]]; then
    if gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sPDFPassword="$password" -sOutputFile="$output_file" "$input_file" 2>/dev/null; then
      success=true
    fi
  fi

  if [[ "$success" == true ]]; then
    echo "✓ Successfully processed: $input_file → $output_file"
    return 0
  else
    echo "✗ Failed to process: $input_file (wrong password or corrupted file?)" >&2
    return 1
  fi
}

main() {
  check_dependencies
  parse_args "$@"
  get_password

  local success_count=0
  local total_count=${#INPUT_FILES[@]}
  local failed_files=()

  for input_file in "${INPUT_FILES[@]}"; do
    # Determine output filename
    local output_file
    if [[ -n "$OUTPUT_FILE" ]]; then
      output_file="$OUTPUT_FILE"
    else
      # Add -unlocked suffix before extension
      local basename="${input_file%.*}"
      local extension="${input_file##*.}"
      if [[ "$basename" == "$input_file" ]]; then
        # No extension
        output_file="${input_file}-unlocked"
      else
        output_file="${basename}-unlocked.${extension}"
      fi
    fi

    if process_pdf "$input_file" "$output_file" "$PASSWORD"; then
      ((success_count++))
    else
      failed_files+=("$input_file")
    fi
  done

  echo ""
  echo "Summary: Successfully processed $success_count/$total_count file(s)"

  if [[ $success_count -eq $total_count ]]; then
    exit 0
  else
    echo "Failed files: ${failed_files[*]}" >&2
    exit 1
  fi
}

main "$@"
