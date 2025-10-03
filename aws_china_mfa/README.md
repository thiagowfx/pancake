# aws_china_mfa.sh

A script to authenticate to AWS China using MFA and export temporary session credentials in the current shell.

## Usage

Source the script (do not execute it directly):

```bash
source ./aws_china_mfa.sh
```

Or with a custom AWS profile:

```bash
source ./aws_china_mfa.sh my-china-profile
```

## Example Output

```
% source ./aws_china_mfa.sh
Using AWS profile: china
Enter the MFA token code for your AWS China account: 123456
Retrieving MFA device ARN...
Requesting session token...

✓ Successfully authenticated to AWS China

Exported AWS credentials:
AWS_ACCESS_KEY_ID=AKIAWHEATLICIOUSPANCAK
AWS_PROFILE=china
AWS_SECRET_ACCESS_KEY=wSyrupyDeliciousSecretKeyForBreakfastDelight42
AWS_SESSION_TOKEN=FwoGZXIvYXdzEBaaDCakesYrUpSWeetToKenArEDelIcIoUs...
```

The script will prompt for your MFA token, retrieve temporary session credentials valid for 24 hours, and export them to your current shell session.
