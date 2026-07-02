# Random Scripts 🛠️

A collection of utility scripts for Git automation, Homebrew setup, and SUSE/Harvester kernel extraction.

## Scripts

*   **[get-harvester-kernel.sh](./get-harvester-kernel.sh)**: Extracts the kernel version from a Harvester release squashfs image without deploying a node.
*   **[git-all](./git-all)**: Runs specified Git operations (`pull` or `gc`) on all Git repositories found recursively under a directory.
*   **[git-pull-all](./git-pull-all)**: Sequentially pulls updates across multiple repositories (fast-forward only).
*   **[git-gc-all](./git-gc-all)**: Performs garbage collection across multiple repositories.

## Usage: `get-harvester-kernel.sh`

Extracts the kernel version from a Harvester release squashfs image without needing to deploy an active node. Downloads the squashfs rootfs, extracts `/lib/modules`, and reads the directory name.

```bash
# Extract kernel version from Harvester v1.7.0 (defaults to amd64)
./get-harvester-kernel.sh v1.7.0

# Extract kernel version from Harvester v1.2.2 for arm64 architecture
./get-harvester-kernel.sh v1.2.2 arm64
```

## Usage: `git-all`

The `git-all` script runs specified Git operations on all Git repositories found recursively under a target directory.

```bash
# Pull operations
git-all pull                   # pull every repo in the directory & sub-directories
git-all pull ~/SUSE            # pull every repo, fast-forward only
git-all pull -n ~/SUSE         # dry-run
git-all pull -s ~/SUSE         # skip repos with uncommitted changes

# Garbage collection operations
git-all gc                     # gc every repo in the current directory and its subdir
git-all gc ~/SUSE              # gc every repo
git-all gc -a ~/SUSE           # aggressive gc
git-all gc -n ~/SUSE           # dry-run
```

## Prerequisites

Dependencies are defined in the **[Brewfile](./Brewfile)** (e.g., `squashfs` for kernel extraction). Install via Homebrew:

```bash
brew bundle
```
