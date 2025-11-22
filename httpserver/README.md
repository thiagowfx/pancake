# httpserver

Start a local HTTP server in the current directory.

## Overview

Simple tool that starts an HTTP file server in the current directory using whatever is available on your system. No need to remember different commands for different languages.

## Installation

Available via the pancake homebrew formula:

```bash
brew install thiagowfx/pancake/pancake
```

## Usage

```bash
# Start server on default port 8000
httpserver

# Start server on custom port
httpserver 3000

# Show help
httpserver --help
```

## Features

- Automatically detects and uses the first available tool:
  - PHP built-in server
  - Python 3 http.server
  - Python 2 SimpleHTTPServer
  - Ruby WEBrick server
- Simple interface with sensible defaults
- Clear output showing server location and access URL

## Examples

```bash
# Serve files from current directory on port 8000
httpserver

# Serve files on port 4200
httpserver 4200

# Access the server
# Open http://localhost:8000 in your browser
```

## Requirements

At least one of:
- PHP
- Python 3
- Python
- Ruby

## Exit Codes

- `0` - Server started successfully
- `1` - No suitable HTTP server tool found or invalid port

## Notes

- Server runs in the foreground. Press Ctrl-C to stop.
- Files in the current directory (and subdirectories) will be accessible via the browser.
- Default port is 8000, a commonly used port for development servers.
