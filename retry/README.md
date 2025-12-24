# retry.sh

Execute a command repeatedly until it succeeds or its output changes.

## Usage

Basic usage - retry until success:

```bash
./retry.sh COMMAND [ARGS...]
```

With options:

```bash
./retry.sh [OPTIONS] COMMAND [ARGS...]
```

## Options

- `-h, --help` - Show help message
- `-i, --interval SECONDS` - Wait time between retries (default: 0.5)
- `-m, --max-attempts COUNT` - Maximum number of attempts (default: unlimited)
- `-t, --timeout SECONDS` - Maximum total time to retry (default: unlimited)
- `-v, --verbose` - Show detailed output for each retry attempt
- `-c, --until-changed` - Retry until command output changes from initial run
- `-u, --until` - Alias for --until-changed
- `-d, --diff` - Alias for --until-changed

## Examples

Wait for a web server to become available:

```bash
./retry.sh curl -s http://localhost:8080/health
```

Retry with custom interval and maximum attempts:

```bash
./retry.sh -i 2 -m 10 ping -c 1 example.com
```

Wait for SSH connection with timeout and verbose output:

```bash
./retry.sh -t 30 -v ssh user@narnia.example.com echo connected
```

Wait for a file to exist with combined limits:

```bash
./retry.sh -i 1 -m 5 -t 10 test -f /tmp/unicorn-ready
```

Wait for a database to accept connections:

```bash
./retry.sh -i 3 -t 60 psql -h localhost -U postgres -c 'SELECT 1'
```

Use `--` to explicitly separate retry options from command options:

```bash
./retry.sh -v -- command-with-dashes --its-own-flag --another-option
```

Wait for git repository to have new changes:

```bash
./retry.sh -c -i 5 git pull
```

Wait for command output to change with timeout:

```bash
./retry.sh -c -t 60 -v kubectl get pods -n default
```

## Example Output

Default (silent) mode:

```
% ./retry.sh curl -s http://localhost:8080/health
{"status":"ok"}
```

Verbose mode:

```
% ./retry.sh -v -i 1 -m 3 curl -s http://localhost:8080/health
Attempt 1: curl -s http://localhost:8080/health
→ Failed, retrying in 1s...
Attempt 2: curl -s http://localhost:8080/health
→ Failed, retrying in 1s...
Attempt 3: curl -s http://localhost:8080/health
→ Success after 3 attempt(s)
{"status":"ok"}
```

## Exit Codes

- `0` - Command succeeded (or output changed when using --until-changed)
- `1` - Invalid arguments or limits exceeded
- `124` - Timeout reached (when --timeout is specified)
- `125` - Max attempts reached (when --max-attempts is specified)
- `126` - Initial command failed (when using --until-changed)

## Use Cases

- Wait for services to start (web servers, databases, APIs)
- Wait for network connectivity to be established
- Wait for files or resources to become available
- Handle transient failures in CI/CD pipelines
- Poll for completion of background tasks
- Monitor commands until their output changes (git pull, kubectl get, etc.)
