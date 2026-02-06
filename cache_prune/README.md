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

Clean only specific cache(s):

```bash
# Preview cleaning pip cache only
./cache_prune.sh pip

# Execute cleanup of npm cache only, no prompts
./cache_prune.sh -x -y npm

# Clean multiple specific caches
./cache_prune.sh -x docker npm pip

# Dry-run for go cache with verbose output
./cache_prune.sh -v go
```

## Example Output

Default dry-run mode:

```
% ./cache_prune.sh
cache_prune - Free up disk space by removing old and unused caches

✓ Docker cache found (~2.3GB reclaimable)
✓ pre-commit cache found (~456MB)
✓ prek cache found (~1.8GB)
✓ Homebrew cache found (~1.2GB)
✓ Helm cache found (~128MB)
✓ Terraform cache found (~4.5GB)
✓ npm cache found (~8.7GB)
✓ pip cache found (~1.7GB)
✓ Go cache found (~7.4GB)
✓ Yarn cache found (~1.2GB)
✓ Bundler/Ruby cache found (~34MB)
✓ Git repositories found (can run garbage collection)

DRY RUN: Showing what would be deleted without actually deleting

docker:
  Command: docker system prune -af --volumes
  Estimated space: ~2.3GB

Clean docker cache? [y/N] y
Pruning Docker cache...
  Would prune unused Docker data (dangling images, stopped containers, unused volumes/networks)

npm:
  Command: npm cache clean --force
  Estimated space: ~8.7GB

Clean npm cache? [y/N] y
Pruning npm cache...
  Would run: npm cache clean --force

go:
  Command: go clean -cache -modcache
  Estimated space: ~7.4GB

Clean go cache? [y/N] n
Skipping go cache.

Dry run completed. No changes were made.
```

Execute mode (`--execute` or `-x`):

```
% ./cache_prune.sh --execute
cache_prune - Free up disk space by removing old and unused caches

✓ Docker cache found (~2.3GB reclaimable)
✓ pre-commit cache found (~456MB)
✓ prek cache found (~1.8GB)
✓ Homebrew cache found (~1.2GB)
✓ Helm cache found (~128MB)
✓ Terraform cache found (~4.5GB)
✓ npm cache found (~8.7GB)
✓ pip cache found (~1.7GB)

docker:
  Command: docker system prune -af --volumes
  Estimated space: ~2.3GB

Clean docker cache? [y/N] y
Pruning Docker cache...
  Docker cache pruned

npm:
  Command: npm cache clean --force
  Estimated space: ~8.7GB

Clean npm cache? [y/N] y
Pruning npm cache...
  npm cache cleaned

pip:
  Command: pip cache purge
  Estimated space: ~1.7GB

Clean pip cache? [y/N] n
Skipping pip cache.

Cache cleanup completed successfully. Cleaned 2 cache(s).
```

Cleaning specific cache only:

```
% ./cache_prune.sh pip
cache_prune - Free up disk space by removing old and unused caches

✓ pip cache found (~1.7GB)

DRY RUN: Showing what would be deleted without actually deleting

pip:
  Command: pip cache purge
  Estimated space: ~1.7GB

Clean pip cache? [y/N] y
Pruning pip cache...
  Would run: pip cache purge

Dry run completed. No changes were made.
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

### prek
- Unused cached repositories
- Unused hook environments
- Other stale data

### Homebrew
- Old formula versions
- Downloaded tarballs and bottles
- Cached downloads

### Helm
- Cached chart repositories (`~/.cache/helm`)
- Repository index files (`~/.config/helm/repository`)
- Downloaded chart archives

### Terraform
- Cached provider plugins (`~/.terraform.d/plugin-cache`)
- Downloaded provider binaries from registry.terraform.io

### npm
- Package cache (`~/.npm`)
- Verified cache integrity before cleaning

### pip
- Python package cache
- Downloaded wheels and source distributions

### Go
- Build cache (compiled packages)
- Module cache (downloaded dependencies)

### Yarn
- Package cache
- Downloaded tarballs

### Bundler/Ruby
- Gem cache (old gem versions)
- Bundle cache directory

### Git
- Garbage collection on repositories in common directories
- Compresses repository databases
- Removes unreachable objects

### Nix
- Unreachable store paths
- Old generations of user profiles
- Unused packages and dependencies

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
- **prek**: Pre-commit reimplementation in Rust ([prek.j178.dev](https://prek.j178.dev/))
- **Homebrew**: macOS/Linux package manager
- **Helm**: Kubernetes package manager
- **Terraform**: Infrastructure as code tool
- **npm**: Node.js package manager
- **pip**: Python package installer (`pip` or `pip3`)
- **Go**: Go programming language toolchain
- **Yarn**: JavaScript package manager
- **Bundler**: Ruby dependency manager
- **Git**: Version control system
- **Nix**: Functional package manager

At least one of these tools must be installed for the script to be useful.
