# pr_dash

TUI dashboard for your open GitHub pull requests.

## Description

`pr_dash` shows all your open GitHub PRs at a glance, grouped by repository, with CI status, review state, draft indicator, and age. When `gum` is installed, it launches an interactive TUI with fuzzy filtering and actions (open in browser, copy URL, view details). Falls back to a plain-text table otherwise.

## Usage

```bash
# Launch interactive TUI dashboard (requires gum)
pr_dash

# Print plain-text table
pr_dash --no-tui

# Include draft PRs (excluded by default)
pr_dash --include-draft

# Include approved PRs (excluded by default)
pr_dash --include-approved

# Output raw JSON for scripting
pr_dash --json

# Check if you have open PRs (for scripts)
pr_dash -q && echo "you have open PRs" || echo "inbox zero"

# Pipe JSON to jq for custom queries
pr_dash --json | jq '[.[] | select(.ci == "FAILURE")]'
```

## Options

- `-h, --help` - Show help message
- `--no-tui` - Force non-interactive output (also used when piping)
- `--include-draft` - Include draft PRs (excluded by default)
- `--include-approved` - Include approved PRs (excluded by default)
- `--json` - Output raw JSON
- `-q, --quiet` - Exit 0 if PRs exist, 1 if none (no output)

## Interactive TUI

When `gum` is available and output is a terminal, `pr_dash` launches an interactive view:

1. **Filter** - fuzzy search across all PRs
2. **Select** - pick a PR and choose an action:
   - Open in browser
   - Copy URL to clipboard
   - View details (via `gh pr view`)

Press Escape at any point to quit.

## Output columns

Each PR line shows:

```
  #42    Fix the flux capacitor wiring       pass  pending   3d  <- doc-brown
```

- `#number` - PR number
- `title` - truncated to 50 characters
- `[draft]` - shown for draft PRs (when `--include-draft` is used)
- CI status: `pass`, `fail`, `pend`, or `--`
- Review state: `approved`, `changes`, `pending`, or `--`
- Age since creation: `5m`, `3h`, `2d`, `1w`, `4mo`
- Pending reviewers (if any)

## Prerequisites

- `gh` (GitHub CLI) - must be installed and authenticated
- `jq` - for JSON processing
- `gum` - optional, for interactive TUI

## Exit Codes

- `0` - PRs found (or help shown)
- `1` - No PRs found, or error occurred
