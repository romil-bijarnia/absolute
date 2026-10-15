#!/usr/bin/env python3
"""Render Absolute's desktop wallpaper: glassy ribbons of light over a deep blue night.

Original artwork generated from arithmetic, so it can be regenerated at any size.
Requires numpy and Pillow (Fedora: python3-numpy python3-pillow).
"""

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

DEFAULT_SIZE = (3456, 2234)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def gradient_stops(t, stops):
    """Interpolate colours along t in [0, 1]; stops is a list of (position, (r, g, b))."""
    out = np.zeros(t.shape + (3,), dtype=np.float32)
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        mask = (t >= p0) & (t <= p1)
        local = np.clip((t[mask] - p0) / max(p1 - p0, 1e-6), 0.0, 1.0)[:, None]
        out[mask] = np.asarray(c0, dtype=np.float32) * (1 - local) + np.asarray(c1, dtype=np.float32) * local
    return out


def render(width, height, seed=7, ribbons=5):
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    u = xs / width
    v = ys / height

    # Night sky: deep navy, slightly lighter toward the lower left, with two soft glows.
    base = np.zeros((height, width, 3), dtype=np.float32)
    top = np.array([0.020, 0.026, 0.080], dtype=np.float32)
    bottom = np.array([0.045, 0.060, 0.160], dtype=np.float32)
    base += top[None, None, :] * (1 - v)[..., None] + bottom[None, None, :] * v[..., None]
    for (cx, cy, radius, colour, strength) in [
        (0.18, 0.95, 0.75, (0.10, 0.22, 0.60), 0.55),
        (0.85, 0.05, 0.70, (0.30, 0.10, 0.45), 0.45),
        (0.55, 0.55, 0.55, (0.05, 0.12, 0.40), 0.35),
    ]:
        d = np.sqrt(((u - cx) * (width / height)) ** 2 + (v - cy) ** 2)
        glow = np.exp(-(d / radius) ** 2) * strength
        base += glow[..., None] * np.asarray(colour, dtype=np.float32)[None, None, :]

    palette = [
        (0.00, (0.25, 0.80, 1.00)),   # cyan
        (0.30, (0.30, 0.45, 1.00)),   # blue
        (0.60, (0.60, 0.35, 0.95)),   # violet
        (0.85, (0.95, 0.45, 0.80)),   # pink
        (1.00, (1.00, 0.70, 0.70)),   # warm edge
    ]

    light = np.zeros_like(base)
    for index in range(ribbons):
        depth = index / max(ribbons - 1, 1)              # 0 far, 1 near
        amplitude = height * (0.06 + 0.10 * rng.random())
        y0 = height * (0.25 + 0.55 * rng.random())
        f1, f2 = 0.6 + 0.9 * rng.random(), 1.4 + 1.6 * rng.random()
        p1, p2 = rng.random() * 2 * math.pi, rng.random() * 2 * math.pi
        tilt = (rng.random() - 0.5) * height * 0.5
        centre = (y0 + tilt * (u[0] - 0.5)
                  + amplitude * np.sin(2 * math.pi * f1 * u[0] + p1)
                  + 0.45 * amplitude * np.sin(2 * math.pi * f2 * u[0] + p2))
        thickness = height * (0.045 + 0.075 * depth) * (0.75 + 0.5 * np.sin(2 * math.pi * (0.5 + rng.random()) * u[0] + rng.random() * 6))
        thickness = np.clip(thickness, height * 0.02, None)
        dy = ys - centre[None, :]
        half = thickness[None, :] * 0.5
        body = 1.0 - smoothstep(half * 0.55, half, np.abs(dy))
        rim = np.exp(-((np.abs(dy) - half * 0.8) / (half * 0.12)) ** 2) * (dy < 0)   # bright upper edge
        shade = 0.55 + 0.45 * np.clip(-dy / (half + 1e-6), -1, 1)                     # lit from above
        hue = np.clip(u + 0.25 * (depth - 0.5) + 0.12 * np.sin(2 * math.pi * u + depth * 3), 0, 1)
        colour = gradient_stops(hue, palette)
        strength = 0.28 + 0.42 * depth
        contribution = (body * shade * strength + rim * 0.9 * strength)[..., None] * colour
        if depth < 0.5:
            blur = int(6 + 18 * (1 - depth * 2)) * (width / DEFAULT_SIZE[0])
            image = Image.fromarray(np.clip(contribution * 255, 0, 255).astype(np.uint8))
            image = image.filter(ImageFilter.GaussianBlur(radius=max(blur, 1)))
            contribution = np.asarray(image, dtype=np.float32) / 255.0
        light += contribution

    colour = base + light
    # Soft overall bloom from the brightest ribbons.
    bloom = Image.fromarray(np.clip(light * 255, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(radius=max(1, int(40 * width / DEFAULT_SIZE[0]))))
    colour += np.asarray(bloom, dtype=np.float32) / 255.0 * 0.35
    # Gentle vignette and film grain.
    vignette = 1.0 - 0.35 * np.clip(np.sqrt(((u - 0.5) * 2) ** 2 + ((v - 0.5) * 2) ** 2) - 0.6, 0, 1)
    colour *= vignette[..., None]
    colour += rng.normal(0, 0.004, size=colour.shape).astype(np.float32)
    colour = np.clip(colour, 0, 1) ** (1 / 1.05)
    return Image.fromarray((colour * 255).astype(np.uint8))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", default="%dx%d" % DEFAULT_SIZE, help="WIDTHxHEIGHT")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--ribbons", type=int, default=5)
    args = parser.parse_args()
    width, height = (int(n) for n in args.size.lower().split("x"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    render(width, height, seed=args.seed, ribbons=args.ribbons).save(args.output, optimize=True)
    print(f"wrote {args.output} ({width}x{height})")


if __name__ == "__main__":
    main()
