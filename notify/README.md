# notify

Send desktop notifications across Linux and macOS platforms.

## Usage

```bash
notify [OPTIONS] [TITLE] [MESSAGE...]
```

## Description

Cross-platform desktop notification tool. Works on both Linux and macOS without configuration.

- **Linux**: Uses `notify-send` with 5-second timeout
- **macOS**: Uses `osascript` with JXA (JavaScript for Automation)

If no arguments provided, sends a notification with title "Notification" and current timestamp.

All arguments after the title are concatenated with spaces to form the notification message.

## Examples

```bash
# Default notification
notify

# Custom title only
notify "Build Complete"

# Title and description
notify "Deploy" "Production is live"

# Unicode support
notify "Coffee Time" "☕"

# Multiple arguments form the message
notify Build complete in 42 seconds
notify Error failed to connect to database

# Use in shell pipelines
make && notify "Build succeeded" || notify "Build failed" "Check logs for details"

# Long-running command notification
sleep 300 && notify "Timer done" "5 minutes elapsed"
```

## Installation

### macOS (via Homebrew)

```bash
brew install thiagowfx/pancake/pancake
```

### From source

```bash
# Clone and add to PATH
git clone https://github.com/thiagowfx/pancake.git
export PATH="$PATH:$PWD/pancake/notify"
```

## Requirements

- **Linux**: `libnotify-bin` package (provides `notify-send`)
- **macOS**: Built-in (uses `osascript`)

On macOS, notification permissions may need to be granted to Terminal.app or your terminal emulator in System Settings > Notifications.

## Exit codes

- `0`: Notification sent successfully
- `1`: Failed to send (no supported notification system available)
