# notify

Send desktop notifications across Linux and macOS platforms.

## Usage

```bash
notify [OPTIONS] [TITLE] [MESSAGE...]
```

## Options

- `-h, --help`: Show help message and exit
- `-p, --persistent`: Keep notification on screen until dismissed (default: auto-dismiss after 5 seconds on Linux)
- `-s, --sound [SOUND]`: Play a sound with the notification
  - `SOUND`: Optional sound name (default: Glass)
  - **macOS**: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
  - **Linux**: Uses system default sound via paplay or aplay

## Description

Cross-platform desktop notification tool. Works on both Linux and macOS without configuration.

- **Linux**: Uses `notify-send` with 5-second timeout (unless `--persistent` flag is used)
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

# Persistent notifications (require manual dismissal)
notify -p "Critical Alert" "Requires immediate attention"
notify --persistent "Deployment Complete" "Review the logs"

# Sound notifications
notify -s "Build Complete"
notify -s Hero "Deploy Done" "Check the dashboard"
notify --sound Ping "Test passed"

# Combine flags
notify -ps Basso "Critical Alert" "Immediate action required"
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
