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
- `goto [pattern]` - Print path to worktree (interactive with fzf if no pattern)
- `cd [pattern]` - Change to worktree directory in new shell
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

Change to a worktree (spawns new shell):
```bash
wt cd feature-dragon
```

Interactive worktree selection with fzf:
```bash
wt cd
```

Navigate to a worktree in current shell:
```bash
cd "$(wt goto feature-dragon)"
```

Clean up stale worktree data:
```bash
wt prune
```

## Features

- Automatically changes directory to new worktree after creation (use --no-cd to skip)
- Auto-generates branch names when none provided (username/word1-word2)
- Automatically creates worktrees as siblings to main repo when no path specified
- Handles new branches, existing local branches, and remote branches
- Simple navigation with `cd` command (spawns new shell) or `goto` command (for command substitution)
- Flexible pattern matching: exact, glob, and partial matches with fzf integration
- Clean interface wrapping git worktree commands

## Prerequisites

- Git 2.5 or newer with worktree support

## Exit Codes

- `0` - Success
- `1` - Error occurred

## Notes

When you create a worktree without specifying a path, it will be created as a sibling to your main repository. For example, if your main repo is at `/home/tacocat/myrepo`, running `wt add feature-x` will create the worktree at `/home/tacocat/feature-x`.

The `goto` command outputs the path for use with command substitution, while the `cd` command spawns a new shell in the worktree directory. Both commands support flexible pattern matching (exact, glob, and partial matches) with fzf integration for interactive selection when multiple matches exist.
