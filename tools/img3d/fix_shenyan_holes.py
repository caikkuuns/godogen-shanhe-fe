#!/usr/bin/env python3
"""Fill Shenyan back/sleeve holes, project nearby robe UVs, and damp black
robe noise in the albedo. Does not touch bone rotation modes or rewrite
actions, so the existing idle/walk/combat clips stay intact.

Starts from the pre-round-4 backup so a previous inpaint cannot stain the belt.

  ~/.local/bin/blender -b --python tools/img3d/fix_shenyan_holes.py
"""
import os
from collections import deque

import bmesh
import bpy
from mathutils import Vector

SRC = "/tmp/glb_backup_pre_round4/shenyan.glb"
DST_TMP = "/tmp/shenyan_fixed.glb"
RENDER = "/tmp/fix_shenyan"
os.makedirs(RENDER, exist_ok=True)


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
    return arm, body, props


def get_albedo(obj):
    mat = obj.data.materials[0]
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 64:
            return n.image
    return None


def world_co(obj, v):
    return obj.matrix_world @ v.co


def is_belt_world(p):
    return 0.84 <= p.z <= 1.03 and abs(p.x) < 0.22 and abs(p.y) < 0.20


def is_hair_world(p):
    return p.z > 1.48 or (p.z > 1.42 and abs(p.x) < 0.16 and p.y > -0.05)


def is_boot_world(p):
    return p.z < 0.22


def is_cloth_world(p):
    if is_hair_world(p) or is_boot_world(p):
        return False
    if p.z < 0.22 or p.z > 1.48:
        return False
    return True


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


def fill_target_holes(obj):
    """Fill compact, planar boundary loops on the back and sleeve sides."""
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
        if not closed or not (6 <= len(loop) <= 100):
            continue
        verts, seen = [], set()
        for e in loop:
            for v in e.verts:
                if v.index not in seen:
                    seen.add(v.index)
                    verts.append(v)
        pts = [world_co(obj, v) for v in verts]
        com = sum(pts, Vector()) / len(pts)
        xs = [p.x for p in pts]
        ys = [p.y for p in pts]
        zs = [p.z for p in pts]
        span = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        extent = max(span)
        nrm = Vector((0, 0, 0))
        for i, p in enumerate(pts):
            nrm += (p - com).cross(pts[(i + 1) % len(pts)] - com)
        if nrm.length < 1e-8:
            continue
        nrm.normalize()
        rms = (sum((p - com).dot(nrm) ** 2 for p in pts) / len(pts)) ** 0.5
        on_back = com.y > 0.02 and 0.70 < com.z < 1.38 and abs(com.x) < 0.34
        on_sleeve = 0.82 < com.z < 1.30 and 0.16 < abs(com.x) < 0.40 and com.y > -0.06
        if not (on_back or on_sleeve):
            continue
        if extent > 0.34 or rms > 0.025:
            continue
        # skip cuff-like loops far out on the arm
        if abs(com.x) > 0.36 and com.z < 1.05:
            continue
        # skip neck
        if com.z > 1.36 and abs(com.x) < 0.12:
            continue
        cands.append((loop, com, extent, rms, len(loop), on_back))

    print("  candidate holes", len(cands))
    # good robe UV fallback: front chest
    fallback = Vector((0.35, 0.45))
    if uvlay is not None:
        best, bestd = None, 1e9
        target = Vector((0.0, -0.08, 1.08))
        for f in bm.faces:
            c = world_co(obj, f.verts[0])
            d = (c - target).length
            if d < bestd and 0.9 < c.z < 1.25 and c.y < -0.04:
                bestd = d
                fallback = f.loops[0][uvlay].uv.copy()
        print("  uv fallback", tuple(round(x, 3) for x in fallback), "d", round(bestd, 3))

    filled_n = 0
    new_total = 0
    skipped = 0
    for loop, com, extent, rms, n, on_back in cands:
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
        # reject oversized or inward-deep caps
        ok = True
        for f in added:
            pts = [world_co(obj, v) for v in f.verts]
            sp = (
                max(p.x for p in pts) - min(p.x for p in pts),
                max(p.y for p in pts) - min(p.y for p in pts),
                max(p.z for p in pts) - min(p.z for p in pts),
            )
            if max(sp) > 0.36 or f.calc_area() > 0.04:
                ok = False
                break
        if not ok:
            bmesh.ops.delete(bm, geom=added, context="FACES")
            skipped += 1
            continue
        assign_uvs_from_rim(uvlay, added, fallback)
        # outward normals: back faces should have +Y
        for f in added:
            c = sum((world_co(obj, v) for v in f.verts), Vector()) / len(f.verts)
            # bmesh normal is in local space
            nw = (obj.matrix_world.to_3x3() @ f.normal).normalized()
            if on_back and nw.y < 0:
                f.normal_flip()
        filled_n += 1
        new_total += len(added)
        print("    filled n=%d ext=%.3f rms=%.3f com=(%.3f,%.3f,%.3f) faces=%d" % (
            n, extent, rms, com.x, com.y, com.z, len(added)))

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
    print("  filled loops", filled_n, "new faces", new_total, "skipped", skipped,
          "mesh", len(obj.data.vertices), "v", len(obj.data.polygons), "f")
    return filled_n


def sample_texel(px, w, h, ch, u, v):
    x = int(max(0, min(w - 1, round(float(u) * w - 0.5))))
    y = int(max(0, min(h - 1, round(float(v) * h - 0.5))))
    i = (y * w + x) * ch
    return px[i], px[i + 1], px[i + 2], x, y


def inpaint_and_bleed(obj, img, bleed_px=64):
    w, h = img.size
    ch = img.channels
    px = list(img.pixels)
    uv = obj.data.uv_layers.active

    used = set()
    cloth_used = set()
    stain = set()
    robe_colors = []
    for poly in obj.data.polygons:
        com = Vector((0, 0, 0))
        for vi in poly.vertices:
            com += obj.matrix_world @ obj.data.vertices[vi].co
        com /= len(poly.vertices)
        cloth = is_cloth_world(com) and not is_belt_world(com)
        for li in poly.loop_indices:
            u, v = uv.data[li].uv
            r, g, b, x, y = sample_texel(px, w, h, ch, u, v)
            used.add((x, y))
            if not cloth:
                continue
            cloth_used.add((x, y))
            lum = r + g + b
            is_blue = (b > r + 0.06) and (b > 0.28) and lum > 0.7
            is_skin = (r > g + 0.04 and r > b + 0.06 and r > 0.35 and lum > 0.9)
            # only nearly-black / leftover-sword brown, not sash blue or soft shadows
            is_brown = (r < 0.55 and g < 0.48 and b < 0.40 and r > b + 0.04 and lum < 1.15)
            on_back = com.y > 0.03 and 0.75 < com.z < 1.38
            if (lum < 0.70 or (is_brown and on_back)) and not is_blue and not is_skin:
                stain.add((x, y))
            elif lum >= 2.10 and not is_skin:
                robe_colors.append((r, g, b))

    if robe_colors:
        n = len(robe_colors)
        robe_avg = tuple(sum(c[i] for c in robe_colors) / n for i in range(3))
    else:
        robe_avg = (0.925, 0.922, 0.902)
    print("  used", len(used), "cloth", len(cloth_used), "stain", len(stain),
          "robe n", len(robe_colors), "avg", tuple(round(c, 3) for c in robe_avg))

    # light grow: only into other very dark used cloth texels (2px)
    grow = set(stain)
    for x, y in list(stain):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                xx, yy = x + dx, y + dy
                if (xx, yy) not in cloth_used:
                    continue
                i = (yy * w + xx) * ch
                r, g, b = px[i], px[i + 1], px[i + 2]
                lum = r + g + b
                is_blue = (b > r + 0.06) and (b > 0.28) and lum > 0.7
                if lum < 0.85 and not is_blue:
                    grow.add((xx, yy))
    print("  stain grown", len(grow))

    def neighbors_color(x, y, radius):
        acc = [0.0, 0.0, 0.0]
        wt = 0.0
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                d2 = dx * dx + dy * dy
                if d2 == 0 or d2 > radius * radius:
                    continue
                xx, yy = x + dx, y + dy
                if (xx, yy) in grow:
                    continue
                if (xx, yy) not in cloth_used and (xx, yy) not in used:
                    continue
                if not (0 <= xx < w and 0 <= yy < h):
                    continue
                i = (yy * w + xx) * ch
                r, g, b = px[i], px[i + 1], px[i + 2]
                lum = r + g + b
                if lum < 1.8:
                    continue
                wgt = (1.0 / (d2 ** 0.5)) * (2.0 if (xx, yy) in cloth_used else 1.0)
                acc[0] += r * wgt
                acc[1] += g * wgt
                acc[2] += b * wgt
                wt += wgt
        if wt < 1e-6:
            return None
        return (acc[0] / wt, acc[1] / wt, acc[2] / wt)

    remaining = set(grow)
    changed = 0
    for _pass in range(6):
        if not remaining:
            break
        done = []
        rad = 10 if _pass < 3 else 18
        for x, y in list(remaining):
            col = neighbors_color(x, y, rad)
            if col is None:
                if _pass == 5:
                    col = robe_avg
                else:
                    continue
            i = (y * w + x) * ch
            px[i], px[i + 1], px[i + 2] = col
            if ch > 3:
                px[i + 3] = 1.0
            done.append((x, y))
            changed += 1
        for p in done:
            remaining.discard(p)
        print("    inpaint pass", _pass, "filled", len(done), "left", len(remaining))

    # isolated dark specks on otherwise bright cloth (close-up noise)
    speck = 0
    for x, y in list(cloth_used):
        i = (y * w + x) * ch
        r, g, b = px[i], px[i + 1], px[i + 2]
        lum = r + g + b
        if lum >= 1.20:
            continue
        is_blue = (b > r + 0.06) and (b > 0.28) and lum > 0.7
        if is_blue:
            continue
        col = neighbors_color(x, y, 8)
        if col is None:
            col = robe_avg
        px[i], px[i + 1], px[i + 2] = col
        if ch > 3:
            px[i + 3] = 1.0
        speck += 1
    print("  speckles", speck, "stain texels", changed)

    # gutter bleed from any used texel into near-black unused padding
    colors = {}
    for x, y in used:
        i = (y * w + x) * ch
        colors[(x, y)] = (px[i], px[i + 1], px[i + 2])
    frontier = list(used)
    dist = {p: 0 for p in used}
    bled = 0
    qi = 0
    while qi < len(frontier):
        x, y = frontier[qi]
        qi += 1
        d = dist[(x, y)]
        if d >= bleed_px:
            continue
        src = colors[(x, y)]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, yy = x + dx, y + dy
            if not (0 <= xx < w and 0 <= yy < h) or (xx, yy) in dist:
                continue
            if (xx, yy) in used:
                continue
            i = (yy * w + xx) * ch
            r, g, b = px[i], px[i + 1], px[i + 2]
            if r + g + b > 0.18:
                continue
            px[i], px[i + 1], px[i + 2] = src
            if ch > 3:
                px[i + 3] = 1.0
            colors[(xx, yy)] = src
            dist[(xx, yy)] = d + 1
            frontier.append((xx, yy))
            bled += 1
    print("  gutter bleed", bled)

    img.pixels[:] = px
    img.update()
    img.pack()
    img.filepath_raw = os.path.join(RENDER, "shenyan_albedo_fixed.png")
    img.file_format = "PNG"
    img.save()
    print("  wrote", img.filepath_raw)


def drop_helpers():
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None and o.name.startswith("Ico"):
            print("  drop", o.name)
            bpy.data.objects.remove(o, do_unlink=True)


def apply_idle(arm):
    act = bpy.data.actions.get("idle") or (bpy.data.actions[0] if bpy.data.actions else None)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    arm.data.pose_position = "POSE"
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    print("  preview action", act.name if act else None)


def setup_preview_world():
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
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("FillL", "AREA"))
    fill.data.energy = 80
    fill.data.size = 4
    fill.location = (1.5, -2.0, 2.2)
    bpy.context.scene.collection.objects.link(fill)


def look_cam(loc, target, name):
    camd = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, camd)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    direction = Vector(target) - Vector(loc)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj
    return obj


def render_views(prefix):
    setup_preview_world()
    look_cam((0.0, 2.4, 1.15), (0.0, 0.0, 1.05), "cam_back")
    bpy.context.scene.render.filepath = os.path.join(RENDER, prefix + "_back.png")
    bpy.ops.render.render(write_still=True)
    print("  render", bpy.context.scene.render.filepath)
    look_cam((0.15, -2.1, 1.35), (0.0, 0.0, 1.1), "cam_front")
    bpy.context.scene.render.filepath = os.path.join(RENDER, prefix + "_front.png")
    bpy.ops.render.render(write_still=True)
    print("  render", bpy.context.scene.render.filepath)
    look_cam((-0.35, 1.3, 1.25), (0.0, 0.05, 1.1), "cam_backclose")
    bpy.context.scene.render.filepath = os.path.join(RENDER, prefix + "_backclose.png")
    bpy.ops.render.render(write_still=True)
    print("  render", bpy.context.scene.render.filepath)


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
    print("SRC", SRC)
    clear_scene()
    arm, body, props = import_keep_anims(SRC)
    print("body", body.name, "v", len(body.data.vertices), "f", len(body.data.polygons),
          "props", [p.name for p in props],
          "actions", [a.name for a in bpy.data.actions])
    filled = fill_target_holes(body)
    # gap/back covers disabled: they grew into floating stair panels
    img = get_albedo(body)
    inpaint_and_bleed(body, img, bleed_px=64)
    apply_idle(arm)
    render_views("after")
    export_keep_anims(DST_TMP, arm)
    print("DONE filled", filled, "tmp", DST_TMP)


if __name__ == "__main__":
    main()
