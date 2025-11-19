# chromium_profile.sh

A script to manage and launch Chrome, Chromium, or Chromium derivative browser profiles.

## Usage

List all available profiles:

```bash
./chromium_profile.sh
# or
./chromium_profile.sh list
```

Open a specific profile by directory name:

```bash
./chromium_profile.sh open "Profile 1"
```

Or by display name:

```bash
./chromium_profile.sh open spongebob
```

Open with a specific URL:

```bash
./chromium_profile.sh open spongebob https://example.com
```

Open with multiple URLs:

```bash
./chromium_profile.sh open spongebob https://example.com https://example.org
```

Use a specific browser:

```bash
./chromium_profile.sh --browser chrome list
./chromium_profile.sh --browser chromium open Default
```

## Supported Browsers

The script supports Chrome, Chromium, and Chromium derivatives. It auto-detects the first available browser unless you specify one with `--browser`.

## Example Output

Listing profiles:

```
% ./chromium_profile.sh list
Available profiles in /Users/spongebob/Library/Application Support/Google/Chrome:

  Default              SpongeBob SquarePants
  Profile 1            Patrick Star
  Profile 2            Squidward Tentacles
```

Opening a profile by display name:

```
% ./chromium_profile.sh open spongebob
Opening browser with profile: Default
```

Opening with a URL:

```
% ./chromium_profile.sh open spongebob https://example.com
Opening browser with profile: Default
URLs: https://example.com
```

## Notes

- Profiles can be opened using either directory names ("Default", "Profile 1") or display names ("SpongeBob SquarePants", "Patrick Star")
- Directory names are internal identifiers, while display names are the friendly names you set in the browser
- The browser opens in the background and the script exits immediately
- Cross-platform: works on macOS and Linux
