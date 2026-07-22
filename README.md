# Random Scripts 🛠️

A collection of utility scripts for Git automation, Homebrew setup, and SUSE/Harvester kernel extraction.

## Scripts

*   **[inspect-harvester-release.sh](./inspect-harvester-release.sh)**: Extracts the kernel version from a Harvester release squashfs image without deploying a node.
*   **[git-all](./git-all)**: Runs specified Git operations (`pull`, `gc`, or `status`) on all Git repositories found recursively under a directory.
*   **[git-pull-all](./git-pull-all)**: Sequentially pulls updates across multiple repositories (fast-forward only).
*   **[git-gc-all](./git-gc-all)**: Performs garbage collection across multiple repositories.
*   **[md2pdf](./md2pdf)**: Converts Markdown documents to beautifully styled PDFs with KaTeX math, Mermaid diagrams, and custom themes.
*   **[check_obsidian_links.py](./check_obsidian_links.py)**: Scans an Obsidian vault recursively to detect and list broken internal links.
*   **[audit_mixed_brackets.py](./audit_mixed_brackets.py)**: Audits an Obsidian vault to find mixed-bracket markdown link typos of the form `[[text](url)]`.
*   **[inspect-sbom.py](./inspect-sbom.py)**: Auto-detects, parses, and queries packages, versions, and licenses from SPDX 2.0 and CycloneDX JSON SBOMs.

## Usage: `inspect-harvester-release.sh`

Extracts the kernel version, the list of installed RPM packages, or the bundle container images from a Harvester release without needing to deploy an active node. Downloads the squashfs rootfs and extracts the information, or uses a high-performance fast-path directly querying the lightweight image list from GitHub.

```bash
Usage: ./inspect-harvester-release.sh [options] [version[,version...]]

Options:
  -a, --arch <arch>      Architecture: amd64 (default) | arm64
  -k, --keep             Keep the downloaded and extracted squashfs files
  -q, --quiet            Quiet mode: suppress progress messages and logs
  -p, --packages         List all installed RPM packages instead of kernel version
  -i, --images           List bundle container images instead of kernel version
  -f, --filter <pattern> Filter packages or images by a case-insensitive pattern
  --force-squashfs       Force image list extraction from squashfs (skip GitHub fast path)
  -s, --squashfs <file>  Read from a local squashfs file instead of downloading
  -h, --help             Show this help message
```

### Examples

```bash
# Extract kernel version from Harvester v1.7.0 (defaults to amd64)
./inspect-harvester-release.sh v1.7.0

# Extract kernel version from Harvester v1.2.2 for arm64 architecture
./inspect-harvester-release.sh v1.2.2 arm64

# Suppress log and progress output to retrieve only the raw kernel version
./inspect-harvester-release.sh -q v1.8.1

# Query multiple versions and print their kernel versions
./inspect-harvester-release.sh -q v1.8.1,v1.8.0

# Extract from multiple versions and keep the downloaded assets
./inspect-harvester-release.sh -k v1.7.0,v1.8.0

# List all packages installed in Harvester v1.8.1 (using local rpm or Docker)
./inspect-harvester-release.sh -p v1.8.1

# List all container images bundled in Harvester v1.8.1
./inspect-harvester-release.sh -i v1.8.1

# List Longhorn container images and tags used in Harvester v1.8.1
./inspect-harvester-release.sh -i -f longhorn v1.8.1

# Force the extraction of the container image list from squashfs rootfs for v1.8.1
./inspect-harvester-release.sh -i --force-squashfs v1.8.1

# Extract the kernel version from a local squashfs file
./inspect-harvester-release.sh -s /path/to/rootfs.squashfs

# List all RPM packages from a local squashfs file
./inspect-harvester-release.sh -s /path/to/rootfs.squashfs -p

# List bundle container images from a local squashfs file (requires ISO squashfs)
./inspect-harvester-release.sh -s /path/to/iso-rootfs.squashfs -i
```

## Usage: `git-all`

The `git-all` script runs specified Git operations on all Git repositories found recursively under a target directory.

```bash
# Pull operations
git-all pull                   # pull every repo in the directory & sub-directories
git-all pull ~/SUSE            # pull every repo, fast-forward only
git-all pull -s ~/SUSE         # skip repos with uncommitted changes

# Garbage collection operations
git-all gc                     # gc every repo in the current directory and its subdir
git-all gc ~/SUSE              # gc every repo
git-all gc -a ~/SUSE           # aggressive gc

# Status operations
git-all status                 # check status of every repo in the directory & sub-directories
git-all status ~/SUSE          # check status of every repo (concise short status)

# List operations
git-all list                   # list every repo found recursively
git-all list ~/SUSE            # list every repo found under ~/SUSE
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

## Usage: `check_obsidian_links.py`

Recursively scans an Obsidian vault, parses frontmatter aliases, and checks that every internal link (`[[target]]` or `[[target|display]]`) resolves to an actual note, media file, or alias within the vault. Reports broken links with source file paths and line numbers.

```bash
# Scan a specific Obsidian vault path
./check_obsidian_links.py /path/to/your/vault

# If no path is specified, it defaults to "~/SUSE/Obsidian/Vault" or the current working directory
./check_obsidian_links.py
```

## Usage: `audit_mixed_brackets.py`

Recursively audits Markdown files for mixed-bracket link typos of the form `[[text](url)]` (unintended combinations of internal wiki-link double brackets and external Markdown link parenthesis).

```bash
# Audit a specific Obsidian vault path
./audit_mixed_brackets.py /path/to/your/vault

# If no path is specified, it defaults to "~/SUSE/Obsidian/Vault" or the current working directory
./audit_mixed_brackets.py
```

## Usage: `inspect-sbom.py`

Inspects and queries software package lists, versions, and declared licenses from standard Software Bill of Materials (SBOM) documents. Features automatic format detection for both SPDX 2.0 and CycloneDX JSON formats.

```bash
Usage: ./inspect-sbom.py [options] <sbom-file.json>

Options:
  -p, --packages         List all package names and versions (default)
  -l, --licenses         List packages alongside their licenses
  -f, --filter <pattern> Filter packages, versions, or licenses by a case-insensitive regex
  -s, --summary          Print high-level summary statistics of the SBOM contents
  -h, --help             Show this help message
```

### Examples

```bash
# List all packages in an SPDX SBOM
./inspect-sbom.py SL-Micro-Extras-6.2-x86_64-GM.spdx.json

# List all packages and versions in a CycloneDX SBOM
./inspect-sbom.py SL-Micro-Extras-6.2-x86_64-GM.cdx.json

# Print high-level stats and top 10 most common licenses
./inspect-sbom.py -s SL-Micro-Extras-6.2-x86_64-GM.spdx.json

# Find all packages containing "kernel" or "linux" and list their licenses
./inspect-sbom.py -l -f "kernel|linux" SL-Micro-Extras-6.2-x86_64-GM.cdx.json
```

## Prerequisites

Dependencies are defined in the **[Brewfile](./Brewfile)** (e.g., `squashfs` for kernel extraction). Install via Homebrew:

```bash
brew bundle
```
