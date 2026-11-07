"""Split an AI icon sheet on a flat dark background into transparent icons.

Usage: python cutout_dark.py SRC OUT_PREFIX GRID SIZE [names...]
  GRID "2x2" cuts the sheet into cells; each cell's dark background (connected to the
  cell border) becomes transparent, the icon is cropped to content and fitted in SIZE x SIZE.
  Output: OUT_PREFIX<name>.png for each cell, left-to-right, top-to-bottom.
"""

import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

src, prefix, grid, size = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
cols, rows = (int(x) for x in grid.split("x"))
names = sys.argv[5:] or [str(i + 1) for i in range(cols * rows)]
im = Image.open(src).convert("RGB")
W, H = im.size
for idx in range(cols * rows):
    r, c = divmod(idx, cols)
    cell = im.crop((c * W // cols, r * H // rows, (c + 1) * W // cols, (r + 1) * H // rows))
    a = np.asarray(cell).astype(int)
    ref = np.median(np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]]), axis=0)
    dist = np.abs(a - ref).max(2)
    bgish = dist < 28
    lab, _ = ndimage.label(bgish)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    fg = ~np.isin(lab, list(border))
    fg = ndimage.binary_fill_holes(ndimage.binary_opening(fg, iterations=2))
    lab2, n2 = ndimage.label(fg)
    if n2:  # keep the main object(s), drop specks
        s2 = ndimage.sum(fg, lab2, range(1, n2 + 1))
        fg = np.isin(lab2, [i + 1 for i, s in enumerate(s2) if s > s2.max() * 0.02])
    # soft edge: partial alpha where the colour is close to the background
    soft = np.clip((dist - 10) / 30, 0, 1)
    alpha = np.where(fg, 1.0, 0.0)
    alpha = np.maximum(alpha, ndimage.binary_dilation(fg, iterations=3) * soft)
    mask = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    out = cell.convert("RGBA")
    out.putalpha(mask)
    box = out.getbbox()
    out = out.crop(box)
    out.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(out, ((size - out.width) // 2, (size - out.height) // 2), out)
    canvas.save(f"{prefix}{names[idx]}.png", optimize=True)
    print(f"{prefix}{names[idx]}.png", out.size)
