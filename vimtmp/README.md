# vimtmp (scratch)

Create a temporary scratch file and open it in your default editor.

## Usage

```bash
vimtmp [OPTIONS]
```

## Description

Creates a temporary file in the system's temporary directory and opens it in your preferred text editor (defined by the `EDITOR` environment variable). The file persists after the editor closes, allowing you to reference it later in the same session.

This is useful for quick notes, temporary calculations, or drafting text without cluttering your workspace with permanent files.

## Prerequisites

- `EDITOR` environment variable must be set to your preferred editor

## Options

- `-h, --help`: Show help message and exit

## Examples

```bash
# Create and edit a scratch file
vimtmp

# Show help
vimtmp --help
```

## How it works

1. Checks that `EDITOR` is set
2. Creates a temporary file using `mktemp`
3. Displays the file path
4. Opens the file in your editor
5. Returns when you close the editor

The temporary file remains on disk until your system cleans up temporary files (typically on reboot), so you can reference it multiple times in the same session.

## Setting your editor

If `EDITOR` is not set, add it to your shell configuration:

```bash
# For vim
export EDITOR=vim

# For nano
export EDITOR=nano

# For VS Code
export EDITOR=code

# For emacs
export EDITOR=emacs
```

## Exit codes

- `0`: Scratch file created and editor launched successfully
- `1`: `EDITOR` not set or other error occurred
