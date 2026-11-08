"""Neon commander portraits: the same paintings, cut out of their parchment background and set
on the game's navy grid with a cyan rim light (owner: keep the art, make it fit the neon look).

Needs onnxruntime and the ISNet general-use background-removal model (isnet-general-use.onnx,
from the rembg project). The model only gives the cutout mask; every figure pixel comes from the
original painting (a slight cool grade is applied).

    python tools/art/neon_commanders.py path/to/isnet-general-use.onnx originals_dir app/assets/armies/commanders
"""

import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageFilter

ARMIES = ["islamic", "ayyubid", "crusader", "roman", "pharaoh", "mongol", "ottoman", "ww2"]


def cutout_mask(sess: ort.InferenceSession, img: Image.Image) -> Image.Image:
    x = np.asarray(img.convert("RGB").resize((1024, 1024), Image.LANCZOS)).astype(np.float32) / 255
    x = ((x - 0.5) / 1.0).transpose(2, 0, 1)[None]
    y = sess.run(None, {sess.get_inputs()[0].name: x})[0][0, 0]
    y = (y - y.min()) / (y.max() - y.min() + 1e-8)
    return Image.fromarray((y * 255).astype("uint8")).resize(img.size, Image.LANCZOS)


def neon(src: Image.Image, m: Image.Image) -> Image.Image:
    W = src.size[0]
    w = np.clip((np.asarray(m).astype(float) / 255 - 0.15) / 0.7, 0, 1)  # 1 = figure
    im = np.asarray(src.convert("RGB")).astype(float)
    yy, xx = np.mgrid[0:W, 0:W]
    r = np.sqrt((xx - W / 2) ** 2 + (yy - W * 0.4) ** 2) / (W * 0.7)
    bg = np.array([6.0, 14, 34]) + np.clip(1 - r, 0, 1)[..., None] ** 1.5 * np.array([16, 50, 92])
    grid = ((xx % 16 == 0) | (yy % 16 == 0))[..., None]
    bg = np.where(grid, bg + np.array([4, 12, 24]), bg)
    f = (im - 128) * 1.08 + 128
    f[..., 0] *= 0.94
    f[..., 2] = f[..., 2] * 0.96 + 14 * (1 - f[..., 2] / 255)
    halo = np.asarray(m.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(6))).astype(float) / 255
    bg = bg + np.clip(halo - w, 0, 1)[..., None] * np.array([63, 208, 255]) * 0.85
    out = f * w[..., None] + bg * (1 - w[..., None])
    return Image.fromarray(np.clip(out, 0, 255).astype("uint8"))


def main() -> None:
    model, src_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    sess = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    for a in ARMIES:
        src = Image.open(src_dir / f"{a}.png").convert("RGB")
        neon(src, cutout_mask(sess, src)).save(out_dir / f"{a}.png", optimize=True)
        print("ok", a)


if __name__ == "__main__":
    main()
