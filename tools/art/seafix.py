"""Replace the grey margins of a painted map with the painting's own sea colour.

Usage: python seafix.py SRC DST WIDTH
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

src, dst, width = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGB")
im = im.resize((width, round(width * im.size[1] / im.size[0])), Image.LANCZOS)
a = np.asarray(im).astype(float)
H, W = a.shape[:2]
mx, mn = a.max(2), a.min(2)
sat = (mx - mn) / np.maximum(mx, 1)
blue = (a[..., 2] > a[..., 0] + 12) & (sat > 0.15)
sea = np.median(a[blue], axis=0)
keep = np.clip((sat - 0.05) / 0.10, 0, 1)
filled = ndimage.binary_fill_holes(ndimage.binary_closing(sat > 0.08, iterations=6))
prot = ndimage.gaussian_filter(ndimage.binary_erosion(filled, iterations=25).astype(float), 6)
alpha = np.maximum(keep, prot)[..., None]
noise = ndimage.gaussian_filter(np.random.default_rng(1).normal(0, 1, (H, W)), 8) * 30
bg = np.clip(sea[None, None, :] + noise[..., None] * np.array([0.5, 0.8, 0.9]), 0, 255)
Image.fromarray((a * alpha + bg * (1 - alpha)).astype(np.uint8)).save(dst, quality=84)
print(dst, (W, H), "sea #%02X%02X%02X" % tuple(int(v) for v in sea))
