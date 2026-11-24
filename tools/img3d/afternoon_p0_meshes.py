#!/usr/bin/env python3
"""Inspect and clean leftover mesh islands on 厉横 / 打手, shorten 厉横's dao.

Uses import_keep_anims / export_keep_anims so walk clips stay intact.
"""
import os
from mathutils import Vector
import bmesh
import bpy

SRC_DIR = "/workspace/godogen-shanhe-fe/assets/glb"
DST_DIR = "/tmp/afternoon_p0"
os.makedirs(DST_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_keep_anims(path):
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = None
    props = []
    extras = []
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if o.type == "MESH":
            if o.parent == arm and o.parent_type == "BONE":
                props.append(o)
            elif o.name.startswith("BackPatch"):
                extras.append(o)
            elif body is None or len(o.data.vertices) > len(body.data.vertices):
                body = o
    return arm, body, props, extras


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


def world_co(obj, i):
    return obj.matrix_world @ obj.data.vertices[i].co


def islands(obj):
    """Return list of (vert_indices, face_count, centroid, bbox_min, bbox_max)."""
    mesh = obj.data
    n = len(mesh.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for p in mesh.polygons:
        vs = list(p.vertices)
        for i in range(1, len(vs)):
            union(vs[0], vs[i])
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    face_count = {k: 0 for k in groups}
    for p in mesh.polygons:
        face_count[find(p.vertices[0])] += 1
    out = []
    for root, idxs in groups.items():
        pts = [world_co(obj, i) for i in idxs]
        cx = sum(p.x for p in pts) / len(pts)
        cy = sum(p.y for p in pts) / len(pts)
        cz = sum(p.z for p in pts) / len(pts)
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        out.append((idxs, face_count[root], Vector((cx, cy, cz)), mn, mx))
    out.sort(key=lambda t: -len(t[0]))
    return out


def bone_world(arm, name):
    b = arm.pose.bones.get(name)
    if b is None:
        return None
    return arm.matrix_world @ b.head, arm.matrix_world @ b.tail


def report(name, body, props):
    print("====", name, "body", body.name, "v", len(body.data.vertices),
          "f", len(body.data.polygons), "props", [p.name for p in props])
    parts = islands(body)
    print("  islands", len(parts))
    for i, (idxs, fc, c, mn, mx) in enumerate(parts[:12]):
        size = (mx - mn)
        print(f"    #{i} v={len(idxs)} f={fc} c=({c.x:.3f},{c.y:.3f},{c.z:.3f}) "
              f"size=({size.x:.3f},{size.y:.3f},{size.z:.3f}) z=[{mn.z:.3f},{mx.z:.3f}]")
    for p in props:
        bb = [p.matrix_world @ Vector(c) for c in p.bound_box]
        xs, ys, zs = [v.x for v in bb], [v.y for v in bb], [v.z for v in bb]
        print(f"  prop {p.name} parent_bone={p.parent_bone} "
              f"loc={tuple(round(x,3) for x in p.location)} "
              f"world_z=[{min(zs):.3f},{max(zs):.3f}] "
              f"len={((max(xs)-min(xs))**2+(max(ys)-min(ys))**2+(max(zs)-min(zs))**2)**0.5:.3f}")
    return parts


def delete_verts(obj, indices):
    if not indices:
        return 0
    kill = set(indices)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in kill if i < len(bm.verts)], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(kill)


def main():
    for name in ("liheng", "yaoxing_dashou", "shenyan"):
        clear_scene()
        path = os.path.join(SRC_DIR, name + ".glb")
        arm, body, props, extras = import_keep_anims(path)
        # play rest / frame 1 idle if possible
        if arm.animation_data and arm.animation_data.nla_tracks:
            for tr in arm.animation_data.nla_tracks:
                tr.mute = False
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        parts = report(name, body, props)
        # print bone hands/feet
        for bn in ("hand.L", "hand.R", "foot.L", "foot.R", "spine", "chest", "hips"):
            pts = bone_world(arm, bn)
            if pts:
                h, t = pts
                print(f"  bone {bn} head=({h.x:.3f},{h.y:.3f},{h.z:.3f}) tail=({t.x:.3f},{t.y:.3f},{t.z:.3f})")
        if name == "shenyan":
            for o in list(bpy.data.objects):
                if "Sword" in o.name or "Tassel" in o.name:
                    print("  sword obj", o.name, "parent", o.parent, "bone", getattr(o, "parent_bone", None),
                          "mw_trans", tuple(round(x, 3) for x in o.matrix_world.translation))


if __name__ == "__main__":
    main()
