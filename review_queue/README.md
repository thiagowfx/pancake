# review_queue

List open GitHub pull requests where your review is requested.

## Description

`review_queue` is the complement of `friendly_ping` and `pr_dash`. Instead of "who's blocking me?", it answers "who am I blocking?" — showing PRs from others that are waiting on your review.

## Usage

```bash
# List PRs awaiting your review
review_queue

# Output raw JSON for scripting
review_queue --json

# Output Slack mrkdwn for pasting
review_queue --slack
review_queue --slack | pbcopy

# Include draft PRs (excluded by default)
review_queue --include-draft

# Filter by organization
review_queue -o helm

# Filter by date
review_queue --created-before "7 days"
review_queue --created-after 2025-01-01

# Filter by specific repos
review_queue helm/helm tulip/terraform

# Check if you have pending reviews (for scripts)
review_queue -q && echo "reviews pending" || echo "inbox zero"
```

## Options

- `-h, --help` - Show help message
- `--json` - Output raw JSON
- `--slack` - Output as Slack mrkdwn (for pasting into Slack)
- `--include-draft` - Include draft PRs (excluded by default)
- `-o, --org ORG` - Filter PRs to a specific organization
- `--created-before WHEN` - Only show PRs created before WHEN (YYYY-MM-DD or relative like "60 days")
- `--created-after WHEN` - Only show PRs created after WHEN (YYYY-MM-DD or relative like "60 days")
- `-q, --quiet` - Exit 0 if PRs exist, 1 if none (no output)
- `REPO ...` - Positional args to filter by specific repos (e.g. `helm/helm tulip/terraform`)

## Example Output

### Plain text

```
tulip/terraform
  #726   docs(adr): add ADR-0010 for garden-based infra                        pass    3h  <- alice
  #700   feat(azure-global-identity): add managed identity support             fail    5d  <- bob

helm/helm
  #31200 fix(install): handle empty values files gracefully                     pend    1d  <- charlie

3 review(s) pending.
```

### Slack (`--slack`)

```
*tulip/terraform*
• :large_green_circle: <https://github.com/tulip/terraform/pull/726|#726 docs(adr): add ADR-0010> · 3h · by alice
• :red_circle: <https://github.com/tulip/terraform/pull/700|#700 feat(azure-global-identity)> · 5d · by bob

_2 review(s) pending._
```

## Prerequisites

- `gh` (GitHub CLI) - must be installed and authenticated
- `jq` - for JSON processing

## Exit Codes

- `0` - PRs found (or help shown)
- `1` - No PRs found, or error occurred
