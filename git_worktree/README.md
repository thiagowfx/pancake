# git_worktree

Manage git worktrees with ease.

## Overview

Git worktrees allow you to check out multiple branches simultaneously in different directories. This tool simplifies common worktree operations with a friendly interface.

## Usage

```bash
git_worktree [COMMAND] [OPTIONS]
```

### Commands

- `add <branch> [path]` - Create new worktree for branch
- `list` - List all worktrees
- `remove <path>` - Remove worktree at path
- `prune` - Remove stale worktree administrative files
- `goto <branch>` - Print path to worktree for branch (useful for cd)
- `help` - Show help message

### Options

- `-h, --help` - Show help message and exit

## Examples

Create worktree as sibling directory:
```bash
git_worktree add feature-unicorn
# Creates ../feature-unicorn
```

Create worktree at specific path:
```bash
git_worktree add feature-dragon ~/projects/myrepo-dragon
```

List all worktrees:
```bash
git_worktree list
```

Remove a worktree:
```bash
git_worktree remove ../feature-unicorn
```

Navigate to a worktree (use with cd):
```bash
cd "$(git_worktree goto feature-dragon)"
```

Clean up stale worktree data:
```bash
git_worktree prune
```

## Features

- Automatically creates worktrees as siblings to main repo when no path specified
- Handles new branches, existing local branches, and remote branches
- Simple navigation with `goto` command
- Clean interface wrapping git worktree commands

## Prerequisites

- Git 2.5 or newer with worktree support

## Exit Codes

- `0` - Success
- `1` - Error occurred

## Notes

When you create a worktree without specifying a path, it will be created as a sibling to your main repository. For example, if your main repo is at `/home/tacocat/myrepo`, running `git_worktree add feature-x` will create the worktree at `/home/tacocat/feature-x`.

The `goto` command is designed to work with shell command substitution for easy navigation between worktrees.
