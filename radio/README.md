# radio

Stream internet radio stations using available media players.

## Usage

```bash
radio [OPTIONS] [station]
radio --list
radio --help
```

## Options

- `-h, --help` - Show help message
- `-l, --list` - List all available stations
- `-r, --running` - List currently running radio stations
- `-f, --foreground` - Run in foreground (default is background)
- `-k, --kill [station]` - Kill radio processes (all or specific station)
- `-b, --burst [N]` - Launch N random stations simultaneously (default: 3)

## Available stations

- **defcon** - DEF CON Radio - Music for hacking (SomaFM)
- **lofi** - Lo-fi hip hop beats
- **trance** - HBR1 Trance
- **salsa** - Latina Salsa
- **kfai** - KFAI (Minneapolis community radio)
- **rain** - Rain sounds for relaxation
- **jazz** - SomaFM - Jazz
- **groovesalad** - SomaFM - Groove Salad (ambient/downtempo)
- **ambient** - SomaFM - Drone Zone
- **indie** - SomaFM - Indie Pop Rocks
- **beatblender** - SomaFM - Beat Blender (deep house)
- **bossa** - SomaFM - Bossa Beyond
- **deepspaceone** - SomaFM - Deep Space One
- **nightride** - Nightride FM (synthwave)
- **spacestation** - SomaFM - Space Station (electronica)
- **wfmu** - WFMU (freeform)

If no station is specified, a random one is selected.

## Examples

Stream a random station in background:
```bash
radio
```

Stream DEF CON Radio in background (default):
```bash
radio defcon
```

Stream lo-fi hip hop in foreground:
```bash
radio -f lofi
```

List all available stations:
```bash
radio --list
```

Show currently running stations:
```bash
radio --running
```

Stop a specific station:
```bash
radio --kill salsa
```

Stop all radio streams:
```bash
radio --kill
```

Launch 3 random stations simultaneously (burst mode):
```bash
radio --burst
```

Launch 5 random stations simultaneously:
```bash
radio --burst 5
```

## Prerequisites

At least one of the following media players:

- **mpv** (recommended)
  - macOS: `brew install mpv`
  - Linux: `sudo apt install mpv`
- **vlc**
  - macOS: `brew install --cask vlc`
  - Linux: `sudo apt install vlc`
- **ffplay** (part of ffmpeg)
  - macOS: `brew install ffmpeg`
  - Linux: `sudo apt install ffmpeg`
- **mplayer**
  - macOS: `brew install mplayer`
  - Linux: `sudo apt install mplayer`

## How it works

The script automatically detects available media players (trying mpv, vlc, ffplay, mplayer in that order) and uses the first one found. It maps station names to streaming URLs and launches the player with minimal output for clean streaming. By default, the player runs in background mode. Processes are named `radio-<station>` for easy identification.

## Exit codes

- **0** - Successfully started streaming
- **1** - Invalid station or no media player available
