# pancake

[![Pre-commit](https://github.com/thiagowfx/pancake/workflows/Pre-commit/badge.svg)](https://github.com/thiagowfx/pancake/actions/workflows/pre-commit.yml)
[![Pre-commit auto-update](https://github.com/thiagowfx/pancake/workflows/Pre-commit%20auto-update/badge.svg)](https://github.com/thiagowfx/pancake/actions/workflows/pre-commit-autoupdate.yml)

A potpourri of sweet ingredients

## Philosophy

Automation that works beats automation that's clever. These are one-off shell scripts that solve real problems without requiring a framework.

Each tool does one thing. Does it well. Works across platforms where it makes sense. Uses standard tools that are already installed. No surprises.

If something should take one command, it takes one command. If it should be boring, it's boring.

## Tools

A Homebrew formula is available in the `Formula/` directory.

<!-- keep-sorted start -->
- **[aws_china_mfa](aws_china_mfa/)** - Authenticate to AWS China using MFA and export temporary session credentials
- **[img_optimize](img_optimize/)** - Optimize images for size while maintaining quality
- **[op_login_all](op_login_all/)** - Automatically log into all your 1Password accounts
- **[pritunl_login](pritunl_login/)** - Connect to Pritunl VPN using credentials stored in 1Password
- **[sd_world](sd_world/)** - Cross-platform full system upgrade script
<!-- keep-sorted end -->
