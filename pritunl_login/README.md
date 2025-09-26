# pritunl_login

A shell script for connecting to Pritunl VPN using credentials stored in 1Password.

## Usage

```bash
./pritunl_login.sh <account> <entry_name> <password_ref>
```

### Arguments

- `account`: 1Password account name/ID (e.g., 'stark-industries')
- `entry_name`: Name of the 1Password entry (e.g., 'Pritunl (VPN)')
- `password_ref`: 1Password password reference (e.g., 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password')

### Example

```bash
./pritunl_login.sh stark-industries 'Pritunl (VPN)' 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password'
```

## Prerequisites

- Pritunl client installed at `/Applications/Pritunl.app/Contents/Resources/pritunl-client`
- 1Password CLI (`op`) installed and configured
- `jq` installed for JSON parsing
- User logged into the specified 1Password account
- At least one Pritunl profile configured

## Exit Codes

- `0`: VPN connection successful
- `1`: Error occurred during connection process

## How It Works

1. Retrieves the first available Pritunl profile ID
2. Fetches the password and OTP from the specified 1Password entry
3. Concatenates the password and OTP for authentication
4. Starts the VPN connection using the Pritunl client
5. Displays the current VPN status upon success