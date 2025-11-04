# copy.sh

Add file contents to the clipboard.

## Usage

```bash
# Copy from stdin
echo "BANANA42SPLIT88SUNDAE99CHERRY" | copy

# Copy a file
copy notes.txt

# Copy multiple files
copy *.md
```

## Platform Support

- **macOS**: Uses `pbcopy` (built-in)
- **Linux**: Auto-detects first available tool:
  - `wl-copy` (Wayland) - prioritized for modern desktops
  - `xclip` (X11)
  - `xsel` (X11)

## Features

- Silent on success (Unix philosophy)
- Supports stdin input
- Supports single or multiple files
- Multiple files are concatenated with newline separators
- Clear error messages for missing files or dependencies

## Installation

On Linux, install a clipboard tool if not already present:

```bash
# Wayland
sudo apt install wl-clipboard    # Debian/Ubuntu
sudo dnf install wl-clipboard    # Fedora
sudo pacman -S wl-clipboard      # Arch

# X11
sudo apt install xclip           # Debian/Ubuntu
sudo dnf install xclip           # Fedora
sudo pacman -S xclip             # Arch
```
