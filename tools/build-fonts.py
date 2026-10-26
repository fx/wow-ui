#!/usr/bin/env python3
"""Instance the variable OFL fonts into the static TTFs FxUI ships.

Usage: build-fonts.py <download-dir> <out-dir>

<download-dir> holds the files from github.com/google/fonts (ofl/):
  Inter.ttf                     inter/Inter[opsz,wght].ttf
  JetBrainsMono.ttf             jetbrainsmono/JetBrainsMono[wght].ttf
  BarlowCondensed-SemiBold.ttf  barlowcondensed/BarlowCondensed-SemiBold.ttf
"""
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

INSTANCES = [
    ("Inter.ttf", "Inter-Regular.ttf", {"wght": 400, "opsz": 14}),
    ("Inter.ttf", "Inter-SemiBold.ttf", {"wght": 600, "opsz": 14}),
    ("JetBrainsMono.ttf", "JetBrainsMono-Regular.ttf", {"wght": 400}),
]

for name, target, axes in INSTANCES:
    font = TTFont(src / name)
    instantiateVariableFont(font, axes, inplace=True, updateFontNames=True)
    font.save(out / target)
    print(target)

shutil.copy(src / "BarlowCondensed-SemiBold.ttf", out / "BarlowCondensed-SemiBold.ttf")
print("BarlowCondensed-SemiBold.ttf")
