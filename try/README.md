# try

Interactive ephemeral workspace manager.

Create and navigate to temporary project directories with fuzzy finding, automatic date-prefixing, and recency scoring. Automatically spawns a new shell in the selected workspace.

Inspired by [tobi/try](https://github.com/tobi/try).

## Features

- **Interactive selection**: Use fzf for fuzzy finding workspaces
- **Auto-select on single match**: When a search term returns exactly one match, automatically select it without opening fzf
- **Date-prefixed directories**: Automatically prefix with `YYYY-MM-DD` format
- **Recency scoring**: Most recently accessed workspaces appear first
- **Quick creation**: Create new workspaces on the fly
- **Customizable path**: Use `--path` option or `TRY_PATH` environment variable

## Usage

```bash
try                    # Open interactive selector
try react              # Open matching workspace (or create if no match)
try +myproject         # Create workspace named myproject
try +                  # Create workspace with random name
try -p ~/projects      # Use custom workspace path
try -l                 # List all workspaces
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

# Open matching workspace or create if no match
try feature

# Create a new workspace with specific name
try +my-project

# Create a new workspace with random name
try +

# Use custom base directory
try -p /tmp/experiments

# List all workspaces without interactive selection
try --list

# List workspaces in custom directory
try --list -p /tmp/experiments
```

## Behavior

When a search term is provided, the script checks for matches:

- **Single match**: Automatically enters that workspace without user interaction
- **Multiple matches**: Opens fzf with the search term pre-filled for further filtering
- **No matches**: Creates a new workspace with the search term as the name (equivalent to `try +search_term`)
- **No search term**: Opens fzf with all workspaces sorted by recency
