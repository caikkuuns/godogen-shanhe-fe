#!/usr/bin/env python3
"""Shen Yan v4: measured from ref3d front/side + turnaround; scripted, subdivided cloth.

No MakeHuman/MPFB2 base mesh is installed locally, so the body is built from a
Blender Skin modifier skeleton and smooth-subdivided. All clothing, hair, boots
and the sword are continuous lofts/tubes/ribbons (no cube or cylinder kit).
Local Blender only; no network or paid APIs.
"""
import argparse
import math
import os
import subprocess
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

TAU = math.tau
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLB_PATH = os.path.join(ROOT, "assets", "glb", "shenyan_script.glb")
PREVIEW_PATH = os.path.join(ROOT, "captures", "shenyan_3d_preview.png")
COMPARE_PATH = os.path.join(ROOT, "captures", "shenyan_3d_compare.png")
RENDER_DIR = "/tmp/shenyan_views"
REF_FRONT = "/workspace/wuxia-team/art/characters/ref3d/shenyan_front.png"
REF_SIDE = "/workspace/wuxia-team/art/characters/ref3d/shenyan_side.png"
REF_ORTHO = 1.865

MATS = {}
_NORM = {"scale": 1.0, "zmin": 0.0}


def srgb(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h):
    r, g, b = (int(h.lstrip('#')[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (srgb(r), srgb(g), srgb(b), 1.0)


def mat(name, hex_code, rough=0.92):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    col = hex_lin(hex_code)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = col
    m.roughness = rough
    MATS[name] = m
    return m


def clean():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions,
                  bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for x in list(block):
            if x.users == 0:
                block.remove(x)
    MATS.clear()


def shade_smooth(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    obj.select_set(False)


def new_mesh(name, verts, faces, material, subsurf=0, solidify=0.0, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if solidify > 0:
        md = obj.modifiers.new("Solidify", "SOLIDIFY")
        md.thickness = solidify
        md.offset = 0.0
        bpy.ops.object.modifier_apply(modifier=md.name)
    if subsurf > 0:
        md = obj.modifiers.new("Subsurf", "SUBSURF")
        md.levels = subsurf
        md.render_levels = subsurf
        bpy.ops.object.modifier_apply(modifier=md.name)
    if smooth:
        bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def add_loft(name, rings, material, sides=16, subsurf=1, caps=True):
    verts = []
    for ring in rings:
        z, rx, ry = ring[:3]
        cx = ring[3] if len(ring) > 3 else 0.0
        cy = ring[4] if len(ring) > 4 else 0.0
        for i in range(sides):
            a = TAU * i / sides
            verts.append((cx + rx * math.cos(a), cy + ry * math.sin(a), z))
    faces = []
    for r in range(len(rings) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((r * sides + i, r * sides + j,
                          (r + 1) * sides + j, (r + 1) * sides + i))
    if caps:
        faces.append(tuple(range(sides - 1, -1, -1)))
        base = (len(rings) - 1) * sides
        faces.append(tuple(base + i for i in range(sides)))
    return new_mesh(name, verts, faces, material, subsurf=subsurf)


def add_tube(name, points, radii, material, sides=12, subsurf=1, caps=True):
    pts = [Vector(p) for p in points]
    tangents = []
    for i in range(len(pts)):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        tangents.append(t.normalized())
    n = Vector((1.0, 0.0, 0.0))
    if abs(n.dot(tangents[0])) > 0.9:
        n = Vector((0.0, 1.0, 0.0))
    n = (n - tangents[0] * n.dot(tangents[0])).normalized()
    verts = []
    prev_t = tangents[0]
    for i, p in enumerate(pts):
        t = tangents[i]
        if i > 0:
            q = prev_t.rotation_difference(t)
            n = (q @ n) - t * (q @ n).dot(t)
            n.normalize()
            prev_t = t
        b = t.cross(n).normalized()
        rx, ry = radii[i]
        for k in range(sides):
            a = TAU * k / sides
            verts.append(tuple(p + n * (math.cos(a) * rx) + b * (math.sin(a) * ry)))
    faces = []
    for r in range(len(pts) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((r * sides + i, r * sides + j,
                          (r + 1) * sides + j, (r + 1) * sides + i))
    if caps:
        faces.append(tuple(range(sides - 1, -1, -1)))
        base = (len(pts) - 1) * sides
        faces.append(tuple(base + i for i in range(sides)))
    return new_mesh(name, verts, faces, material, subsurf=subsurf)


def add_ribbon(name, points, width, thickness, material, normal_hint=(0, -1, 0),
               subsurf=1):
    pts = [Vector(p) for p in points]
    hint = Vector(normal_hint)
    rows = []
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        t.normalize()
        n = hint - t * hint.dot(t)
        if n.length < 1e-5:
            n = Vector((0, 0, 1)) - t * t.z
        n.normalize()
        w = n.cross(t).normalized()
        row = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            row.append(tuple(p + w * (a * width * 0.5) + n * (b * thickness * 0.5)))
        rows.append(row)
    verts = [v for row in rows for v in row]
    faces = []
    for r in range(len(rows) - 1):
        for i in range(4):
            j = (i + 1) % 4
            faces.append((r * 4 + i, r * 4 + j, (r + 1) * 4 + j, (r + 1) * 4 + i))
    faces.append((0, 1, 2, 3))
    base = (len(rows) - 1) * 4
    faces.append((base + 3, base + 2, base + 1, base + 0))
    return new_mesh(name, verts, faces, material, subsurf=subsurf)


def add_ellipsoid(name, loc, scale, material, seg=16, rings=10, subsurf=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings,
                                         radius=1.0, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.data.materials.append(material)
    if subsurf:
        md = o.modifiers.new("Subsurf", "SUBSURF")
        md.levels = subsurf
        bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.ops.object.shade_smooth()
    return o


def P(x, y, z):
    s = _NORM["scale"]
    return Vector((x * s, y * s, (z - _NORM["zmin"]) * s))


def normalize(target=1.70):
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    zmin = min((o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices)
    zmax = max((o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices)
    s = target / (zmax - zmin)
    for o in meshes:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            v.co = Vector((p.x * s, p.y * s, (p.z - zmin) * s))
        o.data.update()
    _NORM["scale"] = s
    _NORM["zmin"] = zmin
    bpy.context.view_layer.update()


def tris():
    total = 0
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            total += len(o.data.loop_triangles)
    return total


# --------------------------------------------------------------- measurements
# All coordinates are metres in the final 1.70 m space (soles z=0, front -Y),
# measured from ref3d/shenyan_front.png + shenyan_side.png (1400 px = 1.70 m)
# and shenyan_turnaround_v2.png (scabbard length / angle).
SH = (0.140, 1.370)      # shoulder joint (x, z)
EL = (0.270, 1.145)      # elbow
WR = (0.385, 0.955)      # wrist
HT = (0.440, 0.835)      # hand tip
HIP = (0.085, 0.900)
KNEE = (0.100, 0.490)
ANK = (0.112, 0.090)

# robe silhouette: z -> (rx, ry, cy)
PROFILE = [
    (0.400, 0.238, 0.186, 0.000),
    (0.550, 0.214, 0.166, 0.000),
    (0.720, 0.188, 0.147, 0.000),
    (0.850, 0.166, 0.131, 0.000),
    (0.950, 0.150, 0.119, 0.000),
    (1.030, 0.134, 0.103, -0.004),
    (1.100, 0.132, 0.101, -0.008),
    (1.200, 0.150, 0.112, -0.012),
    (1.300, 0.162, 0.118, -0.014),
    (1.355, 0.160, 0.112, -0.008),
    (1.400, 0.128, 0.094, 0.000),
    (1.432, 0.078, 0.066, 0.004),
    (1.452, 0.056, 0.052, 0.006),
]


def prof(z):
    if z <= PROFILE[0][0]:
        return PROFILE[0][1:]
    for a, b in zip(PROFILE, PROFILE[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            t = t * t * (3 - 2 * t)
            return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3))
    return PROFILE[-1][1:]


def surf(x, z, side=-1, off=0.006):
    """Point on the robe surface (front side=-1, back side=+1)."""
    rx, ry, cy = prof(z)
    u = max(-0.97, min(0.97, x / rx))
    return (x, cy + side * (ry * math.sqrt(1 - u * u) + off), z)


def lerp2(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


# ------------------------------------------------------------------- body
def build_body():
    """Skin-modifier neck (arms are bandage + hand; torso/legs are under cloth)."""
    verts, edges, radii, idx = [], [], [], {}

    def V(name, x, y, z, rx, ry):
        idx[name] = len(verts)
        verts.append((x, y, z))
        radii.append((rx, ry))
        return idx[name]

    pelvis = V("pelvis", 0, 0, 1.30, 0.07, 0.05)
    upper = V("upper", 0, 0, 1.36, 0.070, 0.050)
    neck = V("neck", 0, 0.004, 1.43, 0.038, 0.038)
    ntop = V("ntop", 0, 0.004, 1.49, 0.036, 0.036)
    edges += [(pelvis, upper), (upper, neck), (neck, ntop)]
    me = bpy.data.meshes.new("BodyMesh")
    me.from_pydata(verts, edges, [])
    me.update()
    obj = bpy.data.objects.new("Body", me)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    md = obj.modifiers.new("Skin", "SKIN")
    data = me.skin_vertices[0].data
    for i, (rx, ry) in enumerate(radii):
        data[i].radius = (rx, ry)
    data[pelvis].use_root = True
    bpy.ops.object.modifier_apply(modifier=md.name)
    md = obj.modifiers.new("Subsurf", "SUBSURF")
    md.levels = 1
    bpy.ops.object.modifier_apply(modifier=md.name)
    obj.data.materials.append(mat("skin", "#E6C4A8"))
    bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def add_sheet(name, rings, a0, a1, cols, material, solidify=0.008, subsurf=1):
    """Open curved cloth panel. rings: (z, rx, ry, cy); angle 270 = front."""
    verts, faces = [], []
    for z, rx, ry, cy in rings:
        for j in range(cols + 1):
            a = math.radians(a0 + (a1 - a0) * j / cols)
            verts.append((rx * math.cos(a), cy + ry * math.sin(a), z))
    for r in range(len(rings) - 1):
        for j in range(cols):
            i = r * (cols + 1) + j
            faces.append((i, i + 1, i + cols + 2, i + cols + 1))
    return new_mesh(name, verts, faces, material, subsurf=subsurf, solidify=solidify)


def add_tube_s(name, points, radii, material, sides=12, subsurf=1, solidify=0.0):
    """Open tube (no caps) with a solidified wall: sleeves, cuffs."""
    o = add_tube(name, points, radii, material, sides, 0, caps=False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    if solidify:
        md = o.modifiers.new("Solidify", "SOLIDIFY"); md.thickness = solidify; md.offset = 0
        bpy.ops.object.modifier_apply(modifier=md.name)
    if subsurf:
        md = o.modifiers.new("Subsurf", "SUBSURF"); md.levels = subsurf
        bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.ops.object.shade_smooth()
    o.select_set(False)
    return o


# ------------------------------------------------------------------ clothes
def build_character():
    clean()
    white = mat("robe_white", "#ECEBE6")
    shade = mat("robe_fold", "#DAD8D2")
    ice = mat("trim_ice", "#A9C3E2")
    blue = mat("sash_stone_blue", "#5B78A6")
    pants_m = mat("pants_white", "#E9E7E1")
    boot_m = mat("boot_grey", "#7C7F86", 0.86)
    dark = mat("sole_dark", "#4A4D53", 0.9)
    hair = mat("hair_ink", "#1B1C22")
    skin = mat("skin", "#E6C4A8")
    band = mat("bandage_white", "#EFEDE7")
    band2 = mat("bandage_shade", "#C9C5BC")
    scab = mat("scabbard_brown", "#4A3328", 0.7)
    wrap = mat("hilt_wrap_black", "#16171C", 0.8)
    grip_m = mat("hilt_grip", "#34343B", 0.8)
    brass = mat("copper_guard", "#9A6538", 0.35)
    eye = mat("eye_dark", "#221E1C")
    mouthm = mat("mouth", "#B07A72")
    ribbon = mat("ribbon_white", "#F6F4EE")

    body = build_body()
    parts = [body]

    # --- robe torso (depth: chest forward, cinched waist)
    rings = [(z, rx, ry, 0.0, cy) for z, rx, ry, cy in PROFILE if 0.94 <= z]
    parts.append(add_loft("robe_torso", rings, white, 16, subsurf=1, caps=False))

    # --- skirt: closed to mid-thigh, then front/back panels with side slits
    skirt_rows = [(z, *prof(z)) for z in (1.03, 0.90, 0.74, 0.62, 0.52, 0.44)]
    parts.append(add_skirt_slit("skirt", skirt_rows, 24, 3, white))
    hem = [(z, rx * 1.012, ry * 1.012, cy) for z, (rx, ry, cy) in ((0.445, prof(0.445)), (0.40, prof(0.40)))]
    panels = (("front", 196, 344), ("back", 16, 164))
    for nm, a0, a1 in panels:
        parts.append(add_sheet("hem_" + nm, hem, a0, a1, 8, ice, 0.010))
        for tag, ang in (("a", a0), ("b", a1)):
            a = math.radians(ang)
            pts = []
            for z in (0.74, 0.60, 0.50, 0.42):
                rx, ry, cy = prof(z)
                pts.append((rx * 1.01 * math.cos(a), cy + ry * 1.01 * math.sin(a), z))
            parts.append(add_ribbon(f"slit_trim_{nm}{tag}", pts, 0.026, 0.010, ice,
                                    (math.cos(a), math.sin(a), 0.0), 1))
    # front wrap edge of the outer robe (right-over-left), runs to the hem
    pts = [surf(-0.085 + 0.01 * i, z, -1, 0.012) for i, z in enumerate((0.99, 0.82, 0.62, 0.45))]
    parts.append(add_ribbon("wrap_edge_trim", pts, 0.030, 0.008, ice, (0, -1, 0), 1))
    # a couple of soft vertical folds for cloth read
    for i, x in enumerate(()):
        pts = [surf(x * f, z, -1, 0.010) for f, z in ((0.8, 0.95), (1.0, 0.70), (1.1, 0.47))]
        parts.append(add_ribbon(f"fold_{i}", pts, 0.012, 0.004, shade, (0, -1, 0), 1))

    # --- cross collar: neck band + outer lapel (left neck -> right waist)
    parts.append(add_loft("collar_band", [(1.405, 0.070, 0.064, 0, 0.006),
                                          (1.462, 0.050, 0.048, 0, 0.008)],
                          ice, 16, 1, caps=False))
    lap = [(0.052, 1.445), (0.040, 1.40), (0.010, 1.33), (-0.040, 1.24),
           (-0.085, 1.15), (-0.100, 1.07)]
    parts.append(add_ribbon("lapel_outer", [surf(x, z, -1, 0.012) for x, z in lap],
                            0.050, 0.010, ice, (0, -1, 0), 1))
    lap2 = [(-0.052, 1.445), (-0.040, 1.40), (-0.020, 1.355)]
    parts.append(add_ribbon("lapel_inner", [surf(x, z, -1, 0.008) for x, z in lap2],
                            0.040, 0.008, ice, (0, -1, 0), 1))
    parts.append(add_ribbon("inner_collar", [surf(x, z, -1, 0.004) for x, z in
                                             ((0.040, 1.43), (0.0, 1.36), (-0.030, 1.42))],
                            0.022, 0.006, white, (0, -1, 0), 1))

    # --- sash, knot on the wearer's right front, long tails
    parts.append(add_loft("sash", [(1.000, 0.140, 0.109, 0, -0.004),
                                   (1.055, 0.137, 0.106, 0, -0.006),
                                   (1.110, 0.139, 0.108, 0, -0.008)], blue, 20, 1, caps=False))
    kx = -0.068
    kp = surf(kx, 1.055, -1, 0.028)
    parts.append(add_ellipsoid("sash_knot", kp, (0.040, 0.026, 0.034), blue, 12, 8, 0))
    parts.append(add_ellipsoid("sash_loop", (kx - 0.03, kp[1] + 0.004, 1.03),
                               (0.030, 0.018, 0.040), blue, 10, 6, 0))
    for i, (x0, x1, zb, w) in enumerate(((-0.072, -0.095, 0.60, 0.060),
                                         (-0.060, -0.040, 0.68, 0.050),
                                         (-0.080, -0.130, 0.80, 0.040))):
        pts = []
        for t in (0.0, 0.33, 0.66, 1.0):
            z = 1.04 + (zb - 1.04) * t
            x = x0 + (x1 - x0) * t
            pts.append(surf(x, z, -1, 0.022 + 0.004 * i - 0.008 * t))
        parts.append(add_ribbon(f"sash_tail{i}", pts, w, 0.010, blue, (0, -1, 0), 1))

    # --- wide drooping sleeves, ice cuffs, bandaged forearms, hands
    for s, sx in (("L", 1), ("R", -1)):
        cl = [(0.090, 1.372), (0.150, 1.330), (0.197, 1.225), (0.237, 1.068), (0.275, 0.995)]
        rr = [(0.044, 0.050), (0.056, 0.056), (0.074, 0.068), (0.096, 0.085), (0.108, 0.092)]
        pts = [(x * sx, 0.0, z) for x, z in cl]
        parts.append(add_tube_s(f"sleeve_{s}", pts, rr, white, 8, 1, 0.008))
        a = Vector(pts[3]).lerp(Vector(pts[4]), 0.45)
        parts.append(add_tube_s(f"cuff_{s}", [tuple(a), pts[4]],
                                [(0.106, 0.091), (0.111, 0.095)], ice, 16, 0, 0.010))
        b0 = lerp2(EL, WR, 0.35)
        wv = Vector((WR[0] * sx, 0.0, WR[1]))
        d = (wv - Vector((b0[0] * sx, 0.0, b0[1]))).normalized()
        bp = [(b0[0] * sx, 0.0, b0[1]), tuple(wv.lerp(Vector((b0[0] * sx, 0.0, b0[1])), 0.5)),
              tuple(wv + d * 0.012)]
        parts.append(add_tube(f"bandage_{s}", bp, [(0.033, 0.031), (0.031, 0.029), (0.028, 0.026)],
                              band, 8, 1))
        # criss-cross wrap lines spiralling down the forearm
        a0 = Vector(bp[0]); a1 = Vector(bp[2]) - d * 0.008
        nrm = Vector((0, 1, 0)); bin_ = d.cross(nrm).normalized()
        for k, sgn in enumerate((1, -1)):
            pts = []
            for q in range(15):
                t = q / 14
                ang = sgn * t * TAU * 2.5 + k * 1.3
                r = 0.033 - 0.004 * t
                pts.append(tuple(a0.lerp(a1, t) + (nrm * math.cos(ang) + bin_ * math.sin(ang)) * r))
            parts.append(add_tube(f"bandage_line{k}_{s}", pts, [(0.0022, 0.0022)] * len(pts),
                                  band2, 4, 0, caps=False))
        w = wv - d * 0.010
        tip = Vector((HT[0] * sx, -0.008, HT[1]))
        hp = [tuple(w), tuple(w.lerp(tip, 0.40)), tuple(w.lerp(tip, 0.78)), tuple(tip)]
        parts.append(add_tube(f"hand_{s}", hp, [(0.026, 0.020), (0.037, 0.017),
                                                 (0.032, 0.013), (0.017, 0.008)], skin, 8, 1))

    # --- loose white trousers gathered into grey knee-high soft boots
    for s, sx in (("L", 1), ("R", -1)):
        parts.append(add_loft(f"pants_{s}", [
            (0.76, 0.086, 0.090, 0.086 * sx, 0.0),
            (0.40, 0.084, 0.088, 0.104 * sx, -0.006),
            (0.34, 0.090, 0.092, 0.108 * sx, -0.006),
            (0.295, 0.072, 0.075, 0.111 * sx, -0.002),
            (0.262, 0.050, 0.054, 0.112 * sx, 0.002)], pants_m, 10, 1, caps=False))
        x = ANK[0] * sx
        parts.append(add_loft(f"boot_shaft_{s}", [
            (0.292, 0.060, 0.063, x, 0.004), (0.268, 0.057, 0.060, x, 0.004),
            (0.180, 0.050, 0.054, x, 0.002), (0.110, 0.047, 0.052, x, 0.000),
            (0.070, 0.049, 0.056, x, -0.004)], boot_m, 10, 1, caps=True))
        foot = [(x, 0.036, 0.050), (x, -0.004, 0.056), (x, -0.055, 0.046),
                (x, -0.095, 0.034), (x, -0.126, 0.027)]
        frad = [(0.041, 0.044), (0.049, 0.050), (0.048, 0.040), (0.043, 0.029), (0.028, 0.019)]
        parts.append(add_tube(f"boot_foot_{s}", foot, frad, boot_m, 8, 1))
        sole = [(x, 0.040, 0.011), (x, -0.010, 0.010), (x, -0.070, 0.010), (x, -0.130, 0.012)]
        srad = [(0.043, 0.011), (0.051, 0.011), (0.050, 0.011), (0.034, 0.010)]
        parts.append(add_tube(f"boot_sole_{s}", sole, srad, dark, 12, 0))
        parts.append(add_ribbon(f"boot_seam_{s}", [(x, -0.052, 0.27), (x, -0.050, 0.14),
                                                   (x, -0.062, 0.085), (x, -0.105, 0.062)],
                                0.006, 0.004, dark, (0, -1, 0), 0))

    build_head(parts, skin, hair, ribbon, eye, mouthm)
    build_sword(parts, scab, wrap, brass, ice, grip_m)
    normalize(1.70)
    setup_ref_cams()
    print("SHENYAN tris=", tris())
    stats = {}
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            k = o.name.rstrip('_LR0123456789')
            stats[k] = stats.get(k, 0) + len(o.data.loop_triangles)
    print("TRIS_BY", sorted(stats.items(), key=lambda kv: -kv[1])[:40])
    return parts


def add_skirt_slit(name, rows, cols, slit_rows, material, solidify=0.008):
    """One-piece skirt (no seams); the lowest rows open at both sides."""
    verts, faces = [], []
    for z, rx, ry, cy in rows:
        for j in range(cols):
            a = TAU * j / cols
            verts.append((rx * math.cos(a), cy + ry * math.sin(a), z))
    for r in range(len(rows) - 1):
        for j in range(cols):
            jn = (j + 1) % cols
            if r >= len(rows) - 1 - slit_rows and (j in (0, cols - 1) or j in (cols // 2 - 1, cols // 2)):
                continue
            faces.append((r * cols + j, r * cols + jn, (r + 1) * cols + jn, (r + 1) * cols + j))
    return new_mesh(name, verts, faces, material, subsurf=1, solidify=solidify)


def cut_face(op, cy, z_hair):
    me = op.data
    bm = bmesh.new()
    bm.from_mesh(me)
    doomed = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z < z_hair - 0.4 * max(0.0, abs(c.x) - 0.03) and c.y < cy + 0.014:
            doomed.append(f)
        elif c.z < 1.512 and c.y < 0.050:
            doomed.append(f)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()


def build_head(parts, skin, hair, ribbon, eye, mouthm):
    HC = Vector((0.0, -0.004, 1.553))
    RX, RY, RZ = 0.074, 0.087, 0.098
    head = add_ellipsoid("head", tuple(HC), (RX, RY, RZ), skin, 16, 12, 0)
    for v in head.data.vertices:
        dz = (HC.z - v.co.z) / RZ
        if dz > 0:  # jaw taper and pointed chin
            v.co.x *= 1.0 - 0.38 * dz ** 1.6
            if v.co.y < HC.y:
                v.co.y = HC.y + (v.co.y - HC.y) * (1.0 - 0.10 * dz)
        if v.co.y > HC.y + 0.03:  # flatter back of skull
            v.co.y = HC.y + 0.03 + (v.co.y - HC.y - 0.03) * 0.92
    head.data.update()
    parts.append(head)

    def front_y(x, z, off):
        dz = (z - HC.z) / RZ
        rx = RX * ((1.0 - 0.38 * max(0, -dz) ** 1.6) if dz < 0 else 1.0)
        k = max(0.0, 1 - dz * dz - (x / rx) ** 2)
        return HC.y - RY * math.sqrt(k) - off

    for s, sx in (("L", 1), ("R", -1)):
        parts.append(add_ellipsoid(f"ear_{s}", (0.068 * sx, 0.004, 1.548),
                                   (0.011, 0.018, 0.026), skin, 6, 4, 0))
        ex, ez = 0.029 * sx, 1.562
        parts.append(add_ellipsoid(f"eye_{s}", (ex, front_y(ex, ez, -0.001), ez),
                                   (0.014, 0.004, 0.0055), eye, 8, 5, 0))
        parts.append(add_ribbon(f"brow_{s}", [(0.012 * sx, front_y(0.012, 1.583, 0.001), 1.581),
                                              (0.030 * sx, front_y(0.030, 1.587, 0.001), 1.587),
                                              (0.048 * sx, front_y(0.048, 1.585, 0.000), 1.584)],
                                0.0045, 0.003, hair, (0.0, -1.0, 0.0), 0))
    parts.append(add_ellipsoid("nose", (0.0, front_y(0, 1.540, 0.004), 1.540),
                               (0.008, 0.012, 0.020), skin, 8, 6, 0))
    parts.append(add_ribbon("mouth", [(-0.012, front_y(0.012, 1.505, 0.0), 1.505),
                                      (0.0, front_y(0.0, 1.504, 0.001), 1.504),
                                      (0.012, front_y(0.012, 1.505, 0.0), 1.505)],
                            0.0035, 0.003, mouthm, (0.0, -1.0, 0.0), 0))

    # hair: skull cap (face cut out), high topknot with white ribbon
    cap = add_ellipsoid("hair_cap", (0.0, 0.006, 1.566), (0.081, 0.095, 0.094), hair, 16, 10, 0)
    for v in cap.data.vertices:  # fuller crown, hair falls to nape
        if v.co.z > 1.58:
            v.co.z += 0.010 * (v.co.z - 1.58) / 0.08
        if v.co.y > 0.03 and v.co.z < 1.52:
            v.co.z -= 0.015
    cap.data.update()
    cut_face(cap, -0.004, 1.605)
    bpy.context.view_layer.objects.active = cap; cap.select_set(True)
    md = cap.modifiers.new("Sub", "SUBSURF"); md.levels = 1
    bpy.ops.object.modifier_apply(modifier=md.name); cap.select_set(False)
    parts.append(cap)
    parts.append(add_ellipsoid("hair_bun", (0.0, 0.033, 1.664), (0.038, 0.038, 0.036), hair, 14, 9, 0))
    parts.append(add_tube("bun_band", [(0.0, 0.031, 1.648), (0.0, 0.033, 1.660)],
                          [(0.031, 0.031), (0.031, 0.031)], ribbon, 12, 1))
    for s, sx in (("L", 1), ("R", -1)):
        parts.append(add_ellipsoid(f"bun_bow_{s}", (0.030 * sx, 0.058, 1.656),
                                   (0.024, 0.008, 0.013), ribbon, 8, 5, 0))
        parts.append(add_ribbon(f"bun_tail_{s}", [(0.010 * sx, 0.062, 1.650),
                                                  (0.030 * sx, 0.090, 1.610),
                                                  (0.040 * sx, 0.106, 1.560)],
                                0.016, 0.004, ribbon, (0.0, 1.0, 0.0), 1))
    # bangs: centre-parted strands sweeping to the temples
    for s, sx in (("L", 1), ("R", -1)):
        for i, (x1, z1, r, xm) in enumerate(((0.036, 1.590, 0.013, 0.016), (0.062, 1.568, 0.011, 0.040),
                                              (0.016, 1.600, 0.010, 0.008))):
            zt = 1.660 - 0.006 * i
            p0 = (0.004 * sx, front_y(0.004, zt, 0.0) + 0.012, zt)
            zm = (zt + z1) / 2 + 0.010
            pm = (xm * sx, front_y(xm, zm, 0.014), zm)
            p1 = (x1 * sx, front_y(x1, z1, 0.008), z1)
            parts.append(add_tube(f"fringe{i}_{s}", [p0, pm, p1],
                                  [(r, r * 0.6), (r * 0.85, r * 0.5), (0.003, 0.002)], hair, 6, 1))
        # long side locks framing the face, down to the jaw
        parts.append(add_ribbon(f"sidelock_{s}", [(0.056 * sx, -0.058, 1.615),
                                                  (0.071 * sx, -0.050, 1.560),
                                                  (0.066 * sx, -0.046, 1.505),
                                                  (0.058 * sx, -0.040, 1.462)],
                                0.016, 0.005, hair, (sx * 0.4, -1.0, 0.0), 1))


def build_sword(parts, scab, wrap, brass, ice, grip_m):
    tip = Vector((0.170, 0.125, 0.740))
    guard = Vector((-0.140, 0.125, 1.350))
    d = (guard - tip).normalized()
    pommel = guard + d * 0.185
    print("SWORD length", round((pommel - tip).length, 3), "pommel", tuple(round(c, 3) for c in pommel))
    parts.append(add_tube("scabbard", [tuple(tip), tuple(tip.lerp(guard, 0.5)), tuple(guard - d * 0.012)],
                          [(0.019, 0.013), (0.021, 0.014), (0.023, 0.015)], scab, 10, 1))
    parts.append(add_tube("scab_chape", [tuple(tip - d * 0.006), tuple(tip + d * 0.045)],
                          [(0.016, 0.011), (0.021, 0.014)], brass, 10, 1))
    parts.append(add_tube("scab_mouth", [tuple(guard - d * 0.055), tuple(guard - d * 0.012)],
                          [(0.025, 0.017), (0.025, 0.017)], brass, 10, 1))
    parts.append(add_tube("guard", [tuple(guard - d * 0.008), tuple(guard + d * 0.008)],
                          [(0.040, 0.026), (0.040, 0.026)], brass, 14, 1))
    parts.append(add_tube("grip", [tuple(guard), tuple(pommel)],
                          [(0.0155, 0.0145), (0.0135, 0.0125)], grip_m, 10, 1))
    for i in range(5):
        p = guard.lerp(pommel, 0.14 + 0.16 * i)
        parts.append(add_tube(f"grip_cord{i}", [tuple(p - d * 0.007), tuple(p + d * 0.007)],
                              [(0.0160, 0.0150), (0.0150, 0.0140)], wrap, 8, 0))
    parts.append(add_ellipsoid("pommel", tuple(pommel), (0.016, 0.016, 0.014), brass, 10, 6, 0))
    top = pommel + Vector((0.0, 0.004, -0.012))
    knot = top + Vector((0.0, 0.004, -0.045))
    parts.append(add_tube("tassel_cord", [tuple(top), tuple(knot)], [(0.004, 0.004)] * 2, ice, 6, 0))
    parts.append(add_ellipsoid("tassel_knot", tuple(knot), (0.010, 0.010, 0.012), ice, 8, 6, 0))
    for i, (dx, dy) in enumerate(((-0.008, 0), (0.008, 0), (0, -0.008), (0, 0.008), (0, 0))):
        p0 = knot + Vector((dx * 0.5, dy * 0.5, -0.008))
        p1 = knot + Vector((dx * 1.4, dy * 1.4, -0.175))
        parts.append(add_tube(f"tassel_{i}", [tuple(p0), tuple(p1)],
                              [(0.006, 0.006), (0.003, 0.003)], ice, 6, 0))


# ------------------------------------------------------------------- rig
BONES = ["hips", "spine", "chest", "neck", "head",
         "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R",
         "hand.L", "hand.R", "thigh.L", "thigh.R", "shin.L", "shin.R",
         "foot.L", "foot.R"]


def build_rig(parts):
    ad = bpy.data.armatures.new("ShenyanArmature")
    arm = bpy.data.objects.new("ShenyanArmature", ad)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = ad.edit_bones

    def mk(n, h, t, parent=None, conn=False):
        b = eb.new(n)
        b.head = h
        b.tail = t
        b.use_deform = n != "root"
        if parent:
            b.parent = eb[parent]
            b.use_connect = conn
        return b

    mk("root", P(0, 0, 0), P(0, 0, 0.12))
    mk("hips", P(0, 0, 0.90), P(0, 0, 1.02), "root")
    mk("spine", P(0, 0, 1.02), P(0, 0, 1.20), "hips", True)
    mk("chest", P(0, 0, 1.20), P(0, 0, 1.38), "spine", True)
    mk("neck", P(0, 0, 1.38), P(0, 0, 1.47), "chest", True)
    mk("head", P(0, 0, 1.47), P(0, 0, 1.68), "neck", True)
    for s, sx in (("L", 1), ("R", -1)):
        mk(f"upper_arm.{s}", P(SH[0] * sx, 0, SH[1]), P(EL[0] * sx, 0, EL[1]), "chest")
        mk(f"forearm.{s}", P(EL[0] * sx, 0, EL[1]), P(WR[0] * sx, 0, WR[1]),
           f"upper_arm.{s}", True)
        mk(f"hand.{s}", P(WR[0] * sx, 0, WR[1]), P(HT[0] * sx, -0.008, HT[1]),
           f"forearm.{s}", True)
        mk(f"thigh.{s}", P(HIP[0] * sx, 0, HIP[1]), P(KNEE[0] * sx, 0, KNEE[1]), "hips")
        mk(f"shin.{s}", P(KNEE[0] * sx, 0, KNEE[1]), P(ANK[0] * sx, 0, ANK[1]),
           f"thigh.{s}", True)
        mk(f"foot.{s}", P(ANK[0] * sx, 0, ANK[1]), P(ANK[0] * sx, -0.13, 0.03),
           f"shin.{s}", True)
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.show_in_front = True

    segs = {b.name: (b.head_local.copy(), b.tail_local.copy())
            for b in ad.bones if b.use_deform}
    for obj in parts:
        bind_by_name(obj, arm, segs)
    bpy.context.view_layer.update()
    return arm


def dist_seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def bind_nearest(obj, arm, segs, allowed=None):
    names = [n for n in segs if allowed is None or n in allowed]
    groups = {n: obj.vertex_groups.new(name=n) for n in names}
    for v in obj.data.vertices:
        p = v.co
        ds = sorted(((dist_seg(p, *segs[n]), n) for n in names))
        d0, n0 = ds[0]
        d1, n1 = ds[1] if len(ds) > 1 else (d0, n0)
        w0 = 1.0 / max(d0, 1e-4) ** 2
        w1 = 1.0 / max(d1, 1e-4) ** 2
        if d1 > d0 * 2.2 or n1 == n0:
            w1 = 0.0
        tot = w0 + w1
        groups[n0].add([v.index], w0 / tot, 'REPLACE')
        if w1 > 0:
            groups[n1].add([v.index], w1 / tot, 'REPLACE')
    bind_mod(obj, arm)


def bind_mod(obj, arm):
    md = obj.modifiers.new("Armature", "ARMATURE")
    md.object = arm
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()


def bind_group(obj, arm, bone):
    vg = obj.vertex_groups.new(name=bone)
    vg.add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
    bind_mod(obj, arm)


def bind_skirt(obj, arm):
    """Hips at the waist, blending toward the nearer thigh near the hem."""
    g = {b: obj.vertex_groups.new(name=b) for b in ("hips", "thigh.L", "thigh.R")}
    top, bot = P(0, 0, 0.90).z, P(0, 0, 0.40).z
    for v in obj.data.vertices:
        t = max(0.0, min(1.0, (top - v.co.z) / (top - bot))) * 0.55
        side = max(-1.0, min(1.0, v.co.x / (0.06 * _NORM["scale"])))
        wl = t * (0.5 + 0.5 * side)
        wr = t * (0.5 - 0.5 * side)
        g["hips"].add([v.index], 1.0 - t, 'REPLACE')
        if wl > 0.001:
            g["thigh.L"].add([v.index], wl, 'REPLACE')
        if wr > 0.001:
            g["thigh.R"].add([v.index], wr, 'REPLACE')
    bind_mod(obj, arm)


def bind_by_name(obj, arm, segs):
    n = obj.name
    s = "L" if n.endswith("_L") or n.endswith(".L") else ("R" if n.endswith("_R") or n.endswith(".R") else "")
    if n == "Body":
        bind_nearest(obj, arm, segs, [b for b in segs if not b.startswith(("thigh", "shin", "foot"))]); return
    if n == "robe_torso":
        bind_nearest(obj, arm, segs, ["hips", "spine", "chest", "neck"]); return
    if n.startswith(("skirt", "hem_", "slit_trim", "wrap_edge", "fold_")) or n.startswith("sash_tail"):
        bind_skirt(obj, arm); return
    if n.startswith("sash"):
        bind_group(obj, arm, "spine"); return
    if n.startswith(("lapel", "collar", "inner_collar")):
        bind_group(obj, arm, "chest"); return
    if n.startswith("sleeve_"):
        bind_nearest(obj, arm, segs, ["chest", "upper_arm." + s, "forearm." + s]); return
    if n.startswith(("cuff_", "bandage")):
        bind_group(obj, arm, "forearm." + s); return
    if n.startswith(("hand_", "thumb_")):
        bind_group(obj, arm, "hand." + s); return
    if n.startswith("pants_"):
        bind_nearest(obj, arm, segs, ["hips", "thigh." + s, "shin." + s]); return
    if n.startswith("boot_shaft") or n.startswith("boot_seam"):
        bind_nearest(obj, arm, segs, ["shin." + s, "foot." + s]); return
    if n.startswith(("boot_foot", "boot_sole")):
        bind_group(obj, arm, "foot." + s); return
    if n.startswith(("hair", "bun", "fringe", "sidelock", "eye", "brow", "nose", "mouth", "ear", "head")):
        bind_group(obj, arm, "head"); return
    bind_group(obj, arm, "chest")


def anim(arm):
    if arm.animation_data is None:
        arm.animation_data_create()

    def key(bone, frame, rot=None, loc=None):
        pb = arm.pose.bones[bone]
        pb.rotation_mode = 'XYZ'
        if rot is not None:
            pb.rotation_euler = tuple(math.radians(a) for a in rot)
            pb.keyframe_insert("rotation_euler", frame=frame)
        if loc is not None:
            pb.location = loc
            pb.keyframe_insert("location", frame=frame)

    def rest(frame):
        for b in BONES:
            key(b, frame, (0, 0, 0))
        key("hips", frame, loc=(0, 0, 0))

    a = bpy.data.actions.new("idle"); a.use_fake_user = True; arm.animation_data.action = a
    for f, br in ((0, 0), (24, 1), (48, 0)):
        rest(f); key("hips", f, loc=(0, 0.007 * br, 0)); key("spine", f, (0.7 * br, 0, 0))
        key("chest", f, (-1.1 * br, 0, 0)); key("head", f, (0.6 * br, 0, 0.8 * br))
        key("upper_arm.L", f, (1.1 * br, 0, 0)); key("upper_arm.R", f, (1.1 * br, 0, 0))
    a = bpy.data.actions.new("walk"); a.use_fake_user = True; arm.animation_data.action = a
    poses = [(0, -24, 24, 6, 30, 22, -22, 0), (6, -2, 4, 4, 42, 8, -8, .02),
             (12, 24, -24, 30, 6, -22, 22, 0), (18, 4, -2, 42, 4, -8, 8, .02),
             (24, -24, 24, 6, 30, 22, -22, 0)]
    for f, tl, tr, sl, sr, al, ar, bob in poses:
        rest(f); key("hips", f, loc=(0, bob, 0))
        key("thigh.L", f, (tl, 0, 0)); key("thigh.R", f, (tr, 0, 0))
        key("shin.L", f, (sl, 0, 0)); key("shin.R", f, (sr, 0, 0))
        key("upper_arm.L", f, (al, 0, 0)); key("upper_arm.R", f, (ar, 0, 0))
        key("forearm.L", f, (8, 0, 0)); key("forearm.R", f, (8, 0, 0))
    arm.animation_data.action = None


def export(arm, parts):
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format='GLB',
                              use_selection=True, export_yup=True, export_apply=False,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_force_sampling=True, export_anim_single_armature=True,
                              export_def_bones=True, export_skins=True,
                              export_cameras=False, export_lights=False,
                              export_materials='EXPORT') 
    print("GLB", GLB_PATH, os.path.getsize(GLB_PATH))


def look_at(cam, target):
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()


def setup_ref_cams():
    for name, loc, path in (("RefCamFront", (0, -4.2, .85), REF_FRONT),
                            ("RefCamSide", (-4.2, 0, .85), REF_SIDE)):
        if not os.path.exists(path):
            print("REF_MISSING", path); continue
        bpy.ops.object.camera_add(location=loc)
        cam = bpy.context.object; cam.name = name; cam.data.type = 'ORTHO'; cam.data.ortho_scale = REF_ORTHO
        look_at(cam, Vector((0, 0, .85)))
        cam.data.show_background_images = True
        bg = cam.data.background_images.new(); bg.image = bpy.data.images.load(path)
        bg.alpha = .55; bg.display_depth = 'BACK'; bg.frame_method = 'FIT'; bg.scale = 1.0
        print("REF_CAM", name, path, REF_ORTHO)


def render_preview():
    os.makedirs(RENDER_DIR, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    sh = scene.display.shading
    sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = False
    sh.show_cavity = False; sh.show_specular_highlight = False
    try:
        sh.show_object_outline = True; sh.object_outline_color = (.05, .05, .06)
    except Exception:
        pass
    scene.world.color = (.84, .84, .81)
    scene.view_settings.view_transform = 'Standard'; scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.9
    scene.render.resolution_x = 700; scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    target = Vector((0, 0, .85))
    views = {"front": Vector((0, -4.2, .85)), "side": Vector((-4.2, 0, .85)),
             "three_quarter": Vector((-2.9, -2.9, 1.45))}
    rendered = []
    for nm, loc in views.items():
        bpy.ops.object.camera_add(location=loc)
        cam = bpy.context.object; cam.name = "Preview_" + nm
        cam.data.type = 'ORTHO'; cam.data.ortho_scale = REF_ORTHO
        look_at(cam, target); scene.camera = cam
        p = os.path.join(RENDER_DIR, nm + ".png")
        scene.render.filepath = p; bpy.ops.render.render(write_still=True)
        rendered.append(p)
    convert = "/home/box/.local/bin/convert" if os.path.exists("/home/box/.local/bin/convert") else "convert"
    args = [convert]
    for p in rendered:
        args += [p, "-bordercolor", "#D8D6CE", "-border", "8"]
    args += ["+append", PREVIEW_PATH]
    subprocess.run(args, check=True)

    def label(src, dst, text):
        subprocess.run([convert, src, "-gravity", "north", "-background", "#D8D6CE",
                        "-splice", "0x48", "-font", "DejaVu-Sans", "-pointsize", "30",
                        "-fill", "#2E2B27", "-annotate", "+0+12", text, dst], check=True)
    panels = []
    for p, t in zip(rendered, ("3D FRONT", "3D SIDE", "3D 45")):
        d = os.path.join(RENDER_DIR, "cmp_" + os.path.basename(p)); label(p, d, t); panels.append(d)
    for src, nm, t in ((REF_FRONT, "ref_front", "REF FRONT"), (REF_SIDE, "ref_side", "REF SIDE")):
        if not os.path.exists(src):
            continue
        r = os.path.join(RENDER_DIR, nm + "_r.png")
        subprocess.run([convert, src, "-resize", "x1000", r], check=True)
        d = os.path.join(RENDER_DIR, nm + "_l.png"); label(r, d, t); panels.append(d)
    if len(panels) == 5:
        args = [convert]
        for p in panels:
            args += [p, "-bordercolor", "#D8D6CE", "-border", "8"]
        args += ["+append", COMPARE_PATH]
        subprocess.run(args, check=True)
        print("COMPARE", COMPARE_PATH, os.path.getsize(COMPARE_PATH))
    print("PREVIEW", PREVIEW_PATH, os.path.getsize(PREVIEW_PATH))


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--stage", default="model",
                                                    choices=["model", "rig", "preview"])
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    parts = build_character()
    if args.stage == "model":
        return
    arm = build_rig(parts)
    anim(arm)
    bpy.context.scene.frame_set(0)
    if args.stage in ("rig", "preview"):
        export(arm, parts)
    if args.stage == "preview":
        render_preview()


if __name__ == "__main__":
    main()
