# apknew

Reconcile `.apk-new` configuration files on Alpine Linux, similar to `pacdiff` on Arch Linux.

## Background

When Alpine Linux upgrades a package, if a configuration file has been modified by the user, the package manager preserves the user's version and saves the new configuration with a `.apk-new` suffix. This script helps you review and reconcile these files interactively.

## Usage

```bash
# Scan /etc (default) for .apk-new files
sudo apknew

# Scan a specific directory
sudo apknew /etc/nginx
```

## Example Output

```
% sudo apknew /etc
Searching for .apk-new files in /etc...
Found 2 file(s) to process.

==============================================
File: /etc/ssh/sshd_config.apk-new
Original: /etc/ssh/sshd_config
==============================================

[v]iew diff  [k]eep original  [r]eplace with new  [m]erge  [s]kip
Action: v
--- /etc/ssh/sshd_config        2024-06-15 10:30:00.000000000 +0000
+++ /etc/ssh/sshd_config.apk-new        2024-12-20 14:22:33.000000000 +0000
@@ -15,7 +15,7 @@
-PermitRootLogin yes
+PermitRootLogin prohibit-password

[v]iew diff  [k]eep original  [r]eplace with new  [m]erge  [s]kip
Action: k
Removing /etc/ssh/sshd_config.apk-new...
Done. Kept original file.

==============================================
Processed 2 file(s).
```

## Actions

| Key | Action | Description |
|-----|--------|-------------|
| `v` | View | Show unified diff between original and new file |
| `k` | Keep | Keep your current configuration, delete the `.apk-new` file |
| `r` | Replace | Replace your configuration with the new version |
| `m` | Merge | Open both files in a diff tool for manual merging |
| `s` | Skip | Skip this file, leave both versions in place |

## Environment Variables

- `DIFFTOOL`: Diff tool to use for merging (default: `vimdiff`). Examples: `meld`, `kdiff3`, `code --diff`.
