"""Model the environment props in Blender and export them as glTF.

    blender --background --python tools/blender_props.py -- <out_dir>

Low-poly, box-projected UVs, no materials: Godot assigns the pixel-art
textures by mesh name (Trunk, Canopy, Rock, Cliff) so the art stays in one
place. Meshes are exported with +Y up and metres as units.
"""
import math
import random
import sys

import bpy
import bmesh
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_object(name, bm, uv_scale=1.0):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    box_uv(mesh, uv_scale)
    # Geometry is authored Y-up (as Godot uses it); Blender is Z-up, so stand
    # it up here and let the exporter's Y-up conversion bring it back.
    obj.rotation_euler = (math.radians(90), 0, 0)
    return obj


def box_uv(mesh, scale):
    """Per-face planar projection along the dominant normal axis, so a tile
    texture wraps without stretching (a poor man's triplanar)."""
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            if ax == 0:
                u, w = v.y, v.z
            elif ax == 1:
                u, w = v.x, v.z
            else:
                u, w = v.x, v.y
            uv.data[li].uv = (u / scale, w / scale)


def cone_ring(bm, y, radius, segments, rng, jitter):
    verts = []
    for i in range(segments):
        a = i / segments * math.tau
        r = radius * (1 + rng.uniform(-jitter, jitter))
        verts.append(bm.verts.new((math.cos(a) * r, y + rng.uniform(-jitter, jitter) * radius * 0.6, math.sin(a) * r)))
    return verts


def pine(index, height, rng):
    """Trunk plus four ragged canopy tiers with drooping skirts, the shape of
    a mountain pine rather than a Christmas tree."""
    # Trunk
    bm = bmesh.new()
    segs = 7
    rings = []
    for k, (y, r) in enumerate(((0, 0.22), (height * 0.35, 0.16), (height * 0.75, 0.09), (height * 0.95, 0.04))):
        rings.append(cone_ring(bm, y, r, segs, rng, 0.08))
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    bm.faces.new(rings[0][::-1])
    trunk = new_object("Trunk", bm, 0.8)
    # Canopy tiers: each a cone with a jagged skirt, offset a little so the
    # silhouette isn't symmetric.
    bm = bmesh.new()
    tiers = 5
    for t in range(tiers):
        base_y = height * (0.22 + t * 0.15)
        top_y = base_y + height * 0.38
        radius = height * (0.24 - t * 0.038) * rng.uniform(0.9, 1.1)
        segs = 9
        off = Vector((rng.uniform(-0.12, 0.12), 0, rng.uniform(-0.12, 0.12))) * height * 0.3
        skirt = []
        for i in range(segs):
            a = i / segs * math.tau + rng.uniform(-0.15, 0.15)
            r = radius * rng.uniform(0.75, 1.15)
            droop = rng.uniform(-0.06, 0.03) * height
            skirt.append(bm.verts.new(Vector((math.cos(a) * r, base_y + droop, math.sin(a) * r)) + off))
        apex = bm.verts.new(Vector((0, top_y, 0)) + off * 0.5)
        inner = []
        for i in range(segs):
            a = i / segs * math.tau
            inner.append(bm.verts.new(Vector((math.cos(a) * radius * 0.35, base_y + height * 0.06, math.sin(a) * radius * 0.35)) + off))
        for i in range(segs):
            bm.faces.new((skirt[i], skirt[(i + 1) % segs], apex))
            # underside so the tier reads from below and casts a solid shadow
            bm.faces.new((skirt[(i + 1) % segs], skirt[i], inner[i], inner[(i + 1) % segs]))
    for f in bm.faces:
        f.smooth = True
    canopy = new_object("Canopy", bm, 1.2)
    return [trunk, canopy]


def boulder(index, size, rng):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts:
        n = v.co.normalized()
        d = 1.0 + rng.uniform(-0.28, 0.22)
        v.co = n * d
        v.co.x *= size * rng.uniform(0.9, 1.1) * 1.3
        v.co.y *= size * 0.75
        v.co.z *= size
        if v.co.y < -size * 0.25:  # flatten the bottom into the ground
            v.co.y = -size * 0.25
    # a few sharp facets
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(18), verts=bm.verts[:], edges=bm.edges[:])
    return [new_object("Rock", bm, 1.6)]


def cliff(index, length, height, rng):
    """A wall of stone with a stepped, noisy front face; sits along -Z."""
    bm = bmesh.new()
    cols, rows = 12, 4
    grid = []
    for r in range(rows + 1):
        row = []
        for c in range(cols + 1):
            x = (c / cols - 0.5) * length
            y = r / rows * height
            z = rng.uniform(-0.6, 0.6) + (0.9 if r == 0 else 0) - (r / rows) * 1.4
            if r == rows:
                z -= 0.8
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    # top cap and back so it is closed
    back = [bm.verts.new((v.co.x, v.co.y, v.co.z - 4.0)) for v in grid[rows]]
    for c in range(cols):
        bm.faces.new((grid[rows][c], grid[rows][c + 1], back[c + 1], back[c]))
    return [new_object("Cliff", bm, 1.6)]


# Crater height profile in metres; HD2D.crater_height() mirrors this exactly
# so the player and props sit on the surface.
def crater_height(r):
    bowl = -1.1 * max(0.0, 1.0 - (r / 3.4) ** 2) ** 1.2 if r < 3.4 else 0.0
    rim = 0.75 * math.exp(-((r - 4.0) / 0.9) ** 2)
    blanket = 0.15 * math.exp(-((r - 5.5) / 1.5) ** 2)
    return bowl + rim + blanket


def crater(rng):
    """Impact bowl with a raised rim and ejecta blanket, 16 m across, UV
    mapped planar so the radial crater texture drapes over it."""
    bm = bmesh.new()
    rings, segs = 26, 56
    radius = 8.0
    grid = []
    centre = bm.verts.new((0, crater_height(0), 0))
    for r in range(1, rings + 1):
        ring = []
        rr = radius * (r / rings) ** 1.15
        for sgm in range(segs):
            a = sgm / segs * math.tau
            h = crater_height(rr)
            # rough the rim and the blanket, keep the glass floor smooth
            rough = 0.02 if rr < 2.5 else (0.18 if rr < 5.0 else 0.06)
            h += rng.uniform(-rough, rough)
            ring.append(bm.verts.new((math.cos(a) * rr, h, math.sin(a) * rr)))
        grid.append(ring)
    for sgm in range(segs):
        bm.faces.new((centre, grid[0][(sgm + 1) % segs], grid[0][sgm]))
    for r in range(rings - 1):
        for sgm in range(segs):
            bm.faces.new((grid[r][sgm], grid[r][(sgm + 1) % segs], grid[r + 1][(sgm + 1) % segs], grid[r + 1][sgm]))
    for f in bm.faces:
        f.smooth = True
    mesh = bpy.data.meshes.new("Crater")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Crater", mesh)
    bpy.context.scene.collection.objects.link(obj)
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (v.x / 16.0 + 0.5, v.z / 16.0 + 0.5)
    obj.rotation_euler = (math.radians(90), 0, 0)
    return [obj]


def log(index, length, rng):
    """Fallen trunk lying along +Z with a splintered broken end at the origin."""
    bm = bmesh.new()
    segs = 8
    rings = []
    for k, (z, r) in enumerate(((0.0, 0.30), (length * 0.3, 0.27), (length * 0.7, 0.22), (length, 0.16))):
        ring = []
        for i in range(segs):
            a = i / segs * math.tau
            rr = r * rng.uniform(0.9, 1.1)
            # broken end: ragged
            zz = z + (rng.uniform(-0.25, 0.1) if k == 0 else 0)
            ring.append(bm.verts.new((math.cos(a) * rr, r + math.sin(a) * rr, zz)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    # a couple of branch stubs
    for _ in range(2):
        z = rng.uniform(length * 0.3, length * 0.9)
        ang = rng.uniform(0.3, 2.6)
        base = (math.cos(ang) * 0.2, 0.25 + math.sin(ang) * 0.2, z)
        tip = (math.cos(ang) * 0.9, 0.25 + math.sin(ang) * 0.9 + 0.2, z + rng.uniform(-0.3, 0.3))
        ring_a, ring_b = [], []
        for i in range(5):
            a = i / 5 * math.tau
            ring_a.append(bm.verts.new((base[0] + math.cos(a) * 0.07, base[1] + math.sin(a) * 0.07, base[2])))
            ring_b.append(bm.verts.new((tip[0] + math.cos(a) * 0.03, tip[1] + math.sin(a) * 0.03, tip[2])))
        for i in range(5):
            bm.faces.new((ring_a[i], ring_a[(i + 1) % 5], ring_b[(i + 1) % 5], ring_b[i]))
    return [new_object("Trunk", bm, 0.8)]


def stump(index, rng):
    bm = bmesh.new()
    segs = 8
    height = rng.uniform(0.5, 1.2)
    bottom, top = [], []
    for i in range(segs):
        a = i / segs * math.tau
        bottom.append(bm.verts.new((math.cos(a) * 0.32, 0, math.sin(a) * 0.32)))
        top.append(bm.verts.new((math.cos(a) * 0.26, height + rng.uniform(-0.25, 0.25), math.sin(a) * 0.26)))
    for i in range(segs):
        bm.faces.new((bottom[i], bottom[(i + 1) % segs], top[(i + 1) % segs], top[i]))
    bm.faces.new(top[::-1])
    return [new_object("Trunk", bm, 0.8)]


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="NONE", export_yup=True)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)


if __name__ == "__main__":
    reset()
    rng = random.Random(7)
    for i in range(3):
        export(pine(i, [4.2, 5.4, 6.5][i], rng), f"pine_{i}")
    for i in range(3):
        export(boulder(i, [0.6, 1.0, 1.5][i], rng), f"boulder_{i}")
    for i in range(2):
        export(cliff(i, 16.0, [5.0, 7.0][i], rng), f"cliff_{i}")
    export(crater(rng), "crater")
    for i in range(3):
        export(log(i, [4.0, 5.5, 7.0][i], rng), f"log_{i}")
    for i in range(2):
        export(stump(i, rng), f"stump_{i}")
    print("PROPS OK")
