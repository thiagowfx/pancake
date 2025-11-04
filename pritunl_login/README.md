# pritunl_login.sh

A shell script for connecting to Pritunl VPN using credentials stored in 1Password.

## Usage

```bash
./pritunl_login.sh <account> <password_ref>
```

### Arguments

- `account`: 1Password account name/ID (e.g., 'stark-industries')
- `password_ref`: 1Password password reference (e.g., 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password')

### Example

```bash
./pritunl_login.sh stark-industries 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password'
```

### Example Output

```
% ./pritunl_login.sh stark-industries 'op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password'
Connecting to Pritunl VPN...
Account: stark-industries
Password reference: op://Employee/x9zm2kddpq4nvbwrfhgtsjloey/password

Getting Pritunl profile ID...
Using profile ID: a1b2c3d4e5f6g7h8
Retrieving credentials from 1Password...
Starting VPN connection...
✓ VPN connection started successfully

Current VPN status:
| ID               | NAME             | STATE  | AUTOSTART | ONLINE FOR     | SERVER ADDRESS | CLIENT ADDRESS |
|------------------|------------------|--------|-----------|----------------|----------------|----------------|
| a1b2c3d4e5f6g7h8 | Stark Industries | Active | Enabled   | 1 hour 52 mins | 203.0.113.42   | 10.0.0.15      |
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
2. Extracts the item ID from the password reference
3. Fetches the password and OTP from 1Password using the extracted item ID
4. Concatenates the password and OTP for authentication
5. Starts the VPN connection using the Pritunl client
6. Displays the current VPN status upon success