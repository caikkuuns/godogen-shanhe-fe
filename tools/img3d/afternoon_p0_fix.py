#!/usr/bin/env python3
"""Remove large loose fragments on 厉横 / 打手 and shorten 厉横's blade.

import_keep_anims / export_keep_anims — do not rewrite clips.
"""
import os
from mathutils import Vector
import bmesh
import bpy

SRC = "/tmp/glb_backup_pre_afternoon"
DST = "/tmp/afternoon_p0"
os.makedirs(DST, exist_ok=True)


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


def drop_helpers():
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None and o.name.startswith("Ico"):
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
    out = []
    for idxs in groups.values():
        pts = [world_co(obj, i) for i in idxs]
        c = Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts),
                    sum(p.z for p in pts) / len(pts)))
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        out.append((idxs, c, mn, mx))
    return out


def min_bone_dist(arm, p, names):
    d = 1e9
    for n in names:
        b = arm.pose.bones.get(n)
        if not b:
            continue
        h = arm.matrix_world @ b.head
        t = arm.matrix_world @ b.tail
        w = t - h
        l2 = w.length_squared
        if l2 < 1e-8:
            d = min(d, (p - h).length)
            continue
        tval = max(0.0, min(1.0, (p - h).dot(w) / l2))
        d = min(d, (h + w * tval - p).length)
    return d


BONES = [
    "head", "neck", "chest", "spine", "hips",
    "shoulder.L", "upper_arm.L", "forearm.L", "hand.L",
    "shoulder.R", "upper_arm.R", "forearm.R", "hand.R",
    "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
]


def should_delete(idxs, c, mn, mx, d):
    # Only flat ground-level debris. Taller islands are shin wraps / trousers.
    size = mx - mn
    v = len(idxs)
    if v >= 16 and d >= 0.12 and mx.z < 0.065 and size.z < 0.07:
        return True
    return False


def delete_verts(obj, indices):
    if not indices:
        return 0
    kill = set(indices)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    geom = [bm.verts[i] for i in kill if i < len(bm.verts)]
    bmesh.ops.delete(bm, geom=geom, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(kill)


def shorten_dao(prop, scale_z=0.68):
    """Scale the blade along local Z about the grip (object origin)."""
    mesh = prop.data
    for v in mesh.vertices:
        v.co.z *= scale_z
    mesh.update()
    print(f"  scaled {prop.name} local Z * {scale_z}")


def render_views(name, tag):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x = 720
    sc.render.resolution_y = 1280
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    # camera
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    sc.camera = cam
    light = bpy.data.objects.new("L", bpy.data.lights.new("L", "AREA"))
    light.data.energy = 400
    light.data.size = 2
    light.location = (1.2, -1.6, 2.2)
    bpy.context.scene.collection.objects.link(light)
    views = {
        "front": ((0, -2.8, 1.0), (0, 0, 0.9)),
        "side": ((2.6, 0.0, 1.0), (0, 0, 0.9)),
    }
    for vname, (loc, look) in views.items():
        cam.location = loc
        direction = Vector(look) - Vector(loc)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(DST, f"{name}_{tag}_{vname}.png")
        bpy.ops.render.render(write_still=True)
        print("  render", sc.render.filepath)


def process(name, shorten=False):
    clear_scene()
    path = os.path.join(SRC, name + ".glb")
    print("====", name)
    arm, body, props = import_keep_anims(path)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    # before renders already exist from the first pass
    parts = islands(body)
    kill = []
    for idxs, c, mn, mx in parts:
        d = min_bone_dist(arm, c, BONES)
        if should_delete(idxs, c, mn, mx, d):
            size = mx - mn
            print(f"  DEL v={len(idxs)} c=({c.x:.3f},{c.y:.3f},{c.z:.3f}) "
                  f"z=[{mn.z:.3f},{mx.z:.3f}] size=({size.x:.3f},{size.y:.3f},{size.z:.3f}) d={d:.3f}")
            kill.extend(idxs)
    n = delete_verts(body, kill)
    print("  deleted verts", n)
    if shorten:
        for p in props:
            if "Dao" in p.name or "dao" in p.name:
                shorten_dao(p, 0.68)
    bpy.context.view_layer.update()
    render_views(name, "after")
    out = os.path.join(DST, name + ".glb")
    export_keep_anims(out, arm)
    # verify anim names
    import json, struct
    with open(out, "rb") as f:
        f.read(12)
        ln, _ = struct.unpack("<I4s", f.read(8))
        js = json.loads(f.read(ln))
    print("  anims", [a.get("name") for a in js.get("animations", [])])


def main():
    process("liheng", shorten=True)
    process("yaoxing_dashou", shorten=False)


if __name__ == "__main__":
    main()
