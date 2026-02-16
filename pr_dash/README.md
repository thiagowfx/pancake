# pr_dash

TUI dashboard for your open GitHub pull requests.

## Description

`pr_dash` shows all your open GitHub PRs at a glance, grouped by repository, with CI status and review state. When `gum` is installed, it launches an interactive TUI with emoji indicators, fuzzy filtering, and actions. Falls back to a colored plain-text table otherwise.

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

# Custom auto-refresh interval (default: 300s)
pr_dash --refresh 120

# Output raw JSON for scripting
pr_dash --json

# Check if you have open PRs (for scripts)
pr_dash -q && echo "you have open PRs" || echo "inbox zero"

# Pipe JSON to jq for custom queries
pr_dash --json | jq '[.[] | select(.ci == "FAILURE")]'

# Output Slack mrkdwn (for pasting into Slack)
pr_dash --slack
pr_dash --slack | pbcopy

# Only show PRs from a specific org
pr_dash -o helm

# Filter by date
pr_dash --created-before "7 days"
pr_dash --created-after 2025-01-01

# Filter by specific repos
pr_dash helm/helm tulip/terraform
```

## Options

- `-h, --help` - Show help message
- `--no-tui` - Force non-interactive output (also used when piping)
- `--include-draft` - Include draft PRs (excluded by default)
- `--include-approved` - Include approved PRs (excluded by default)
- `--json` - Output raw JSON
- `--slack` - Output as Slack mrkdwn (for pasting into Slack)
- `--refresh SECS` - Auto-refresh interval in seconds (default: 300, TUI only)
- `--stale-after DAYS` - Hide PRs older than DAYS behind a toggle (default: 28, TUI only)
- `-o, --org ORG` - Filter PRs to a specific organization
- `--created-before WHEN` - Only show PRs created before WHEN (YYYY-MM-DD or relative like "60 days")
- `--created-after WHEN` - Only show PRs created after WHEN (YYYY-MM-DD or relative like "60 days")
- `-q, --quiet` - Exit 0 if PRs exist, 1 if none (no output)
- `REPO ...` - Positional args to filter by specific repos (e.g. `helm/helm tulip/terraform`)

## Interactive TUI

When `gum` is available and output is a terminal, `pr_dash` launches an interactive view with a loading spinner on fetch:

1. **Filter** - fuzzy search across all PRs
2. **Select** - pick a PR and choose an action:
   - Open in browser
   - Copy URL to clipboard
   - View details (via `gh pr view`)
3. **Refresh** - select `>> Refresh <<` at the top of the list to re-fetch

Data auto-refreshes every 5 minutes (configurable with `--refresh`). Press Escape to quit.

### Status indicators

The header shows a legend for the emoji columns:

```
CI: 🟢pass 🔴fail 🟡pending  Review: ✅ok 🔴changes 👀pending  [refresh: 5m]
```

Each line is prefixed with two emoji:

```
🟢 ✅ tulip/gitops-china     #319   ci(prek): migrate from pre-commit to prek
🔴 👀 tulip/terraform        #700   DO NOT SUBMIT: feat(azure-global-identity)...
```

## Plain-text output (`--no-tui`)

PRs are grouped by repository with ANSI-colored status columns:

```
tulip/terraform
  #726   docs(adr): add ADR-0010 for garden-based infra                       pass   pending    1d <- TechOps

14 open PRs.
```

- `#number` - PR number
- `title` - up to 72 characters
- `[draft]` - shown for draft PRs (when `--include-draft` is used)
- CI status: `pass`, `fail`, `pend`, or `--`
- Review state: `approved`, `changes`, `pending`, or `--`
- Age since creation: `5m`, `3h`, `2d`, `1w`, `4mo`
- Pending reviewers (if any)

## Slack output (`--slack`)

Formats PRs as Slack mrkdwn with emoji indicators and linked titles, ready to paste:

```
*tulip/terraform*
• :large_green_circle: :eyes: <https://github.com/tulip/terraform/pull/726|#726 docs(adr): add ADR-0010 for garden-base migration plan> · 3h · jgdef-tulip, DomZach
• :red_circle: :eyes: <https://github.com/tulip/terraform/pull/700|#700 DO NOT SUBMIT: feat(azure-global-identity)> · 3d · TechOps, aranair

_2 open PR(s)._
```

## Prerequisites

- `gh` (GitHub CLI) - must be installed and authenticated
- `jq` - for JSON processing
- `gum` - optional, for interactive TUI

## Exit Codes

- `0` - PRs found (or help shown)
- `1` - No PRs found, or error occurred
