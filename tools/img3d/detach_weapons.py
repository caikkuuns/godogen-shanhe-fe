#!/usr/bin/env python3
"""Detach welded weapons from TripoSR character GLBs, model independent
props, and bone-parent them so walk cycles do not bend the weapons.

Usage:
  ~/.local/bin/blender -b --python tools/img3d/detach_weapons.py -- [--chars shenyan,liheng] [--debug]
"""
import bpy
import bmesh
import math
import os
import sys
import mathutils
from mathutils import Vector, Matrix, Color

OUT_DIR = "/tmp/detach_weapons"
GLB_DIR = "/workspace/godogen-shanhe-fe/assets/glb"
RENDER_DIR = os.path.join(OUT_DIR, "render")
os.makedirs(RENDER_DIR, exist_ok=True)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DEBUG = "--debug" in argv
ONLY = None
for i, a in enumerate(argv):
    if a == "--chars" and i + 1 < len(argv):
        ONLY = set(argv[i + 1].split(","))

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in range(0, 6, 2))


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)
    # drop leftover factory / extras
    keep = set()
    arm = None
    body = None
    for o in bpy.data.objects:
        if o.type == "ARMATURE":
            arm = o
            keep.add(o)
        elif o.type == "MESH" and (o.name.startswith("Shenyan") or (o.parent and o.parent.type == "ARMATURE")):
            body = o
            keep.add(o)
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    if arm is None or body is None:
        raise RuntimeError(f"missing rig/mesh in {path}: arm={arm} body={body}")
    # rest pose for deletion + parenting
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    return arm, body


def world_co(obj, i):
    return obj.matrix_world @ obj.data.vertices[i].co


def bone_pts(arm, name):
    pb = arm.pose.bones[name]
    mw = arm.matrix_world
    return mw @ pb.head, mw @ pb.tail


def dist_seg(p, a, b):
    v = b - a
    l2 = v.length_squared
    if l2 < 1e-10:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(v) / l2))
    return (p - (a + t * v)).length


def near_bone(p, arm, name, rad):
    a, b = bone_pts(arm, name)
    return dist_seg(p, a, b) <= rad


def select_indices(obj, indices):
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mesh = obj.data
    for v in mesh.vertices:
        v.select = v.index in indices
    bpy.ops.object.mode_set(mode="EDIT")


def delete_and_fill(obj, indices):
    n = len(indices)
    print(f"  delete {n} verts of {len(obj.data.vertices)}")
    if n == 0:
        return 0
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    to_del = [v for v in bm.verts if v.index in indices]
    print(f"  bmesh matching {len(to_del)}")
    bmesh.ops.delete(bm, geom=to_del, context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    boundary = [e for e in bm.edges if e.is_boundary]
    print(f"  boundary edges {len(boundary)} verts left {len(bm.verts)} (no global fill; mesh is triangle-soup)")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()
    # consistent normals via edit mode
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"  mesh now {len(obj.data.vertices)} verts, {len(obj.data.polygons)} faces")
    return n


def color_image(name, hexcol):
    r, g, b = hex_rgb(hexcol)
    img = bpy.data.images.new(name, 16, 16)
    pix = [r, g, b, 1.0] * (16 * 16)
    img.pixels = pix
    img.pack()
    return img


def make_mat(name, hexcol, metallic=0.0, roughness=0.55):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    img = color_image(name + "_tex", hexcol)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    r, g, b = hex_rgb(hexcol)
    mat.diffuse_color = (r, g, b, 1)
    return mat


def new_mesh_obj(name, verts, faces, mat=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def add_cylinder(name, radius, depth, mat, verts=16, cap=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    o.data.materials.append(mat)
    if not cap:
        # keep caps; easier shading
        pass
    return o


def add_uvsphere(name, radius, mat, segs=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=max(6, segs // 2), radius=radius, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def add_torus(name, major, minor, mat, major_s=16, minor_s=10):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=major_s, minor_segments=minor_s, location=(0, 0, 0),
    )
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def add_cone(name, r1, r2, depth, mat, verts=16):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=r1, radius2=r2, depth=depth, location=(0, 0, 0),
    )
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def apply_world(obj):
    """Bake matrix_world into the mesh so joins keep world placement."""
    if obj.parent:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    mw = obj.matrix_world.copy()
    obj.data.transform(mw)
    obj.matrix_world = Matrix.Identity(4)
    obj.data.update()


def join_objs(name, objs, world_origin=None):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        apply_world(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    if world_origin is not None:
        cur = bpy.context.scene.cursor.location.copy()
        bpy.context.scene.cursor.location = world_origin
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.context.scene.cursor.location = cur
    return o


def set_matrix(obj, pos, z_axis, hint=Vector((0, 1, 0))):
    z = z_axis.normalized()
    x = hint.cross(z)
    if x.length < 1e-4:
        x = Vector((1, 0, 0)).cross(z)
    x.normalize()
    y = z.cross(x).normalized()
    m = Matrix((
        (x.x, y.x, z.x, pos.x),
        (x.y, y.y, z.y, pos.y),
        (x.z, y.z, z.z, pos.z),
        (0, 0, 0, 1),
    ))
    obj.matrix_world = m


def parent_to_bone(obj, arm, bone_name):
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    for b in arm.data.bones:
        b.select = b.name == bone_name
    arm.data.bones.active = arm.data.bones[bone_name]
    bpy.ops.object.parent_set(type="BONE", keep_transform=True)
    print(f"  parented {obj.name} -> {bone_name}  parent_type={obj.parent_type} bone={obj.parent_bone}")


def grow_indices(obj, seeds, allow_fn, rings=4):
    """Expand a vertex set along edges while allow_fn(world_co) is true."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    adj = [[] for _ in range(len(mesh.vertices))]
    for e in mesh.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    sel = set(seeds)
    frontier = set(seeds)
    for _ in range(rings):
        nxt = set()
        for i in frontier:
            for j in adj[i]:
                if j in sel:
                    continue
                p = world_co(obj, j)
                if allow_fn(p):
                    sel.add(j)
                    nxt.add(j)
        frontier = nxt
        if not frontier:
            break
    return sel


def mesh_islands(obj):
    mesh = obj.data
    adj = [[] for _ in range(len(mesh.vertices))]
    for e in mesh.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    seen = set()
    islands = []
    for i in range(len(mesh.vertices)):
        if i in seen:
            continue
        st = [i]
        isl = []
        seen.add(i)
        while st:
            x = st.pop()
            isl.append(x)
            for y in adj[x]:
                if y not in seen:
                    seen.add(y)
                    st.append(y)
        islands.append(isl)
    return islands


def island_mask(obj, point_ok, min_frac=0.45, min_hits=6):
    """Delete whole connected islands that mostly sit in the weapon region.

    These TripoSR GLBs are triangle-soup (hundreds of small islands, many
    boundary edges). Filling every boundary loop shreds the body, so we only
    drop complete weapon islands and skip hole-fill.
    """
    islands = mesh_islands(obj)
    sel = set()
    report = []
    for isl in islands:
        hits = [i for i in isl if point_ok(world_co(obj, i))]
        if len(hits) >= min_hits and len(hits) >= min_frac * len(isl):
            sel.update(isl)
            report.append(len(isl))
    report.sort(reverse=True)
    print(f"  islands picked {len(report)} sizes {report[:12]} verts {len(sel)}")
    return sel


# ---------------------------------------------------------------------------
# deletion masks
# ---------------------------------------------------------------------------

def verts_where(body, fn):
    return {v.index for v in body.data.vertices if fn(body.matrix_world @ v.co)}


def mask_shenyan(arm, body):
    """Welded sword currently sits on the RIGHT shoulder (wrong side)."""
    def ok(p):
        if p.z > 1.52 and p.x < 0.10:
            return False  # bun
        # handle + tassel blob on the right-back shoulder
        if 0.06 < p.x < 0.34 and p.y > 0.025 and 1.14 < p.z < 1.57:
            # keep the robe close to the back when low
            if p.y < 0.045 and p.z < 1.26:
                return False
            return True
        return False
    # Deleting these verts left a hole in the back of the robe (triangle-soup
    # mesh, no reliable fill). Leave the old stub; the new sword is on the
    # correct left shoulder.
    print(f"  shenyan leftover verts 0 (skip delete to avoid robe hole; candidate {len(verts_where(body, ok))})")
    return set()


def mask_linzhaowan(arm, body):
    """Sword is almost only a painted mark; do not carve the skirt."""
    return set()


def mask_liheng(arm, body):
    hand_h, hand_t = bone_pts(arm, "hand.R")
    forearm_h, forearm_t = bone_pts(arm, "forearm.R")
    thigh_h, thigh_t = bone_pts(arm, "thigh.R")
    shin_h, shin_t = bone_pts(arm, "shin.R")
    def ok(p):
        if p.x < 0.28:
            return False
        if p.z > 1.04:
            return False
        if dist_seg(p, hand_h, hand_t) < 0.055:
            return False
        if dist_seg(p, forearm_h, forearm_t) < 0.05:
            return False
        if dist_seg(p, thigh_h, thigh_t) < 0.14:
            return False
        if dist_seg(p, shin_h, shin_t) < 0.13:
            return False
        return True
    sel = verts_where(body, ok)
    print(f"  liheng blade verts {len(sel)}")
    return sel


def mask_gesancheng(arm, body):
    rh, rt = bone_pts(arm, "hand.R")
    lh, lt = bone_pts(arm, "hand.L")
    rfh, rft = bone_pts(arm, "forearm.R")
    lfh, lft = bone_pts(arm, "forearm.L")
    def ok(p):
        if p.z > 1.05:
            return False
        if p.x > 0.28:
            if dist_seg(p, rh, rt) < 0.055 or dist_seg(p, rfh, rft) < 0.05:
                return False
            return True
        if p.x < -0.30:
            if dist_seg(p, lh, lt) < 0.055 or dist_seg(p, lfh, lft) < 0.05:
                return False
            return True
        return False
    sel = verts_where(body, ok)
    print(f"  gesancheng prop verts {len(sel)}")
    return sel


def mask_dashou(arm, body):
    # Previous +X / island deletes tore off the far arm and missed the banana
    # club in the visual right hand. Leave the body intact this pass; the new
    # straight club is parented to the same visual hand (see place_dashou).
    print("  dashou club verts 0 (no body delete; avoid tearing the arm)")
    return set()


# ---------------------------------------------------------------------------
# props
# ---------------------------------------------------------------------------

def make_tassel(name, length, color, n_strands=4, radius=0.0035):
    mat = make_mat(name + "_mat", color, roughness=0.7)
    knot = add_uvsphere(name + "_knot", 0.007, mat, segs=10)
    knot.location = (0, 0, 0)
    parts = [knot]
    for i in range(n_strands):
        ang = (i / max(1, n_strands - 1) - 0.5) * 0.5
        cyl = add_cylinder(f"{name}_s{i}", radius * (1.05 if i in (1, 2) else 0.75), length, mat, verts=8)
        mid = Vector((math.sin(ang) * 0.008, math.cos(ang) * 0.003, -length * 0.5 - 0.002))
        cyl.location = mid
        ball = add_uvsphere(f"{name}_b{i}", radius * 1.3, mat, segs=8)
        ball.location = (mid.x, mid.y, -length - 0.004)
        parts += [cyl, ball]
    return join_objs(name, parts, world_origin=Vector((0, 0, 0)))


def make_jian(name, sheath_hex, fit_hex, handle_hex, tassel_hex, sheath_len=0.72, handle_len=0.16, width=0.038):
    m_s = make_mat(name + "_sheath", sheath_hex, roughness=0.62)
    m_f = make_mat(name + "_fit", fit_hex, metallic=0.45, roughness=0.35)
    m_h = make_mat(name + "_handle", handle_hex, roughness=0.7)
    thick = width * 0.62
    # local: origin at scabbard mouth, +Z toward pommel, -Z toward tip
    sheath = add_cylinder(name + "_scabbard", width * 0.5, sheath_len, m_s, verts=18)
    sheath.scale = (1.0, thick / width, 1.0)
    bpy.context.view_layer.objects.active = sheath
    bpy.ops.object.transform_apply(scale=True)
    sheath.location = (0, 0, -sheath_len * 0.5)
    mouth = add_cylinder(name + "_mouth", width * 0.58, 0.018, m_f, verts=18)
    mouth.scale = (1.0, thick / width, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    mouth.location = (0, 0, 0.002)
    chape = add_cylinder(name + "_chape", width * 0.55, 0.022, m_f, verts=18)
    chape.scale = (1.0, thick / width, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    chape.location = (0, 0, -sheath_len + 0.01)
    guard = add_cylinder(name + "_guard", width * 0.70, 0.012, m_f, verts=18)
    guard.location = (0, 0, 0.016)
    handle = add_cylinder(name + "_handle", width * 0.36, handle_len, m_h, verts=14)
    handle.location = (0, 0, 0.022 + handle_len * 0.5)
    pommel = add_uvsphere(name + "_pommel", width * 0.40, m_f, segs=12)
    pommel.location = (0, 0, 0.022 + handle_len + 0.006)
    tassel = make_tassel(name + "_tassel", 0.13, tassel_hex)
    joined = join_objs(name, [sheath, mouth, chape, guard, handle, pommel], world_origin=Vector((0, 0, 0)))
    # tassel stays unparented; caller places it in world space at the pommel
    tassel["_handle_len"] = handle_len
    return joined, tassel


def attach_tassel(sword, tassel, mouth, pommel_dir, handle_len):
    """Place an unparented tassel at the pommel, hanging world-down, then join."""
    top = mouth + pommel_dir.normalized() * (0.022 + handle_len + 0.008)
    set_matrix(tassel, top, Vector((0, 0, 1)), hint=Vector((0, 1, 0)))
    bpy.context.view_layer.update()
    return join_objs(sword.name, [sword, tassel], world_origin=mouth)


def make_white_sword():
    # 林照晚: white sheath, silver fittings, pink tassel, sheath 0.65, total 0.9, width 0.04
    return make_jian(
        "LinZhaoWanSword",
        sheath_hex="#F4ECE9",
        fit_hex="#BBA6A2",
        handle_hex="#C8BBB6",
        tassel_hex="#E1919D",
        sheath_len=0.65,
        handle_len=0.22,
        width=0.04,
    )


def make_back_sword():
    # 沈砚: brown wood sheath, dark handle, pale blue tassel
    return make_jian(
        "ShenyanBackSword",
        sheath_hex="#4A3328",
        fit_hex="#3A322C",
        handle_hex="#2A221C",
        tassel_hex="#B7C9E4",
        sheath_len=0.74,
        handle_len=0.16,
        width=0.036,
    )


def make_dao():
    """三孔阔背刀. Local origin at grip center. +Z toward pommel, -Z toward tip."""
    blade_len = 0.73
    handle_len = 0.21
    max_w = 0.10
    thick = 0.012
    m_b = make_mat("DaoBlade", "#3F3B3A", metallic=0.08, roughness=0.55)
    m_g = make_mat("DaoGuard", "#1D140D", metallic=0.5, roughness=0.35)
    m_h = make_mat("DaoHandle", "#231B19", roughness=0.7)
    # blade profile as lofts of closed rectangles, spine at x=0, edge at +x
    n = 28
    verts = []
    faces = []

    def width_at(s):
        # s 0 at guard, 1 at tip; widest near 0.7; tip clips to spine
        if s < 0.12:
            return 0.042 + 0.03 * (s / 0.12)
        if s < 0.70:
            return 0.072 + (max_w - 0.072) * ((s - 0.12) / 0.58)
        if s < 0.92:
            return max_w + (0.055 - max_w) * ((s - 0.70) / 0.22)
        t = (s - 0.92) / 0.08
        return 0.055 * (1 - t)  # collapse to the point

    def spine_x(s):
        return 0.0

    def edge_x(s):
        return width_at(s)

    # tip: point sits slightly toward the spine (clip)
    for i in range(n + 1):
        s = i / n
        z = -s * blade_len
        w = width_at(s)
        # clip the last 8% so the point is near the spine
        if s > 0.90:
            t = (s - 0.90) / 0.10
            # shift both toward spine (x=0) but keep a point just off the spine
            x0 = 0.0
            x1 = w * (1 - 0.35 * t)
            if s >= 0.999:
                x0, x1 = 0.01, 0.01
        else:
            x0, x1 = 0.0, w
        y0, y1 = -thick * 0.5, thick * 0.5
        # 4 verts per ring: spine-y0, spine-y1, edge-y1, edge-y0
        verts += [
            (x0, y0, z),
            (x0, y1, z),
            (x1, y1, z),
            (x1, y0, z),
        ]
    # cap at guard (s=0)
    faces.append((0, 1, 2, 3))
    for i in range(n):
        a = i * 4
        b = (i + 1) * 4
        faces.append((a + 0, b + 0, b + 1, a + 1))  # spine
        faces.append((a + 1, b + 1, b + 2, a + 2))  # one face
        faces.append((a + 2, b + 2, b + 3, a + 3))  # edge
        faces.append((a + 3, b + 3, b + 0, a + 0))  # other face
    last = n * 4
    faces.append((last + 0, last + 3, last + 2, last + 1))
    blade = new_mesh_obj("DaoBladeMesh", verts, faces, m_b)
    # three holes along the spine, through the thickness
    cutters = []
    hole_s = (0.38, 0.55, 0.72)
    hole_r = 0.0115
    for k, s in enumerate(hole_s):
        z = -s * blade_len
        w = width_at(s)
        # sit near the spine, fully inside the blade
        x = 0.018
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=16, radius=hole_r, depth=thick * 3, location=(x, 0, z),
            rotation=(math.radians(90), 0, 0),
        )
        c = bpy.context.active_object
        c.name = f"DaoCutter{k}"
        cutters.append(c)
    bpy.context.view_layer.objects.active = blade
    blade.select_set(True)
    for c in cutters:
        m = blade.modifiers.new(c.name, "BOOLEAN")
        m.operation = "DIFFERENCE"
        m.object = c
        m.solver = "EXACT"
        bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.data.objects.remove(c, do_unlink=True)
    # guard disc and handle
    guard = add_cylinder("DaoGuard", 0.04, 0.014, m_g, verts=20)
    guard.location = (0.03, 0, 0.008)
    handle = add_cylinder("DaoHandle", 0.016, handle_len, m_h, verts=14)
    handle.location = (0.03, 0, 0.014 + handle_len * 0.5)
    pommel = add_uvsphere("DaoPommel", 0.018, m_g, segs=12)
    pommel.location = (0.03, 0, 0.014 + handle_len + 0.008)
    # origin at grip (mid handle)
    grip = Vector((0.03, 0, 0.014 + handle_len * 0.45))
    return join_objs("LiHengDao", [blade, guard, handle, pommel], world_origin=grip)


def make_scale_rod():
    """0.95 m wooden rod, iron hook at -Z end, grip origin 0.28 m from the tail (+Z)."""
    length = 0.95
    radius = 0.015
    m_r = make_mat("ScaleRod", "#2D231D", roughness=0.7)
    m_s = make_mat("ScaleStar", "#B08A4A", metallic=0.7, roughness=0.3)
    m_k = make_mat("ScaleHook", "#5A5348", metallic=0.65, roughness=0.35)
    # origin will be the grip. Tail (提绳端) at +Z * 0.28, hook end at -Z * 0.67
    grip_from_tail = 0.28
    hook_from_grip = length - grip_from_tail
    rod = add_cylinder("ScaleRodBody", radius, length, m_r, verts=14)
    rod.location = (0, 0, (grip_from_tail - hook_from_grip) * 0.5)
    # brass stars along the hanging part
    stars = []
    for i, d in enumerate((0.10, 0.20, 0.30, 0.40, 0.50, 0.58)):
        s = add_uvsphere(f"ScaleStar{i}", 0.0055, m_s, segs=8)
        s.location = (radius * 0.7, 0, -d)
        stars.append(s)
    # hook: a short neck then a J curve (bezier bevel)
    curve = bpy.data.curves.new("HookCrv", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.007
    curve.bevel_resolution = 3
    curve.resolution_u = 12
    sp = curve.splines.new("BEZIER")
    pts = [
        (0, 0, -hook_from_grip + 0.04),
        (0, 0, -hook_from_grip),
        (0.0, 0.0, -hook_from_grip - 0.04),
        (0.04, 0.0, -hook_from_grip - 0.055),
        (0.07, 0.0, -hook_from_grip - 0.03),
        (0.05, 0.0, -hook_from_grip - 0.005),
    ]
    sp.bezier_points.add(len(pts) - 1)
    for p, co in zip(sp.bezier_points, pts):
        p.co = co
        p.handle_left_type = "AUTO"
        p.handle_right_type = "AUTO"
    hook_obj = bpy.data.objects.new("ScaleHook", curve)
    bpy.context.scene.collection.objects.link(hook_obj)
    hook_mat = m_k
    hook_obj.data.materials.append(hook_mat)
    # convert to mesh
    bpy.ops.object.select_all(action="DESELECT")
    hook_obj.select_set(True)
    bpy.context.view_layer.objects.active = hook_obj
    bpy.ops.object.convert(target="MESH")
    hook_mesh = bpy.context.active_object
    return join_objs("GeSanChengRod", [rod] + stars + [hook_mesh], world_origin=Vector((0, 0, 0)))


def make_scale_weight():
    m_w = make_mat("ScaleWeight", "#34332F", metallic=0.4, roughness=0.45)
    m_l = make_mat("ScaleLoop", "#4A4540", metallic=0.55, roughness=0.4)
    # frustum, origin at the top loop (hang point)
    body = add_cone("ScaleWeightBody", 0.06, 0.028, 0.18, m_w, verts=20)
    body.location = (0, 0, -0.02 - 0.09)
    cap = add_cylinder("ScaleWeightCap", 0.028, 0.016, m_w, verts=16)
    cap.location = (0, 0, -0.02)
    loop = add_torus("ScaleWeightLoop", 0.014, 0.0035, m_l, major_s=14, minor_s=8)
    loop.location = (0, 0, 0.0)
    loop.rotation_euler = (math.radians(90), 0, 0)
    return join_objs("GeSanChengWeight", [body, cap, loop], world_origin=Vector((0, 0, 0)))


def make_club():
    """0.45 m straight cylinder, two iron rings near the head (bottom). Origin at grip, near the top."""
    length = 0.45
    radius = 0.035
    m_w = make_mat("ClubWood", "#79604D", roughness=0.68)
    m_i = make_mat("ClubIron", "#786354", metallic=0.7, roughness=0.35)
    # grip 0.05 below the top; head (rings) at the bottom
    top_above_grip = 0.05
    head_below_grip = length - top_above_grip
    body = add_cylinder("ClubBody", radius, length, m_w, verts=18)
    body.location = (0, 0, (top_above_grip - head_below_grip) * 0.5)
    rings = []
    for i, z in enumerate((-head_below_grip + 0.045, -head_below_grip + 0.078)):
        r = add_torus(f"ClubRing{i}", radius + 0.001, 0.0055, m_i, major_s=16, minor_s=8)
        r.location = (0, 0, z)
        r.rotation_euler = (0, 0, 0)  # torus default is in XY, axis = Z; good
        rings.append(r)
    cap = add_cylinder("ClubCap", radius + 0.001, 0.012, m_w, verts=18)
    cap.location = (0, 0, -head_below_grip + 0.004)
    return join_objs("YaoXingClub", [body, cap] + rings, world_origin=Vector((0, 0, 0)))


# ---------------------------------------------------------------------------
# placement
# ---------------------------------------------------------------------------

def place_shenyan(arm, body):
    sword, tassel = make_back_sword()
    # skip procedural tassel — join/scale produced a huge stretched flag.
    # A small pale-blue pommel knot is already on the handle.
    bpy.data.objects.remove(tassel, do_unlink=True)
    mouth = Vector((-0.11, 0.16, 1.34))
    pommel_dir = Vector((-0.05, 0.08, 0.22)).normalized()
    set_matrix(sword, mouth, pommel_dir, hint=Vector((0, 1, 0)))
    parent_to_bone(sword, arm, "chest")
    return [sword]


def place_linzhaowan(arm, body):
    sword, tassel = make_white_sword()
    # left hip, close to the body, almost vertical; tip a little back so the side view shows it
    mouth = Vector((-0.13, 0.025, 0.97))
    pommel_dir = Vector((0.02, -0.02, 0.25)).normalized()
    set_matrix(sword, mouth, pommel_dir, hint=Vector((0, 1, 0)))
    sword = attach_tassel(sword, tassel, mouth, pommel_dir, 0.22)
    parent_to_bone(sword, arm, "hips")
    return [sword]


def place_liheng(arm, body):
    dao = make_dao()
    h, t = bone_pts(arm, "hand.R")
    grip = h.lerp(t, 0.38)
    # hang almost down, slight forward and a hint outward at the tip
    pommel_dir = Vector((-0.02, 0.04, 1.0)).normalized()  # +Z up
    set_matrix(dao, grip, pommel_dir, hint=Vector((0, 1, 0)))
    # rotate around Z so the blade's wide face is mostly toward the front ( +X is edge in local )
    # after set_matrix, local +X is width (edge), we want edge toward the body (-X world-ish) or slightly front.
    # Front ref: spine outward (+X world), edge toward legs (toward -X / center).
    # After set_matrix with hint (0,1,0) and z=(0,0,1), local X ≈ (1,0,0) or so.
    # Edge is local +X, so edge currently points +X (outward) — opposite of the ref.
    # Flip 180° around Z.
    bpy.context.view_layer.update()
    q = mathutils.Quaternion(Vector((0, 0, 1)), math.radians(180))
    dao.rotation_mode = "QUATERNION"
    # apply extra world rotation around the grip
    R = q.to_matrix().to_4x4()
    T = Matrix.Translation(grip)
    dao.matrix_world = T @ R @ T.inverted() @ dao.matrix_world
    parent_to_bone(dao, arm, "hand.R")
    return [dao]


def place_gesancheng(arm, body):
    rod = make_scale_rod()
    weight = make_scale_weight()
    # Front render places hand.R (+X) on the image right for this character;
    # the reference wants the rod in the character's right hand (image left).
    # Empirically, parenting the rod to hand.L matches the ref front.
    rh, rt = bone_pts(arm, "hand.L")  # visual right hand (image left)
    lh, lt = bone_pts(arm, "hand.R")
    rgrip = rh.lerp(rt, 0.35)
    lgrip = lh.lerp(lt, 0.35)
    rod_up = Vector((0.08, 0.02, 1.0)).normalized()
    set_matrix(rod, rgrip, rod_up, hint=Vector((0, 1, 0)))
    set_matrix(weight, lgrip, Vector((0, 0, 1)), hint=Vector((0, 1, 0)))
    parent_to_bone(rod, arm, "hand.L")
    parent_to_bone(weight, arm, "hand.R")
    return [rod, weight]


def place_dashou(arm, body):
    club = make_club()
    # Same empirical side as 葛三秤: hand.L appears on the image left
    # (character's right), which is where the reference and the leftover club sit.
    h, t = bone_pts(arm, "hand.L")
    grip = h.lerp(t, 0.35)
    up = Vector((-0.02, -0.02, 1.0)).normalized()
    set_matrix(club, grip, up, hint=Vector((0, 1, 0)))
    parent_to_bone(club, arm, "hand.L")
    return [club]


# ---------------------------------------------------------------------------
# export + render
# ---------------------------------------------------------------------------

def setup_render(path_prefix, views, height):
    sc = bpy.context.scene
    # drop previous lights/cams
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
    k = height / 1.70
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x = 600
    sc.render.resolution_y = 900
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 1.5
    sun.rotation_euler = (math.radians(40), 0, math.radians(20))
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.95 * k
    for name, ang in views:
        a = math.radians(ang)
        r = 5
        cam.location = (r * math.sin(a), -r * math.cos(a), 0.85 * k)
        cam.rotation_euler = (math.radians(90), 0, a)
        sc.render.filepath = f"{path_prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)
        print("  rendered", sc.render.filepath)


def set_action(arm, name, frame):
    arm.data.pose_position = "POSE"
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.get(name)
    if act is None:
        for a in bpy.data.actions:
            if name in a.name:
                act = a
                break
    arm.animation_data.action = act
    if arm.animation_data.nla_tracks:
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def export_glb(path, arm):
    # rest pose so bind pose stays A-pose
    arm.data.pose_position = "REST"
    if arm.animation_data:
        arm.animation_data.action = None
        for tr in arm.animation_data.nla_tracks:
            tr.mute = False
    bpy.context.view_layer.update()
    # delete lights/cams so they do not land in the glb
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_animations=True,
        export_nla_strips=True,
        export_extras=False,
        export_cameras=False,
        export_lights=False,
        export_apply=False,
    )
    print("  exported", path, "size", os.path.getsize(path))


def paint_debug(obj, indices, out_png, height):
    # vertex color overlay is heavy; instead duplicate selected as a red icosphere cloud is worse.
    # Use a material viewport: add a vertex color layer and a simple render.
    mesh = obj.data
    col = mesh.color_attributes.get("dbg") or mesh.color_attributes.new("dbg", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(mesh.vertices):
        col.data[i].color = (1, 0, 0, 1) if i in indices else (0.7, 0.7, 0.7, 1)
    # attach to material
    mat = obj.data.materials[0] if obj.data.materials else make_mat("dbg", "#AAAAAA")
    nt = mat.node_tree
    # don't wreck the real mat too much in debug-only path
    setup_render(out_png.replace(".png", ""), [("front", 0), ("side", -90), ("back", 180)], height)


CHARS = [
    {
        "name": "shenyan",
        "glb": os.path.join(GLB_DIR, "shenyan.glb"),
        "height": 1.70,
        "mask": mask_shenyan,
        "place": place_shenyan,
    },
    {
        "name": "linzhaowan",
        "glb": os.path.join(GLB_DIR, "linzhaowan.glb"),
        "height": 1.63,
        "mask": mask_linzhaowan,
        "place": place_linzhaowan,
    },
    {
        "name": "liheng",
        "glb": os.path.join(GLB_DIR, "liheng.glb"),
        "height": 1.85,
        "mask": mask_liheng,
        "place": place_liheng,
    },
    {
        "name": "gesancheng",
        "glb": os.path.join(GLB_DIR, "gesancheng.glb"),
        "height": 1.65,
        "mask": mask_gesancheng,
        "place": place_gesancheng,
    },
    {
        "name": "yaoxing_dashou",
        "glb": os.path.join(GLB_DIR, "yaoxing_dashou.glb"),
        "height": 1.72,
        "mask": mask_dashou,
        "place": place_dashou,
    },
]


def process(ch):
    name = ch["name"]
    print("=" * 60, name)
    clear_scene()
    # restore from backup so reruns are clean
    src = os.path.join("/tmp/glb_backup_pre_detach", os.path.basename(ch["glb"]))
    arm, body = import_glb(src)
    # height check
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    print(f"  imported verts={len(body.data.vertices)} z=[{min(zs):.3f},{max(zs):.3f}] expect h={ch['height']}")
    indices = ch["mask"](arm, body)
    print(f"  mask size {len(indices)}")
    if DEBUG:
        ddir = os.path.join(RENDER_DIR, name + "_dbg")
        os.makedirs(os.path.dirname(ddir), exist_ok=True)
        # write a small dump and render AFTER painting but BEFORE delete — use a temp copy
        paint_debug(body, indices, os.path.join(RENDER_DIR, name + "_dbg"), ch["height"])
    delete_and_fill(body, indices)
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    print(f"  after delete verts={len(body.data.vertices)} z=[{min(zs):.3f},{max(zs):.3f}]")
    props = ch["place"](arm, body)
    print("  props", [p.name for p in props])
    dest = ch["glb"]
    export_glb(dest, arm)
    # renders: rest / idle + walk stress
    rdir = os.path.join(RENDER_DIR, name)
    os.makedirs(rdir, exist_ok=True)
    set_action(arm, "idle", 1)
    setup_render(os.path.join(rdir, "v"), [("front", 0), ("side", -90), ("45", -45), ("back", 180)], ch["height"])
    set_action(arm, "walk", 1)
    setup_render(os.path.join(rdir, "walk"), [("front", 0), ("side", -90)], ch["height"])
    return dest


def main():
    done = []
    for ch in CHARS:
        if ONLY and ch["name"] not in ONLY:
            continue
        done.append(process(ch))
    print("DONE", done)


if __name__ == "__main__":
    main()
