# cache_prune.sh

Free up disk space by pruning old and unused cache data from various tools.

**By default, runs in dry-run mode** (shows what would be cleaned without actually cleaning). Use `--execute` to perform actual cleanup.

## Usage

Preview what would be cleaned (default dry-run mode):

```bash
./cache_prune.sh
```

Actually perform cleanup (prompts for confirmation for each cache):

```bash
./cache_prune.sh --execute
```

Execute cleanup without prompts:

```bash
./cache_prune.sh -x -y
```

Verbose output with detailed information:

```bash
./cache_prune.sh -v
```

Execute with verbose output:

```bash
./cache_prune.sh -x -v
```

## Example Output

Default dry-run mode:

```
% ./cache_prune.sh
cache_prune - Free up disk space by removing old and unused caches

✓ Docker cache found (~2.3GB reclaimable)
✓ pre-commit cache found (~456MB)
✓ Homebrew cache found (~1.2GB)
✓ Terraform cache found (~4.5GB)

DRY RUN: Showing what would be deleted without actually deleting

docker:
  Command: docker system prune -af --volumes
  Estimated space: ~2.3GB

Clean docker cache? [y/N] y
Pruning Docker cache...
  Would prune unused Docker data (dangling images, stopped containers, unused volumes/networks)

pre-commit:
  Command: pre-commit gc + remove old environments (30+ days)
  Estimated space: ~456MB

Clean pre-commit cache? [y/N] y
Pruning pre-commit cache...
  Would clean pre-commit cache:
    12 old environments (30+ days)

homebrew:
  Command: brew cleanup --prune=all
  Estimated space: ~1.2GB

Clean homebrew cache? [y/N] n
Skipping homebrew cache.

Dry run completed. No changes were made.
```

Execute mode (`--execute` or `-x`):

```
% ./cache_prune.sh --execute
cache_prune - Free up disk space by removing old and unused caches

✓ Docker cache found (~2.3GB reclaimable)
✓ pre-commit cache found (~456MB)
✓ Homebrew cache found (~1.2GB)
✓ Terraform cache found (~4.5GB)

docker:
  Command: docker system prune -af --volumes
  Estimated space: ~2.3GB

Clean docker cache? [y/N] y
Pruning Docker cache...
  Docker cache pruned

pre-commit:
  Command: pre-commit gc + remove old environments (30+ days)
  Estimated space: ~456MB

Clean pre-commit cache? [y/N] y
Pruning pre-commit cache...
  pre-commit cache cleaned

homebrew:
  Command: brew cleanup --prune=all
  Estimated space: ~1.2GB

Clean homebrew cache? [y/N] n
Skipping homebrew cache.

Cache cleanup completed successfully. Cleaned 2 cache(s).
```

## What It Cleans

The script safely removes old and unused cache data from:

### Docker
- Dangling images (not tagged and not referenced by any container)
- Unused containers
- Unused volumes
- Unused networks
- Build cache

### pre-commit
- Old hook environments not used recently (30+ days)
- Temporary files

### Homebrew
- Old formula versions
- Downloaded tarballs and bottles
- Cached downloads

### Terraform
- Cached provider plugins (`~/.terraform.d/plugin-cache`)
- Downloaded provider binaries from registry.terraform.io

## Features

- **Safe by default**: Dry-run mode by default (must use `--execute` to actually clean)
- **Individual confirmation**: Prompts separately for each cache system (skip with `-y`)
- **Selective cleaning**: Choose which caches to clean, skip others
- **Smart detection**: Only removes old/unused data, preserves active caches
- **Cross-platform**: Works on macOS and Linux
- **Graceful degradation**: Skips tools that aren't installed
- **Space reporting**: Shows estimated space for each cache system
- **Extensible**: Easy to add support for more cache systems

## Prerequisites

The script will automatically check for and use whichever tools you have installed:

- **Docker**: `docker` command-line tool
- **pre-commit**: Python package (`pip install pre-commit`)
- **Homebrew**: macOS/Linux package manager
- **Terraform**: Infrastructure as code tool

At least one of these tools must be installed for the script to be useful.
