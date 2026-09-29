"""Generate the character and monster sprite sheets.

    python3 tools/gen_sprites.py            (run from game/)

Baihua faces right (party side); monsters face left. Scale: 44 px per metre,
so Baihua (1.64 m) is 72 px tall and a 4 m wolf-demon really towers.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from pixelkit import (blank, ellipse, erode, flip_h, hex_rgb, inner_line, line, outline, paint, polygon, ramp,  # noqa: E402
                      rect, shade, write_sheet)

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
PPM = 44.0

# Palette from docs/ART_DIRECTION.md
HAIR = ramp(hex_rgb("e8c872"), 5, 0.13, 0.03)
SKIN = ramp(hex_rgb("f4e4d8"), 5, 0.10, 0.02)
ROBE = ramp(hex_rgb("233268"), 5, 0.13, 0.03)
ROBE_DARK = ramp(hex_rgb("151d42"), 5, 0.12, 0.03)
WHITE = ramp(hex_rgb("f2f0ea"), 5, 0.09, 0.02)
GREY = ramp(hex_rgb("b9b6c4"), 5, 0.10, 0.02)
BOOT = ramp(hex_rgb("2c3e78"), 5, 0.12, 0.03)
ARMOR = ramp(hex_rgb("e9e6e0"), 5, 0.09, 0.02)
ARMOR_DARK = ramp(hex_rgb("c9c5c4"), 5, 0.10, 0.02)
CRACK = hex_rgb("6e6878")
INK = hex_rgb("1a1428")
EYE = hex_rgb("2a1e2e")

LIGHT = (-0.55, -0.75, 0.55)


# --- Baihua -----------------------------------------------------------------

def baihua(pose: dict) -> np.ndarray:
    """One frame. pose keys (all optional): bob, lean, hem, hair, boot_f,
    boot_b, arm_f, arm_b, head_tilt."""
    W, H = 56, 84
    c = blank(W, H)
    bob = pose.get("bob", 0)
    lean = pose.get("lean", 0)
    hem = pose.get("hem", 0)
    hair = pose.get("hair", 0)
    bf = pose.get("boot_f", 0)
    bb = pose.get("boot_b", 0)
    arm_f = pose.get("arm_f", "rest")
    arm_b = pose.get("arm_b", "rest")
    cx = 26 + lean
    base = 78

    # Long hair down the back (behind everything). Sways at the tips.
    hair_pts = [(cx - 2, 12 + bob), (cx - 9, 16 + bob), (cx - 12 - hair, 36 + bob), (cx - 11 - hair * 2, 50 + bob),
                (cx - 7 - hair, 52 + bob), (cx - 6, 40 + bob), (cx - 3, 22 + bob)]
    hm = polygon(W, H, hair_pts)
    shade(c, hm, HAIR, LIGHT, depth=4, vgrad=0.35, seed=1)
    # strands
    for i, x in enumerate((cx - 10, cx - 8)):
        paint(c, line(W, H, [(x - hair, 26 + bob), (x - hair * 2, 48 + bob)]) & hm, HAIR[1])

    # Far arm (behind the robe)
    _arm(c, cx, bob, arm_b, front=False)

    # Robe body: shoulders -> waist -> flared hem
    body = polygon(W, H, [
        (cx - 8, 25 + bob), (cx + 8, 25 + bob), (cx + 7, 40 + bob), (cx + 12 + hem, 74),
        (cx + 10 + hem, base - 2), (cx - 10 - hem, base - 2), (cx - 12 - hem, 74), (cx - 7, 40 + bob)])
    shade(c, body, ROBE, LIGHT, depth=7, vgrad=0.45, hgrad=0.25, dither=0.15, seed=2)
    # Folds: two darker vertical creases in the skirt
    for x in (cx - 4, cx + 3):
        paint(c, line(W, H, [(x, 46 + bob), (x + (hem if x > cx else -hem), 72)]) & body, ROBE[1])
    # Inner grey robe at the collar, and pale grey underskirt peeking at the hem
    collar = polygon(W, H, [(cx - 3, 24 + bob), (cx + 4, 24 + bob), (cx + 1, 31 + bob), (cx - 1, 31 + bob)])
    shade(c, collar & body, GREY, LIGHT, depth=2, seed=3)
    under = rect(W, H, cx - 9 - hem, base - 3, cx + 9 + hem, base - 1) & body
    paint(c, under, GREY[2])
    # White blossom embroidery along the hem
    rng = np.random.default_rng(7)
    for _ in range(9):
        x = int(rng.integers(cx - 10 - hem, cx + 10 + hem))
        y = int(rng.integers(64, 74))
        pts = [(x, y), (x + 1, y), (x, y + 1), (x - 1, y), (x, y - 1)]
        for px, py in pts:
            if 0 <= px < W and 0 <= py < H and body[py, px]:
                c[py, px, :3] = WHITE[3]
        if 0 <= x < W and 0 <= y < H and body[y, x]:
            c[y, x, :3] = HAIR[3]  # gold centre
    # Sash: white band at the waist with a trailing end on the left hip
    sash = rect(W, H, cx - 8, 40 + bob, cx + 8, 44 + bob) & body
    shade(c, sash, WHITE, LIGHT, depth=2, hgrad=0.2, seed=4)
    tail = polygon(W, H, [(cx - 8, 43 + bob), (cx - 5, 43 + bob), (cx - 6 - hem, 60 + bob), (cx - 9 - hem, 60 + bob)])
    shade(c, tail, WHITE, LIGHT, depth=2, vgrad=0.3, seed=5)

    # Boots
    for x, dx, front in ((cx - 5, bb, False), (cx + 1, bf, True)):
        boot = polygon(W, H, [(x - 3 + dx, base - 6), (x + 3 + dx, base - 6), (x + 5 + dx, base), (x - 3 + dx, base)])
        shade(c, boot, BOOT if front else ROBE_DARK, LIGHT, depth=3, seed=6)

    # Head
    hy = 15 + bob + pose.get("head_tilt", 0)
    head = _head(c, cx, hy, W, H)
    # Neck
    neck = rect(W, H, cx - 1, hy + 7, cx + 3, 26 + bob) & ~head
    shade(c, neck, SKIN, LIGHT, depth=2, seed=10)
    # Near arm (in front of the robe)
    _arm(c, cx, bob, arm_f, front=True)
    inner_line(c, body & ~sash, 0.0)
    outline(c, 0.55, 0.02)
    return c


def _arm(c, cx, bob, mode, front: bool, sleeve_pal=None, hand_pal=None, bare=False):
    W, H = c.shape[1], c.shape[0]
    sx = cx + (5 if front else -4)
    sy = 27 + bob
    if mode == "rest":
        pts = [(sx - 3, sy), (sx + 3, sy), (sx + 4 + (2 if front else -2), sy + 14), (sx + 2 + (2 if front else -2), sy + 20), (sx - 3 + (2 if front else -2), sy + 20), (sx - 4, sy + 14)]
        hand = (sx + (2 if front else -2), sy + 21)
        glove = polygon(W, H, [(sx - 3 + (2 if front else -2), sy + 14), (sx + 4 + (2 if front else -2), sy + 14), (sx + 3 + (2 if front else -2), sy + 23), (sx - 2 + (2 if front else -2), sy + 23)])
    elif mode == "strike":
        pts = [(sx - 3, sy - 1), (sx + 3, sy + 3), (sx + 14, sy + 4), (sx + 14, sy + 9), (sx + 2, sy + 9), (sx - 4, sy + 5)]
        hand = (sx + 19, sy + 6)
        glove = polygon(W, H, [(sx + 12, sy + 3), (sx + 21, sy + 2), (sx + 22, sy + 9), (sx + 12, sy + 10)])
    elif mode == "windup":
        pts = [(sx - 3, sy), (sx + 3, sy), (sx - 2, sy + 12), (sx - 6, sy + 16), (sx - 9, sy + 14), (sx - 6, sy + 8)]
        hand = (sx - 8, sy + 15)
        glove = polygon(W, H, [(sx - 4, sy + 10), (sx + 1, sy + 13), (sx - 6, sy + 19), (sx - 11, sy + 15)])
    elif mode == "raise":
        pts = [(sx - 3, sy), (sx + 3, sy), (sx + 12, sy - 6), (sx + 13, sy - 1), (sx + 3, sy + 7), (sx - 4, sy + 5)]
        hand = (sx + 16, sy - 5)
        glove = polygon(W, H, [(sx + 10, sy - 8), (sx + 19, sy - 9), (sx + 19, sy - 2), (sx + 11, sy)])
    elif mode == "guard":
        pts = [(sx - 3, sy), (sx + 3, sy), (sx + 8, sy + 6), (sx + 6, sy + 12), (sx + 1, sy + 10), (sx - 4, sy + 6)]
        hand = (sx + 6, sy + 13)
        glove = polygon(W, H, [(sx + 3, sy + 8), (sx + 10, sy + 6), (sx + 11, sy + 14), (sx + 3, sy + 16)])
    else:
        return
    sleeve = polygon(W, H, pts)
    if bare:
        # Armoured arm: slimmer than a sleeve, so shrink the polygon toward its axis.
        sleeve = sleeve & ~(sleeve & ~erode(sleeve) & np.roll(~sleeve, 1, axis=1))
    sp = sleeve_pal if sleeve_pal else (ROBE if front else ROBE_DARK)
    hp = hand_pal if hand_pal else WHITE
    shade(c, sleeve, sp, LIGHT, depth=4, vgrad=0.3, dither=0.15, seed=11)
    shade(c, glove, hp, LIGHT, depth=3, seed=12)
    if 0 <= hand[1] < H and 0 <= hand[0] < W:
        c[hand[1], hand[0], :3] = hp[4]


def _head(c, cx, hy, W, H):
    head = ellipse(W, H, cx + 1, hy, 7, 8)
    shade(c, head, SKIN, LIGHT, depth=5, seed=8)
    cap = ellipse(W, H, cx - 1, hy - 4, 8, 5) | polygon(W, H, [(cx - 8, hy - 4), (cx + 1, hy - 4), (cx + 1, hy + 7), (cx - 4, hy + 8), (cx - 8, hy + 4)])
    fringe = polygon(W, H, [(cx - 1, hy - 8), (cx + 8, hy - 5), (cx + 7, hy - 2), (cx + 3, hy - 3), (cx, hy - 1)])
    shade(c, (cap | fringe) & (head | cap), HAIR, LIGHT, depth=4, seed=9)
    ex, ey = cx + 5, hy + 1
    paint(c, rect(W, H, ex, ey, ex + 1, ey + 2), EYE)
    paint(c, rect(W, H, ex, ey, ex + 1, ey + 1), (60, 45, 70))
    c[hy + 4, cx + 4, :3] = SKIN[1]
    paint(c, rect(W, H, cx + 2, hy - 2, cx + 7, hy - 1) & head & ~cap & ~fringe, SKIN[1])
    return head


def _cracks(c, mask, seed, count=5):
    """Fine impact cracks across the ceramic plating."""
    W, H = c.shape[1], c.shape[0]
    rng = np.random.default_rng(seed)
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return
    for _ in range(count):
        k = int(rng.integers(0, len(xs)))
        x, y = int(xs[k]), int(ys[k])
        pts = [(x, y)]
        for _ in range(int(rng.integers(2, 5))):
            x += int(rng.integers(-3, 4))
            y += int(rng.integers(-4, 5))
            pts.append((x, y))
        m = line(W, H, pts, 1) & mask
        c[m, :3] = CRACK
        lit = np.roll(m, (0, 1), axis=(0, 1)) & mask & ~m
        c[lit, :3] = ARMOR[4]


def baihua_armor(pose: dict) -> np.ndarray:
    """Chapter One: the cracked white ceramic-composite chassis, no robe."""
    W, H = 56, 84
    c = blank(W, H)
    bob = pose.get("bob", 0)
    lean = pose.get("lean", 0)
    hair = pose.get("hair", 0)
    lf = pose.get("boot_f", 0)
    lb = pose.get("boot_b", 0)
    arm_f = pose.get("arm_f", "rest")
    arm_b = pose.get("arm_b", "rest")
    cx = 26 + lean
    base = 78

    hair_pts = [(cx - 2, 12 + bob), (cx - 9, 16 + bob), (cx - 12 - hair, 36 + bob), (cx - 11 - hair * 2, 50 + bob),
                (cx - 7 - hair, 52 + bob), (cx - 6, 40 + bob), (cx - 3, 22 + bob)]
    hm = polygon(W, H, hair_pts)
    shade(c, hm, HAIR, LIGHT, depth=4, vgrad=0.35, seed=1)
    for x in (cx - 10, cx - 8):
        paint(c, line(W, H, [(x - hair, 26 + bob), (x - hair * 2, 48 + bob)]) & hm, HAIR[1])

    # Far leg and arm
    knee_b = (cx - 3 + lb // 2, 62 + bob // 2)
    far_leg = polygon(W, H, [(cx - 6, 48 + bob), (cx, 48 + bob), (knee_b[0] + 3, knee_b[1]), (cx - 2 + lb, base), (cx - 7 + lb, base), (knee_b[0] - 3, knee_b[1])])
    shade(c, far_leg, ARMOR_DARK, LIGHT, depth=3, vgrad=0.25, seed=13)
    _arm(c, cx, bob, arm_b, front=False, sleeve_pal=ARMOR_DARK, hand_pal=ARMOR_DARK, bare=True)

    # Torso: shoulder plates, narrow waist, hip plates
    torso = polygon(W, H, [(cx - 8, 25 + bob), (cx + 8, 25 + bob), (cx + 6, 42 + bob), (cx + 7, 50 + bob), (cx - 7, 50 + bob), (cx - 6, 42 + bob)])
    shade(c, torso, ARMOR, LIGHT, depth=6, vgrad=0.2, hgrad=0.2, dither=0.15, seed=2)
    # Plate seams
    for y in (33, 42):
        paint(c, rect(W, H, cx - 8, y + bob, cx + 8, y + bob + 1) & torso, ARMOR_DARK[1])
    paint(c, line(W, H, [(cx, 25 + bob), (cx, 42 + bob)]) & torso, ARMOR_DARK[2])
    # Core glow behind the chest plating: a faint warm pixel pair
    c[31 + bob, cx + 1, :3] = (255, 214, 150)
    c[31 + bob, cx + 2, :3] = (255, 190, 120)

    # Near leg
    knee_f = (cx + 3 + lf // 2, 62 + bob // 2)
    near_leg = polygon(W, H, [(cx - 1, 48 + bob), (cx + 6, 48 + bob), (knee_f[0] + 3, knee_f[1]), (cx + 5 + lf, base), (cx - 1 + lf, base), (knee_f[0] - 3, knee_f[1])])
    shade(c, near_leg, ARMOR, LIGHT, depth=4, vgrad=0.25, dither=0.15, seed=14)
    paint(c, rect(W, H, knee_f[0] - 3, knee_f[1], knee_f[0] + 3, knee_f[1] + 1) & near_leg, ARMOR_DARK[1])
    # Feet
    for x, dx, pal in ((cx - 4, lb, ARMOR_DARK), (cx + 2, lf, ARMOR)):
        foot = polygon(W, H, [(x - 3 + dx, base - 3), (x + 3 + dx, base - 3), (x + 6 + dx, base), (x - 3 + dx, base)])
        shade(c, foot, pal, LIGHT, depth=2, seed=15)

    _cracks(c, torso, 21, 6)
    _cracks(c, near_leg, 22, 3)

    hy = 15 + bob + pose.get("head_tilt", 0)
    head = _head(c, cx, hy, W, H)
    neck = rect(W, H, cx - 1, hy + 7, cx + 3, 26 + bob) & ~head
    shade(c, neck, ARMOR_DARK, LIGHT, depth=2, seed=10)

    _arm(c, cx, bob, arm_f, front=True, sleeve_pal=ARMOR, hand_pal=ARMOR, bare=True)
    outline(c, 0.5, 0.02)
    return c


def baihua_sheet():
    _write_baihua("baihua", baihua)
    _write_baihua("baihua_armor", baihua_armor)


def _write_baihua(name, draw):
    idle = []
    for i in range(4):
        idle.append(draw({"bob": [0, -1, 0, 0][i], "hair": [0, 1, 1, 0][i], "hem": [0, 0, 1, 0][i]}))
    walk = []
    for i in range(6):
        t = i / 6.0 * math.tau
        walk.append(draw({
            "bob": -1 if i in (1, 4) else 0, "hair": int(round(1.5 * math.sin(t))) + 1,
            "hem": int(round(1.2 * abs(math.sin(t)))), "boot_f": int(round(4 * math.sin(t))),
            "boot_b": int(round(-4 * math.sin(t))), "lean": 1,
        }))
    attack = [
        draw({"lean": -3, "arm_f": "windup", "arm_b": "rest", "hair": 1}),
        draw({"lean": 5, "arm_f": "strike", "arm_b": "windup", "hair": 3, "hem": 2, "boot_f": 6, "boot_b": -3}),
        draw({"lean": 3, "arm_f": "strike", "arm_b": "rest", "hair": 2, "hem": 1, "boot_f": 4, "boot_b": -2}),
        draw({"lean": 0, "arm_f": "guard", "hair": 1}),
    ]
    cast = [
        draw({"lean": -1, "arm_f": "guard", "arm_b": "guard", "hair": 1}),
        draw({"lean": 0, "arm_f": "raise", "arm_b": "raise", "hair": 2, "hem": 1}),
        draw({"lean": 1, "arm_f": "raise", "arm_b": "raise", "hair": 3, "hem": 2, "bob": -1}),
    ]
    hurt = [draw({"lean": -4, "arm_f": "guard", "arm_b": "windup", "hair": -2, "head_tilt": -1, "bob": 1})]
    write_sheet(os.path.join(OUT, name + ".png"),
                {"idle": idle, "walk": walk, "attack": attack, "cast": cast, "hurt": hurt},
                {"idle": 3, "walk": 9, "attack": 10, "cast": 8, "hurt": 1},
                {"idle": True, "walk": True, "attack": False, "cast": False, "hurt": True}, PPM,
                {"origin": "bottom_center", "height_m": 1.64})


# --- Wolves -----------------------------------------------------------------

def wolf(pose: dict, demon: bool = False) -> np.ndarray:
    """Acid-fang wolf (1.3 m at the shoulder) facing left. `demon` swaps in
    the wolf-demon palette; the caller scales it up."""
    W, H = 96, 68
    c = blank(W, H)
    fur = ramp(hex_rgb("3a2226") if demon else hex_rgb("5a5a64"), 5, 0.13, 0.03)
    fur_dark = ramp(hex_rgb("1c1014") if demon else hex_rgb("34343e"), 5, 0.12, 0.03)
    eye = hex_rgb("ff3a2a") if demon else hex_rgb("ffb030")
    drool = hex_rgb("ff3a2a") if demon else hex_rgb("8cff50")
    crouch = pose.get("crouch", 0)
    lunge = pose.get("lunge", 0)
    breathe = pose.get("breathe", 0)
    jaw = pose.get("jaw", 0)
    base = 62
    bx = 52 - lunge
    by = 36 + crouch

    # Far legs
    for x in (bx + 14, bx - 10):
        leg = polygon(W, H, [(x - 3, by + 6), (x + 4, by + 6), (x + 3 + pose.get("far", 0), base), (x - 3 + pose.get("far", 0), base)])
        shade(c, leg, fur_dark, LIGHT, depth=3, seed=20)
    # Tail
    tail = polygon(W, H, [(bx + 20, by - 2), (bx + 24, by - 8 + breathe), (bx + 34, by - 12 + breathe), (bx + 36, by - 8 + breathe), (bx + 28, by - 2), (bx + 22, by + 4)])
    shade(c, tail, fur, LIGHT, depth=4, seed=21)
    # Body: shoulders too high (a hump over the front legs), lean belly
    body = polygon(W, H, [(bx - 24, by - 10 + breathe), (bx - 12, by - 14 + breathe), (bx + 4, by - 12 + breathe), (bx + 20, by - 6),
                          (bx + 22, by + 4), (bx + 12, by + 10), (bx - 10, by + 10), (bx - 24, by + 2)])
    shade(c, body, fur, LIGHT, depth=8, vgrad=0.35, seed=22)
    # Pale belly
    belly = polygon(W, H, [(bx - 8, by + 4), (bx + 14, by + 2), (bx + 12, by + 10), (bx - 10, by + 10)]) & body
    shade(c, belly, ramp(fur[3], 5, 0.1, 0.02), LIGHT, depth=3, vgrad=0.4, seed=29)
    # Near legs: the hind leg has a hock, the foreleg is straight and high-shouldered
    n = pose.get("near", 0)
    hind = polygon(W, H, [(bx + 8, by + 2), (bx + 18, by + 2), (bx + 20, by + 12), (bx + 14 + n, by + 18), (bx + 16 + n, base), (bx + 10 + n, base), (bx + 9 + n, by + 18), (bx + 6, by + 10)])
    shade(c, hind, fur, LIGHT, depth=4, vgrad=0.2, seed=23)
    fore = polygon(W, H, [(bx - 17, by + 2), (bx - 10, by + 2), (bx - 10 - n, base), (bx - 17 - n, base)])
    shade(c, fore, fur, LIGHT, depth=3, vgrad=0.2, seed=28)
    for x in (bx + 12, bx - 14):
        c[base - 1, x + (n if x > bx else -n), :3] = fur[3]
    # Neck and flattened skull
    neck = polygon(W, H, [(bx - 24, by - 10 + breathe), (bx - 30, by - 8), (bx - 34, by - 2), (bx - 26, by + 2), (bx - 20, by + 2)])
    shade(c, neck, fur, LIGHT, depth=5, seed=24)
    skull = polygon(W, H, [(bx - 34, by - 9), (bx - 26, by - 11), (bx - 20, by - 8), (bx - 22, by - 2), (bx - 36, by), (bx - 44, by - 1), (bx - 46, by - 5), (bx - 42, by - 8)])
    shade(c, skull, fur, LIGHT, depth=4, seed=25)
    # Ears, flat and swept back
    ear = polygon(W, H, [(bx - 28, by - 10), (bx - 22, by - 16), (bx - 20, by - 9)])
    shade(c, ear, fur_dark, LIGHT, depth=2, seed=26)
    # Lower jaw, open when attacking
    jaw_m = polygon(W, H, [(bx - 34, by - 1), (bx - 46, by + 1 + jaw), (bx - 44, by + 4 + jaw), (bx - 32, by + 3)])
    shade(c, jaw_m, fur_dark, LIGHT, depth=2, seed=27)
    # Fangs
    for x in (bx - 43, bx - 39):
        c[by, x, :3] = (235, 225, 210)
        c[by + 1, x, :3] = (200, 190, 175)
        c[by + 2 + jaw, x + 1, :3] = (235, 225, 210)
    # Corrosive drool
    c[by + 4 + jaw, bx - 42, :3] = drool
    c[by + 5 + jaw, bx - 42, :3] = drool
    c[by + 4 + jaw, bx - 42, 3] = 255
    c[by + 5 + jaw, bx - 42, 3] = 255
    # Eye: uniform reflective amber, no pupil
    paint(c, rect(W, H, bx - 40, by - 6, bx - 37, by - 4), eye)
    c[by - 6, bx - 40, :3] = (255, 240, 200) if not demon else (255, 160, 140)
    outline(c, 0.55, 0.02)
    return c


def wolf_sheet(demon: bool):
    idle = [wolf({"breathe": 0}, demon), wolf({"breathe": 1}, demon), wolf({"breathe": 1, "jaw": 1}, demon), wolf({"breathe": 0}, demon)]
    attack = [wolf({"crouch": 3, "lunge": -4, "breathe": 1}, demon), wolf({"lunge": 8, "crouch": -2, "jaw": 4, "near": 6, "far": -5}, demon), wolf({"lunge": 4, "jaw": 2, "near": 2}, demon)]
    hurt = [wolf({"crouch": 2, "lunge": -6, "jaw": 3, "breathe": -1}, demon)]
    name = "wolf_demon" if demon else "wolf"
    write_sheet(os.path.join(OUT, name + ".png"), {"idle": idle, "attack": attack, "hurt": hurt},
                {"idle": 3, "attack": 9, "hurt": 1}, {"idle": True, "attack": False, "hurt": True},
                PPM / (3.0 if demon else 1.0), {"origin": "bottom_center", "height_m": 4.0 if demon else 1.3})


# --- Quill-bear ---------------------------------------------------------------

def bear(pose: dict) -> np.ndarray:
    W, H = 128, 96
    c = blank(W, H)
    fur = ramp(hex_rgb("6b4a33"), 5, 0.13, 0.03)
    fur_dark = ramp(hex_rgb("40291c"), 5, 0.12, 0.03)
    quill = ramp(hex_rgb("d8c8a0"), 5, 0.12, 0.02)
    rear = pose.get("rear", 0)
    breathe = pose.get("breathe", 0)
    swipe = pose.get("swipe", 0)
    base = 90
    bx, by = 66, 52 - rear
    # Far legs
    for x in (bx + 26, bx - 18):
        shade(c, polygon(W, H, [(x - 6, by + 10), (x + 8, by + 10), (x + 8, base), (x - 8, base)]), fur_dark, LIGHT, depth=4, seed=30)
    # Body
    body = polygon(W, H, [(bx - 34, by - 14 + breathe), (bx - 10, by - 26 + breathe), (bx + 20, by - 26 + breathe), (bx + 38, by - 12),
                          (bx + 40, by + 8), (bx + 28, by + 18), (bx - 20, by + 18), (bx - 36, by + 6)])
    shade(c, body, fur, LIGHT, depth=10, vgrad=0.4, seed=31)
    # Quills along the spine
    rng = np.random.default_rng(3)
    for i in range(11):
        x = bx - 30 + i * 6
        top = by - 26 + breathe - int(rng.integers(8, 16)) + (i - 5) ** 2 // 3
        base_y = by - 22 + breathe + (i - 5) ** 2 // 3 - 2
        q = polygon(W, H, [(x - 2, base_y), (x + 2, base_y), (x + (3 if i > 5 else -1), top)])
        shade(c, q, quill, LIGHT, depth=2, vgrad=-0.3, seed=32 + i)
        c[top + 1, x + (2 if i > 5 else 0), :3] = (90, 30, 30)  # dark tip
    # Near legs
    for x, d in ((bx + 22, 0), (bx - 22, swipe)):
        shade(c, polygon(W, H, [(x - 7, by + 8), (x + 8, by + 8), (x + 9 + d, base), (x - 9 + d, base)]), fur, LIGHT, depth=5, vgrad=0.2, seed=33)
        for k in range(3):  # claws
            c[base - 1, x - 8 + d + k * 3, :3] = (230, 220, 200)
    # Head with heavy brow
    head = ellipse(W, H, bx - 40, by - 6 - rear // 2, 15, 12)
    shade(c, head, fur, LIGHT, depth=6, seed=34)
    snout = ellipse(W, H, bx - 52, by - 2 - rear // 2, 8, 6)
    shade(c, snout, fur_dark, LIGHT, depth=4, seed=35)
    paint(c, rect(W, H, bx - 60, by - 5 - rear // 2, bx - 56, by - 2 - rear // 2), (30, 20, 25))
    ear = ellipse(W, H, bx - 34, by - 18 - rear // 2, 4, 4)
    shade(c, ear, fur_dark, LIGHT, depth=2, seed=36)
    # Red luminescent eye
    ey = by - 9 - rear // 2
    paint(c, rect(W, H, bx - 48, ey, bx - 45, ey + 3), hex_rgb("ff4030"))
    c[ey, bx - 48, :3] = (255, 200, 180)
    # Mouth line
    paint(c, line(W, H, [(bx - 58, by + 2 - rear // 2), (bx - 46, by + 3 - rear // 2)]) & (head | snout), fur_dark[0])
    outline(c, 0.55, 0.02)
    return c


def bear_sheet():
    idle = [bear({"breathe": 0}), bear({"breathe": 1}), bear({"breathe": 2}), bear({"breathe": 1})]
    attack = [bear({"rear": 6, "breathe": 1}), bear({"rear": 2, "swipe": -10}), bear({"swipe": -4})]
    hurt = [bear({"rear": -2, "breathe": -2})]
    write_sheet(os.path.join(OUT, "quill_bear.png"), {"idle": idle, "attack": attack, "hurt": hurt},
                {"idle": 2.5, "attack": 8, "hurt": 1}, {"idle": True, "attack": False, "hurt": True},
                PPM / 1.6, {"origin": "bottom_center", "height_m": 2.4})


if __name__ == "__main__":
    baihua_sheet()
    wolf_sheet(False)
    wolf_sheet(True)
    bear_sheet()
    print("sprites written to", os.path.abspath(OUT))
