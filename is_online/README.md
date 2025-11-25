# is_online.sh

Check if internet connectivity is available by making HTTP requests to reliable endpoints.

## Usage

Check connectivity with default settings:

```bash
./is_online.sh
```

Use in scripts with quiet mode:

```bash
if ./is_online.sh --quiet; then
    echo "We're online!"
else
    echo "We're offline!"
fi
```

Use custom timeout:

```bash
./is_online.sh --timeout 10
```

## Example Output

```
% ./is_online.sh
✓ Online

% ./is_online.sh
✗ Offline
```

## How It Works

This tool checks internet connectivity by making HTTP requests to generate_204 endpoints. These are services that return HTTP 204 No Content status codes and are specifically designed for connectivity checks. This approach exercises the full network stack (DNS, TCP, and HTTP) rather than just ICMP, providing a more accurate representation of real internet access.

The script tries multiple endpoints in sequence:
1. Google's generate_204 (primary)
2. Google Static Content connectivity check (fallback)
3. Cloudflare CDN trace (fallback)

## Options

- `-h, --help` - Show help message
- `-q, --quiet` - Suppress output (useful for scripts)
- `-t, --timeout N` - Set connection timeout in seconds (default: 5)

## Exit Codes

- `0` - Internet is available
- `1` - Internet is not available or error occurred
