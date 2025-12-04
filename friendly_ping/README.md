# friendly_ping

List all open GitHub pull requests created by you that are awaiting review.

## Description

`friendly_ping` queries GitHub's API to find all pull requests you created that are still open. It groups results by repository and displays them in an easy-to-scan format.

Perfect for:
- Checking on contributions waiting for maintainer review
- Getting a quick overview of pending work across multiple projects
- CI/CD pipelines that need to report on PR status

## Usage

```bash
# List all your open PRs (requires git user.name to be configured)
friendly_ping

# List PRs from a specific user
friendly_ping --user alice

# List PRs only from a specific organization
friendly_ping --org helm

# List PRs created 3 days ago or older
friendly_ping --since "3 days"

# List PRs created on or before a specific date
friendly_ping --since 2024-12-01

# List PRs with detailed info (reviewers and assignees)
friendly_ping --detailed

# Include PRs that are already approved (normally skipped)
friendly_ping --include-approved

# Group PRs by repository (default)
friendly_ping --group-by repo

# Group PRs by user (reviewer or assignee) to see all PRs for each person
friendly_ping --group-by user --detailed

# Group PRs by reviewer to see all PRs awaiting each reviewer
friendly_ping --group-by reviewer --detailed

# Group PRs by assignee to see all assigned work
friendly_ping --group-by assignee --detailed

# Combine filters
friendly_ping --org helm --since "1 week"

# Filter by specific repositories
friendly_ping thiagowfx/.dotfiles thiagowfx/pre-commit-hooks

# Filter by repos and other options
friendly_ping --since "3 days" thiagowfx/.dotfiles thiagowfx/pre-commit-hooks

# Output as JSON for further processing
friendly_ping --json

# Check if you have open PRs (for scripts)
if friendly_ping --quiet; then
    echo "You have open PRs waiting for review"
fi
```

## Options

- `-h, --help` - Show help message
- `-u, --user USER` - GitHub username (defaults to authenticated gh user or git user.name)
- `-q, --quiet` - Suppress output
- `-j, --json` - Output as JSON
- `-o, --org ORG` - Filter to show only PRs from a specific organization
- `-s, --since WHEN` - Filter to show only PRs created on or before WHEN (format: YYYY-MM-DD or relative like "60 days")
- `-d, --detailed` - Fetch detailed PR info including reviewers and assignees (slower, requires additional API calls)
- `-g, --group-by FIELD` - Group PRs by 'repo', 'user', 'reviewer', or 'assignee' (default: repo; requires `--detailed` for user/reviewer/assignee)
- `--include-approved` - Include approved PRs in results (skipped by default)
- `REPO ...` - Filter by specific repositories (e.g. `thiagowfx/.dotfiles thiagowfx/pre-commit-hooks`)

## Prerequisites

- `gh` (GitHub CLI) - preferred method, or `curl` as fallback
- `jq` - for JSON processing
- Git configured with `user.name` (unless using `--user` flag)

## Environment Variables

- `GITHUB_TOKEN` - GitHub personal access token for higher API rate limits (only used with curl fallback)

## Example Output

### Default (grouped by repository):

```
helm/helm
  fix(helm-lint): do not validate metadata.name for List resources
  https://github.com/helm/helm/pull/31169
  Reviewers: john, jane
  Assignees: maintainer

loeffel-io/ls-lint
  feat: introduce a json schema file for ls-lint
  https://github.com/loeffel-io/ls-lint/pull/256
```

### With `--group-by user --detailed`:

```
jane
  fix(helm-lint): do not validate metadata.name for List resources
  https://github.com/helm/helm/pull/31169 (helm/helm)
  Role: Reviewer + Assignee

  feat: introduce a json schema file for ls-lint
  https://github.com/loeffel-io/ls-lint/pull/256 (loeffel-io/ls-lint)
  Role: Reviewer

john
  fix(helm-lint): do not validate metadata.name for List resources
  https://github.com/helm/helm/pull/31169 (helm/helm)
  Role: Reviewer
```

This makes it easy to send a message to people about all their pending PRs, whether they're reviewing or assigned.
