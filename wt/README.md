# wt

Manage git worktrees with ease.

## Overview

Git worktrees allow you to check out multiple branches simultaneously in different directories. This tool simplifies common worktree operations with a friendly interface.

## Usage

```bash
wt [COMMAND] [OPTIONS]
```

### Commands

- `add [branch] [path]` - Create new worktree (auto-generates branch if omitted). Aliases: `new`, `create`
- `list` - List all worktrees. Aliases: `ls`
- `remove [path]` - Remove worktree (current if no path given). Aliases: `rm`, `del`, `delete`
- `prune` - Remove stale worktree administrative files
- `world` - Delete worktrees with merged/deleted remote branches
- `goto [pattern]` - Print path to worktree (interactive with fzf if no pattern)
- `cd [pattern]` - Change to worktree directory in new shell
- `cd -` - Change to main worktree
- `help` - Show help message

### Options

- `-h, --help` - Show help message and exit

## Examples

Quick worktree with auto-generated branch (and cd to it):
```bash
wt add
# Auto-generates: thiago-perrotta/taco-unicorn
# Creates ../thiago-perrotta-taco-unicorn and changes to that directory
```

Create worktree with specific branch (and cd to it):
```bash
wt add feature-unicorn
# Creates ../feature-unicorn and changes to that directory
```

Create worktree without changing directory:
```bash
wt add --no-cd feature-unicorn
# Creates ../feature-unicorn but stays in current directory
```

Create worktree at specific path:
```bash
wt add feature-dragon ~/projects/myrepo-dragon
```

List all worktrees:
```bash
wt list
```

Remove current worktree and return to main:
```bash
wt remove
# Removes current worktree and changes to main checkout
```

Remove a specific worktree:
```bash
wt remove ../feature-unicorn
```

Navigate to a worktree interactively:
```bash
wt cd
# Opens fzf to select a worktree
```

Navigate to a specific worktree:
```bash
wt cd feature-dragon
```

Return to main worktree:
```bash
wt cd -
```

Navigate to a worktree (alternative using goto and cd):
```bash
cd "$(wt goto feature-dragon)"
```

Clean up stale worktree data:
```bash
wt prune
```

Clean up worktrees for merged branches:
```bash
wt world
# Fetches from remotes and removes worktrees whose upstream branches have been deleted
```

## Features

- Automatically changes directory to new worktree after creation (use --no-cd to skip)
- Auto-generates branch names when none provided (username/word1-word2)
- Automatically creates worktrees as siblings to main repo when no path specified
- Handles new branches, existing local branches, and remote branches
- Simple navigation with `cd` command (spawns new shell in worktree)
- Quick return to main worktree with `cd -`
- Flexible matching: exact, glob, or partial (with fzf for interactive selection)
- Alternative `goto` command for use with shell command substitution
- Clean interface wrapping git worktree commands

## Prerequisites

- Git 2.5 or newer with worktree support

## Exit Codes

- `0` - Success
- `1` - Error occurred

## Notes

When you create a worktree without specifying a path, it will be created as a sibling to your main repository. For example, if your main repo is at `/home/tacocat/myrepo`, running `wt add feature-x` will create the worktree at `/home/tacocat/feature-x`.

The `goto` command is designed to work with shell command substitution for easy navigation between worktrees.
