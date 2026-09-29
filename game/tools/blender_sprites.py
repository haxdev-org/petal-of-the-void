"""Render the characters from 3D models at all 8 facings, Infinity Engine style.

    blender --background --python tools/blender_sprites.py -- <out_dir> [characters...]

The camera matches the game's isometric view (orthographic, pitched
HD2D.ISO_PITCH = 42 degrees). Each frame is rendered twice: lit (Cycles, one
sun plus ambient) and as flat material IDs. tools/post_sprites.py turns the
pair into pixel art. Scale is 44 px per metre at 2x supersampling.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "/tmp/sprites"
ONLY = [a for a in ARGS[1:] if a != "smoke"]
SMOKE = "smoke" in ARGS
PPM = 44.0
SUPER = 2
PITCH = 42.0
DIRS = 8

# Material palette: name -> (base colour 0..1, flat ID colour 0..255)
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
_mats = {}


def material(name):
    if name in _mats:
        return _mats[name]
    base, _ = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Specular IOR Level"].default_value = 0.1
    _mats[name] = m
    return m


def set_id_mode(on: bool):
    """Swap every material between lit shading and flat ID emission."""
    for name, m in _mats.items():
        base, idc = MATERIALS[name]
        tree = m.node_tree
        out = tree.nodes["Material Output"]
        if on:
            if "ID" not in tree.nodes:
                e = tree.nodes.new("ShaderNodeEmission")
                e.name = "ID"
                e.inputs["Color"].default_value = (idc[0] / 255.0, idc[1] / 255.0, idc[2] / 255.0, 1.0)
                e.inputs["Strength"].default_value = 1.0
            tree.links.new(tree.nodes["ID"].outputs["Emission"], out.inputs["Surface"])
        else:
            tree.links.new(tree.nodes["Principled BSDF"].outputs["BSDF"], out.inputs["Surface"])
    bpy.context.scene.view_settings.view_transform = "Standard" if on else "Standard"
    world = bpy.context.scene.world
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0 if on else 0.22
    for o in bpy.context.scene.objects:
        if o.type == "LIGHT":
            o.hide_render = on


# --- primitives ---------------------------------------------------------------------

def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


def _finish(obj, parent, loc, scale, mat, rot=(0, 0, 0)):
    obj.parent = parent
    obj.location = loc
    obj.scale = scale
    obj.rotation_euler = rot
    obj.data.materials.append(material(mat))
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def sphere(name, parent, loc, scale, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0)
    return _finish(bpy.context.active_object, parent, loc, scale, mat)


def cyl(name, parent, loc, radius, depth, mat, r2=None, rot=(0, 0, 0)):
    """Cylinder (or cone when r2 differs) along local Z."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=radius, radius2=r2, depth=depth)
    return _finish(bpy.context.active_object, parent, loc, (1, 1, 1), mat, rot)


def box(name, parent, loc, scale, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    return _finish(bpy.context.active_object, parent, loc, scale, mat, rot)


# --- Baihua -----------------------------------------------------------------------------

class Baihua:
    """Faces +X. Joints are empties; limbs hang along -Z from them."""

    def __init__(self, robe: bool):
        self.robe = robe
        r = self.root = empty("root")
        self.pelvis = empty("pelvis", r, (0, 0, 0.95))
        self.torso = empty("torso", self.pelvis, (0, 0, 0.05))
        armor = not robe
        # pelvis / hips
        box("hips", self.pelvis, (0, 0, 0), (0.20, 0.26, 0.14), "armor" if armor else "robe")
        # torso: tapered, wider than deep
        t = cyl("chest", self.torso, (0, 0, 0.22), 0.11, 0.44, "armor" if armor else "robe", r2=0.15)
        t.scale = (1.0, 1.3, 1.0)
        if armor:
            box("chest_plate", self.torso, (0.09, 0, 0.26), (0.06, 0.24, 0.20), "armor")
            box("belt", self.torso, (0, 0, 0.03), (0.26, 0.32, 0.03), "armor_dark")
        else:
            # collar
            cyl("collar", self.torso, (0, 0, 0.42), 0.075, 0.06, "grey")
            # sash and its trailing end on the left hip
            cyl("sash", self.torso, (0, 0, 0.06), 0.155, 0.07, "white")
            box("sash_tail", self.pelvis, (-0.02, -0.15, -0.12), (0.03, 0.05, 0.26), "white")
        # head
        self.neck = empty("neck", self.torso, (0, 0, 0.45))
        cyl("neck_c", self.neck, (0, 0, 0.03), 0.04, 0.07, "skin" if robe else "armor_dark")
        head = empty("head", self.neck, (0, 0, 0.06))
        sphere("face", head, (0, 0, 0.11), (0.105, 0.11, 0.12), "skin")
        sphere("hair_cap", head, (-0.025, 0, 0.14), (0.115, 0.125, 0.115), "hair")
        # fringe sweeps across the brow, eyes below it
        box("fringe", head, (0.07, 0.0, 0.18), (0.09, 0.19, 0.05), "hair", rot=(0, math.radians(-15), 0))
        for y in (-0.04, 0.04):
            sphere("eye", head, (0.10, y, 0.11), (0.012, 0.016, 0.02), "eye")
        # long hair down the back
        self.hair = empty("hair", head, (-0.09, 0, 0.10))
        box("hair_back", self.hair, (-0.02, 0, -0.20), (0.05, 0.14, 0.42), "hair")
        box("hair_tip", self.hair, (-0.03, 0, -0.44), (0.04, 0.10, 0.10), "hair")
        # arms
        self.arm = {}
        for side, y in (("L", 0.19), ("R", -0.19)):
            sh = empty(f"shoulder{side}", self.torso, (0, y, 0.40))
            if armor:
                sphere("pauldron", sh, (0, y * 0.15, 0.01), (0.07, 0.07, 0.06), "armor")
                cyl("upper", sh, (0, 0, -0.14), 0.045, 0.28, "armor")
            else:
                cyl("sleeve", sh, (0, 0, -0.15), 0.075, 0.30, "robe", r2=0.06)
            el = empty(f"elbow{side}", sh, (0, 0, -0.28))
            if armor:
                sphere("elbow_j", el, (0, 0, 0), (0.045, 0.045, 0.045), "armor_dark")
                cyl("fore", el, (0, 0, -0.13), 0.04, 0.26, "armor")
                sphere("hand", el, (0, 0, -0.29), (0.04, 0.05, 0.06), "armor_dark")
            else:
                cyl("sleeve2", el, (0, 0, -0.12), 0.11, 0.24, "robe", r2=0.07)
                cyl("glove", el, (0, 0, -0.26), 0.04, 0.10, "white")
                sphere("hand", el, (0, 0, -0.32), (0.04, 0.045, 0.05), "white")
            self.arm[side] = (sh, el)
        # legs / skirt
        self.leg = {}
        if robe:
            skirt = cyl("skirt", self.pelvis, (0, 0, -0.48), 0.30, 0.92, "robe", r2=0.16)
            skirt.scale = (1.0, 1.1, 1.0)
            cyl("underskirt", self.pelvis, (0, 0, -0.93), 0.29, 0.05, "grey")
        for side, y in (("L", 0.085), ("R", -0.085)):
            hip = empty(f"hip{side}", self.pelvis, (0, y, -0.04))
            if armor:
                cyl("thigh", hip, (0, 0, -0.21), 0.072, 0.42, "armor", r2=0.058)
            kn = empty(f"knee{side}", hip, (0, 0, -0.42))
            if armor:
                sphere("knee_j", kn, (0, 0, 0), (0.055, 0.055, 0.05), "armor_dark")
                cyl("shin", kn, (0, 0, -0.20), 0.05, 0.40, "armor", r2=0.04)
                box("foot", kn, (0.05, 0, -0.42), (0.16, 0.08, 0.06), "armor")
            else:
                box("boot", kn, (0.04, 0, -0.44), (0.15, 0.09, 0.08), "boot")
            self.leg[side] = (hip, kn)
        self.rest()

    # pose helpers: fwd swings the limb toward +X
    @staticmethod
    def swing(e, fwd, side=0.0):
        e.rotation_euler = (side, -fwd, 0)

    def leg_swing(self, e, fwd):
        # Under the robe the legs barely show, so keep the boots inside the skirt.
        self.swing(e, fwd * (0.3 if self.robe else 1.0))

    def rest(self):
        self.root.location = (0, 0, 0)
        self.root.rotation_euler = (0, 0, 0)
        self.pelvis.location = (0, 0, 0.95)
        self.pelvis.rotation_euler = (0, 0, 0)
        self.torso.rotation_euler = (0, 0, 0)
        self.neck.rotation_euler = (0, 0, 0)
        self.hair.rotation_euler = (0, 0, 0)
        for side in "LR":
            sh, el = self.arm[side]
            self.swing(sh, 0.05, 0.08 if side == "L" else -0.08)
            self.swing(el, 0.25)
            hip, kn = self.leg[side]
            self.swing(hip, 0.0)
            self.swing(kn, 0.0)

    def pose(self, anim, i, n):
        self.rest()
        t = i / n
        w = math.tau * t
        if anim == "idle":
            self.pelvis.location = (0, 0, 0.95 + 0.012 * math.sin(w))
            self.hair.rotation_euler = (0, 0.06 * math.sin(w), 0)
        elif anim == "walk":
            s = math.sin(w)
            self.pelvis.location = (0, 0, 0.95 + 0.025 * abs(math.sin(w * 2)))
            self.torso.rotation_euler = (0, -0.06, 0)
            self.leg_swing(self.leg["L"][0], 0.38 * s)
            self.leg_swing(self.leg["R"][0], -0.38 * s)
            self.leg_swing(self.leg["L"][1], -0.7 * max(0.0, -math.sin(w - 0.6)))
            self.leg_swing(self.leg["R"][1], -0.7 * max(0.0, math.sin(w - 0.6)))
            self.swing(self.arm["L"][0], -0.3 * s, 0.08)
            self.swing(self.arm["R"][0], 0.3 * s, -0.08)
            self.swing(self.arm["L"][1], 0.35)
            self.swing(self.arm["R"][1], 0.35)
            self.hair.rotation_euler = (0, 0.15 + 0.08 * s, 0)
        elif anim == "attack":
            phase = [0.0, 1.0, 0.8, 0.3][i]
            if i == 0:  # windup
                self.torso.rotation_euler = (0, 0.12, 0.45)
                self.swing(self.arm["R"][0], -0.9, -0.2)
                self.swing(self.arm["R"][1], 1.2)
                self.swing(self.arm["L"][0], 0.5, 0.2)
            else:  # palm strike
                self.root.location = (0.12 * phase, 0, 0)
                self.torso.rotation_euler = (0, -0.25 * phase, -0.55 * phase)
                self.swing(self.arm["R"][0], 1.55 * phase, -0.1)
                self.swing(self.arm["R"][1], 0.05)
                self.swing(self.arm["L"][0], -0.4 * phase, 0.15)
                self.swing(self.arm["L"][1], 0.8)
                self.leg_swing(self.leg["R"][0], 0.55 * phase)
                self.leg_swing(self.leg["L"][0], -0.35 * phase)
                self.leg_swing(self.leg["L"][1], -0.5 * phase)
                self.hair.rotation_euler = (0, 0.5 * phase, 0)
        elif anim == "cast":
            lift = [0.5, 1.1, 1.45][i]
            for side in "LR":
                self.swing(self.arm[side][0], lift, 0.35 if side == "L" else -0.35)
                self.swing(self.arm[side][1], 0.5 - 0.2 * i)
            self.pelvis.location = (0, 0, 0.95 + 0.01 * i)
            self.hair.rotation_euler = (0, 0.1 * i, 0)
        elif anim == "hurt":
            self.root.location = (-0.08, 0, 0)
            self.torso.rotation_euler = (0, 0.35, 0.2)
            self.neck.rotation_euler = (0, 0.3, 0)
            self.swing(self.arm["R"][0], 0.9, -0.5)
            self.swing(self.arm["R"][1], 1.0)
            self.swing(self.arm["L"][0], 0.4, 0.6)
            self.leg_swing(self.leg["L"][0], -0.3)
            self.hair.rotation_euler = (0, -0.3, 0)


# --- Monsters -----------------------------------------------------------------------

class Wolf:
    """Acid-fang wolf: shoulders too high, flattened skull, amber eyes. Faces +X."""

    def __init__(self):
        r = self.root = empty("root")
        self.body = empty("body", r, (0, 0, 0.84))
        b = sphere("barrel", self.body, (-0.02, 0, 0.02), (0.66, 0.22, 0.25), "fur")
        sphere("belly", self.body, (-0.05, 0, -0.06), (0.50, 0.19, 0.15), "fur_light")
        sphere("hump", self.body, (0.30, 0, 0.12), (0.24, 0.23, 0.21), "fur")
        sphere("haunch", self.body, (-0.44, 0, 0.0), (0.20, 0.21, 0.22), "fur")
        self.neck = empty("neck", self.body, (0.48, 0, 0.16))
        cyl("neck_c", self.neck, (0.12, 0, 0.02), 0.11, 0.30, "fur", rot=(0, math.radians(80), 0))
        self.head = empty("head", self.neck, (0.28, 0, 0.04))
        box("skull", self.head, (0.06, 0, 0.0), (0.26, 0.15, 0.10), "fur")
        box("snout", self.head, (0.27, 0, -0.03), (0.22, 0.09, 0.07), "fur_dark")
        self.jaw = empty("jaw", self.head, (0.14, 0, -0.06))
        box("jaw_c", self.jaw, (0.10, 0, -0.02), (0.20, 0.08, 0.04), "fur_dark")
        for y in (-0.075, 0.075):
            box("ear", self.head, (-0.08, y, 0.09), (0.06, 0.03, 0.10), "fur_dark", rot=(0, math.radians(30), 0))
            sphere("eye", self.head, (0.13, y * 0.85, 0.035), (0.02, 0.022, 0.018), "amber")
        for y in (-0.03, 0.03):
            box("fang", self.jaw, (0.16, y, 0.0), (0.02, 0.012, 0.035), "white")
        self.tail = empty("tail", self.body, (-0.56, 0, 0.06))
        cyl("tail_c", self.tail, (-0.16, 0, 0.06), 0.035, 0.36, "fur", r2=0.015, rot=(0, math.radians(-70), 0))
        self.legs = {}
        for name, x, y in (("FL", 0.32, 0.13), ("FR", 0.32, -0.13), ("BL", -0.36, 0.13), ("BR", -0.36, -0.13)):
            hip = empty(f"hip{name}", self.body, (x, y, -0.06))
            cyl("thigh", hip, (0, 0, -0.18), 0.07, 0.36, "fur", r2=0.05)
            kn = empty(f"knee{name}", hip, (0, 0, -0.36))
            cyl("shin", kn, (0, 0, -0.19), 0.045, 0.38, "fur_dark", r2=0.04)
            box("paw", kn, (0.04, 0, -0.39), (0.13, 0.09, 0.06), "fur_dark")
            self.legs[name] = (hip, kn)
        self.rest()

    def rest(self):
        self.root.location = (0, 0, 0)
        self.body.location = (0, 0, 0.84)
        self.body.rotation_euler = (0, 0, 0)
        self.body.scale = (1, 1, 1)
        self.neck.rotation_euler = (0, 0, 0)
        self.head.rotation_euler = (0, 0, 0)
        self.jaw.rotation_euler = (0, 0, 0)
        self.tail.rotation_euler = (0, 0, 0)
        for name, (hip, kn) in self.legs.items():
            hip.rotation_euler = (0, 0, 0)
            kn.rotation_euler = (0, 0.25 if name[0] == "B" else 0.0, 0)

    def pose(self, anim, i, n):
        self.rest()
        w = math.tau * i / n
        if anim == "idle":
            self.body.scale = (1, 1 + 0.03 * math.sin(w), 1 + 0.03 * math.sin(w))
            self.head.rotation_euler = (0, 0.05 * math.sin(w), 0)
            self.tail.rotation_euler = (0, 0, 0.15 * math.sin(w))
            if i == 2:
                self.jaw.rotation_euler = (0, 0.25, 0)
        elif anim == "attack":
            if i == 0:  # crouch
                self.body.location = (-0.15, 0, 0.70)
                self.body.rotation_euler = (0, -0.12, 0)
                for name, (hip, kn) in self.legs.items():
                    hip.rotation_euler = (0, -0.5 if name[0] == "B" else 0.4, 0)
                    kn.rotation_euler = (0, 0.9, 0)
            else:  # lunge
                s = 1.0 if i == 1 else 0.6
                self.root.location = (0.45 * s, 0, 0)
                self.body.location = (0, 0, 0.9)
                self.body.rotation_euler = (0, 0.2 * s, 0)
                self.jaw.rotation_euler = (0, 0.55 * s, 0)
                self.neck.rotation_euler = (0, -0.25 * s, 0)
                for name, (hip, kn) in self.legs.items():
                    hip.rotation_euler = (0, -0.9 * s if name[0] == "F" else 0.7 * s, 0)
                    kn.rotation_euler = (0, 0.3, 0)
        elif anim == "hurt":
            self.root.location = (-0.2, 0, 0)
            self.body.rotation_euler = (0, -0.15, 0)
            self.neck.rotation_euler = (0, -0.4, 0)
            self.jaw.rotation_euler = (0, 0.4, 0)
            for name, (hip, kn) in self.legs.items():
                hip.rotation_euler = (0, 0.3 if name[0] == "F" else -0.2, 0)


class Bear:
    """Quill-bear: twice a natural bear, quills along the spine, red eyes."""

    def __init__(self):
        r = self.root = empty("root")
        self.body = empty("body", r, (0, 0, 1.15))
        sphere("barrel", self.body, (0, 0, 0), (0.95, 0.52, 0.58), "bear")
        sphere("shoulders", self.body, (0.45, 0, 0.18), (0.55, 0.52, 0.52), "bear")
        sphere("rump", self.body, (-0.6, 0, 0.05), (0.45, 0.48, 0.48), "bear_dark")
        self.head = empty("head", self.body, (1.05, 0, 0.12))
        sphere("skull", self.head, (0.1, 0, 0), (0.30, 0.27, 0.26), "bear")
        sphere("snout", self.head, (0.36, 0, -0.06), (0.16, 0.13, 0.12), "bear_dark")
        sphere("nose", self.head, (0.50, 0, -0.03), (0.04, 0.05, 0.04), "eye")
        for y in (-0.16, 0.16):
            sphere("ear", self.head, (-0.05, y, 0.22), (0.07, 0.05, 0.07), "bear_dark")
            sphere("eye", self.head, (0.30, y * 0.6, 0.08), (0.03, 0.035, 0.03), "red")
        import random
        rng = random.Random(3)
        for k in range(12):
            x = -0.85 + k * 0.16
            h = rng.uniform(0.35, 0.6)
            cyl("quill", self.body, (x, rng.uniform(-0.06, 0.06), 0.45 + h / 2 - abs(x) * 0.12), 0.045, h, "quill", r2=0.005,
                rot=(0, math.radians(rng.uniform(-25, 10)), 0))
        self.legs = {}
        for name, x, y in (("FL", 0.55, 0.30), ("FR", 0.55, -0.30), ("BL", -0.60, 0.30), ("BR", -0.60, -0.30)):
            hip = empty(f"hip{name}", self.body, (x, y, -0.25))
            cyl("thigh", hip, (0, 0, -0.30), 0.15, 0.60, "bear", r2=0.12)
            kn = empty(f"knee{name}", hip, (0, 0, -0.55))
            cyl("shin", kn, (0, 0, -0.18), 0.12, 0.36, "bear_dark", r2=0.11)
            box("paw", kn, (0.08, 0, -0.36), (0.30, 0.22, 0.10), "bear_dark")
            self.legs[name] = (hip, kn)
        self.rest()

    def rest(self):
        self.root.location = (0, 0, 0)
        self.body.location = (0, 0, 1.15)
        self.body.rotation_euler = (0, 0, 0)
        self.body.scale = (1, 1, 1)
        self.head.rotation_euler = (0, 0, 0)
        for name, (hip, kn) in self.legs.items():
            hip.rotation_euler = (0, 0, 0)
            kn.rotation_euler = (0, 0, 0)

    def pose(self, anim, i, n):
        self.rest()
        w = math.tau * i / n
        if anim == "idle":
            self.body.scale = (1, 1 + 0.02 * math.sin(w), 1 + 0.025 * math.sin(w))
            self.head.rotation_euler = (0, 0.06 * math.sin(w), 0.05 * math.cos(w))
        elif anim == "attack":
            if i == 0:  # rear up
                self.body.location = (-0.2, 0, 1.45)
                self.body.rotation_euler = (0, -0.6, 0)
                for name, (hip, kn) in self.legs.items():
                    hip.rotation_euler = (0, -1.2 if name[0] == "F" else 0.4, 0)
            else:  # swipe down
                s = 1.0 if i == 1 else 0.5
                self.root.location = (0.25 * s, 0, 0)
                self.body.rotation_euler = (0, 0.18 * s, 0)
                self.head.rotation_euler = (0, 0.25 * s, 0)
                self.legs["FR"][0].rotation_euler = (0, -0.9 * s, 0)
                self.legs["FL"][0].rotation_euler = (0, 0.3 * s, 0)
        elif anim == "hurt":
            self.root.location = (-0.25, 0, 0)
            self.body.rotation_euler = (0, -0.2, 0)
            self.head.rotation_euler = (0, -0.35, 0)


# --- rendering ------------------------------------------------------------------------

ANIMS = {
    "baihua": {"idle": 4, "walk": 8, "attack": 4, "cast": 3, "hurt": 1},
    "wolf": {"idle": 4, "attack": 3, "hurt": 1},
    "bear": {"idle": 4, "attack": 3, "hurt": 1},
}
# frame size in final pixels (width, height) and the world height covered
FRAMES = {"baihua": (64, 96), "wolf": (112, 80), "bear": (160, 112)}


def setup_scene(frame_px):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    sc = bpy.context.scene
    # Cycles on the CPU: no GPU or display needed, and fast at sprite sizes.
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 2
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.resolution_x = frame_px[0] * SUPER
    sc.render.resolution_y = frame_px[1] * SUPER
    sc.render.resolution_percentage = 100
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.58, 0.75, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22
    sc.world = world
    # Camera: in front of the character (-Y), looking +Y, pitched down.
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(frame_px) / PPM
    cam.clip_start = 0.1
    cam.clip_end = 100
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    pitch = math.radians(PITCH)
    dist = 20.0
    co.location = (0, -math.cos(pitch) * dist, math.sin(pitch) * dist)
    co.rotation_euler = (math.radians(90 - PITCH), 0, 0)
    sc.camera = co
    # Sun from the camera's upper left, slightly in front.
    sun = bpy.data.lights.new("sun", "SUN")
    # Keep the brightest lit white below clipping so the post step still has
    # a brightness range to quantise into tones.
    sun.energy = 0.9
    sun.angle = 0.02
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    travel = Vector((0.55, 0.35, -0.75)).normalized()
    so.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
    so.location = (0, 0, 10)
    # Fill from the other side so the dark side keeps some form.
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 0.12
    fo = bpy.data.objects.new("fill", fill)
    sc.collection.objects.link(fo)
    fo.rotation_euler = Vector((-0.5, 0.2, -0.6)).normalized().to_track_quat("-Z", "Y").to_euler()
    return sc


def frame_offset(frame_px, name):
    """Camera aims a little above the feet so tall frames are used well."""
    h_m = frame_px[1] / PPM
    # Feet sit 12% up the frame, in screen metres.
    return h_m * 0.5 - h_m * 0.12


def render_character(name, build):
    frame_px = FRAMES[name]
    sc = setup_scene(frame_px)
    rig = build()
    cam = sc.camera
    # Shift the camera so the origin (feet) sits near the bottom of the frame:
    # move along the camera's up axis.
    up = cam.matrix_world.to_quaternion() @ Vector((0, 1, 0))
    cam.location = cam.location + up * frame_offset(frame_px, name)
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    for anim, count in ANIMS[name].items():
        for d in range(DIRS):
            for i in range(count):
                if SMOKE and (d not in (0, 5) or i != 0 or anim not in ("idle", "attack")):
                    continue
                rig.pose(anim, i, count)
                rig.root.rotation_euler = (0, 0, math.radians(d * 45))
                base = os.path.join(out, f"{anim}_{d}_{i}")
                set_id_mode(False)
                sc.render.filepath = base + "_lit.png"
                bpy.ops.render.render(write_still=True)
                set_id_mode(True)
                sc.render.filepath = base + "_id.png"
                bpy.ops.render.render(write_still=True)
    print(f"RENDERED {name}")


if __name__ == "__main__":
    builders = {
        "baihua_armor": lambda: Baihua(robe=False),
        "baihua": lambda: Baihua(robe=True),
        "wolf": Wolf,
        "bear": Bear,
    }
    for key, build in builders.items():
        if ONLY and key not in ONLY:
            continue
        animset = "baihua" if key.startswith("baihua") else key
        FRAMES.setdefault(key, FRAMES[animset])
        ANIMS.setdefault(key, ANIMS[animset])
        render_character(key, build)
    print("SPRITES OK")
