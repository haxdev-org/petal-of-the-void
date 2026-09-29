"""Generate tileable pixel-art textures, normal maps and ground decals.

    python3 tools/gen_textures.py           (run from game/)

Ground/rock/bark tiles are 128x128 and tile seamlessly; one tile covers about
1.45 m (HD2D.TILE_M). Each tile also gets a normal map derived from the same
height field so the sun rakes across the surface.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from pixelkit import (blank, ellipse, fbm, hex_rgb, line, outline, quantize, ramp, save, shade,  # noqa: E402
                      tileable_noise_aniso, worley)

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
LIGHT = (-0.55, -0.75, 0.55)
TILE = 128


# --- height fields (shared by albedo and normal maps) ------------------------

def h_grass(size, seed=1):
    return fbm(size, (16, 8, 4), seed, 0.6)


def h_loam(size, seed=2):
    return fbm(size, (16, 8, 4), seed, 0.6)


def h_path(size, seed=3):
    return fbm(size, (32, 8, 4), seed)


def h_rock(size, seed=4):
    f = fbm(size, (32, 16, 8), seed)
    d1, d2 = worley(size, 9 * (size // 64) ** 2, seed + 9)
    facet = np.clip((d2 - d1) / (12.0 * size / 64), 0, 1)
    cracks = (d2 - d1) < 1.2 * (size / 64)
    return f, facet, cracks


def h_bark(size, seed=5):
    return tileable_noise_aniso(size, 4, 32, seed) * 0.6 + tileable_noise_aniso(size, 8, 64, seed + 1) * 0.4


def h_needles(size, seed=6):
    return fbm(size, (16, 8, 4), seed)


# --- tiles ------------------------------------------------------------------------

def tile_grass(size=TILE, seed=1):
    pal = [hex_rgb(h) for h in ("1d2b1f", "27392a", "324a34", "3f5c3d", "55744a")]
    img = quantize(np.clip((h_grass(size, seed) - 0.2) * 1.5, 0, 1), pal, 0.4)
    rng = np.random.default_rng(seed)
    # Blades: short lighter strokes with a dark base pixel, sparse so it reads as turf.
    for _ in range(size * size // 14):
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        h = int(rng.integers(2, 5))
        tone = pal[3] if rng.random() < 0.7 else pal[4]
        for k in range(h):
            img[(y - k) % size, x, :3] = tone
        img[(y + 1) % size, x, :3] = pal[0]
    return img


def tile_loam(size=TILE, seed=2):
    pal = [hex_rgb(h) for h in ("241a16", "33261e", "463426", "5a4530", "6d5a3d")]
    img = quantize(np.clip((h_loam(size, seed) - 0.2) * 1.5, 0, 1), pal, 0.5)
    rng = np.random.default_rng(seed)
    for _ in range(size * size // 30):  # fallen needles
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        d = 1 if rng.random() < 0.5 else -1
        for k in range(3):
            img[(y + k) % size, (x + k * d) % size, :3] = (120, 96, 60) if rng.random() < 0.6 else pal[4]
    for _ in range(size * size // 90):  # pebbles
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        img[y, x, :3] = (110, 105, 100)
        img[(y + 1) % size, x, :3] = pal[0]
    return img


def tile_path(size=TILE, seed=3):
    pal = [hex_rgb(h) for h in ("4a3c2e", "5c4c3a", "6f5e48", "837259", "978667")]
    img = quantize(np.clip((h_path(size, seed) - 0.1) * 1.3, 0, 1), pal, 0.5)
    rng = np.random.default_rng(seed)
    for _ in range(size * size // 40):
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        img[y, x, :3] = pal[4] if rng.random() < 0.5 else (140, 130, 120)
        img[(y + 1) % size, x, :3] = pal[0]
    return img


def tile_rock(size=TILE, seed=4):
    pal = [hex_rgb(h) for h in ("232128", "33313a", "43404a", "55515d", "68636f")]
    f, facet, cracks = h_rock(size, seed)
    img = quantize(np.clip((f - 0.1) * 1.1 + facet * 0.25, 0, 1), pal, 0.3)
    img[cracks, :3] = pal[0]
    lit = np.roll(cracks, (-1, -1), axis=(0, 1)) & ~cracks
    img[lit, :3] = pal[4]
    return img


def tile_bark(size=TILE, seed=5):
    pal = [hex_rgb(h) for h in ("2a1d17", "3b2a22", "4c382c", "5e4838", "715845")]
    img = quantize(np.clip((h_bark(size, seed) - 0.15) * 1.5, 0, 1), pal, 0.35)
    fissure = tileable_noise_aniso(size, 4, 16, seed + 3) < 0.22
    img[fissure, :3] = pal[0]
    lit = np.roll(fissure, (0, 1), axis=(0, 1)) & ~fissure
    img[lit, :3] = pal[3]
    return img


def tile_needles(size=TILE, seed=6):
    pal = [hex_rgb(h) for h in ("142420", "1c3229", "244334", "2f5642", "3d6b4c")]
    img = quantize(np.clip((h_needles(size, seed) - 0.2) * 1.6, 0, 1), pal, 0.45)
    rng = np.random.default_rng(seed)
    for _ in range(size * size // 10):
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        d = 1 if rng.random() < 0.5 else -1
        for k in range(2):
            img[(y - k) % size, (x + k * d) % size, :3] = pal[4] if rng.random() < 0.5 else pal[3]
    return img


def tile_glass(size=TILE, seed=7):
    pal = [hex_rgb(h) for h in ("07060c", "0d0b16", "15111f", "1e1729", "2b2038")]
    f = fbm(size, (32, 16, 4), seed)
    img = quantize(np.clip((f - 0.2) * 1.4, 0, 1), pal, 0.3)
    rng = np.random.default_rng(seed)
    for _ in range(size * size // 120):
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        img[y, x, :3] = (120, 90, 140)
    return img


# --- normal maps ----------------------------------------------------------------

def normal_map(height: np.ndarray, strength: float = 2.5):
    """Tangent-space normal map (OpenGL +Y) from a tileable height field."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    nx, ny, nz = -dx, dy, np.ones_like(height)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    c = blank(height.shape[1], height.shape[0])
    c[..., 0] = ((nx / l) * 0.5 + 0.5) * 255
    c[..., 1] = ((ny / l) * 0.5 + 0.5) * 255
    c[..., 2] = ((nz / l) * 0.5 + 0.5) * 255
    c[..., 3] = 255
    return c


def tile_heights(size):
    f, facet, cracks = h_rock(size)
    rock = facet * 0.8 + f * 0.2
    rock[cracks] -= 0.5
    return {
        "grass": h_grass(size) * 0.5 + fbm(size, (4, 2), 11) * 0.5,
        "loam": h_loam(size),
        "path": h_path(size),
        "rock": rock,
        "bark": h_bark(size),
        "needles": h_needles(size),
    }


# --- scenery sprites ------------------------------------------------------------

def grass_tuft(variant: int):
    W, H = 20, 16
    c = blank(W, H)
    rng = np.random.default_rng(100 + variant)
    pal = ramp(hex_rgb("4a6b3f"), 5, 0.13, 0.03)
    for i in range(7 + variant):
        x0 = 4 + int(rng.integers(0, 12))
        top = 2 + int(rng.integers(0, 6))
        bend = int(rng.integers(-3, 4))
        m = line(W, H, [(x0, H - 1), (x0 + bend, top)], 1) | line(W, H, [(x0, H - 1), (x0 + bend // 2, (top + H) // 2)], 2)
        shade(c, m, pal, LIGHT, depth=1, vgrad=0.5, seed=i)
    outline(c, 0.45, 0.02)
    return c


def fern():
    W, H = 34, 26
    c = blank(W, H)
    pal = ramp(hex_rgb("2f6b4a"), 5, 0.13, 0.03)
    for k, (dx, dy) in enumerate(((-14, -10), (-8, -16), (4, -18), (12, -12), (16, -4))):
        stem = line(W, H, [(17, H - 1), (17 + dx, H - 1 + dy)], 1)
        frond = stem.copy()
        for t in range(3, 12):
            px = 17 + dx * t // 12
            py = H - 1 + dy * t // 12
            frond |= line(W, H, [(px, py), (px + (2 if dx > 0 else -2), py - 2)], 1) | line(W, H, [(px, py), (px + (-2 if dx > 0 else 2), py + 1)], 1)
        shade(c, frond, pal, LIGHT, depth=1, vgrad=0.3, seed=k)
    outline(c, 0.45, 0.02)
    return c


def pebbles():
    """A few small stones lying on the ground, for a flat decal."""
    W, H = 32, 24
    c = blank(W, H)
    rng = np.random.default_rng(300)
    pal = ramp(hex_rgb("6a6472"), 5, 0.12, 0.02)
    for i in range(6):
        cx, cy = int(rng.integers(4, 28)), int(rng.integers(4, 20))
        rx, ry = int(rng.integers(2, 5)), int(rng.integers(1, 3))
        shade(c, ellipse(W, H, cx, cy, rx, ry), pal, LIGHT, depth=2, seed=i)
    outline(c, 0.5, 0.02)
    return c


def light_shaft():
    W, H = 32, 256
    c = blank(W, H)
    ys, xs = np.mgrid[0:H, 0:W]
    fx = 1.0 - np.abs((xs - W / 2) / (W / 2))
    fy = np.sin(np.clip(ys / H, 0, 1) * np.pi)
    a = np.clip(fx * fx * fy * 255, 0, 255)
    c[..., :3] = (255, 236, 200)
    c[..., 3] = a.astype(np.uint8)
    return c


def soft_circle():
    W = 64
    c = blank(W, W)
    ys, xs = np.mgrid[0:W, 0:W]
    d = np.sqrt((xs - W / 2 + 0.5) ** 2 + (ys - W / 2 + 0.5) ** 2) / (W / 2)
    a = np.clip(1 - d, 0, 1) ** 2
    c[..., :3] = 255
    c[..., 3] = (a * 255).astype(np.uint8)
    return c


def smoke_puff():
    W = 64
    c = blank(W, W)
    ys, xs = np.mgrid[0:W, 0:W]
    d = np.sqrt((xs - W / 2 + 0.5) ** 2 + (ys - W / 2 + 0.5) ** 2) / (W / 2)
    n = fbm(W, (32, 16, 8), 200)
    a = np.clip((1 - d) * 1.4 - n * 0.6, 0, 1) ** 1.5
    c[..., :3] = (70, 62, 80)
    c[..., 3] = (a * 255).astype(np.uint8)
    return c


# --- decals ---------------------------------------------------------------------------

def macro_variation():
    """Large, soft brightness variation multiplied over tiled ground so the
    repeat is never obvious."""
    S = 256
    f = fbm(S, (128, 64, 32), 123)
    v = np.clip(0.72 + (f - 0.5) * 0.9, 0.55, 1.0)
    c = blank(S, S)
    c[..., :3] = (v[..., None] * 255).astype(np.uint8)
    c[..., 3] = 255
    return c


def clearing():
    """Soft-edged loam decal for trodden ground and dirt patches."""
    S = 256
    base = tile_loam(128, 2)
    c = blank(S, S)
    for y in range(0, S, 128):
        for x in range(0, S, 128):
            c[y:y + 128, x:x + 128] = base
    ys, xs = np.mgrid[0:S, 0:S]
    d = np.sqrt(((xs - S / 2) / (S / 2)) ** 2 + ((ys - S / 2) / (S / 2)) ** 2)
    n = fbm(S, (64, 32, 16), 77)
    edge = np.clip((1.05 - d + (n - 0.5) * 0.35) * 3.0, 0, 1)
    c[..., 3] = (edge * 255).astype(np.uint8)
    return c


def path_strip():
    """Path tile repeated down a strip with soft sides; tiles vertically."""
    tile = tile_path(128, 3)
    H = 512
    c = blank(128, H)
    for y in range(0, H, 128):
        c[y:y + 128] = tile
    xs = np.arange(128)
    side = np.clip((1.0 - np.abs((xs - 63.5) / 63.5)) * 2.6, 0, 1)
    n = fbm(128, (32, 16, 8), 55)
    a = np.clip(side[None, :] - (n[:1, :] - 0.5) * 0.6, 0, 1)
    c[..., 3] = (np.repeat(a, H, axis=0) * 255).astype(np.uint8)
    return c


def crater_rim():
    """Radial texture for the crater mesh: black glass floor, charred ring,
    ejecta blanket with bright rays fading into the soil. Covers 16 m."""
    S = 512
    ys, xs = np.mgrid[0:S, 0:S]
    dx, dy = xs - S / 2, ys - S / 2
    d = np.sqrt(dx * dx + dy * dy) / (S / 2)
    ang = np.arctan2(dy, dx)
    n = fbm(S, (128, 64, 32, 16, 8), 90)
    rays = np.clip(np.sin(ang * 23 + n * 6.0) * 0.5 + 0.5, 0, 1) ** 3 * np.clip((d - 0.42) * 4, 0, 1) * np.clip(1.1 - d, 0, 1)
    dd = d + (n - 0.5) * 0.12
    pal = [hex_rgb(h) for h in ("07060c", "110d18", "1c1526", "2a2028", "3a2a24", "4b3a2c", "5a4530", "6a5a3e", "7a6a4a")]
    img = quantize(np.clip(dd * 1.05 + rays * 0.25, 0, 1), pal, 0.5)
    rng = np.random.default_rng(91)
    glints = (d < 0.22) & (rng.random((S, S)) < 0.03)
    img[glints, :3] = np.array([(90, 70, 110)], dtype=np.uint8)
    embers = (d > 0.05) & (d < 0.24) & (np.abs(n - 0.5) < 0.012) & (rng.random((S, S)) < 0.5)
    img[embers, :3] = np.array([hex_rgb("ff8a2a")], dtype=np.uint8)
    rubble = (d > 0.28) & (d < 0.75) & (rng.random((S, S)) < 0.01)
    img[rubble, :3] = np.array([(95, 90, 98)], dtype=np.uint8)
    img[np.roll(rubble, 1, axis=0), :3] = np.array([(35, 30, 38)], dtype=np.uint8)
    # Opaque almost to the edge: the ground mesh has a hole under the crater.
    img[..., 3] = (np.clip((1.0 - d) * 10, 0, 1) * 255).astype(np.uint8)
    return img


def crater_normal():
    S = 512
    ys, xs = np.mgrid[0:S, 0:S]
    d = np.sqrt((xs - S / 2) ** 2 + (ys - S / 2) ** 2) / (S / 2)
    n = fbm(S, (64, 32, 16, 8), 90)
    h = n * 0.6 * np.clip((d - 0.3) * 3, 0, 1) + fbm(S, (8, 4), 93) * 0.25
    return normal_map(h, 4.0)


if __name__ == "__main__":
    for name, fn in (("grass", tile_grass), ("loam", tile_loam), ("path", tile_path), ("rock", tile_rock),
                     ("bark", tile_bark), ("needles", tile_needles), ("glass", tile_glass)):
        save(os.path.join(OUT, f"tile_{name}.png"), fn())
    for name, h in tile_heights(TILE).items():
        save(os.path.join(OUT, f"tile_{name}_n.png"), normal_map(h, 6.0 if name == "rock" else 3.0))
    for v in range(3):
        save(os.path.join(OUT, f"grass_tuft_{v}.png"), grass_tuft(v))
    save(os.path.join(OUT, "fern.png"), fern())
    save(os.path.join(OUT, "pebbles.png"), pebbles())
    save(os.path.join(OUT, "light_shaft.png"), light_shaft())
    save(os.path.join(OUT, "soft_circle.png"), soft_circle())
    save(os.path.join(OUT, "smoke.png"), smoke_puff())
    save(os.path.join(OUT, "crater.png"), crater_rim())
    save(os.path.join(OUT, "crater_n.png"), crater_normal())
    save(os.path.join(OUT, "macro.png"), macro_variation())
    save(os.path.join(OUT, "clearing.png"), clearing())
    save(os.path.join(OUT, "path_strip.png"), path_strip())
    for stale in ("tile_moss_stone.png", "mountains_0.png", "mountains_1.png", "mountains_2.png"):
        for suffix in ("", ".import"):
            p = os.path.join(OUT, stale + suffix)
            if os.path.exists(p):
                os.remove(p)
    print("textures written to", os.path.abspath(OUT))
