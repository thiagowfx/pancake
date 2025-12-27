#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Add file contents to the clipboard.

Copy file contents or stdin to the system clipboard. On macOS, uses pbcopy.
On Linux, auto-detects the first available clipboard tool: wl-copy (Wayland),
xclip (X11), or xsel (X11). When multiple files are provided, their contents
are concatenated with newline separators.

USAGE:
    copy [FILE...]
    echo "text" | copy

OPTIONS:
    -h, --help    Show this help message

EXAMPLES:
    Copy stdin to clipboard:
        echo "BANANA42SPLIT88SUNDAE99CHERRY" | copy

    Copy a single file:
        copy notes.txt

    Copy multiple files:
        copy recipe.md ingredients.txt instructions.md

    Copy all markdown files:
        copy *.md

EXIT CODES:
    0    Success
    1    Error (missing dependencies, file not found, etc.)
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

check_dependencies() {
  local -a missing_deps=()

  if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! command -v pbcopy &>/dev/null; then
      missing_deps+=("pbcopy")
    fi
  else
    # Linux: check for at least one clipboard tool
    local has_clipboard_tool=false
    # keep-sorted start
    local -a clipboard_tools=("wl-copy" "xclip" "xsel")
    # keep-sorted end

    for tool in "${clipboard_tools[@]}"; do
      if command -v "$tool" &>/dev/null; then
        has_clipboard_tool=true
        break
      fi
    done

    if [[ "$has_clipboard_tool" == false ]]; then
      echo "Error: No clipboard tool found. Install one of: ${clipboard_tools[*]}" >&2
      exit 1
    fi
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
    echo "Install them and try again." >&2
    exit 1
  fi
}

get_clipboard_command() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "pbcopy"
    return
  fi

  # Linux: prioritize Wayland, then X11 tools
  # keep-sorted start
  local -a clipboard_tools=("wl-copy" "xclip" "xsel")
  # keep-sorted end

  for tool in "${clipboard_tools[@]}"; do
    if command -v "$tool" &>/dev/null; then
      echo "$tool"
      return
    fi
  done

  # Should never reach here due to check_dependencies
  echo "Error: No clipboard tool available" >&2
  exit 1
}

remove_trailing_newline() {
   if [[ -s "$1" ]] && [[ $(tail -c 1 "$1" | wc -l) -eq 1 ]]; then
     dd if="$1" bs=1 count=$(($(wc -c < "$1") - 1)) 2>/dev/null
   else
     cat "$1"
   fi
}

copy_to_clipboard() {
   local clipboard_cmd
   clipboard_cmd="$(get_clipboard_command)"

   if [[ $# -eq 0 ]]; then
     # Read from stdin - remove trailing newline if present
     local tmpfile
     tmpfile="$(mktemp)"
     cat > "$tmpfile"

     remove_trailing_newline "$tmpfile" | "$clipboard_cmd"

     rm "$tmpfile"
   elif [[ $# -eq 1 ]]; then
     # Single file - remove trailing newline
     if [[ ! -f "$1" ]]; then
       echo "Error: File not found: $1" >&2
       exit 1
     fi

     if [[ ! -r "$1" ]]; then
       echo "Error: File not readable: $1" >&2
       exit 1
     fi

     remove_trailing_newline "$1" | "$clipboard_cmd"
   else
     # Multiple files - concatenate with separators
     local first_file=true
     for file in "$@"; do
       if [[ ! -f "$file" ]]; then
         echo "Error: File not found: $file" >&2
         exit 1
       fi

       if [[ ! -r "$file" ]]; then
         echo "Error: File not readable: $file" >&2
         exit 1
       fi

       if [[ "$first_file" == true ]]; then
         first_file=false
         cat "$file"
       else
         echo  # Newline separator between files
         cat "$file"
       fi
     done | "$clipboard_cmd"
   fi
}

main() {
  check_dependencies
  copy_to_clipboard "$@"
}

main "$@"
