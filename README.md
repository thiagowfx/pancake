# pancake

## CI status

`> grep -Erl '\b(push|schedule|workflow_dispatch):$' .github/workflows | xargs -n 1 basename | sort -d | sed -e 's|^release.yml$|- [![](https://github.com/thiagowfx/pancake/actions/workflows/release.yml/badge.svg)](https://github.com/thiagowfx/pancake/actions/workflows/release.yml)|' -e 's|^[^-].*|- [![](https://github.com/thiagowfx/pancake/actions/workflows/&/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/&)|'`

<!-- BEGIN mdsh -->
- [![](https://github.com/thiagowfx/pancake/actions/workflows/ls-lint.yml/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/ls-lint.yml)
- [![](https://github.com/thiagowfx/pancake/actions/workflows/prek-autoupdate.yml/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/prek-autoupdate.yml)
- [![](https://github.com/thiagowfx/pancake/actions/workflows/prek.yml/badge.svg?branch=master)](https://github.com/thiagowfx/pancake/actions/workflows/prek.yml)
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
- **[apknew](apknew/)** - Reconcile .apk-new configuration files on Alpine Linux
- **[aws_china_mfa](aws_china_mfa/)** - Authenticate to AWS China using MFA and export temporary session credentials
- **[cache_prune](cache_prune/)** - Free up disk space by pruning old and unused cache data from various tools
- **[chromium_profile](chromium_profile/)** - Manage and launch Chrome, Chromium, or Chromium derivative browser profiles
- **[copy](copy/)** - Add file contents to the clipboard
- **[friendly_ping](friendly_ping/)** - List all open GitHub pull requests created by you that are awaiting review
- **[git_world](git_world/)** - Tidy up a git repository by fetching, pruning remotes, and cleaning up stale branches and worktrees
- **[github_ooo](github_ooo/)** - Set your GitHub status to Out of Office until a specified date
- **[helm_template_diff](helm_template_diff/)** - Compare rendered Helm chart output between branches
- **[http_server](http_server/)** - Start a local HTTP server in the current directory
- **[img_optimize](img_optimize/)** - Optimize images for size while maintaining quality
- **[is_online](is_online/)** - Check if internet connectivity is available
- **[murder](murder/)** - Kill processes gracefully using escalating signals
- **[nato](nato/)** - Convert text to the NATO phonetic alphabet
- **[notify](notify/)** - Send desktop notifications across Linux and macOS platforms
- **[ocr](ocr/)** - Extract text from images using optical character recognition
- **[op_login_all](op_login_all/)** - Automatically log into all your 1Password accounts
- **[pdf_password_remove](pdf_password_remove/)** - Remove password protection from PDF files
- **[pr_dash](pr_dash/)** - TUI dashboard for your open GitHub pull requests
- **[pritunl_login](pritunl_login/)** - Connect to Pritunl VPN using credentials stored in 1Password
- **[radio](radio/)** - Stream internet radio stations using available media players
- **[randwords](randwords/)** - Generate random word combinations similar to Docker container names
- **[retry](retry/)** - Execute a command repeatedly until it succeeds or its output changes
- **[sd_world](sd_world/)** - Cross-platform full system upgrade script
- **[spawn](spawn/)** - Run a command in the background and exit cleanly
- **[ssh_mux_restart](ssh_mux_restart/)** - Restart SSH multiplexed connections to refresh authentication credentials
- **[timer](timer/)** - Count down for a specified duration and notify when complete
- **[try](try/)** - Interactive ephemeral workspace manager with fuzzy finding
- **[uwatch](uwatch/)** - Run a command repeatedly with watch, preserving colored output
- **[vimtmp](vimtmp/)** - Create a temporary scratch file and open it in your editor
- **[wt](wt/)** - Manage git worktrees with ease (includes interactive TUI)
<!-- keep-sorted end -->

## Patterns

These tools compose well together. A few ideas:

```bash
# Watch for new commits upstream, then notify
retry --until-changed -i 30 git pull && notify "Repo updated" "New commits pulled"

# Wait for a server to come up, then notify
retry -v -t 120 curl -sf http://localhost:8080/health && notify -s "Server ready"

# OCR an image and copy the text to clipboard
ocr screenshot.png | copy

# Wait for internet to come back, then notify
retry -i 5 is_online -q && notify "Back online" "Internet restored"

# Run a long build in the background, get notified when it finishes
spawn "make -j8 && notify -s 'Build done' || notify -s Basso 'Build failed'"

# Generate a random branch name for throwaway work
git checkout -b "exp/$(randwords)"

# Kill whatever is hogging a port, then start your own server
murder -f :8080 && http_server
```

## Contributing

1. Create a new directory for your script (e.g., `my_tool/my_tool.sh`)
2. Include `-h`/`--help` support with usage, examples, and exit codes
3. Add the script to both `Formula/pancake.rb` and `APKBUILD`
4. Update the Tools section in this README
5. Run `prek run --all-files` before committing
6. Keep dependencies minimal; prefer POSIX-ish tools
