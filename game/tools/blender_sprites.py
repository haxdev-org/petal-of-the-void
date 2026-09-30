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
    if obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def _soft(obj, levels=2):
    """Subdivision surface: turns a box into a rounded blob, a cone into a
    soft-capped tube."""
    mod = obj.modifiers.new("subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
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


def blob(name, parent, loc, scale, mat, rot=(0, 0, 0)):
    """Rounded box: the workhorse for heads, torsos, hands and feet."""
    return _soft(box(name, parent, loc, scale, mat, rot))


def tube(name, parent, loc, r_top, r_bottom, length, mat, rot=(0, 0, 0)):
    """Tapered limb segment hanging down local -Z from `loc`, soft-capped."""
    obj = cyl(name, parent, (loc[0], loc[1], loc[2] - length / 2.0), r_bottom, length, mat, r2=r_top, rot=rot)
    return _soft(obj, 1)


def mball(family, parent, loc, scale, mat, rot=(0, 0, 0)):
    """One blended lump of an organic body. Every object whose name starts
    with `family` fuses into one smooth surface, so a torso, neck and legs
    made this way flow into each other. The first object of a family owns
    the material and resolution."""
    basis = bpy.data.objects.get(family)
    mb = bpy.data.metaballs.new(family)
    if basis is None:
        mb.resolution = 0.12
        mb.render_resolution = 0.025
        # At threshold t and stiffness s a ball of radius r shows a surface at
        # r * sqrt(1 - sqrt(t / s)); these values put it at ~r and leave a
        # generous field so neighbouring lumps fuse.
        mb.threshold = 0.25
    el = mb.elements.new()
    el.type = "BALL"
    el.radius = 1.18
    el.stiffness = 2.0
    obj = bpy.data.objects.new(family, mb)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = loc
    obj.scale = scale
    obj.rotation_euler = rot
    if basis is None:
        mb.materials.append(material(mat))
    return obj


# --- Baihua -----------------------------------------------------------------------------

class Baihua:
    """Faces +X. Joints are empties; limbs hang along -Z from them.

    Proportions: 1.64 m, slight build. Chassis version shows the white
    ceramic plating as separate panels with dark seams and joints; robe
    version wraps the same body in the ink-blue silk."""

    def __init__(self, robe: bool):
        self.robe = robe
        armor = not robe
        plate = "armor" if armor else "robe"
        r = self.root = empty("root")
        self.pelvis = empty("pelvis", r, (0, 0, 0.96))
        self.torso = empty("torso", self.pelvis, (0, 0, 0.04))
        # Body core: hips, waist, ribcage as rounded masses.
        blob("hips", self.pelvis, (0, 0, -0.03), (0.20, 0.29, 0.15), plate)
        blob("waist", self.torso, (0, 0, 0.10), (0.16, 0.21, 0.18), plate)
        blob("chest", self.torso, (0, 0, 0.30), (0.21, 0.32, 0.28), plate)
        if armor:
            # Front plating: two pectoral panels, three abdominal segments
            # with dark seams, a belt and a backplate.
            for y in (-0.08, 0.08):
                blob("pec", self.torso, (0.10, y, 0.33), (0.06, 0.14, 0.15), "armor")
            for k in range(3):
                z = 0.19 - k * 0.055
                blob("ab", self.torso, (0.085, 0, z), (0.05, 0.21 - k * 0.02, 0.045), "armor")
                box("seam", self.torso, (0.09, 0, z + 0.03), (0.05, 0.20, 0.006), "armor_dark")
            box("belt", self.torso, (0, 0, 0.015), (0.23, 0.32, 0.035), "armor_dark")
            blob("back", self.torso, (-0.10, 0, 0.30), (0.05, 0.28, 0.26), "armor")
            box("spine_seam", self.torso, (-0.125, 0, 0.30), (0.005, 0.012, 0.26), "armor_dark")
        else:
            cyl("collar", self.torso, (0, 0, 0.43), 0.08, 0.06, "grey")
            cyl("sash", self.torso, (0, 0, 0.05), 0.165, 0.07, "white")
            blob("sash_knot", self.pelvis, (0.02, -0.15, 0.06), (0.06, 0.07, 0.06), "white")
            box("sash_tail", self.pelvis, (-0.02, -0.16, -0.14), (0.03, 0.05, 0.30), "white", rot=(0.12, 0, 0))
        # Neck and head.
        self.neck = empty("neck", self.torso, (0, 0, 0.45))
        cyl("neck_c", self.neck, (0, 0, 0.04), 0.042, 0.09, "skin" if robe else "armor_dark")
        head = empty("head", self.neck, (0, 0, 0.07))
        blob("skull", head, (0, 0, 0.13), (0.19, 0.19, 0.22), "skin")
        blob("jaw", head, (0.015, 0, 0.055), (0.17, 0.16, 0.12), "skin")
        blob("nose", head, (0.10, 0, 0.10), (0.03, 0.025, 0.03), "skin")
        for y in (-0.045, 0.045):
            box("eye", head, (0.093, y, 0.115), (0.015, 0.03, 0.022), "eye")
            box("brow", head, (0.095, y, 0.145), (0.012, 0.035, 0.007), "hair")
        # Hair: cap over the crown, a fringe swept across the brow, side
        # locks in front of the ears and the long fall down the back.
        blob("hair_cap", head, (-0.03, 0, 0.17), (0.21, 0.22, 0.19), "hair")
        box("fringe", head, (0.07, 0.0, 0.19), (0.09, 0.19, 0.05), "hair", rot=(0, math.radians(-15), 0))
        for y in (-0.105, 0.105):
            blob("lock", head, (0.05, y, 0.04), (0.05, 0.045, 0.20), "hair")
        self.hair = empty("hair", head, (-0.09, 0, 0.12))
        blob("hair_upper", self.hair, (-0.02, 0, -0.12), (0.07, 0.19, 0.30), "hair")
        self.hair2 = empty("hair2", self.hair, (-0.01, 0, -0.26))
        blob("hair_lower", self.hair2, (-0.01, 0, -0.14), (0.06, 0.16, 0.30), "hair")
        for y in (-0.05, 0.05):
            blob("hair_tip", self.hair2, (-0.02, y, -0.31), (0.05, 0.06, 0.10), "hair")
        # Arms.
        self.arm = {}
        for side, y in (("L", 0.21), ("R", -0.21)):
            sh = empty(f"shoulder{side}", self.torso, (0, y, 0.41))
            if armor:
                blob("pauldron", sh, (0, y * 0.12, 0.02), (0.11, 0.10, 0.09), "armor")
                tube("upper", sh, (0, 0, 0.0), 0.062, 0.07, 0.29, "armor")
            else:
                tube("sleeve", sh, (0, 0, 0.0), 0.10, 0.085, 0.30, "robe")
            el = empty(f"elbow{side}", sh, (0, 0, -0.28))
            if armor:
                sphere("elbow_j", el, (0, 0, 0), (0.05, 0.05, 0.05), "armor_dark")
                tube("fore", el, (0, 0, 0.0), 0.04, 0.052, 0.26, "armor")
                cyl("wrist", el, (0, 0, -0.26), 0.036, 0.025, "armor_dark")
                blob("hand", el, (0.01, 0, -0.31), (0.05, 0.045, 0.08), "armor")
                blob("thumb", el, (0.035, y * 0.12, -0.29), (0.02, 0.02, 0.04), "armor")
            else:
                tube("sleeve2", el, (0, 0, 0.0), 0.12, 0.085, 0.25, "robe")
                cyl("glove", el, (0, 0, -0.27), 0.04, 0.10, "white")
                blob("hand", el, (0.01, 0, -0.33), (0.045, 0.045, 0.07), "white")
            self.arm[side] = (sh, el)
        # Legs (under the robe only the boots show).
        self.leg = {}
        if robe:
            skirt = cyl("skirt", self.pelvis, (0, 0, -0.48), 0.31, 0.92, "robe", r2=0.17)
            skirt.scale = (1.0, 1.1, 1.0)
            for k in range(6):
                a = k / 6.0 * math.tau + 0.3
                box("fold", self.pelvis, (math.cos(a) * 0.26, math.sin(a) * 0.29, -0.62), (0.03, 0.03, 0.62), "robe",
                    rot=(math.sin(a) * 0.16, -math.cos(a) * 0.16, 0))
            cyl("underskirt", self.pelvis, (0, 0, -0.93), 0.30, 0.05, "grey")
        for side, y in (("L", 0.09), ("R", -0.09)):
            hip = empty(f"hip{side}", self.pelvis, (0, y, -0.06))
            if armor:
                tube("thigh", hip, (0, 0, 0.02), 0.06, 0.082, 0.42, "armor")
            kn = empty(f"knee{side}", hip, (0, 0, -0.42))
            if armor:
                sphere("knee_j", kn, (0, 0, 0), (0.058, 0.058, 0.052), "armor_dark")
                tube("shin", kn, (0, 0, 0.0), 0.042, 0.056, 0.40, "armor")
                cyl("ankle", kn, (0, 0, -0.40), 0.04, 0.03, "armor_dark")
                blob("foot", kn, (0.05, 0, -0.44), (0.20, 0.09, 0.07), "armor")
                blob("toe", kn, (0.14, 0, -0.455), (0.06, 0.08, 0.05), "armor_dark")
            else:
                blob("boot", kn, (0.04, 0, -0.44), (0.16, 0.09, 0.08), "boot")
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
        self.pelvis.location = (0, 0, 0.96)
        self.pelvis.rotation_euler = (0, 0, 0)
        self.torso.rotation_euler = (0, 0, 0)
        self.neck.rotation_euler = (0, 0, 0)
        self.hair.rotation_euler = (0, 0, 0)
        self.hair2.rotation_euler = (0, 0.08, 0)
        for side in "LR":
            sh, el = self.arm[side]
            self.swing(sh, 0.05, 0.10 if side == "L" else -0.10)
            self.swing(el, 0.25)
            hip, kn = self.leg[side]
            self.swing(hip, 0.0)
            self.swing(kn, 0.0)

    def pose(self, anim, i, n):
        self.rest()
        t = i / n
        w = math.tau * t
        if anim == "idle":
            self.pelvis.location = (0, 0, 0.96 + 0.012 * math.sin(w))
            self.hair.rotation_euler = (0, 0.05 * math.sin(w), 0)
            self.hair2.rotation_euler = (0, 0.08 + 0.06 * math.sin(w + 0.8), 0)
        elif anim == "walk":
            s = math.sin(w)
            self.pelvis.location = (0, 0, 0.96 + 0.025 * abs(math.sin(w * 2)))
            self.torso.rotation_euler = (0, -0.06, 0)
            self.leg_swing(self.leg["L"][0], 0.38 * s)
            self.leg_swing(self.leg["R"][0], -0.38 * s)
            self.leg_swing(self.leg["L"][1], -0.7 * max(0.0, -math.sin(w - 0.6)))
            self.leg_swing(self.leg["R"][1], -0.7 * max(0.0, math.sin(w - 0.6)))
            self.swing(self.arm["L"][0], -0.3 * s, 0.10)
            self.swing(self.arm["R"][0], 0.3 * s, -0.10)
            self.swing(self.arm["L"][1], 0.35)
            self.swing(self.arm["R"][1], 0.35)
            self.hair.rotation_euler = (0, 0.15 + 0.08 * s, 0)
            self.hair2.rotation_euler = (0, 0.2 + 0.1 * math.sin(w - 0.9), 0)
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
                self.hair2.rotation_euler = (0, 0.5 * phase, 0)
        elif anim == "cast":
            lift = [0.5, 1.1, 1.45][i]
            for side in "LR":
                self.swing(self.arm[side][0], lift, 0.35 if side == "L" else -0.35)
                self.swing(self.arm[side][1], 0.5 - 0.2 * i)
            self.pelvis.location = (0, 0, 0.96 + 0.01 * i)
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
            self.hair2.rotation_euler = (0, -0.4, 0)


# --- Monsters -----------------------------------------------------------------------

class Wolf:
    """Acid-fang wolf: shoulders too high, flattened skull, uniform amber
    eyes. 1.3 m at the shoulder, faces +X. The body is one blended
    metaball surface; dark parts (muzzle, ears, paws) are meshes."""

    def __init__(self):
        r = self.root = empty("root")
        self.body = empty("body", r, (0, 0, 0.86))
        F = "WolfFur"
        mball(F, self.body, (0.30, 0, 0.02), (0.30, 0.20, 0.26), "fur")       # chest
        mball(F, self.body, (-0.02, 0, -0.02), (0.36, 0.18, 0.20), "fur")     # ribs
        mball(F, self.body, (-0.44, 0, -0.02), (0.22, 0.19, 0.23), "fur")     # haunches
        mball(F, self.body, (0.38, 0, 0.16), (0.17, 0.17, 0.14), "fur")       # the hump over the shoulders
        mball("WolfBelly", self.body, (-0.05, 0, -0.12), (0.38, 0.16, 0.13), "fur_light")
        self.neck = empty("neck", self.body, (0.52, 0, 0.14))
        mball(F, self.neck, (0.13, 0, 0.03), (0.19, 0.11, 0.12), "fur")
        self.head = empty("head", self.neck, (0.30, 0, 0.03))
        mball(F, self.head, (0.04, 0, 0.0), (0.17, 0.12, 0.10), "fur")        # flattened skull
        mball(F, self.head, (0.20, 0, -0.03), (0.15, 0.07, 0.06), "fur")      # muzzle
        blob("nose", self.head, (0.35, 0, -0.02), (0.05, 0.05, 0.045), "fur_dark")
        self.jaw = empty("jaw", self.head, (0.14, 0, -0.07))
        blob("jaw_c", self.jaw, (0.11, 0, -0.02), (0.22, 0.08, 0.045), "fur_dark")
        for y in (-0.08, 0.08):
            blob("ear", self.head, (-0.06, y, 0.10), (0.06, 0.03, 0.11), "fur_dark", rot=(0, math.radians(30), y * 3))
            sphere("eye", self.head, (0.14, y * 0.8, 0.035), (0.02, 0.022, 0.018), "amber")
        for y in (-0.035, 0.035):
            box("fang", self.jaw, (0.19, y, 0.005), (0.02, 0.012, 0.035), "white")
        self.tail = empty("tail", self.body, (-0.60, 0, 0.06))
        tube("tail_c", self.tail, (0, 0, 0), 0.015, 0.04, 0.38, "fur", rot=(0, math.radians(-115), 0))
        self.legs = {}
        for name, x, y in (("FL", 0.34, 0.13), ("FR", 0.34, -0.13), ("BL", -0.38, 0.13), ("BR", -0.38, -0.13)):
            hip = empty(f"hip{name}", self.body, (x, y, -0.06))
            mball(F, hip, (0, 0, -0.15), (0.12, 0.10, 0.23), "fur")
            kn = empty(f"knee{name}", hip, (0, 0, -0.36))
            mball(F, kn, (0, 0, -0.17), (0.085, 0.08, 0.21), "fur")
            blob("paw", kn, (0.04, 0, -0.40), (0.14, 0.09, 0.06), "fur_dark")
            self.legs[name] = (hip, kn)
        self.rest()

    def rest(self):
        self.root.location = (0, 0, 0)
        self.body.location = (0, 0, 0.86)
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
                self.body.location = (-0.15, 0, 0.72)
                self.body.rotation_euler = (0, -0.12, 0)
                for name, (hip, kn) in self.legs.items():
                    hip.rotation_euler = (0, -0.5 if name[0] == "B" else 0.4, 0)
                    kn.rotation_euler = (0, 0.9, 0)
            else:  # lunge
                s = 1.0 if i == 1 else 0.6
                self.root.location = (0.45 * s, 0, 0)
                self.body.location = (0, 0, 0.92)
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
    """Quill-bear: twice a natural bear, heavy brow, quills along the spine,
    red eyes. One blended body; dark muzzle, ears and paws."""

    def __init__(self):
        r = self.root = empty("root")
        self.body = empty("body", r, (0, 0, 1.15))
        F = "BearFur"
        mball(F, self.body, (0, 0, 0), (0.85, 0.50, 0.55), "bear")            # barrel
        mball(F, self.body, (0.50, 0, 0.16), (0.50, 0.50, 0.50), "bear")      # shoulders
        mball(F, self.body, (-0.62, 0, 0.02), (0.42, 0.46, 0.46), "bear")     # rump
        self.head = empty("head", self.body, (1.05, 0, 0.12))
        mball(F, self.head, (0.06, 0, 0.0), (0.30, 0.28, 0.27), "bear")       # skull
        mball(F, self.head, (0.24, 0, 0.10), (0.20, 0.24, 0.12), "bear")      # brow
        blob("snout", self.head, (0.40, 0, -0.06), (0.30, 0.24, 0.22), "bear_dark")
        blob("nose", self.head, (0.55, 0, -0.02), (0.07, 0.09, 0.06), "eye")
        for y in (-0.17, 0.17):
            blob("ear", self.head, (-0.04, y, 0.24), (0.11, 0.08, 0.11), "bear_dark")
            sphere("eye", self.head, (0.31, y * 0.6, 0.075), (0.03, 0.035, 0.03), "red")
        import random
        rng = random.Random(3)
        for k in range(13):
            x = -0.90 + k * 0.15
            h = rng.uniform(0.35, 0.62)
            cyl("quill", self.body, (x, rng.uniform(-0.07, 0.07), 0.46 + h / 2 - abs(x) * 0.12), 0.045, h, "quill", r2=0.005,
                rot=(0, math.radians(rng.uniform(-25, 10)), 0))
        self.legs = {}
        for name, x, y in (("FL", 0.58, 0.30), ("FR", 0.58, -0.30), ("BL", -0.62, 0.30), ("BR", -0.62, -0.30)):
            hip = empty(f"hip{name}", self.body, (x, y, -0.22))
            mball(F, hip, (0, 0, -0.28), (0.20, 0.17, 0.34), "bear")
            kn = empty(f"knee{name}", hip, (0, 0, -0.55))
            mball(F, kn, (0, 0, -0.16), (0.15, 0.14, 0.22), "bear")
            blob("paw", kn, (0.09, 0, -0.37), (0.32, 0.24, 0.10), "bear_dark")
            for c in range(3):
                box("claw", kn, (0.26, -0.07 + c * 0.07, -0.40), (0.06, 0.02, 0.025), "white")
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
