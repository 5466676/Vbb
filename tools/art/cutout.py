"""Cut an AI image on a white background into a transparent PNG.

Usage: python cutout.py SRC DST MAXSIZE
Removes white connected to the border plus large enclosed white patches,
crops to content and resizes so the longest side is MAXSIZE.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(int)
bgish = (a.min(2) > 230) & ((a.max(2) - a.min(2)) < 24)
lab, n = ndimage.label(bgish)
sizes = ndimage.sum(bgish, lab, range(1, n + 1))
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
big = {i + 1 for i, s in enumerate(sizes) if s > a.shape[0] * a.shape[1] * 0.0004}
bg = np.isin(lab, list(border | big))
fg = ndimage.binary_opening(~bg, iterations=2)
lab2, n2 = ndimage.label(fg)
if n2:
    s2 = ndimage.sum(fg, lab2, range(1, n2 + 1))
    fg = np.isin(lab2, [i + 1 for i, s in enumerate(s2) if s > 400])
mask = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(
    ImageFilter.GaussianBlur(1))
out = im.convert("RGBA")
out.putalpha(mask)
out = out.crop(mask.getbbox())
out.thumbnail((size, size), Image.LANCZOS)
out.save(dst)
print(dst, out.size)
