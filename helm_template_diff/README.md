# helm_template_diff.sh

Compare rendered Helm chart output between the current branch and another branch.

## Usage

```bash
# Compare against auto-detected main/master branch
helm_template_diff.sh mychart/ --values prod-values.yaml

# Compare against specific branch
helm_template_diff.sh mychart/ --values prod-values.yaml --against origin/main

# Compare with multiple values files
helm_template_diff.sh charts/api/ -f values.yaml -f overrides.yaml --against feature/update

# Show help
helm_template_diff.sh --help
```

## Example Output

```console
$ helm_template_diff.sh ./mychart --values values.yaml --against origin/main
Auto-detected comparison branch: origin/main
Rendering chart on current branch...
Creating temporary worktree for origin/main...
Rendering chart on origin/main...

Diff (current branch vs origin/main):

diff --git a/tmp/other.yaml b/tmp/current.yaml
index 1234567..abcdefg 100644
--- a/tmp/other.yaml
+++ b/tmp/current.yaml
@@ -10,7 +10,7 @@ metadata:
   name: myapp
 spec:
   replicas: 3
-  image: myapp:v1.0.0
+  image: myapp:v1.1.0
   ports:
   - containerPort: 8080
```

## Prerequisites

- `bash` 3.x or later - Script uses bash-specific features. The `#!/bin/bash` shebang ensures it runs in bash even if your shell is zsh.
- `git` - For branch management and diff operations
- `helm` - For rendering Helm charts
- Must be run from within a git repository

## How It Works

1. Parses command-line arguments to extract the `--against` branch (or auto-detects origin/main or origin/master)
2. Validates that you're in a git repository and the target branch exists
3. Renders the Helm chart on your current branch (including all staged and unstaged changes)
4. Creates a temporary git worktree for the comparison branch
5. Renders the Helm chart in the worktree (clean state of the other branch)
6. Uses `git diff --no-index` to compare the two rendered outputs
7. Cleans up temporary files and worktree

**Automatic Fallback:** If `helm template` fails on either branch (e.g., due to file size limits, template errors, or missing dependencies), the script automatically falls back to comparing the raw chart source files using `git diff`. This ensures you can still see what changed even when rendering isn't possible.

The use of git worktree ensures your current working directory remains untouched during the comparison.

## Exit Codes

- `0` - Success (diff generated, which may be empty or show differences)
- `1` - Error (missing dependencies, git errors, or helm template failures)
