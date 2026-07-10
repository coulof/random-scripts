# Random Scripts 🛠️

A collection of utility scripts for Git automation, Homebrew setup, and SUSE/Harvester kernel extraction.

## Scripts

*   **[get-harvester-kernel.sh](./get-harvester-kernel.sh)**: Extracts the kernel version from a Harvester release squashfs image without deploying a node.
*   **[git-all](./git-all)**: Runs specified Git operations (`pull` or `gc`) on all Git repositories found recursively under a directory.
*   **[git-pull-all](./git-pull-all)**: Sequentially pulls updates across multiple repositories (fast-forward only).
*   **[git-gc-all](./git-gc-all)**: Performs garbage collection across multiple repositories.
*   **[md2pdf](./md2pdf)**: Converts Markdown documents to beautifully styled PDFs with KaTeX math, Mermaid diagrams, and custom themes.

## Usage: `get-harvester-kernel.sh`

Extracts the kernel version or the list of installed RPM packages from a Harvester release squashfs image without needing to deploy an active node. Downloads the squashfs rootfs, extracts `/lib/modules` (for kernel version) or `/usr/lib/sysimage/rpm` (for package list), and reads the information.

```bash
Usage: ./get-harvester-kernel.sh [options] <version[,version...]>

Options:
  -a, --arch <arch>      Architecture: amd64 (default) | arm64
  -k, --keep             Keep the downloaded and extracted squashfs files
  -q, --quiet            Quiet mode: suppress progress messages and logs
  -p, --packages         List all installed RPM packages instead of kernel version
  -h, --help             Show this help message
```

### Examples

```bash
# Extract kernel version from Harvester v1.7.0 (defaults to amd64)
./get-harvester-kernel.sh v1.7.0

# Extract kernel version from Harvester v1.2.2 for arm64 architecture
./get-harvester-kernel.sh v1.2.2 arm64

# Suppress log and progress output to retrieve only the raw kernel version
./get-harvester-kernel.sh -q v1.3.1

# Query multiple versions and print their kernel versions
./get-harvester-kernel.sh -q v1.3.1,v1.3.0

# Extract from multiple versions and keep the downloaded assets
./get-harvester-kernel.sh -k v1.7.0,v1.8.0

# List all packages installed in Harvester v1.3.1 (using local rpm or Docker)
./get-harvester-kernel.sh -p v1.3.1
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

## Usage: `md2pdf`

The `md2pdf` script converts Markdown documents to beautifully styled PDFs using a headless browser. It features native support for KaTeX math equations, Mermaid diagrams, and modern CSS themes without requiring LaTeX or root privileges.

### Installation

```bash
chmod +x md2pdf && mv md2pdf ~/.local/bin/md2pdf
```

On its first run, `md2pdf` automatically installs its Node.js dependencies (including a headless Chromium browser via Puppeteer, ~150 MB total) into a isolated directory at `~/.md2pdf/`.

### Options

```text
md2pdf — Markdown to PDF (KaTeX math + Mermaid diagrams, no LaTeX)

Usage:
  md2pdf input.md                     → input.pdf (same directory)
  md2pdf input.md output.pdf          → explicit output path
  md2pdf input.md --theme suse        → SUSE brand theme
  md2pdf input.md --css custom.css    → extra CSS on top of theme
  md2pdf input.md --margins 20mm      → all margins (default: 15mm)
  md2pdf input.md --paper A4          → page format (default: A4)
  md2pdf input.md --landscape         → landscape orientation
  md2pdf input.md --no-math           → skip KaTeX (faster, fully offline)
  md2pdf input.md --no-diagrams       → skip Mermaid (faster, fully offline)
  md2pdf --list-themes                → list available themes

Built-in themes: default, suse, minimal, consulting
```

> [!NOTE]
> KaTeX math rendering and Mermaid diagram rendering require network access to fetch assets from the jsDelivr CDN. Use the `--no-math` or `--no-diagrams` flags to work in fully offline environments.

### Examples

```bash
# Convert input.md to input.pdf in the same directory using default style
md2pdf input.md

# Convert with an explicit output location
md2pdf input.md output.pdf

# Convert using the sleek built-in SUSE brand theme
md2pdf input.md --theme suse

# Convert with custom margins and landscape orientation
md2pdf input.md --margins 20mm --landscape
```

## Prerequisites

Dependencies are defined in the **[Brewfile](./Brewfile)** (e.g., `squashfs` for kernel extraction). Install via Homebrew:

```bash
brew bundle
```
