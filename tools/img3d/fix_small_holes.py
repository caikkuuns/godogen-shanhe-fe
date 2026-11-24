#!/usr/bin/env python3
"""Fill remaining small boundary holes on Shenyan and Linzhaowan, and
press Shenyan's back patch into the robe so the stair-step edge is hidden.

Does not force-sew large tears. Leaves bone rotations and existing actions
alone.

  ~/.local/bin/blender -b --python tools/img3d/fix_small_holes.py
"""
import os
import sys
from mathutils import Vector

import bmesh
import bpy

ROOT = "/tmp/glb_backup_pre_round6"
OUT = "/tmp/fix_small_holes"
os.makedirs(OUT, exist_ok=True)


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
            elif o.name.startswith("BackPatch"):
                continue
            elif body is None or len(o.data.vertices) > len(body.data.vertices):
                body = o
    return arm, body, props


def world_co(obj, v):
    return obj.matrix_world @ v.co


def ordered_loop_verts(edges):
    if not edges:
        return []
    adj = {}
    for e in edges:
        a, b = e.verts[0], e.verts[1]
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    start = edges[0].verts[0]
    verts = [start]
    prev = None
    cur = start
    for _ in range(len(edges) + 2):
        nxts = [v for v in adj.get(cur, []) if v is not prev]
        if not nxts:
            break
        nxt = nxts[0]
        if nxt is start:
            break
        verts.append(nxt)
        prev, cur = cur, nxt
    return verts


def manual_fan(bm, edges):
    verts = ordered_loop_verts(edges)
    if len(verts) < 3:
        return []
    new = []
    v0 = verts[0]
    for i in range(1, len(verts) - 1):
        try:
            f = bm.faces.new((v0, verts[i], verts[i + 1]))
            new.append(f)
        except ValueError:
            continue
    return new


def assign_uvs_from_rim(uvlay, faces, fallback):
    for f in faces:
        for lp in f.loops:
            src = None
            for l2 in lp.vert.link_loops:
                if l2 is lp or uvlay is None:
                    continue
                uv = l2[uvlay].uv.copy()
                if uv.length > 1e-6:
                    src = uv
                    break
            if src is None:
                src = fallback.copy()
            lp[uvlay].uv = src


def classify(name, com):
    """Return (keep, max_extent, tag). Conservative small-hole regions."""
    if name == "shenyan":
        if com.z > 1.52:  # bun / hair volume, not the face openings
            return True, 0.10, "hair"
        if 1.38 < com.z <= 1.52 and com.y > -0.02:  # back of head / hair
            return True, 0.10, "hair"
        if 0.22 <= com.z <= 0.58 and abs(com.x) < 0.28:  # hem
            return True, 0.16, "hem"
        if 0.70 <= com.z <= 1.35 and 0.15 < abs(com.x) < 0.42:  # sleeve sides
            return True, 0.14, "sleeve"
        if 0.55 <= com.z <= 1.40 and abs(com.x) < 0.22 and com.y < 0.05:
            # front chest / robe, and mid sides
            return True, 0.14, "front"
        if 0.70 <= com.z <= 1.38 and com.y > 0.02 and abs(com.x) < 0.34:
            return True, 0.12, "back"
        return False, 0.0, ""
    # linzhaowan
    if com.z < 0.85 and abs(com.x) < 0.38:  # skirt / hem
        return True, 0.18, "skirt"
    if 0.85 <= com.z <= 1.35 and abs(com.x) < 0.28 and com.y < 0.08:
        return True, 0.12, "torso"
    if com.z > 1.40:
        return True, 0.10, "hair"
    return False, 0.0, ""


def fill_small_holes(obj, name):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    uvlay = bm.loops.layers.uv.active

    used = set()
    cands = []
    for e0 in bm.edges:
        if not e0.is_boundary or e0.index in used:
            continue
        loop = [e0]
        used.add(e0.index)
        vcur = e0.verts[1]
        closed = False
        for _ in range(20000):
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
        if not closed or not (4 <= len(loop) <= 80):
            continue
        verts, seen = [], set()
        for e in loop:
            for v in e.verts:
                if v.index not in seen:
                    seen.add(v.index)
                    verts.append(v)
        pts = [world_co(obj, v) for v in verts]
        com = sum(pts, Vector()) / len(pts)
        keep, max_ext, tag = classify(name, com)
        if not keep:
            continue
        xs = [p.x for p in pts]
        ys = [p.y for p in pts]
        zs = [p.z for p in pts]
        extent = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        if extent > max_ext:
            continue
        nrm = Vector((0, 0, 0))
        for i, p in enumerate(pts):
            nrm += (p - com).cross(pts[(i + 1) % len(pts)] - com)
        if nrm.length < 1e-8:
            continue
        nrm.normalize()
        rms = (sum((p - com).dot(nrm) ** 2 for p in pts) / len(pts)) ** 0.5
        if rms > 0.028:
            continue
        cands.append((loop, com, extent, rms, tag, len(loop)))

    print("  candidate small holes", len(cands), "on", name)
    fallback = Vector((0.4, 0.4))
    if uvlay is not None:
        # pick a cloth UV near the torso
        best, bestd = None, 1e9
        target = Vector((0.0, -0.06, 1.00))
        for f in bm.faces:
            c = world_co(obj, f.verts[0])
            d = (c - target).length
            if d < bestd and 0.7 < c.z < 1.25:
                bestd = d
                fallback = f.loops[0][uvlay].uv.copy()

    filled_n = 0
    new_total = 0
    skipped = 0
    tags = {}
    for loop, com, extent, rms, tag, n in cands:
        edges = [e for e in loop if e.is_valid and e.is_boundary]
        if len(edges) < 3:
            continue
        before = set(bm.faces)
        added = []
        for fn in (
            lambda: bmesh.ops.triangle_fill(bm, use_beauty=True, edges=edges),
            lambda: bmesh.ops.holes_fill(bm, edges=edges, sides=0),
            lambda: bmesh.ops.edgeloop_fill(bm, edges=edges),
        ):
            try:
                fn()
            except Exception:
                continue
            added = [f for f in bm.faces if f not in before and f.is_valid]
            if added:
                break
        if not added:
            added = manual_fan(bm, edges)
        if not added:
            skipped += 1
            continue
        ok = True
        for f in added:
            pts = [world_co(obj, v) for v in f.verts]
            sp = (
                max(p.x for p in pts) - min(p.x for p in pts),
                max(p.y for p in pts) - min(p.y for p in pts),
                max(p.z for p in pts) - min(p.z for p in pts),
            )
            if max(sp) > 0.22 or f.calc_area() > 0.025:
                ok = False
                break
        if not ok:
            bmesh.ops.delete(bm, geom=added, context="FACES")
            skipped += 1
            continue
        assign_uvs_from_rim(uvlay, added, fallback)
        for f in added:
            f.smooth = True
            c = sum((world_co(obj, v) for v in f.verts), Vector()) / len(f.verts)
            nw = (obj.matrix_world.to_3x3() @ f.normal).normalized()
            # Outward: front should face -Y, back +Y.
            if c.y < 0 and nw.y > 0:
                f.normal_flip()
            elif c.y > 0 and nw.y < 0:
                f.normal_flip()
        filled_n += 1
        new_total += len(added)
        tags[tag] = tags.get(tag, 0) + 1
        print("    filled %s n=%d ext=%.3f rms=%.3f com=(%.3f,%.3f,%.3f)" % (
            tag, n, extent, rms, com.x, com.y, com.z))

    try:
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    except Exception:
        pass
    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.mesh.normals_make_consistent(inside=False)
    except Exception as exc:
        print("  normals skip", exc)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("  filled loops", filled_n, "faces", new_total, "skipped", skipped, "by tag", tags)
    return filled_n


def polish_back_patch(arm):
    cover = next((o for o in bpy.data.objects if o.name.startswith("BackPatch")), None)
    if cover is None:
        print("  no BackPatch")
        return
    # Recolor closer to the mid-back robe (slightly cooler, less flat-white).
    color = (0.755, 0.745, 0.775, 1.0)
    if cover.data.materials:
        mat = cover.data.materials[0]
        if mat and mat.use_nodes:
            bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf:
                bsdf.inputs["Base Color"].default_value = color
        mat.diffuse_color = color
        print("  patch color", color[:3])

    mesh = cover.data
    # Boundary verts: any edge used by only one face.
    bound = set()
    edge_faces = {}
    for p in mesh.polygons:
        vs = list(p.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            key = (min(a, b), max(a, b))
            edge_faces.setdefault(key, []).append(p.index)
    for (a, b), fs in edge_faces.items():
        if len(fs) == 1:
            bound.add(a)
            bound.add(b)
    print("  patch boundary verts", len(bound), "of", len(mesh.vertices))

    # Press the patch into the robe: edges go in further so the existing
    # cloth covers the stair-step, the interior stays just outside the holes.
    for i, v in enumerate(mesh.vertices):
        if i in bound:
            v.co.y -= 0.014
        else:
            v.co.y -= 0.004

    # Extra Laplacian on x/z (and a little y) to round leftover stairs.
    nbrs = [[] for _ in mesh.vertices]
    for (a, b) in edge_faces:
        nbrs[a].append(b)
        nbrs[b].append(a)
    verts = mesh.vertices
    for _ in range(6):
        new_co = [v.co.copy() for v in verts]
        for i, v in enumerate(verts):
            if not nbrs[i]:
                continue
            avg = sum((verts[j].co for j in nbrs[i]), Vector()) / len(nbrs[i])
            k = 0.45 if i in bound else 0.28
            new_co[i].x = (1 - k) * v.co.x + k * avg.x
            new_co[i].y = (1 - k * 0.6) * v.co.y + (k * 0.6) * avg.y
            new_co[i].z = (1 - k) * v.co.z + k * avg.z
        for i, v in enumerate(verts):
            v.co = new_co[i]
    mesh.update()
    print("  patch pressed and smoothed")


def apply_idle(arm):
    act = bpy.data.actions.get("idle")
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    arm.data.pose_position = "POSE"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def setup_preview():
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    bpy.context.scene.eevee.taa_render_samples = 8
    bpy.context.scene.render.resolution_x = 720
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


def render_one(path, loc, target, name):
    look_cam(loc, target, name)
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


def process(name, dst, views):
    src = os.path.join(ROOT, name + ".glb")
    print("====", name, "SRC", src)
    clear_scene()
    arm, body, props = import_keep_anims(src)
    print("body", body.name, "v", len(body.data.vertices), "props", [p.name for p in props],
          "actions", [a.name for a in bpy.data.actions])
    fill_small_holes(body, name)
    if name == "shenyan":
        polish_back_patch(arm)
    apply_idle(arm)
    setup_preview()
    for fname, loc, target, cam in views:
        render_one(os.path.join(OUT, fname), loc, target, cam)
    export_keep_anims(dst, arm)
    print("DONE", dst)


def main():
    process("shenyan", "/tmp/shenyan_r6.glb", [
        ("shenyan_front.png", (0.0, -2.4, 1.15), (0.0, 0.0, 1.05), "cf"),
        ("shenyan_frontclose.png", (0.0, -1.4, 1.20), (0.0, 0.0, 1.10), "cfc"),
        ("shenyan_back.png", (0.0, 2.4, 1.15), (0.0, 0.0, 1.05), "cb"),
        ("shenyan_backclose.png", (-0.2, 1.4, 1.2), (0.0, 0.05, 1.1), "cc"),
    ])
    process("linzhaowan", "/tmp/linzhaowan_r6.glb", [
        ("lin_front.png", (0.0, -2.6, 1.0), (0.0, 0.0, 0.95), "lf"),
        ("lin_side.png", (2.2, -0.6, 1.0), (0.0, 0.0, 0.95), "ls"),
        ("lin_walk.png", (0.0, -2.6, 1.0), (0.0, 0.0, 0.95), "lw"),
    ])


if __name__ == "__main__":
    main()
