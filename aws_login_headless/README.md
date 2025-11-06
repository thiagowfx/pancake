# aws_login_headless.sh

Fully automated AWS SSO login using headless browser automation. No manual browser interaction required.

## Prerequisites

1. AWS CLI v2:
   ```bash
   aws --version  # Should be 2.x
   ```

2. uv (Python package manager - handles Python and Playwright automatically):
   ```bash
   # macOS/Linux
   curl -LsSf https://astral.sh/uv/install.sh | sh

   # Or via Homebrew
   brew install uv

   # Verify installation
   uv --version
   ```

3. Optional - 1Password CLI for automatic password retrieval:
   ```bash
   op --version
   ```

## Usage

### Interactive Mode

Prompts for password (uses `default` profile):

```bash
./aws_login_headless.sh
```

Specify a different AWS profile:

```bash
./aws_login_headless.sh --profile production
```

### 1Password Integration

Retrieve password from 1Password using item name:

```bash
./aws_login_headless.sh --op-item TACO42BURRITO88SALSA99
```

Or using full secret reference:

```bash
./aws_login_headless.sh --op-item "op://Employee/AWS/password"
```

Use specific 1Password account:

```bash
./aws_login_headless.sh --op-item TACO42BURRITO88SALSA99 --op-account work
```

Combine with custom AWS profile:

```bash
./aws_login_headless.sh --profile staging --op-item "AWS" --op-account my.1password.com
```

### Additional Options

Pre-fill username (if required by your IdP):

```bash
./aws_login_headless.sh --username joe@example.com --op-item xyz123
```

Debug with visible browser:

```bash
./aws_login_headless.sh --no-headless
```

## Example Output

```
% ./aws_login_headless.sh --op-item NACHOS77CHIPS42QUESO88
Retrieving SSO password from 1Password...
Initiating AWS SSO login for profile: default
Verification URL: https://device.sso.us-east-1.amazonaws.com/?user_code=WXYZ-ABCD
Launching headless browser automation...
Navigating to: https://device.sso.us-east-1.amazonaws.com/?user_code=WXYZ-ABCD
Filling password
Submitting login form
Waiting for authentication to complete...
✓ Authentication successful!

✓ Successfully authenticated to AWS SSO

AWS profile 'default' is now logged in.
```

## How It Works

1. Script starts `aws sso login --no-browser` and captures the verification URL
2. Optionally retrieves SSO password from 1Password
3. Uses `uvx` to run Python script with Playwright (automatically manages dependencies)
4. Launches headless Chrome browser using Playwright
5. Automates form filling and submission
6. Waits for authentication confirmation
7. Exits when login completes

## Troubleshooting

### uv Not Found

```
Error: Missing required dependencies: uv
```

**Solution**: Install uv using the instructions in Prerequisites section

### Browser Installation Failed

If first-time browser installation fails:

```bash
uvx --from playwright playwright install chromium
```

### Browser State Issues

If authentication fails repeatedly, clear browser state:

```bash
rm -rf ~/.aws_login_browser_data
```

### Debugging Login Flow

Run with visible browser to see what's happening:

```bash
./aws_login_headless.sh --no-headless
```

### Already Logged In

If you're already authenticated:

```
✓ Already logged in to AWS SSO
```

Script exits early - no action needed.

## Security Notes

- Passwords are never stored or logged
- Browser session data stored in `~/.aws_login_browser_data` for persistent login sessions
- When using 1Password, credentials are retrieved securely via `op` CLI
- Headless browser runs in isolated user data directory
- Python dependencies managed by uv in isolated environments

## Notes

- Supports any AWS profile via `--profile` flag (defaults to `default`)
- Requires AWS CLI v2 configured with SSO
- Uses uv to automatically manage Python and Playwright dependencies
- Browser automation selectors work with standard AWS SSO login pages
- Optimized for Okta SSO with fast polling and short timeouts
- Custom IdP login pages may require selector adjustments in `aws_login_headless_playwright.py`
- First run automatically installs Chromium browser (one-time setup)
