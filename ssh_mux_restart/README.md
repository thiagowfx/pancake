# ssh_mux_restart.sh

Restart SSH multiplexed connections to refresh authentication credentials.

## Usage

Basic usage to kill SSH multiplexed connections:

```bash
./ssh_mux_restart.sh
```

To also restart the 1Password SSH agent:

```bash
./ssh_mux_restart.sh --restart-1password
# or use the short alias
./ssh_mux_restart.sh --restart-1p
```

## Example Output

```
% ./ssh_mux_restart.sh
Finding SSH multiplexed connections...
Found SSH multiplexed connections:
  88002 ssh: /tmp/ssh-control-FLAPJACK42 [mux]
  88123 ssh: /tmp/ssh-control-WAFFLE55 [mux]
Killing SSH multiplexed connections...
✓ Killed SSH mux process: 88002
✓ Killed SSH mux process: 88123
Killed 2/2 SSH multiplexed connections.

All operations completed successfully!
```

With the `--restart-1password` flag:

```
% ./ssh_mux_restart.sh --restart-1password
Finding SSH multiplexed connections...
Found SSH multiplexed connections:
  88002 ssh: /tmp/ssh-control-PANCAKE99 [mux]
Killing SSH multiplexed connections...
✓ Killed SSH mux process: 88002
Killed 1/1 SSH multiplexed connections.

Restarting 1Password application...
Found 1Password process: 67690
Quitting 1Password...
✓ 1Password quit successfully
Starting 1Password...
✓ 1Password started successfully
1Password SSH agent is now ready for use.

All operations completed successfully!
```

## Why This Matters

SSH multiplexed connections can cache stale authentication credentials, causing issues when:

- GitHub organizations enable or enforce SAML SSO
- 1Password SSH agent credentials need refreshing
- SSH keys have been rotated or updated

Restarting these connections forces SSH to re-authenticate with fresh credentials.

## Prerequisites

- Standard Unix tools (`pgrep`, `pkill`)
- 1Password app (macOS) if using the `--restart-1password` flag

## Exit Codes

- `0`: All operations completed successfully
- `1`: Failed to find or kill processes, or dependencies missing
- `2`: Partial success (some operations failed)

## References

- [GitHub: The organization has enabled or enforced SAML SSO](https://perrotta.dev/2025/10/github-the-organization-has-enabled-or-enforced-saml-sso/)
- [1Password SSH Agent Error](https://perrotta.dev/2025/05/1password-ssh-agent-error/)
