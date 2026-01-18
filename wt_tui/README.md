# wt_tui

Interactive TUI for managing git worktrees.

## Overview

A visual dashboard for git worktrees, inspired by [conductor.build](https://conductor.build/). Provides an interactive interface to view, create, switch between, and clean up worktrees.

![wt_tui screenshot](screenshot.png)

## Usage

```bash
wt_tui
```

Launch the TUI and use arrow keys to navigate the menu.

## Features

### Dashboard

Shows all worktrees at a glance with:

- Branch name
- Path (relative)
- Status (clean / N changes)
- Sync state (↑ahead ↓behind)

### Actions

- **New worktree** - Create from default branch, current branch, or specific branch
- **Check out branch** - Create a worktree for any existing branch (local or remote)
- **Checkout PR** - Fetch a GitHub PR into a new worktree
- **Switch to worktree** - Open a worktree in a new shell
- **Open in editor** - Launch `$EDITOR` (or `code`) in worktree
- **Show diff** - View uncommitted changes
- **Remove worktree** - Delete worktree and its branch
- **Clean** - Batch remove merged/deleted worktrees

## Prerequisites

- Git 2.5+ with worktree support
- [gum](https://github.com/charmbracelet/gum) for TUI elements
- GitHub CLI (`gh`) for PR checkout feature (optional)

### Installing gum

```bash
# macOS
brew install gum

# Arch Linux
pacman -S gum

# Alpine
apk add gum

# Other
go install github.com/charmbracelet/gum@latest
```

## Examples

Launch the TUI:

```bash
wt_tui
```

## Comparison with wt

| Feature | wt | wt_tui |
|---------|-----|--------|
| Scripting-friendly | ✓ | |
| Interactive dashboard | | ✓ |
| Visual status overview | | ✓ |
| Bulk cleanup selection | | ✓ |
| No extra dependencies | ✓ | |

Use `wt` for scripts and quick CLI operations. Use `wt_tui` for interactive sessions.

## Exit Codes

- `0` - Success
- `1` - Error occurred
