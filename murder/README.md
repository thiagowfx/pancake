# murder

Kill processes gracefully using escalating signals.

## Usage

```bash
murder [OPTIONS] TARGET
```

## Arguments

- `TARGET` - Process identifier, can be:
  - PID (e.g., `1234`)
  - Name (e.g., `node`)
  - Port (e.g., `:8080` or `8080`)

## Options

- `-h, --help` - Show help message and exit
- `-f, --force` - Skip confirmation prompts

## Description

This script terminates processes using an escalating signal strategy:

1. **SIGTERM (15)** - graceful shutdown, 3s wait
2. **SIGINT (2)** - interrupt, 3s wait
3. **SIGHUP (1)** - hangup, 4s wait
4. **SIGKILL (9)** - force kill

When killing by name or port, the script shows matching processes and asks for confirmation before terminating each one (unless `-f` is used).

## Prerequisites

- Standard Unix utilities: `ps`, `kill`, `lsof` (for port-based killing)

## Examples

Kill a specific process by PID:
```bash
murder 1234
```

Kill all processes matching a name:
```bash
murder node
```

Kill the process listening on a specific port:
```bash
murder :8080
# or
murder 8080
```

Kill all Python processes without confirmation:
```bash
murder -f python
```

Show help:
```bash
murder --help
```

## Exit codes

- `0` - Successfully killed target process(es)
- `1` - Error occurred or no processes found

## Signal escalation

The script gives processes time to shut down gracefully:

- **SIGTERM** allows processes to clean up resources and exit normally
- **SIGINT** simulates Ctrl+C keyboard interrupt
- **SIGHUP** signals hangup, useful for daemons
- **SIGKILL** forcefully terminates if all else fails (cannot be caught or ignored)

## Safety features

- Prevents self-termination
- Shows process details before killing
- Interactive confirmation for batch operations (name/port)
- Validates inputs before attempting to kill
