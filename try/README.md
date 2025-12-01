# try

Interactive ephemeral workspace manager.

Create and navigate to temporary project directories with fuzzy finding, automatic date-prefixing, and recency scoring. Automatically spawns a new shell in the selected workspace.

Inspired by [tobi/try](https://github.com/tobi/try).

## Features

- **Interactive selection**: Use fzf for fuzzy finding workspaces
- **Date-prefixed directories**: Automatically prefix with `YYYY-MM-DD` format
- **Recency scoring**: Most recently accessed workspaces appear first
- **Quick creation**: Create new workspaces on the fly
- **Customizable path**: Use `--path` option or `TRY_PATH` environment variable

## Usage

```bash
try                    # Open interactive selector
try react              # Filter workspaces matching "react"
try +myproject         # Create workspace named myproject
try +                  # Create workspace with random name
try -p ~/projects      # Use custom workspace path
```

## Prerequisites

- `fzf` - Fuzzy finder for interactive selection

## Configuration

Default path is `~/workspace/tries`. Set a custom path:

```bash
export TRY_PATH="$HOME/my-workspaces"
```

## Examples

```bash
# Select from existing workspaces
try

# Quick filter for "feature"
try feature

# Create a new workspace with specific name
try +my-project

# Create a new workspace with random name
try +

# Use custom base directory
try -p /tmp/experiments
```
