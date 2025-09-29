# sd-world.sh

A cross-platform script to perform full system upgrades across different operating systems and package managers.

## Usage

Simply run the script:

```bash
./sd-world.sh
```

## Supported Systems

### Linux
- **Alpine Linux**: `apk update && apk upgrade` (with `doas`)
- **Arch Linux**: `pacman -Syu` (with `sudo`)
- **Debian/Ubuntu**: `apt update && apt upgrade -y && apt autoremove -y` (with `sudo`)
- **Nix**: `nix-channel --update && nix-env -u`

### macOS
- **Homebrew**: `brew update && brew upgrade && brew cleanup`
- **Mac App Store**: `mas upgrade` (requires `mas` CLI tool)
- **System Updates**: `softwareupdate --install --all`

## Example Output

### Successful Upgrade (macOS)
```
% ./sd-world.sh
Starting system upgrade...

Detected macOS system

Upgrading Homebrew...
==> Updating Homebrew...
Already up-to-date.
==> Upgrading 2 outdated packages:
node@18, python@3.11
==> Upgrading node@18 18.17.0 -> 18.19.0
==> Upgrading python@3.11 3.11.6 -> 3.11.7
✓ Homebrew upgrade completed successfully

Upgrading Mac App Store...
✓ Mac App Store upgrade completed successfully

Upgrading System Updates...
Software Update Tool

Finding available software
No new software available.
✓ System Updates upgrade completed successfully

Upgrade Summary:
Successfully upgraded: 3/3 package managers
All package managers upgraded successfully!
```

### Successful Upgrade (Arch Linux)
```
% ./sd-world.sh
Starting system upgrade...

Detected Linux system

Upgrading Arch (pacman)...
:: Synchronizing package databases...
 core                   130.8 KiB  1074 KiB/s 00:00 [######################] 100%
 extra                 1851.6 KiB  1560 KiB/s 00:01 [######################] 100%
 community               6.9 MiB  2.84 MiB/s 00:02 [######################] 100%
:: Starting full system upgrade...
:: Replace lib32-mesa with extra/lib32-mesa? [Y/n]
:: Proceed with installation? [Y/n]
(15/15) checking keys in keyring                     [######################] 100%
(15/15) checking package integrity                   [######################] 100%
(15/15) loading package files                        [######################] 100%
(15/15) checking for file conflicts                  [######################] 100%
(15/15) checking available disk space                [######################] 100%
:: Processing package changes...
( 1/15) upgrading firefox                            [######################] 100%
( 2/15) upgrading linux                              [######################] 100%
✓ Arch (pacman) upgrade completed successfully

Upgrade Summary:
Successfully upgraded: 1/1 package managers
All package managers upgraded successfully!
```

### Interrupted Upgrade
```
% ./sd-world.sh
Starting system upgrade...

Detected macOS system

Upgrading Homebrew...
==> Updating Homebrew...
Already up-to-date.
✓ Homebrew upgrade completed successfully

Upgrading Mac App Store...
✓ Mac App Store upgrade completed successfully

Upgrading System Updates...
Software Update Tool

Finding available software
^C
⚠ Interrupted during System Updates upgrade
⚠ Script interrupted by user

Interrupt Summary:
Processed: 3 package managers
Successful: 2
Failed: 0
Interrupted/Skipped: 1
```

## Features

- **Cross-platform**: Automatically detects operating system and available package managers
- **Graceful handling**: Continues even if individual package managers fail
- **Clear feedback**: Shows progress and results for each upgrade operation
- **Summary reporting**: Provides final count of successful vs failed upgrades
- **Proper error handling**: Returns appropriate exit codes for automation use