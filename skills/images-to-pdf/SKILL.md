---
name: images-to-pdf
description: Merge, convert, and compress multiple images (HEIC, PNG, JPG, WEBP, TIFF) into an optimized, size-bounded multi-page PDF with optional watermarking (filigrane). Use when the user asks to "merge pictures into a pdf", "convert images to pdf", "combine photos into a pdf", "HEIC to pdf", add a watermark / filigrane, or optimize/compress an image-based PDF.
---

# Images to PDF Merging and Optimization

This skill provides instructions and tools to merge images (including Apple HEIC photos, PNGs, JPEGs, WEBPs) into high-quality, lightweight multi-page PDFs with file size budgeting.

## Workflow

### 1. Direct Helper Script (Recommended)
Use the included helper script `./merge_to_pdf.py` to automatically auto-orient images, preserve aspect ratios, enforce a file size budget (e.g. `< 2 MB`), and optionally apply watermarks:

```bash
./merge_to_pdf.py image1.heic image2.heic -o output.pdf --max-size-mb 2.0
```

#### Basic Options:
- `-o / --output`: Path to output PDF (default: `merged.pdf`).
- `--max-size-mb`: Maximum target file size in megabytes (default: `2.0`).
- `--max-dimension`: Maximum pixel width/height (default: `2400`).
- `--quality`: Starting JPEG compression quality (default: `82`).

#### Watermark / Filigrane Options:
- `-w / --watermark`: Text string to watermark across pages (e.g. `"CONFIDENTIEL"`, `"COPIE"`, `"DRAFT"`).
- `--watermark-repeat` / `--watermark-tile`: Tile the watermark repeatedly across the entire page (useful for rental/identity dossiers).
- `--watermark-opacity`: Opacity from `0.0` to `1.0` (default: `0.25`).
- `--watermark-angle`: Rotation angle in degrees (default: `-45.0`).
- `--watermark-color`: Color name (`gray`, `red`, `black`, `blue`, etc.) or hex code (default: `gray`).
- `--watermark-size`: Font point size (default: auto-scaled to image dimensions).
- `--watermark-image`: Path to an image file (e.g. PNG stamp/logo) to overlay centered.

#### Examples:

```bash
# Basic merge with custom output name
./merge_to_pdf.py scan1.jpg scan2.png scan3.heic -o scanned-doc.pdf

# Add centered diagonal watermark
./merge_to_pdf.py doc1.heic doc2.heic -o out.pdf -w "CONFIDENTIEL"

# Add repeated/tiled watermark for document protection
./merge_to_pdf.py id1.heic id2.heic -o dossier.pdf -w "DOSSIER LOCATION 2026" --watermark-repeat --max-size-mb 1.5

# Add custom colored stamp
./merge_to_pdf.py doc.heic -o out.pdf -w "ANNULÉ" --watermark-color red --watermark-opacity 0.35
```

---

### 2. Manual ImageMagick Command
Alternatively, execute ImageMagick (`magick` or `convert`) directly:

```bash
# Standard merge
magick input1.HEIC input2.HEIC -auto-orient -resize "2400x2400>" -compress jpeg -quality 82 output.pdf

# With watermark
magick input1.HEIC input2.HEIC -auto-orient -resize "2400x2400>" -gravity Center -fill "rgba(128,128,128,0.25)" -pointsize 120 -annotate -45 "CONFIDENTIEL" -compress jpeg -quality 82 output.pdf
```

#### Key Flags:
- `-auto-orient`: Respects EXIF camera orientation metadata.
- `-resize "2400x2400>"`: Downscales only if dimensions exceed 2400px (preserves full resolution if smaller).
- `-compress jpeg -quality 82`: Keeps crisp visual readability for text/photos while significantly reducing PDF size.

---

### 3. Verification
Verify the generated PDF page count and size:
```bash
# Check size
ls -lh output.pdf

# Check page count and metadata (macOS)
mdls -name kMDItemNumberOfPages output.pdf
```
