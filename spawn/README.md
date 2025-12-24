# spawn

Run a command in the background and exit cleanly.

## Overview

`spawn` is a simple utility that starts a command in the background with `nohup`, allowing your current shell to exit immediately without waiting. This is useful when you need to start long-running processes from scripts or interactive shells and want to detach them cleanly.

## Usage

```bash
spawn [--no-log] COMMAND [ARGS...]
spawn [--no-log] "SHELL COMMAND"
```

For shell commands with pipes, operators, or redirects, pass them as a single quoted string.

## Options

- `--no-log` - Send output to `/dev/null` instead of logging to a file
- `-h, --help` - Show help message

## Behavior

By default, `spawn` logs all output (stdout and stderr) to `~/.cache/spawn/<command>-<timestamp>.log`.

With `--no-log`, output is discarded (sent to `/dev/null`).

The script always exits with code 0 on success, making it safe to use in pipelines and conditional expressions.

When a single argument containing shell metacharacters (`|`, `&`, `;`, `<`, `>`, backticks) is passed, it's executed through `bash` to allow pipes, redirects, and other shell operators to work naturally. Otherwise, arguments are passed directly to the command.

## Examples

### Basic usage

Start a long-running process and return immediately:

```bash
spawn sleep 3600
```

Start a web server without keeping logs:

```bash
spawn --no-log python -m http.server 8000
```

Run a command with arguments:

```bash
spawn echo "Hello World"
```

### Shell operators and pipes

Use pipes, redirects, and conditionals by quoting the entire command:

```bash
# Pipe
spawn "echo hello | tr a-z A-Z"

# Logical operators
spawn "echo first && echo second"
spawn "test -f /etc/config || echo config not found"

# Command substitution
spawn "mkdir -p /tmp/$(date +%s)"

# Complex shell code
spawn "for i in 1 2 3; do echo Item \$i; done"
```

### Real-world examples

Use in a shell script to start a background service:

```bash
#!/bin/bash
set -e

spawn /opt/myservice/bin/start --config /etc/myservice.conf
echo "Service started in the background"
```

Start a background sync:

```bash
spawn rsync -av --delete /source/ /dest/
```

Run a command with conditional logic:

```bash
spawn "test -d /backup || mkdir -p /backup && rsync -a /source/ /backup/"
```

## Implementation Notes

- Uses `nohup` to ensure the command survives shell exit
- Redirects both stdout and stderr to the log file
- Returns exit code 0 on success to be safe for use in scripts
- Log files are timestamped for easy identification
- Log directory is created automatically if it doesn't exist

## See Also

- `nohup(1)` - Run a command immune to hangups, with output to a non-tty
- `disown` - bash builtin for removing jobs from the job table
