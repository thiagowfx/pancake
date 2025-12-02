# github_ooo

Set your GitHub status to Out of Office until a specified date.

## Installation

This tool is included in the pancake collection. For standalone use, download
the script and make it executable:

```bash
chmod +x github_ooo.sh
```

## Usage

```bash
github_ooo [OPTIONS] [DATE] [EMOJI] [MESSAGE...]
```

Set or clear your GitHub user status to out of office. The status will
automatically clear at the end of the specified date (23:59:59 UTC).

### Arguments

- `DATE` - End date for OOO status in YYYY-MM-DD format (required unless using `--clear`)
- `EMOJI` - Optional emoji to display (e.g., 🏖️, 🎄, 🏥)
- `MESSAGE...` - Optional status message (all remaining arguments joined)

### Options

- `-c, --clear` - Clear the current status immediately (no DATE needed)
- `-o, --org ORG` - Limit status visibility to specific organization
- `-h, --help` - Show help message

### Environment

- `GITHUB_PAT` - GitHub Personal Access Token (required)
  - Must have `user` scope
  - Create at https://github.com/settings/tokens

### Examples

Set OOO until December 25:

```bash
GITHUB_PAT=ghp_xxx github_ooo 2025-12-25
```

With emoji:

```bash
GITHUB_PAT=ghp_xxx github_ooo 2025-12-25 🏖️
```

With emoji and message:

```bash
GITHUB_PAT=ghp_xxx github_ooo 2025-12-25 🏖️ "Enjoying the beaches"
```

Message without emoji:

```bash
GITHUB_PAT=ghp_xxx github_ooo 2025-12-25 "Away for the holidays"
```

Clear status immediately:

```bash
GITHUB_PAT=ghp_xxx github_ooo --clear
```

With organization visibility restriction:

```bash
GITHUB_PAT=ghp_xxx github_ooo 2025-12-25 🏖️ "Away" --org mycompany
```

## Requirements

- `curl` - HTTP client
- `jq` - JSON processor
- A GitHub Personal Access Token with `user` scope

## Exit Codes

- `0` - Status set successfully
- `1` - Missing token, invalid date, or API request failed
