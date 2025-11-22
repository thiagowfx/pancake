# timer

Count down for a specified duration and notify when complete.

## Usage

```bash
timer [OPTIONS] DURATION
```

## Description

Simple countdown timer that waits for the specified duration and alerts you with an audio cue and desktop notification when the time is up.

The DURATION argument uses the same format as the `sleep` command, supporting multiple time units.

## Examples

```bash
# Wait 5 seconds
timer 5

# Wait 5 minutes
timer 5m

# Wait 1 hour
timer 1h

# Wait 90 seconds (1.5 minutes)
timer 90s

# Wait 1.5 hours
timer 1h 30m

# Silent mode (no audio, notification only)
timer --silent 10m
timer -s 300

# Useful for reminders
timer 25m  # Pomodoro technique
timer 8h   # End of workday reminder
timer 3m   # Tea steeping timer
```

## Duration format

The timer accepts any duration format supported by the `sleep` command:

- Numbers without suffix: seconds (e.g., `5` = 5 seconds)
- `s`: seconds
- `m`: minutes
- `h`: hours
- `d`: days

You can combine multiple values: `1h 30m`, `2m 30s`

## Options

- `-h, --help`: Show help message
- `-s, --silent`: Skip audio notification (desktop notification only)

## Installation

### macOS (via Homebrew)

```bash
brew install thiagowfx/pancake/pancake
```

### From source

```bash
# Clone and add to PATH
git clone https://github.com/thiagowfx/pancake.git
export PATH="$PATH:$PWD/pancake/timer"
```

## Features

- **Audio notification**: Plays a system sound when timer completes
  - macOS: Uses `afplay` with built-in Glass sound
  - Linux: Tries `paplay` (PulseAudio) or `aplay` (ALSA)
  - Gracefully degrades if no audio system available

- **Desktop notification**: Shows notification with timer duration
  - Integrates with the pancake `notify` tool
  - Works on both Linux and macOS

- **Silent mode**: Option to disable audio while keeping desktop notification

## Requirements

- **Audio** (optional):
  - macOS: Built-in (uses `afplay`)
  - Linux: PulseAudio (`paplay`) or ALSA (`aplay`)

- **Desktop notifications** (optional):
  - Requires the `notify` tool from pancake
  - Falls back gracefully if not available

## Exit codes

- `0`: Timer completed successfully
- `1`: Invalid arguments or timer interrupted
