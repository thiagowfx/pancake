# aws_china_mfa.sh

A script to authenticate to AWS China using MFA and export temporary session credentials.

## Usage

### Option 1: Source the script

```bash
source ./aws_china_mfa.sh
```

Or with a custom AWS profile:

```bash
source ./aws_china_mfa.sh my-china-profile
```

### Option 2: Execute with eval

```bash
eval "$(./aws_china_mfa.sh)"
```

Or with a custom AWS profile:

```bash
eval "$(./aws_china_mfa.sh my-china-profile)"
```

### Option 3: Execute and copy/paste export commands

```bash
./aws_china_mfa.sh
```

The script will print export commands that you can copy and paste into your shell.

## Example Output

### Option 1: Source the script

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

### Option 2: Execute with eval

```
% eval "$(./aws_china_mfa.sh)"
Note: Script is being executed. To apply credentials, run:
  eval "$(./aws_china_mfa.sh china)"

Using AWS profile: china
Enter the MFA token code for your AWS China account: 123456
Retrieving MFA device ARN...
Requesting session token...

✓ Successfully authenticated to AWS China

Copy and paste the export commands above to apply credentials.

  export AWS_PROFILE='china'
  export AWS_ACCESS_KEY_ID='AKIAWHEATLICIOUSPANCAK'
  export AWS_SECRET_ACCESS_KEY='wSyrupyDeliciousSecretKeyForBreakfastDelight42'
  export AWS_SESSION_TOKEN='FwoGZXIvYXdzEBaaDCakesYrUpSWeetToKenArEDelIcIoUs...'
```

### Option 3: Execute and copy/paste

```
% ./aws_china_mfa.sh
Note: Script is being executed. To apply credentials, run:
  eval "$(./aws_china_mfa.sh china)"

Using AWS profile: china
Enter the MFA token code for your AWS China account: 123456
Retrieving MFA device ARN...
Requesting session token...

✓ Successfully authenticated to AWS China

Copy and paste the export commands above to apply credentials.

  export AWS_PROFILE='china'
  export AWS_ACCESS_KEY_ID='AKIAWHEATLICIOUSPANCAK'
  export AWS_SECRET_ACCESS_KEY='wSyrupyDeliciousSecretKeyForBreakfastDelight42'
  export AWS_SESSION_TOKEN='FwoGZXIvYXdzEBaaDCakesYrUpSWeetToKenArEDelIcIoUs...'
```

The script prompts for your MFA token, retrieves temporary session credentials valid for 24 hours, and exports them to your current shell session.
