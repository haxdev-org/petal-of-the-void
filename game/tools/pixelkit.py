"""Small pixel-art toolkit shared by the asset generators.

Everything is drawn at native pixel resolution into numpy RGBA canvases.
Shapes are built as boolean masks, then shaded with an erosion-based depth
field (so rounded forms get a proper light side, core shadow and rim), tones
are quantised to a hue-shifted palette ramp, and the final silhouette gets a
selective dark outline. That is the workflow a pixel artist follows by hand,
automated.
"""
from __future__ import annotations

import colorsys
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

BAYER2 = np.array([[0, 2], [3, 1]], dtype=np.float32) / 4.0


# --- colour ---------------------------------------------------------------

def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shift(rgb, dv: float, ds: float = 0.0, dh: float = 0.0) -> tuple[int, int, int]:
    """Value/saturation/hue shift in HSV space; hue shift in turns."""
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + dh) % 1.0
    s = min(1.0, max(0.0, s + ds))
    v = min(1.0, max(0.0, v + dv))
    return tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(h, s, v))


def ramp(base, steps: int = 5, spread: float = 0.16, hue_shift: float = 0.035):
    """Palette ramp around `base`, darkest first. Values are spread across a
    band that always fits inside 0..1, so a near-white base gets real shadow
    tones instead of clipping, and a near-black base still has a highlight.
    Shadows get more saturated and cooler, lights less saturated and warmer."""
    r, g, b = [c / 255.0 for c in base]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    span = spread * (steps - 1)
    v_hi = min(1.0, v + spread * 0.8)
    v_lo = max(0.10, v_hi - span)
    v_hi = min(1.0, v_lo + span)
    warm = _is_warm(base)
    out = []
    for i in range(steps):
        t = i / (steps - 1)                      # 0 = darkest, 1 = lightest
        vi = v_lo + (v_hi - v_lo) * t
        k = (i - (steps - 1) / 2.0)              # negative = shadow
        si = min(1.0, max(0.0, s + (0.10 * -k if k < 0 else -0.12 * k)))
        hi = (h + (hue_shift * k * (0.4 if warm else -0.4))) % 1.0
        out.append(tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(hi, si, vi)))
    return out


def _is_warm(rgb) -> bool:
    h = colorsys.rgb_to_hsv(*[c / 255.0 for c in rgb])[0]
    return h < 0.2 or h > 0.85


# --- masks ------------------------------------------------------------------

def blank(w: int, h: int) -> np.ndarray:
    return np.zeros((h, w, 4), dtype=np.uint8)


def ellipse(w: int, h: int, cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    return np.array(img) > 127


def polygon(w: int, h: int, pts) -> np.ndarray:
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).polygon([tuple(p) for p in pts], fill=255)
    return np.array(img) > 127


def rect(w: int, h: int, x0, y0, x1, y1) -> np.ndarray:
    m = np.zeros((h, w), dtype=bool)
    m[max(0, int(y0)):max(0, int(y1)), max(0, int(x0)):max(0, int(x1))] = True
    return m


def line(w: int, h: int, pts, width: int = 1) -> np.ndarray:
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).line([tuple(p) for p in pts], fill=255, width=width)
    return np.array(img) > 127


def erode(m: np.ndarray) -> np.ndarray:
    p = np.pad(m, 1, constant_values=False)
    return m & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]


def dilate(m: np.ndarray) -> np.ndarray:
    p = np.pad(m, 1, constant_values=False)
    return m | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]


def depth_field(m: np.ndarray, max_depth: int = 8) -> np.ndarray:
    d = np.zeros(m.shape, dtype=np.float32)
    cur = m.copy()
    for i in range(max_depth):
        d[cur] = i + 1
        cur = erode(cur)
        if not cur.any():
            break
    return d


# --- shading ----------------------------------------------------------------

def shade(canvas: np.ndarray, mask: np.ndarray, colors, light=(-0.55, -0.7, 0.6),
          depth: int = 6, vgrad: float = 0.0, hgrad: float = 0.0, dither: float = 0.35,
          flat: float = 0.0, noise: float = 0.0, seed: int = 0) -> None:
    """Paint `mask` onto `canvas` with a rounded-form shading model.

    colors: palette ramp, darkest first. light: direction the light comes
    from (x right, y down, z toward viewer). vgrad/hgrad: extra tone slope
    down / to the right, for cloth and large flat areas. flat: 0 = fully
    rounded shading, 1 = ignore the form and use only gradients.
    """
    if not mask.any():
        return
    h, w = mask.shape
    d = depth_field(mask, depth)
    d = np.minimum(d, depth)
    # Smooth the depth a little so gradients are not staircase-y.
    dp = np.pad(d, 1, mode="edge")
    ds = (dp[1:-1, 1:-1] * 4 + dp[:-2, 1:-1] + dp[2:, 1:-1] + dp[1:-1, :-2] + dp[1:-1, 2:]) / 8.0
    gy, gx = np.gradient(ds)
    nz = np.full_like(gx, 0.9)
    nl = np.sqrt(gx * gx + gy * gy + nz * nz)
    lx, ly, lz = light
    ll = math.sqrt(lx * lx + ly * ly + lz * lz)
    lam = -(gx * lx + gy * ly) / nl / ll + (nz * lz) / nl / ll  # gradient points inward
    lam = (lam - 0.55) * 2.2  # centre the response
    ys, xs = np.mgrid[0:h, 0:w]
    if mask.any():
        y0, y1 = np.where(mask.any(axis=1))[0][[0, -1]]
        x0, x1 = np.where(mask.any(axis=0))[0][[0, -1]]
    else:
        y0 = y1 = x0 = x1 = 0
    vt = (ys - y0) / max(1, y1 - y0)
    ht = (xs - x0) / max(1, x1 - x0)
    tone = lam * (1.0 - flat) - vgrad * (vt - 0.5) * 2.0 + hgrad * (ht - 0.5) * 2.0
    if noise > 0:
        rng = np.random.default_rng(seed)
        tone = tone + rng.uniform(-noise, noise, size=tone.shape)
    n = len(colors)
    mid = (n - 1) / 2.0
    idx = mid + tone * (n - 1) / 2.4
    # ordered dither between adjacent tones
    frac = idx - np.floor(idx)
    thresh = np.tile(BAYER2, (h // 2 + 1, w // 2 + 1))[:h, :w]
    idx = np.floor(idx) + (frac > (1.0 - dither) + thresh * dither * 2.0 - dither).astype(np.float32)
    idx = np.clip(idx, 0, n - 1).astype(int)
    pal = np.array(colors, dtype=np.uint8)
    rgb = pal[idx]
    canvas[mask, :3] = rgb[mask]
    canvas[mask, 3] = 255


def paint(canvas: np.ndarray, mask: np.ndarray, color) -> None:
    canvas[mask, :3] = np.array(color, dtype=np.uint8)
    canvas[mask, 3] = 255


def outline(canvas: np.ndarray, darken: float = 0.5, cool: float = 0.02) -> None:
    """Selective outline: darken every opaque pixel that touches transparency."""
    a = canvas[..., 3] > 0
    edge = a & ~erode(a)
    rgb = canvas[edge, :3].astype(np.float32)
    ys, xs = np.where(edge)
    out = []
    for (r, g, b) in rgb:
        out.append(shift((int(r), int(g), int(b)), -darken * 0.6, 0.15, cool))
    canvas[edge, :3] = np.array(out, dtype=np.uint8) if out else rgb.astype(np.uint8)


def inner_line(canvas: np.ndarray, mask: np.ndarray, darken: float = 0.35) -> None:
    """Darken pixels of `mask` that border a *different* opaque region: used
    to separate overlapping parts (arm over robe) without a full outline."""
    a = canvas[..., 3] > 0
    edge = mask & ~erode(mask) & a
    rgb = canvas[edge, :3]
    canvas[edge, :3] = np.array([shift(tuple(int(c) for c in px), -darken, 0.1) for px in rgb], dtype=np.uint8) if edge.any() else rgb


def over(dst: np.ndarray, src: np.ndarray) -> None:
    a = src[..., 3:4].astype(np.float32) / 255.0
    dst[..., :3] = (src[..., :3] * a + dst[..., :3] * (1 - a)).astype(np.uint8)
    dst[..., 3] = np.maximum(dst[..., 3], src[..., 3])


def flip_h(canvas: np.ndarray) -> np.ndarray:
    return canvas[:, ::-1].copy()


def scale_nearest(canvas: np.ndarray, k: int) -> np.ndarray:
    return np.repeat(np.repeat(canvas, k, axis=0), k, axis=1)


# --- sheets -----------------------------------------------------------------

def write_sheet(path: str, anims: dict[str, list[np.ndarray]], fps: dict[str, float],
                loops: dict[str, bool], ppm: float, extra: dict | None = None) -> None:
    """Write a sprite sheet PNG (one row per animation) plus a JSON sidecar."""
    fw = max(f.shape[1] for frames in anims.values() for f in frames)
    fh = max(f.shape[0] for frames in anims.values() for f in frames)
    cols = max(len(frames) for frames in anims.values())
    sheet = np.zeros((fh * len(anims), fw * cols, 4), dtype=np.uint8)
    meta = {"frame_w": fw, "frame_h": fh, "ppm": ppm, "anims": {}}
    for row, (name, frames) in enumerate(anims.items()):
        for col, f in enumerate(frames):
            y = row * fh + (fh - f.shape[0])
            x = col * fw + (fw - f.shape[1]) // 2
            sheet[y:y + f.shape[0], x:x + f.shape[1]] = f
        meta["anims"][name] = {"row": row, "frames": len(frames), "fps": fps.get(name, 6), "loop": loops.get(name, True)}
    if extra:
        meta.update(extra)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(path)
    with open(path[:-4] + ".json", "w") as fh_:
        json.dump(meta, fh_, indent=1)


def save(path: str, canvas: np.ndarray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(canvas, "RGBA").save(path)


# --- noise ------------------------------------------------------------------

def tileable_noise(size: int, period: int, seed: int) -> np.ndarray:
    """Value noise that tiles at `size`, lattice spacing `period`."""
    rng = np.random.default_rng(seed)
    n = size // period
    lat = rng.random((n, n)).astype(np.float32)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) / period
    x0 = np.floor(xs).astype(int) % n
    y0 = np.floor(ys).astype(int) % n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    fx = xs - np.floor(xs)
    fy = ys - np.floor(ys)
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = lat[y0, x0]
    b = lat[y0, x1]
    c = lat[y1, x0]
    d = lat[y1, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def tileable_noise_aniso(size: int, px: int, py: int, seed: int) -> np.ndarray:
    """Value noise with different lattice spacing in x and y (streaks)."""
    rng = np.random.default_rng(seed)
    nx, ny = size // px, size // py
    lat = rng.random((ny, nx)).astype(np.float32)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    xs, ys = xs / px, ys / py
    x0 = np.floor(xs).astype(int) % nx
    y0 = np.floor(ys).astype(int) % ny
    x1, y1 = (x0 + 1) % nx, (y0 + 1) % ny
    fx, fy = xs - np.floor(xs), ys - np.floor(ys)
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    return (lat[y0, x0] * (1 - fx) + lat[y0, x1] * fx) * (1 - fy) + (lat[y1, x0] * (1 - fx) + lat[y1, x1] * fx) * fy


def worley(size: int, points: int, seed: int):
    """Tileable cellular noise: returns (distance to nearest, to second nearest)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((points, 2)) * size
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    d1 = np.full((size, size), 1e9, dtype=np.float32)
    d2 = np.full((size, size), 1e9, dtype=np.float32)
    for (px, py) in pts:
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        dx = np.minimum(dx, size - dx)
        dy = np.minimum(dy, size - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        d1 = np.where(closer, d, d1)
    return d1, d2


def fbm(size: int, periods=(32, 16, 8, 4), seed: int = 0, gain: float = 0.5) -> np.ndarray:
    out = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for i, p in enumerate(periods):
        out += tileable_noise(size, p, seed + i * 101) * amp
        total += amp
        amp *= gain
    return out / total


def quantize(field: np.ndarray, colors, dither: float = 0.5) -> np.ndarray:
    """Map a 0..1 field onto a palette with ordered dithering. Returns RGBA."""
    h, w = field.shape
    n = len(colors)
    idx = field * (n - 1)
    frac = idx - np.floor(idx)
    thresh = np.tile(BAYER2, (h // 2 + 1, w // 2 + 1))[:h, :w]
    idx = np.floor(idx) + (frac > 0.5 + (thresh - 0.375) * dither * 2).astype(np.float32)
    idx = np.clip(idx, 0, n - 1).astype(int)
    pal = np.array(colors, dtype=np.uint8)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = pal[idx]
    out[..., 3] = 255
    return out
