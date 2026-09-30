"""Turn the Blender renders (lit + material-ID pairs) into pixel-art sheets.

    python3 tools/post_sprites.py <render_dir>        (run from game/)

For every frame: downsample the 2x render, look up each pixel's material from
the ID pass, quantise its lit brightness onto that material's 5-tone
hue-shifted ramp, then add the selective outline. Rows in the sheet are
"<anim>_<dir>" for the 8 facings (0 = screen right, counter-clockwise).
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pixelkit import outline, ramp  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
SUPER = 2
PPM = 44.0

# Must match MATERIALS in blender_sprites.py (base colour 0..1, ID colour).
MATERIALS = {
    "armor": ((0.91, 0.90, 0.88), (255, 0, 0)),
    "armor_dark": ((0.62, 0.61, 0.64), (0, 255, 0)),
    "skin": ((0.96, 0.87, 0.80), (0, 0, 255)),
    "hair": ((0.91, 0.78, 0.45), (255, 255, 0)),
    "eye": ((0.10, 0.07, 0.11), (255, 0, 255)),
    "robe": ((0.14, 0.20, 0.42), (0, 255, 255)),
    "robe_dark": ((0.08, 0.11, 0.26), (128, 0, 0)),
    "white": ((0.95, 0.94, 0.92), (0, 128, 0)),
    "grey": ((0.72, 0.71, 0.77), (0, 0, 128)),
    "boot": ((0.17, 0.24, 0.47), (128, 128, 0)),
    "fur": ((0.35, 0.35, 0.39), (128, 0, 128)),
    "fur_dark": ((0.20, 0.20, 0.24), (0, 128, 128)),
    "fur_light": ((0.55, 0.55, 0.58), (255, 128, 0)),
    "amber": ((1.0, 0.69, 0.19), (255, 0, 128)),
    "bear": ((0.42, 0.29, 0.20), (128, 255, 0)),
    "bear_dark": ((0.25, 0.16, 0.11), (0, 255, 128)),
    "quill": ((0.85, 0.78, 0.63), (128, 0, 255)),
    "red": ((1.0, 0.25, 0.19), (255, 128, 128)),
    "core": ((1.0, 0.84, 0.59), (128, 255, 255)),
}
# Palette swaps: output sheet -> (source renders, material overrides)
VARIANTS = {
    "baihua_armor": ("baihua_armor", {}),
    "baihua": ("baihua", {}),
    "wolf": ("wolf", {}),
    "wolf_demon": ("wolf", {"fur": (0.23, 0.13, 0.15), "fur_dark": (0.11, 0.06, 0.08), "fur_light": (0.36, 0.22, 0.24), "amber": (1.0, 0.23, 0.16)}),
    "quill_bear": ("bear", {}),
}
META = {
    "baihua_armor": {"ppm": PPM, "height_m": 1.64},
    "baihua": {"ppm": PPM, "height_m": 1.64},
    "wolf": {"ppm": PPM, "height_m": 1.3},
    "wolf_demon": {"ppm": PPM / 3.0, "height_m": 4.0},
    "quill_bear": {"ppm": PPM / 1.6, "height_m": 2.4},
}
FPS = {"idle": 3, "walk": 10, "attack": 10, "cast": 8, "hurt": 1}
LOOP = {"idle": True, "walk": True, "attack": False, "cast": False, "hurt": True}
# Brightness thresholds (lit / base luminance) for the 5 ramp tones.
TONES = np.array([0.40, 0.62, 0.80, 0.94])
# Some materials look better with flatter shading (fewer tones).
FLAT = {"eye": 1, "amber": 2, "red": 2, "core": 2, "white": 4}


def build_lookup(overrides):
    ids = []
    ramps = []
    lums = []
    for name, (base, idc) in MATERIALS.items():
        base = overrides.get(name, base)
        rgb8 = tuple(int(round(c * 255)) for c in base)
        ids.append(idc)
        ramps.append(np.array(ramp(rgb8, 5, 0.13, 0.03), dtype=np.uint8))
        lums.append(0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2])
    return np.array(ids, dtype=np.int32), ramps, np.array(lums), list(MATERIALS.keys())


def downsample(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[0] // SUPER, img.shape[1] // SUPER
    return img[:h * SUPER, :w * SUPER].reshape(h, SUPER, w, SUPER, -1).mean(axis=(1, 3))


def load_pair(lit_path, id_path, ids):
    """Downsampled lit colour, per-pixel material index and coverage mask."""
    lit = np.array(Image.open(lit_path).convert("RGBA"), dtype=np.float32)
    idi = np.array(Image.open(id_path).convert("RGBA"), dtype=np.float32)
    h, w = lit.shape[0] // SUPER, lit.shape[1] // SUPER
    blocks = idi[:h * SUPER, :w * SUPER].reshape(h, SUPER, w, SUPER, 4)
    # Pick, per block, the first opaque ID sample so materials never mix; a
    # block with no opaque sample is background.
    cover = blocks[..., 3] > 128
    count = cover.sum(axis=(1, 3))
    alpha = count >= (SUPER * SUPER) // 2
    flat = blocks.transpose(0, 2, 1, 3, 4).reshape(h, w, SUPER * SUPER, 4)
    first = np.argmax(flat[..., 3] > 128, axis=2)
    id_px = np.take_along_axis(flat, first[..., None, None], axis=2)[:, :, 0, :3]
    # The renderer's view transform sRGB-encodes the flat ID emission
    # (128 comes out as 188); undo it so IDs match exactly.
    c = id_px / 255.0
    id_px = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4) * 255.0
    d = ((id_px.reshape(-1, 3)[:, None, :] - ids[None, :, :].astype(np.float32)) ** 2).sum(axis=2)
    mat = d.argmin(axis=1).reshape(h, w)
    # An edge sample whose ID colour is blended (far from every ID) takes the
    # material of its most common opaque neighbour instead.
    unsure = (d.min(axis=1).reshape(h, w) > 45.0 ** 2) & alpha
    if unsure.any():
        padded = np.pad(mat, 1, mode="edge")
        pad_a = np.pad(alpha & ~unsure, 1, constant_values=False)
        for y, x in zip(*np.where(unsure)):
            neigh = padded[y:y + 3, x:x + 3][pad_a[y:y + 3, x:x + 3]]
            if neigh.size:
                mat[y, x] = np.bincount(neigh).argmax()
    # Lit colour averaged over the covered samples only (no background bleed).
    lb = lit[:h * SUPER, :w * SUPER].reshape(h, SUPER, w, SUPER, 4)
    weights = (lb[..., 3] > 128).astype(np.float32)
    lit_s = (lb[..., :3] * weights[..., None]).sum(axis=(1, 3)) / np.maximum(weights.sum(axis=(1, 3)), 1)[..., None]
    lum = (0.299 * lit_s[..., 0] + 0.587 * lit_s[..., 1] + 0.114 * lit_s[..., 2]) / 255.0
    return lum, mat, alpha


def calibrate(pairs, ids, lums, n_mats):
    """Per-material brightness scale: the 90th percentile of lit/base across
    every frame becomes tone 4, so each material uses its whole ramp."""
    samples = [[] for _ in range(n_mats)]
    for lit_path, id_path in pairs:
        lum, mat, alpha = load_pair(lit_path, id_path, ids)
        for m in range(n_mats):
            sel = alpha & (mat == m)
            if sel.any():
                samples[m].append(lum[sel] / max(lums[m], 0.02))
    scale = np.ones(n_mats)
    for m in range(n_mats):
        if samples[m]:
            scale[m] = max(np.percentile(np.concatenate(samples[m]), 90), 0.05)
    return scale


def pixelate(lit_path, id_path, ids, ramps, lums, names, scale):
    lum, mat, alpha = load_pair(lit_path, id_path, ids)
    h, w = lum.shape
    out = np.zeros((h, w, 4), dtype=np.uint8)
    if not alpha.any():
        return out
    ratio = lum / np.maximum(lums[mat], 0.02) / scale[mat]
    tone = np.searchsorted(TONES, ratio).clip(0, 4)
    for m, name in enumerate(names):
        sel = alpha & (mat == m)
        if not sel.any():
            continue
        t = tone[sel]
        if name in FLAT:
            lo = FLAT[name]
            t = np.clip(t, lo, 4) if lo < 4 else np.clip(t, 2, 4)
        out[sel, :3] = ramps[m][t]
        out[sel, 3] = 255
    outline(out, 0.62, 0.03)
    return out


def assemble(sheet_name, render_dir):
    src, overrides = VARIANTS[sheet_name]
    folder = os.path.join(render_dir, src)
    if not os.path.isdir(folder):
        print("skip", sheet_name, "(no renders)")
        return
    ids, ramps, lums, names = build_lookup(overrides)
    files = sorted(f for f in os.listdir(folder) if f.endswith("_lit.png"))
    pairs = [(os.path.join(folder, f), os.path.join(folder, f.replace("_lit", "_id"))) for f in files]
    scale = calibrate(pairs, ids, lums, len(names))
    anims = {}
    for f, (lit_path, id_path) in zip(files, pairs):
        anim, d, i = f[:-8].rsplit("_", 2)
        frame = pixelate(lit_path, id_path, ids, ramps, lums, names, scale)
        anims.setdefault((anim, int(d)), {})[int(i)] = frame
    if not anims:
        return
    fh, fw = next(iter(anims.values()))[0].shape[:2]
    keys = sorted(anims.keys(), key=lambda k: (list(FPS).index(k[0]) if k[0] in FPS else 9, k[1]))
    cols = max(max(v) + 1 for v in anims.values())
    sheet = np.zeros((fh * len(keys), fw * cols, 4), dtype=np.uint8)
    meta = {"frame_w": fw, "frame_h": fh, "dirs": 8, "origin": "bottom_center", "anims": {}}
    meta.update(META[sheet_name])
    for row, key in enumerate(keys):
        frames = anims[key]
        for i in sorted(frames):
            sheet[row * fh:(row + 1) * fh, i * fw:(i + 1) * fw] = frames[i]
        name = f"{key[0]}_{key[1]}"
        meta["anims"][name] = {"row": row, "frames": max(frames) + 1, "fps": FPS.get(key[0], 6), "loop": LOOP.get(key[0], True)}
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, sheet_name + ".png"))
    with open(os.path.join(OUT, sheet_name + ".json"), "w") as fp:
        json.dump(meta, fp, indent=1)
    print("wrote", sheet_name, sheet.shape)


if __name__ == "__main__":
    render_dir = sys.argv[1]
    for sheet_name in VARIANTS:
        assemble(sheet_name, render_dir)
