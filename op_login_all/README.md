# op_login_all.sh

A script to automatically log into all your 1Password accounts.

## Usage

Simply run the script:

```bash
./op_login_all.sh
```

## Example Output

```
% ./op_login_all.sh
Logging into all 1Password accounts...
Attempting to sign in to account: BANANA42SPLIT88SUNDAE99CHERRY
✓ Successfully signed in to: BANANA42SPLIT88SUNDAE99CHERRY

Attempting to sign in to account: PIZZA69SLICE77CHEESE33PEPPERONI
✓ Successfully signed in to: PIZZA69SLICE77CHEESE33PEPPERONI

Login Summary:
Successfully logged in: 2/2 accounts
All accounts logged in successfully!
```

The script will attempt to authenticate with each 1Password account and provide a summary of successful logins.