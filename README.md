# pancake

## CI status

`> grep -Erl '\b(push|schedule|workflow_dispatch):$' .github/workflows | xargs -n 1 basename | sort -d | sed -e 's|^release.yml$|- [![](https://github.com/thiagowfx/pancake/actions/workflows/release.yml/badge.svg)](https://github.com/thiagowfx/pancake/actions/workflows/release.yml)|' -e 's|^[^-].*|- [![](https://github.com/thiagowfx/pancake/actions/workflows/&/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/&)|'`

<!-- BEGIN mdsh -->
- [![](https://github.com/thiagowfx/pancake/actions/workflows/bats.yml/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/bats.yml)
- [![](https://github.com/thiagowfx/pancake/actions/workflows/pre-commit-autoupdate.yml/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/pre-commit-autoupdate.yml)
- [![](https://github.com/thiagowfx/pancake/actions/workflows/pre-commit.yml/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/pre-commit.yml)
- [![](https://github.com/thiagowfx/pancake/actions/workflows/release.yml/badge.svg)](https://github.com/thiagowfx/pancake/actions/workflows/release.yml)
<!-- END mdsh -->

A potpourri of sweet ingredients.

## Philosophy

Automation that works beats automation that's clever. These are one-off shell scripts that solve real problems without requiring a framework.

Each tool does one thing. Does it well. Works across platforms where it makes sense. Uses standard tools that are already installed. No surprises.

If something should take one command, it takes one command. If it should be boring, it's boring.

## Installation

Homebrew formula is available:

```bash
# Tap the repository (first time only)
brew tap thiagowfx/pancake

# Install stable release
brew install thiagowfx/pancake/pancake

# Or install development version from HEAD
brew install thiagowfx/pancake/pancake --HEAD
```

Releases follow calendar versioning ([calver](https://calver.org/) – `YYYY.MM.DD`).

## Tools

<!-- keep-sorted start -->
- **[aws_china_mfa](aws_china_mfa/)** - Authenticate to AWS China using MFA and export temporary session credentials
- **[aws_login_headless](aws_login_headless/)** - Fully automated AWS SSO login using headless browser automation
- **[cache_prune](cache_prune/)** - Free up disk space by pruning old and unused cache data from various tools
- **[chromium_profile](chromium_profile/)** - Manage and launch Chrome, Chromium, or Chromium derivative browser profiles
- **[copy](copy/)** - Add file contents to the clipboard
- **[helm_template_diff](helm_template_diff/)** - Compare rendered Helm chart output between branches
- **[httpserver](httpserver/)** - Start a local HTTP server in the current directory
- **[img_optimize](img_optimize/)** - Optimize images for size while maintaining quality
- **[murder](murder/)** - Kill processes gracefully using escalating signals
- **[nato](nato/)** - Convert text to the NATO phonetic alphabet
- **[notify](notify/)** - Send desktop notifications across Linux and macOS platforms
- **[op_login_all](op_login_all/)** - Automatically log into all your 1Password accounts
- **[pdf_password_remove](pdf_password_remove/)** - Remove password protection from PDF files
- **[pritunl_login](pritunl_login/)** - Connect to Pritunl VPN using credentials stored in 1Password
- **[radio](radio/)** - Stream internet radio stations using mpv
- **[sd_world](sd_world/)** - Cross-platform full system upgrade script
- **[ssh_mux_restart](ssh_mux_restart/)** - Restart SSH multiplexed connections to refresh authentication credentials
- **[vimtmp](vimtmp/)** - Create a temporary scratch file and open it in your editor
<!-- keep-sorted end -->
