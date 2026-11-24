#!/usr/bin/env python3
"""Cut 林照晚's T-pose sleeve flaps off the body, sew the arms, and add
independent wide-sleeve meshes bound to upper_arm + forearm.

Does not rewrite actions (no rotation_mode change), so idle/walk stay intact.

  ~/.local/bin/blender -b --python tools/img3d/fix_linzhaowan_sleeves.py
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector, Matrix

SRC = "/tmp/glb_backup_pre_round4/linzhaowan.glb"
DST_TMP = "/tmp/linzhaowan_sleeves.glb"
RENDER = "/tmp/fix_sleeves"
os.makedirs(RENDER, exist_ok=True)

PINK = (0.737, 0.548, 0.564, 1.0)
LINING = (0.90, 0.78, 0.76, 1.0)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_keep_anims(path):
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = None
    props = []
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if o.type == "MESH":
            if o.parent == arm and o.parent_type == "BONE":
                props.append(o)
            elif body is None or len(o.data.vertices) > len(body.data.vertices):
                body = o
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    return arm, body, props


def bone_pts(arm, name):
    b = arm.data.bones[name]
    h = arm.matrix_world @ b.head_local
    t = arm.matrix_world @ b.tail_local
    return h, t


def dist_seg(p, h, t):
    d = t - h
    l2 = d.length_squared
    if l2 < 1e-12:
        return (p - h).length
    u = max(0.0, min(1.0, (p - h).dot(d) / l2))
    return (p - (h + d * u)).length


def weights_of(body, i):
    out = []
    for g in body.vertex_groups:
        try:
            w = g.weight(i)
            if w > 1e-4:
                out.append((w, g.name))
        except RuntimeError:
            pass
    out.sort(reverse=True)
    return out


def collect_flap_indices(arm, body):
    arm_segs = []
    for side in "LR":
        for n in ("shoulder." + side, "upper_arm." + side, "forearm." + side, "hand." + side):
            h, t = bone_pts(arm, n)
            arm_segs.append((n, h, t))

    def dist_pt(p, h, t):
        d = t - h
        l2 = d.length_squared
        if l2 < 1e-12:
            return (p - h).length, h
        u = max(0.0, min(1.0, (p - h).dot(d) / l2))
        q = h + d * u
        return (p - q).length, q

    flap = []
    for i, v in enumerate(body.data.vertices):
        p = body.matrix_world @ v.co
        best, bestq = 1e9, None
        for n, h, t in arm_segs:
            d, q = dist_pt(p, h, t)
            if d < best:
                best, bestq = d, q
        if bestq is None:
            continue
        # hanging T-wing: forearm/hand weighted, below the arm, outside the cylinder
        if p.z >= bestq.z - 0.05:
            continue
        if best <= 0.06:
            continue
        ws = weights_of(body, i)
        if not ws:
            continue
        if not ws[0][1].startswith(("forearm", "hand")):
            continue
        flap.append(i)
    return flap


def delete_and_sew(obj, indices):
    n = len(indices)
    print("  delete flap verts", n, "/", len(obj.data.vertices))
    if n == 0:
        return 0
    if n > 2500:
        print("  ABORT delete, too many verts")
        return -1
    idx = set(indices)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    layer = bm.verts.layers.int.new("cut_rim")
    for v in bm.verts:
        v[layer] = 0
    for i in idx:
        if i >= len(bm.verts):
            continue
        v = bm.verts[i]
        for e in v.link_edges:
            o = e.other_vert(v)
            if o.index not in idx:
                o[layer] = 1
    to_del = [bm.verts[i] for i in idx if i < len(bm.verts)]
    bmesh.ops.delete(bm, geom=to_del, context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    rim = [e for e in bm.edges if e.is_boundary and e.verts[0][layer] == 1 and e.verts[1][layer] == 1]
    print("  cut rim edges", len(rim), "verts left", len(bm.verts))
    uvlay = bm.loops.layers.uv.active
    if rim:
        before = set(bm.faces)
        filled = False
        for op in ("holes_fill", "edgeloop_fill", "triangle_fill"):
            try:
                if op == "holes_fill":
                    bmesh.ops.holes_fill(bm, edges=rim, sides=0)
                elif op == "edgeloop_fill":
                    bmesh.ops.edgeloop_fill(bm, edges=rim)
                else:
                    bmesh.ops.triangle_fill(bm, use_beauty=True, edges=rim)
                added = [f for f in bm.faces if f not in before and f.is_valid]
                if added:
                    filled = True
                    print("  sewed with", op, "faces", len(added))
                    # UV from rim
                    if uvlay is not None:
                        for f in added:
                            for lp in f.loops:
                                src = None
                                for l2 in lp.vert.link_loops:
                                    if l2 is lp:
                                        continue
                                    uv = l2[uvlay].uv
                                    if uv.length > 1e-6:
                                        src = uv.copy()
                                        break
                                if src is not None:
                                    lp[uvlay].uv = src
                    break
            except Exception as exc:
                print("  ", op, exc)
        if not filled:
            # 76 rim edges are usually several small loops; fill each.
            used = set()
            nfill = 0
            for e0 in list(rim):
                if not e0.is_valid or not e0.is_boundary or e0.index in used:
                    continue
                loop = [e0]
                used.add(e0.index)
                vcur = e0.verts[1]
                closed = False
                for _ in range(400):
                    nxt = None
                    for e2 in vcur.link_edges:
                        if e2.is_boundary and e2.index not in used:
                            nxt = e2
                            break
                    if nxt is None:
                        break
                    used.add(nxt.index)
                    loop.append(nxt)
                    vcur = nxt.other_vert(vcur)
                    if vcur == loop[0].verts[0]:
                        closed = True
                        break
                if not closed or len(loop) < 3:
                    continue
                before = set(bm.faces)
                try:
                    bmesh.ops.triangle_fill(bm, use_beauty=True, edges=loop)
                except Exception:
                    try:
                        bmesh.ops.holes_fill(bm, edges=loop, sides=0)
                    except Exception:
                        continue
                added = [f for f in bm.faces if f not in before and f.is_valid]
                if added:
                    nfill += 1
                    if uvlay is not None:
                        for f in added:
                            for lp in f.loops:
                                src = None
                                for l2 in lp.vert.link_loops:
                                    if l2 is lp:
                                        continue
                                    uv = l2[uvlay].uv
                                    if uv.length > 1e-6:
                                        src = uv.copy()
                                        break
                                if src is not None:
                                    lp[uvlay].uv = src
            print("  sewed per-loop", nfill)
            if nfill == 0:
                print("  WARN no sew")
    try:
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    except Exception:
        pass
    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("  body now", len(obj.data.vertices), "v", len(obj.data.polygons), "f")
    return n



def sample_robe_pink(body):
    """Mean colour of bright-ish robe faces, used for the sleeve material."""
    img = None
    if body.data.materials:
        mat = body.data.materials[0]
        if mat and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 64:
                    img = n.image
                    break
    if img is None:
        return PINK[:3]
    w, h = img.size
    ch = img.channels
    px = list(img.pixels)
    uv = body.data.uv_layers.active
    acc = [0.0, 0.0, 0.0]
    n = 0
    for poly in body.data.polygons:
        com = Vector((0, 0, 0))
        for vi in poly.vertices:
            com += body.matrix_world @ body.data.vertices[vi].co
        com /= len(poly.vertices)
        if not (0.55 < com.z < 1.25 and abs(com.x) < 0.22):
            continue
        for li in poly.loop_indices:
            u, v = uv.data[li].uv
            x = int(max(0, min(w - 1, u * w)))
            y = int(max(0, min(h - 1, v * h)))
            i = (y * w + x) * ch
            r, g, b = px[i], px[i + 1], px[i + 2]
            lum = r + g + b
            if lum < 1.2 or r < g:
                continue
            acc[0] += r
            acc[1] += g
            acc[2] += b
            n += 1
    if n < 8:
        return PINK[:3]
    col = tuple(acc[i] / n for i in range(3))
    print("  sampled robe pink", tuple(round(c, 3) for c in col), "n", n)
    return col


def make_sleeve_texture(color, name, size=32):
    img = bpy.data.images.new(name, size, size)
    # slight variation so it is not a perfectly flat plastic
    pix = []
    for y in range(size):
        for x in range(size):
            s = 1.0 + 0.04 * ((x * 13 + y * 7) % 5 - 2) / 2.0
            pix.extend([max(0, min(1, color[0] * s)),
                        max(0, min(1, color[1] * s)),
                        max(0, min(1, color[2] * s)), 1.0])
    img.pixels = pix
    img.pack()
    return img


def make_solid_image(name, color):
    img = bpy.data.images.new(name, 8, 8, alpha=True)
    c = color if len(color) >= 3 else (0.7, 0.5, 0.52)
    pix = [float(c[0]), float(c[1]), float(c[2]), 1.0] * 64
    img.pixels.foreach_set(pix)
    img.update()
    img.pack()
    print("  image", name, [round(v, 3) for v in list(img.pixels)[:4]])
    return img


def make_mat(name, color, image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col4 = color if len(color) == 4 else tuple(color) + (1.0,)
    bsdf.inputs["Base Color"].default_value = col4
    bsdf.inputs["Roughness"].default_value = 0.92
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.15
    mat.diffuse_color = col4
    # Do not hook a packed image: those came out white in EEVEE/export.
    # Solid Base Color exports as albedo_color; ToonModel no longer adds a hull.
    if image is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def orthonormal_basis(axis):
    a = axis.normalized()
    helper = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
    x = a.cross(helper)
    if x.length < 1e-8:
        x = a.cross(Vector((0, 1, 0)))
    x.normalize()
    y = a.cross(x).normalized()
    return x, y


def make_sleeve(arm, side, mat_outer, mat_inner):
    """Frustum along the rest-pose arm, slightly past the wrist, wide cuff."""
    ua_h, ua_t = bone_pts(arm, "upper_arm." + side)
    fa_h, fa_t = bone_pts(arm, "forearm." + side)
    ha_h, ha_t = bone_pts(arm, "hand." + side)
    # start a little down the upper arm so it tucks under the shoulder robe
    p0 = ua_h.lerp(ua_t, -0.28)  # overlap the shoulder robe so the seam is soft
    # cuff past the wrist, not to the fingertips
    p1 = ha_h + (ha_t - ha_h) * 0.28
    axis = p1 - p0
    length = axis.length
    xaxis, yaxis = orthonormal_basis(axis)

    # radii in metres: shoulder cap, mid, wide cuff (reference 宽袖)
    r_start = 0.062  # overlaps the shoulder cap
    r_mid = 0.058     # slightly cinches so it is not a lantern
    r_cuff = 0.100    # wide hanging cuff, not a board
    rings = 9
    sides = 22
    verts = []
    # two layers: outer then inner (smaller, reversed)
    thickness = 0.007

    def ring_radius(t, outer=True):
        # Tight through the forearm, flare only in the last third: 上窄下宽,
        # not a mid-sleeve lantern. Cuff hangs past the wrist along the arm.
        if t < 0.62:
            u = t / 0.62
            r = r_start * (1 - u) + r_mid * u
        else:
            u = (t - 0.62) / 0.38
            u = u * u * (3 - 2 * u)
            r = r_mid * (1 - u) + r_cuff * u
        return r if outer else max(0.02, r - thickness)

    def add_layer(outer):
        base = len(verts)
        for i in range(rings):
            t = i / (rings - 1)
            c = p0 + axis * t
            r = ring_radius(t, outer)
            for k in range(sides):
                ang = 2 * math.pi * k / sides
                offset = xaxis * math.cos(ang) * r + yaxis * math.sin(ang) * r
                # slight downward (world -Z) bias so the sleeve hangs a little
                # even in A-pose, like cloth; small so it still follows the arm
                droop = Vector((0, 0, -1)) * (0.01 * t * t)
                verts.append(c + offset + droop)
        faces = []
        for i in range(rings - 1):
            for k in range(sides):
                a = base + i * sides + k
                b = base + i * sides + (k + 1) % sides
                c2 = base + (i + 1) * sides + (k + 1) % sides
                d = base + (i + 1) * sides + k
                if outer:
                    faces.append((a, b, c2, d))
                else:
                    faces.append((a, d, c2, b))
        return faces

    faces_o = add_layer(True)
    faces_i = add_layer(False)
    name = "Sleeve." + side
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces_o + faces_i)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.append(mat_outer)
    mesh.materials.append(mat_inner)
    # assign inner faces to slot 1
    n_outer = len(faces_o)
    for i, p in enumerate(mesh.polygons):
        p.material_index = 0 if i < n_outer else 1
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = arm
    obj.parent_type = "OBJECT"

    # vertex groups
    for n in ("shoulder." + side, "upper_arm." + side, "forearm." + side):
        obj.vertex_groups.new(name=n)

    # weight by ring parameter t along the arm
    # two layers, each rings*sides verts
    n_layer = rings * sides
    for li in range(2):
        for i in range(rings):
            t = i / (rings - 1)
            # 0..0.35 upper_arm, 0.35..0.65 blend, 0.65..1 forearm
            if t <= 0.30:
                wu, wf, ws = 0.85, 0.0, 0.15 * (1 - t / 0.30)
                wu = 1.0 - ws
                wf = 0.0
            elif t >= 0.62:
                wu, wf, ws = 0.0, 1.0, 0.0
            else:
                u = (t - 0.30) / 0.32
                wu, wf, ws = 1.0 - u, u, 0.0
            idxs = [li * n_layer + i * sides + k for k in range(sides)]
            if ws > 0:
                obj.vertex_groups["shoulder." + side].add(idxs, ws, "REPLACE")
            if wu > 0:
                obj.vertex_groups["upper_arm." + side].add(idxs, wu, "REPLACE")
            if wf > 0:
                obj.vertex_groups["forearm." + side].add(idxs, wf, "REPLACE")

    am = obj.modifiers.new("arm", "ARMATURE")
    am.object = arm
    print("  made", name, "verts", len(verts), "len", round(length, 3))
    return obj


def apply_action(arm, name, frame=1):
    act = bpy.data.actions.get(name)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    arm.data.pose_position = "POSE"
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def setup_preview():
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    bpy.context.scene.eevee.taa_render_samples = 8
    bpy.context.scene.render.resolution_x = 900
    bpy.context.scene.render.resolution_y = 1080
    bpy.context.scene.render.film_transparent = True
    world = bpy.data.worlds.new("W")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.97, 0.97, 0.97, 1)
    bg.inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("SunL", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.7, 0.2, 0.4)
    bpy.context.scene.collection.objects.link(sun)


def look_cam(loc, target, name):
    camd = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, camd)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj
    return obj


def render_one(path, loc, target, cam_name):
    look_cam(loc, target, cam_name)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  render", path)


def drop_helpers():
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None and o.name.startswith("Ico"):
            print("  drop", o.name)
            bpy.data.objects.remove(o, do_unlink=True)


def export_keep_anims(path, arm):
    if arm.animation_data:
        arm.animation_data.action = None
        for tr in arm.animation_data.nla_tracks:
            tr.mute = False
    bpy.context.scene.frame_start = 1
    bpy.context.scene.render.fps = 24
    drop_helpers()
    bpy.context.view_layer.update()
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


def main():
    print("SRC", SRC, "exists", os.path.exists(SRC))
    clear_scene()
    arm, body, props = import_keep_anims(SRC)
    print("body", body.name, "v", len(body.data.vertices), "f", len(body.data.polygons),
          "props", [p.name for p in props],
          "actions", [a.name for a in bpy.data.actions])
    flap = collect_flap_indices(arm, body)
    print("flap verts", len(flap))
    # side split
    xs = [(body.matrix_world @ body.data.vertices[i].co).x for i in flap] if flap else [0]
    print("  flap x", round(min(xs), 3), round(max(xs), 3), "nL", sum(1 for x in xs if x < 0),
          "nR", sum(1 for x in xs if x >= 0))
    n = delete_and_sew(body, flap)
    if n < 0:
        return
    pink = sample_robe_pink(body)
    # Sampled robe is a bit high-key under EEVEE; deepen and saturate so the
    # untextured sleeves sit next to the textured robe instead of looking pale.
    pink = (
        max(0.05, min(1.0, pink[0] * 0.92)),
        max(0.05, min(1.0, pink[1] * 0.88)),
        max(0.05, min(1.0, pink[2] * 0.90)),
    )
    lining = (min(1.0, pink[0] + 0.08), min(1.0, pink[1] + 0.10), min(1.0, pink[2] + 0.10))
    print("  sleeve color", tuple(round(c, 3) for c in pink))
    mat_o = make_mat("LinSleeveOuter", (pink[0], pink[1], pink[2], 1.0))
    mat_i = make_mat("LinSleeveLining", (lining[0], lining[1], lining[2], 1.0))
    make_sleeve(arm, "L", mat_o, mat_i)
    make_sleeve(arm, "R", mat_o, mat_i)

    setup_preview()
    apply_action(arm, "idle", 1)
    render_one(os.path.join(RENDER, "idle_front.png"), (0.15, -2.2, 1.25), (0, 0, 1.0), "cf")
    render_one(os.path.join(RENDER, "idle_side.png"), (2.2, -0.4, 1.2), (0, 0, 1.0), "cs")
    apply_action(arm, "walk", 8)
    render_one(os.path.join(RENDER, "walk_front.png"), (0.15, -2.2, 1.25), (0, 0, 1.0), "cw")
    export_keep_anims(DST_TMP, arm)
    print("DONE", DST_TMP)


if __name__ == "__main__":
    main()
