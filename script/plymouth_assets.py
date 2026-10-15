#!/usr/bin/env python3
"""Render the Absolute boot splash's images: the mark, the bar's track and fill.

Usage: plymouth_assets.py LOGO.png OUT_DIR
LOGO.png is the rendered Absolute mark (white on transparent); the script fits it
to the splash size and draws the progress bar pieces with Pillow.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> None:
    logo_src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    logo = Image.open(logo_src).convert("RGBA")
    size = 180
    logo.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(logo, ((size - logo.width) // 2, (size - logo.height) // 2), logo)
    canvas.save(out / "logo.png")
    width, height = 300, 8
    track = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(track).rounded_rectangle((0, 0, width - 1, height - 1), radius=height // 2, fill=(70, 70, 70, 255))
    track.save(out / "track.png")
    fill = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(fill).rounded_rectangle((0, 0, width - 1, height - 1), radius=height // 2, fill=(235, 235, 235, 255))
    fill.save(out / "fill.png")


if __name__ == "__main__":
    main()
