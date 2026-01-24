# Local GitHub Actions Testing with Act

This guide explains how to run GitHub Actions workflows locally using [act](https://github.com/nektos/act) for the dd-trace-rb repository.

## Prerequisites

- **act v0.2.84+** (has native cache server support)
- **Docker Desktop** (or compatible Docker runtime)
- macOS with Apple Silicon requires x86_64 emulation via Docker

## Directory Structure

```
.act/
├── build-images.sh       # Script to build local Docker images
└── Dockerfile.ruby-3.4   # Generated Dockerfile (created by build script)

scripts/
├── act-with-cache.sh     # Main helper to run act with caching enabled
└── act-test-cache.sh     # Test script to verify cache behavior
```

## Quick Start

### 1. Build Local Docker Images (Recommended)

Build a local image with Node.js pre-installed to avoid slow `apt-get install` on every run:

```bash
# Build for Ruby 3.4 (default)
./.act/build-images.sh 3.4

# Build for multiple versions
./.act/build-images.sh 3.3 3.4
```

This creates `act-ruby-3.4` (etc.) images based on `ghcr.io/datadog/images-rb/engines/ruby:3.4-gnu-gcc` with Node.js added.

### 2. Run Workflows with Cache Support

Use the helper script which enables act's built-in cache server:

```bash
# Run the test bundle cache workflow
./scripts/act-with-cache.sh workflow_dispatch \
  -W .github/workflows/_test-bundle-cache.yml \
  --container-architecture linux/amd64

# Run with a specific Ruby version
./scripts/act-with-cache.sh workflow_dispatch \
  -W .github/workflows/_test-bundle-cache.yml \
  --container-architecture linux/amd64 \
  --input ruby-version=3.3

# List available jobs in a workflow
./scripts/act-with-cache.sh --list -W .github/workflows/_unit_test.yml

# Run a specific job
./scripts/act-with-cache.sh -W .github/workflows/_unit_test.yml -j ruby-34
```

### 3. Test Cache Behavior

Run the dedicated cache test script twice to verify caching works:

```bash
# First run - should show "cache miss" and save cache
./scripts/act-test-cache.sh 3.4

# Second run - should show "cache hit" (no bundle install)
./scripts/act-test-cache.sh 3.4
```

## How Caching Works

Act v0.2.84+ has **built-in cache server support** with these options:

| Option | Default | Description |
|--------|---------|-------------|
| `--cache-server-addr` | `192.168.1.65` | Address to bind (use `host.docker.internal` for Docker Desktop on macOS) |
| `--cache-server-path` | `~/.cache/actcache` | Local directory to store cached artifacts |
| `--cache-server-port` | `0` (random) | Port for cache server |
| `--no-cache-server` | - | Disable caching |

The helper script `act-with-cache.sh` configures these automatically.

### Cache Storage

- **Location**: `~/.cache/actcache` (or `$ACT_CACHE_PATH` if set)
- **Key format**: `bundle-{os}-{arch}-{ruby-alias}-{lockfile-hash}`
- **Cache path**: `/usr/local/bundle` (where bundler installs gems)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ACT_CACHE_PATH` | `~/.cache/actcache` | Override cache storage location |
| `ACT_CACHE_PORT` | `0` | Override cache server port |
| `ACT_RUBY_VERSION` | `3.4` | Default Ruby version for local images |

## Common Commands

```bash
# Run workflow_dispatch trigger
./scripts/act-with-cache.sh workflow_dispatch -W .github/workflows/<workflow>.yml

# Run push trigger (simulates git push)
./scripts/act-with-cache.sh push -W .github/workflows/<workflow>.yml

# Run with verbose output
./scripts/act-with-cache.sh -v workflow_dispatch -W .github/workflows/<workflow>.yml

# Run specific job only
./scripts/act-with-cache.sh -j <job-name> -W .github/workflows/<workflow>.yml

# Clear local cache
rm -rf ~/.cache/actcache
```

## Troubleshooting

### Image Not Found
```
WARNING: Local image act-ruby-3.4 not found.
```
**Solution**: Run `./.act/build-images.sh 3.4` first.

### Cache Not Working
1. Verify cache directory exists: `ls -la ~/.cache/actcache`
2. Check that `--cache-server-addr "host.docker.internal"` is used (required for Docker Desktop on macOS)
3. Run the test script twice: `./scripts/act-test-cache.sh`

### Slow Performance on Apple Silicon
The workflows use `--container-architecture linux/amd64` which requires x86_64 emulation. This is expected to be slower than native ARM64.

### Node.js Required Error
The CI workflows require Node.js for `actions/checkout`. Either:
- Build local images with `./.act/build-images.sh` (recommended)
- Or let act install Node.js on each run (slower)

## Key Files Reference

| File | Purpose |
|------|---------|
| `.act/build-images.sh` | Builds local Docker images with Node.js |
| `scripts/act-with-cache.sh` | Main helper to run act with caching |
| `scripts/act-test-cache.sh` | Verifies cache save/restore works |
| `.github/workflows/_test-bundle-cache.yml` | Test workflow for cache validation |
| `.github/actions/bundle-restore/` | Composite action to restore bundle cache |
| `.github/actions/bundle-save/` | Composite action to save bundle cache |
