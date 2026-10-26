#!/usr/bin/env python3
"""Generate FxUI's rounded-rectangle textures as uncompressed 32-bit TGA.

Usage: build-textures.py <out-dir>

Each radius gets a filled shape and a 1 px ring, plus a filled circle. Both are white with
anti-aliased alpha so the client can tint them, and are drawn on a square
of 4 x radius so they can be nine-sliced with margins equal to the radius.
"""
import math
import struct
import sys
from pathlib import Path

SS = 8  # supersamples per axis


def coverage(px, py, size, r, inset):
    """Fraction of pixel (px, py) inside the rounded rect inset by `inset`."""
    hits = 0
    lo, hi = inset, size - inset
    rr = r - inset
    for sy in range(SS):
        for sx in range(SS):
            x = px + (sx + 0.5) / SS
            y = py + (sy + 0.5) / SS
            if not (lo <= x <= hi and lo <= y <= hi):
                continue
            cx = min(max(x, lo + rr), hi - rr)
            cy = min(max(y, lo + rr), hi - rr)
            if (x - cx) ** 2 + (y - cy) ** 2 <= rr * rr:
                hits += 1
    return hits / (SS * SS)


def write_tga(path, size, alpha):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8 | 0x20)
    body = bytearray()
    for y in range(size):
        for x in range(size):
            body += bytes((255, 255, 255, alpha[y][x]))
    path.write_bytes(header + bytes(body))


def build(out, r):
    size = 4 * r
    fill = [[round(255 * coverage(x, y, size, r, 0)) for x in range(size)] for y in range(size)]
    ring = [
        [round(255 * max(0.0, coverage(x, y, size, r, 0) - coverage(x, y, size, r, 1))) for x in range(size)]
        for y in range(size)
    ]
    write_tga(out / f"Round{r}.tga", size, fill)
    write_tga(out / f"Round{r}Ring.tga", size, ring)
    print(f"Round{r}.tga", f"Round{r}Ring.tga")


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for radius in (4, 8):
    build(out, radius)

circle = [[round(255 * coverage(x, y, 32, 16, 0)) for x in range(32)] for y in range(32)]
write_tga(out / "Circle.tga", 32, circle)
print("Circle.tga")
