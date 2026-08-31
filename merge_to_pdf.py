#!/usr/bin/env python3
"""
merge_to_pdf.py

Merges multiple image files (HEIC, JPG, PNG, WEBP, TIFF, etc.) into an optimized
multi-page PDF with size-budget enforcement and optional watermarking.
"""

import argparse
import os
import shutil
import subprocess
import sys


def find_magick_command():
    """Find available ImageMagick CLI binary."""
    for cmd in ["magick", "convert"]:
        path = shutil.which(cmd)
        if path:
            return path
    return None


def find_system_font():
    """Find a readable TTF/TTC font on the system for ImageMagick text annotations."""
    candidates = [
        # macOS
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttf",
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/SFCompact.ttf",
        "/System/Library/Fonts/Geneva.ttf",
        # Linux
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        # Windows
        "C:\\Windows\\Fonts\\arial.ttf",
        "C:\\Windows\\Fonts\\calibri.ttf",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


def format_color(color, opacity=0.25):
    """Convert color name or hex code to rgba string with opacity."""
    color_map = {
        "gray": (128, 128, 128),
        "grey": (128, 128, 128),
        "black": (0, 0, 0),
        "white": (255, 255, 255),
        "red": (220, 20, 60),
        "blue": (30, 144, 255),
        "green": (34, 139, 34),
        "orange": (255, 140, 0),
        "purple": (128, 0, 128),
        "yellow": (255, 215, 0),
    }
    c = color.lower().strip()
    if c in color_map:
        r, g, b = color_map[c]
        return f"rgba({r},{g},{b},{opacity})"
    if c.startswith("#"):
        c = c.lstrip("#")
        if len(c) == 6:
            r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
            return f"rgba({r},{g},{b},{opacity})"
        if len(c) == 3:
            r, g, b = int(c[0] * 2, 16), int(c[1] * 2, 16), int(c[2] * 2, 16)
            return f"rgba({r},{g},{b},{opacity})"
    if c.startswith("rgba(") or c.startswith("rgb("):
        return color
    return f"rgba(128,128,128,{opacity})"


def run_magick(
    magick_bin,
    images,
    output_pdf,
    max_dim=2400,
    quality=82,
    watermark_text=None,
    watermark_repeat=False,
    watermark_opacity=0.25,
    watermark_angle=-45.0,
    watermark_color="gray",
    watermark_size=None,
    watermark_image=None,
):
    """Run ImageMagick to produce a PDF with given dimension, quality, and optional watermark."""
    cmd = [
        magick_bin,
        *images,
        "-auto-orient",
        "-resize",
        f"{max_dim}x{max_dim}>",
    ]

    # Watermark text
    if watermark_text:
        font_path = find_system_font()
        if font_path:
            cmd.extend(["-font", font_path])

        fill_color = format_color(watermark_color, watermark_opacity)
        pointsize = watermark_size if watermark_size else max(24, int(max_dim / 20))
        cmd.extend(["-fill", fill_color, "-pointsize", str(pointsize)])

        if watermark_repeat:
            step_x = max(200, int(max_dim / 3))
            step_y = max(150, int(max_dim / 4))
            for x in range(-max_dim // 2 + step_x // 2, max_dim // 2, step_x):
                for y in range(-max_dim // 2 + step_y // 2, max_dim // 2, step_y):
                    cmd.extend(["-gravity", "Center", "-annotate", f"{watermark_angle:+.1f}+{x}+{y}", watermark_text])
        else:
            cmd.extend(["-gravity", "Center", "-annotate", f"{watermark_angle:+.1f}", watermark_text])

    # Watermark image overlay
    elif watermark_image:
        if not os.path.isfile(watermark_image):
            raise FileNotFoundError(f"Watermark image '{watermark_image}' not found.")
        cmd.extend([
            "-gravity", "Center",
            "-draw", f"image Over 0,0 0,0 '{watermark_image}'",
        ])

    cmd.extend([
        "-compress", "jpeg",
        "-quality", str(quality),
        output_pdf,
    ])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ImageMagick failed: {result.stderr.strip()}")


def merge_images_to_pdf(
    images,
    output_pdf,
    max_size_mb=None,
    initial_max_dim=2400,
    initial_quality=82,
    watermark_text=None,
    watermark_repeat=False,
    watermark_opacity=0.25,
    watermark_angle=-45.0,
    watermark_color="gray",
    watermark_size=None,
    watermark_image=None,
):
    magick_bin = find_magick_command()
    if not magick_bin:
        print("Error: ImageMagick ('magick' or 'convert') is required but not found in PATH.", file=sys.stderr)
        sys.exit(1)

    for img in images:
        if not os.path.isfile(img):
            print(f"Error: Image file '{img}' does not exist.", file=sys.stderr)
            sys.exit(1)

    max_dim = initial_max_dim
    quality = initial_quality
    max_bytes = int(max_size_mb * 1024 * 1024) if max_size_mb else None

    # Iterative budget optimization if max_size_mb is requested
    attempts = 0
    while attempts < 6:
        attempts += 1
        run_magick(
            magick_bin=magick_bin,
            images=images,
            output_pdf=output_pdf,
            max_dim=max_dim,
            quality=quality,
            watermark_text=watermark_text,
            watermark_repeat=watermark_repeat,
            watermark_opacity=watermark_opacity,
            watermark_angle=watermark_angle,
            watermark_color=watermark_color,
            watermark_size=watermark_size,
            watermark_image=watermark_image,
        )

        file_size = os.path.getsize(output_pdf)
        if not max_bytes or file_size <= max_bytes:
            break

        # Need to reduce size
        if quality > 65:
            quality = max(60, quality - 10)
        else:
            max_dim = int(max_dim * 0.8)
            quality = 75

    file_size_mb = os.path.getsize(output_pdf) / (1024 * 1024)
    print(f"Successfully generated '{output_pdf}'")
    print(f"  - Pages: {len(images)}")
    print(f"  - Final Size: {file_size_mb:.2f} MB ({os.path.getsize(output_pdf):,} bytes)")
    print(f"  - Settings: Max Dimension = {max_dim}px, JPEG Quality = {quality}%")
    if watermark_text:
        repeat_str = " (repeated/tiled)" if watermark_repeat else ""
        print(f"  - Watermark: \"{watermark_text}\"{repeat_str}, color={watermark_color}, opacity={watermark_opacity}")
    elif watermark_image:
        print(f"  - Watermark Image: '{watermark_image}'")


def main():
    parser = argparse.ArgumentParser(description="Merge and optimize images into a single PDF.")
    parser.add_argument("images", nargs="+", help="Input image file paths in desired page order")
    parser.add_argument("-o", "--output", default="merged.pdf", help="Output PDF file path (default: merged.pdf)")
    parser.add_argument("--max-size-mb", type=float, default=2.0, help="Maximum target PDF size in MB (default: 2.0)")
    parser.add_argument("--max-dimension", type=int, default=2400, help="Maximum image dimension in px (default: 2400)")
    parser.add_argument("--quality", type=int, default=82, help="Initial JPEG quality 1-100 (default: 82)")

    # Watermarking options
    parser.add_argument("-w", "--watermark", type=str, default=None, help="Text string to watermark across pages")
    parser.add_argument("--watermark-repeat", "--watermark-tile", dest="watermark_repeat", action="store_true", help="Tile watermark repeatedly across the page")
    parser.add_argument("--watermark-opacity", type=float, default=0.25, help="Watermark opacity from 0.0 to 1.0 (default: 0.25)")
    parser.add_argument("--watermark-angle", type=float, default=-45.0, help="Watermark rotation angle in degrees (default: -45.0)")
    parser.add_argument("--watermark-color", type=str, default="gray", help="Watermark color name or hex code (default: gray)")
    parser.add_argument("--watermark-size", type=int, default=None, help="Watermark font size in pt (default: auto)")
    parser.add_argument("--watermark-image", type=str, default=None, help="Path to image stamp/logo to overlay centered")

    args = parser.parse_args()
    merge_images_to_pdf(
        images=args.images,
        output_pdf=args.output,
        max_size_mb=args.max_size_mb,
        initial_max_dim=args.max_dimension,
        initial_quality=args.quality,
        watermark_text=args.watermark,
        watermark_repeat=args.watermark_repeat,
        watermark_opacity=args.watermark_opacity,
        watermark_angle=args.watermark_angle,
        watermark_color=args.watermark_color,
        watermark_size=args.watermark_size,
        watermark_image=args.watermark_image,
    )


if __name__ == "__main__":
    main()
