#!/usr/bin/env python3
"""Reassign UVs on gray fill-cap triangles so they sample interior cloth
texels from neighbouring faces, not atlas gutters.

  ~/.local/bin/blender -b --python tools/img3d/fix_fill_uvs.py
"""
import os
from mathutils import Vector

import bmesh
import bpy

SRC_DIR = "/tmp/glb_backup_pre_round7"
OUT = "/tmp/fix_fill_uv"
os.makedirs(OUT, exist_ok=True)

# A texel is "cloth" if reasonably lit and not a near-black gutter / hole.
LUM_MIN = 0.38
LUM_MAX = 0.97
EDGE_PX = 3


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_keep_anims(path):
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = None
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if o.type == "MESH":
            if o.name.startswith("BackPatch"):
                continue
            if o.parent == arm and o.parent_type == "BONE":
                continue
            if body is None or len(o.data.vertices) > len(body.data.vertices):
                body = o
    return arm, body


def get_image(obj):
    if not obj.data.materials:
        return None
    mat = obj.data.materials[0]
    if not mat or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 64:
            return n.image
    return None


def lum_of(rgb):
    return 0.30 * rgb[0] + 0.59 * rgb[1] + 0.11 * rgb[2]


def sample(px, w, h, ch, u, v):
    x = int(max(0, min(w - 1, u * w)))
    y = int(max(0, min(h - 1, v * h)))
    i = (y * w + x) * ch
    return px[i], px[i + 1], px[i + 2]


def is_cloth_uv(px, w, h, ch, u, v):
    """Interior cloth texel, not an atlas gutter or a painted hole."""
    r, g, b = sample(px, w, h, ch, u, v)
    lum = lum_of((r, g, b))
    if lum < 0.45 or lum > 0.97:
        return False
    # Near the 0/1 wrap a dark sample is almost certainly gutter.
    if (u < 3.0 / w or u > 1.0 - 3.0 / w or v < 3.0 / h or v > 1.0 - 3.0 / h) and lum < 0.60:
        return False
    return True


def face_uv_centroid(f, uvlay):
    acc = Vector((0.0, 0.0))
    n = 0
    for lp in f.loops:
        acc += lp[uvlay].uv
        n += 1
    return acc / n if n else Vector((0.5, 0.5))


def vert_key(p, nd=4):
    return (round(p.x, nd), round(p.y, nd), round(p.z, nd))


def face_key(obj, poly):
    return frozenset(vert_key(obj.matrix_world @ obj.data.vertices[i].co) for i in poly.vertices)


def original_lookup(pre_path):
    """Face keys and per-vertex cloth UVs from the pre-fill mesh."""
    # Import into the current scene, capture, then delete the imported objects.
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=pre_path)
    imported = [o for o in bpy.data.objects if o not in before]
    pre_body = None
    for o in imported:
        if o.type == "MESH" and not o.name.startswith("BackPatch"):
            if o.parent_type == "BONE":
                continue
            if pre_body is None or len(o.data.vertices) > len(pre_body.data.vertices):
                pre_body = o
    keys = set()
    uv_at = {}
    if pre_body is not None and pre_body.data.uv_layers.active:
        uv = pre_body.data.uv_layers.active
        for poly in pre_body.data.polygons:
            keys.add(face_key(pre_body, poly))
            for li, vi in zip(poly.loop_indices, poly.vertices):
                p = vert_key(pre_body.matrix_world @ pre_body.data.vertices[vi].co)
                uv_at.setdefault(p, []).append(uv.data[li].uv.copy())
        print("  pre faces", len(keys), "vert uv keys", len(uv_at))
    # Delete imported objects (and their data).
    for o in imported:
        bpy.data.objects.remove(o, do_unlink=True)
    # Also drop leftover meshes/actions? Don't drop actions — they may collide
    # with the already-imported current file if we call this AFTER current import.
    return keys, uv_at


def world_co_mesh(obj, vi):
    return obj.matrix_world @ obj.data.vertices[vi].co


def is_cloth_region(name, p):
    """Only retarget fills on the robe / sleeves / skirt, never hair or belt."""
    if name == "shenyan":
        if p.z > 1.42 or p.z < 0.20:
            return False
        if 0.84 <= p.z <= 1.03 and abs(p.x) < 0.18 and abs(p.y) < 0.16:
            return False  # belt
        return True
    # linzhaowan: skirt and lower/mid dress, not hair
    if p.z > 1.38:
        return False
    if p.z < 0.90 and abs(p.x) < 0.40:
        return True
    if 0.90 <= p.z <= 1.35 and abs(p.x) < 0.30:
        return True
    return False


def fix_uvs(obj, name, pre_keys, uv_at, img):
    w, h, ch = img.size[0], img.size[1], img.channels
    px = list(img.pixels)
    print("  tex", img.name, w, h, ch)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    uvlay = bm.loops.layers.uv.active
    if uvlay is None:
        print("  no uv")
        bm.free()
        return 0

    def fkey(f):
        return frozenset(vert_key(obj.matrix_world @ v.co) for v in f.verts)

    def fcom(f):
        return sum((obj.matrix_world @ v.co for v in f.verts), Vector()) / len(f.verts)

    new_faces = []
    for f in bm.faces:
        if fkey(f) in pre_keys:
            continue
        c = fcom(f)
        if not is_cloth_region(name, c):
            continue
        new_faces.append(f)
    print("  fill faces in cloth region", len(new_faces))

    # Original cloth samples: (world pos, uv, rgb). Prefer bright robe / pink
    # texels so a fill does not pick a mid-grey gutter neighbour.
    def bright_enough(rgb, name, p):
        lum = lum_of(rgb)
        if name == "shenyan":
            # Pale robe, or the light-blue trim.
            if lum >= 0.70:
                return True
            r, g, b = rgb
            if lum >= 0.55 and b > r + 0.04 and b > 0.45:
                return True
            return False
        r, g, b = rgb
        if lum >= 0.78:
            return True  # white underskirt
        if r >= 0.55 and r > g + 0.04 and lum >= 0.50:
            return True  # pink robe
        return False

    orig_samples = []
    for key, uvs in uv_at.items():
        for uv in uvs:
            rgb = sample(px, w, h, ch, uv.x, uv.y)
            if bright_enough(rgb, name, Vector(key)):
                orig_samples.append((Vector(key), uv.copy(), rgb))
                break
    print("  bright orig samples", len(orig_samples))

    def pick_uv(p, name):
        # Among nearby original cloth samples, pick the brightest (then nearest).
        best, score = None, -1e9
        for q, uv, rgb in orig_samples:
            d = (p - q).length
            if d > 0.18:
                continue
            lum = lum_of(rgb)
            # closer and brighter wins
            s = lum * 1.4 - d * 3.0
            if s > score:
                score, best = s, uv
        if best is not None:
            return best
        # fallback: nearest bright sample even if slightly farther
        bd, best = 1e9, None
        for q, uv, rgb in orig_samples:
            d = (p - q).length_squared
            if d < bd:
                bd, best = d, uv
        return best

    fixed, skipped = 0, 0
    still_bad = 0
    for f in new_faces:
        c = fcom(f)
        uv = pick_uv(c, name)
        if uv is None:
            skipped += 1
            continue
        rgb = sample(px, w, h, ch, uv.x, uv.y)
        if not bright_enough(rgb, name, c):
            skipped += 1
            continue
        # Use a tiny spread so the cap is not a single-texel sparkle.
        for i, lp in enumerate(f.loops):
            off = Vector((0.001 * ((i % 3) - 1), 0.001 * ((i // 3) - 0.5)))
            lp[uvlay].uv = uv + off
        fixed += 1

    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()
    print("  retargeted", fixed, "skipped", skipped)
    return fixed


def apply_idle(arm):
    act = bpy.data.actions.get("idle")
    if arm.animation_data is None:
        arm.animation_data_create()
    if act:
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


def render_one(path, loc, target, name):
    camd = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, camd)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  render", path)


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


def process(name, views):
    src = os.path.join(SRC_DIR, name + ".glb")
    pre = os.path.join("/tmp/glb_backup_pre_round6", name + ".glb")
    dst = "/tmp/%s_r7.glb" % name
    print("====", name)
    clear_scene()
    # Read the pre-fill mesh first, then fully reset so actions don't duplicate.
    pre_keys, uv_at = original_lookup(pre)
    clear_scene()
    arm, body = import_keep_anims(src)
    print("body", body.name, "v", len(body.data.vertices), "f", len(body.data.polygons),
          "actions", [a.name for a in bpy.data.actions])
    img = get_image(body)
    if img is None:
        print("  no image, abort")
        return
    fix_uvs(body, name, pre_keys, uv_at, img)
    apply_idle(arm)
    setup_preview()
    for fname, loc, target, cam in views:
        render_one(os.path.join(OUT, fname), loc, target, cam)
    export_keep_anims(dst, arm)
    print("DONE", dst)


def main():
    process("shenyan", [
        ("shenyan_frontclose.png", (0.0, -1.4, 1.20), (0.0, 0.0, 1.10), "cfc"),
        ("shenyan_backclose.png", (-0.2, 1.4, 1.2), (0.0, 0.05, 1.1), "cc"),
    ])
    process("linzhaowan", [
        ("lin_front.png", (0.0, -2.6, 1.0), (0.0, 0.0, 0.95), "lf"),
        ("lin_side.png", (2.2, -0.6, 1.0), (0.0, 0.0, 0.95), "ls"),
    ])


if __name__ == "__main__":
    main()
