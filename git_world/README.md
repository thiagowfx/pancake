# git_world.sh

Tidy up a git repository by fetching, pruning remotes, and cleaning up stale local branches and worktrees.

## Usage

Run from any git repository:

```bash
git_world
```

## What it does

1. Fetches all remotes and prunes stale remote-tracking references
2. Prunes unreachable objects
3. Deletes local branches whose upstream has been deleted
4. Cleans up stale worktrees (via `wt world`, if worktrees exist)

## Example Output

```
% git_world
Fetching all remotes...
Fetching origin
Pruning unreachable objects...
Deleting local branches with gone upstreams...
  Deleted branch: thiagowfx/stale-feature-branch
  Deleted branch: thiagowfx/old-bugfix
Cleaning up stale worktrees...
Done.
```
