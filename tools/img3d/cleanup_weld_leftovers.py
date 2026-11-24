#!/usr/bin/env python3
"""Remove leftover welded weapons, sew only the new cut rim, move Shenyan's
new sword to the visual left shoulder (image right), add a pale-blue tassel.

Start from /tmp/glb_backup_pre_detach so Liheng's feet stay intact.
Do not trust bone L/R names for screen side: hand.L is world -X = image left
= the character's right hand in these facing--Y GLBs.
"""
import importlib.util
import math
import os

import bmesh
import bpy
from mathutils import Vector, Matrix

SD = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("dw", os.path.join(SD, "detach_weapons.py"))
dw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dw)

BACKUP = "/tmp/glb_backup_pre_detach"
GLB_DIR = "/workspace/godogen-shanhe-fe/assets/glb"
RENDER = "/tmp/detach_weapons/cleanup_render"
os.makedirs(RENDER, exist_ok=True)


def world_cos(obj):
    mw = obj.matrix_world
    return [mw @ v.co for v in obj.data.vertices]


def adjacency(obj):
    n = len(obj.data.vertices)
    adj = [[] for _ in range(n)]
    for e in obj.data.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    return adj


def flood_indices(obj, seed_idx, protected):
    adj = adjacency(obj)
    seen = set()
    stack = [i for i in seed_idx if i not in protected]
    for i in stack:
        seen.add(i)
    while stack:
        i = stack.pop()
        for j in adj[i]:
            if j not in seen and j not in protected:
                seen.add(j)
                stack.append(j)
    print(f"  flood seeds={len(seed_idx)} protected={len(protected)} delete={len(seen)}")
    return seen


def bone_protect_set(arm, body, radii, extra_pred=None):
    """Verts within radius of a listed bone, plus any extra_pred(p) == True."""
    segs = []
    for name, r in radii.items():
        try:
            h, t = dw.bone_pts(arm, name)
            segs.append((h, t, r))
        except Exception:
            pass
    prot = set()
    for i, p in enumerate(world_cos(body)):
        hit = False
        if extra_pred is not None and extra_pred(p):
            hit = True
        else:
            for h, t, r in segs:
                if dw.dist_seg(p, h, t) < r:
                    hit = True
                    break
        if hit:
            prot.add(i)
    return prot


def delete_and_local_fill(obj, indices, uv_fallback=None):
    n = len(indices)
    print(f"  delete {n} / {len(obj.data.vertices)} verts")
    if n == 0:
        return 0
    if n > 1800:
        print("  ABORT delete, too many verts — leaving body untouched")
        return 0
    idx_set = set(indices)
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    layer = bm.verts.layers.int.new("cut_rim")
    for v in bm.verts:
        v[layer] = 0
    for i in idx_set:
        if i >= len(bm.verts):
            continue
        v = bm.verts[i]
        for e in v.link_edges:
            o = e.other_vert(v)
            if o.index not in idx_set:
                o[layer] = 1
    to_del = [bm.verts[i] for i in idx_set if i < len(bm.verts)]
    bmesh.ops.delete(bm, geom=to_del, context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    rim_edges = [
        e for e in bm.edges
        if e.is_boundary and e.verts[0][layer] == 1 and e.verts[1][layer] == 1
    ]
    print(f"  cut rim edges {len(rim_edges)} verts left {len(bm.verts)}")
    if rim_edges:
        filled = False
        for op in ("holes_fill", "edgeloop_fill", "triangle_fill"):
            try:
                if op == "holes_fill":
                    bmesh.ops.holes_fill(bm, edges=rim_edges, sides=0)
                elif op == "edgeloop_fill":
                    bmesh.ops.edgeloop_fill(bm, edges=rim_edges)
                else:
                    bmesh.ops.triangle_fill(bm, edges=rim_edges)
                filled = True
                print("  filled with", op)
                break
            except Exception as e:
                print(f"  {op}:", e)
        if not filled:
            print("  WARN no fill")
    if uv_fallback is not None and bm.loops.layers.uv:
        uvlay = bm.loops.layers.uv.active
        for f in bm.faces:
            if all(v[layer] == 1 for v in f.verts):
                for loop in f.loops:
                    loop[uvlay].uv = uv_fallback
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
    print(f"  mesh now {len(obj.data.vertices)} verts, {len(obj.data.polygons)} faces")
    return n


def collect_uvs(obj, indices):
    idx = set(indices)
    uv = obj.data.uv_layers.active
    if uv is None:
        return []
    out = []
    for p in obj.data.polygons:
        for li in p.loop_indices:
            if obj.data.loops[li].vertex_index in idx:
                out.append(tuple(uv.data[li].uv))
    return out


def robe_uv_sample(obj):
    uv = obj.data.uv_layers.active
    if uv is None:
        return (0.5, 0.4)
    best, bestd = (0.5, 0.4), 1e9
    target = Vector((0.0, -0.06, 1.05))
    for p in obj.data.polygons:
        for li in p.loop_indices:
            vi = obj.data.loops[li].vertex_index
            w = obj.matrix_world @ obj.data.vertices[vi].co
            d = (w - target).length
            if d < bestd and 0.8 < w.z < 1.25 and w.y < 0:
                bestd = d
                best = tuple(uv.data[li].uv)
    return best


def inpaint_texture_gated(obj, uvs, radius_px=6):
    """Only recolor sheath-brown / tassel-blue texels near deleted UVs.
    Leave robe white, collar blue, sash mid-blue alone."""
    if not uvs or not obj.data.materials:
        return
    mat = obj.data.materials[0]
    img = None
    if mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                img = n.image
                break
    if img is None:
        return
    w, h = img.size
    px = list(img.pixels)
    # robe target
    tr, tg, tb = 0.925, 0.922, 0.902
    marked = set()
    for u, v in uvs:
        cx = int(u * w) % w
        cy = int(v * h) % h
        for dy in range(-radius_px, radius_px + 1):
            for dx in range(-radius_px, radius_px + 1):
                if dx * dx + dy * dy > radius_px * radius_px:
                    continue
                marked.add(((cx + dx) % w, (cy + dy) % h))
    changed = 0
    for x, y in marked:
        i = (y * w + x) * 4
        r, g, b = px[i], px[i + 1], px[i + 2]
        # sheath / hair-dark brown (not skin)
        is_brown = (r < 0.55 and g < 0.45 and b < 0.40 and r > b + 0.04 and (r + g + b) < 1.2)
        # pale tassel blue, not the deeper collar/sash
        luma = r + g + b
        is_tassel = (b > r + 0.04 and b > 0.45 and luma > 1.6 and luma < 2.55 and r > 0.40)
        if is_brown or is_tassel:
            px[i], px[i + 1], px[i + 2] = tr, tg, tb
            changed += 1
    img.pixels[:] = px
    img.update()
    print(f"  inpainted {changed}/{len(marked)} gated texels on {img.name} {w}x{h}")


def mask_shenyan_old(arm, body):
    # Old welded sword is on world -X = image left = character's right shoulder.
    radii = {
        "hips": 0.18, "spine": 0.15, "neck": 0.10, "head": 0.14,
        "shoulder.R": 0.10, "upper_arm.R": 0.11, "forearm.R": 0.09, "hand.R": 0.08,
        "upper_arm.L": 0.10, "forearm.L": 0.09, "hand.L": 0.08,
        "thigh.L": 0.14, "shin.L": 0.13, "foot.L": 0.14,
        "thigh.R": 0.14, "shin.R": 0.13, "foot.R": 0.14,
    }
    # tight shoulder cap + chest robe close to the back, never the +X side
    def extra(p):
        if p.x > -0.02:
            return True
        if p.z < 1.08 or p.z > 1.64:
            return True
        if p.y < 0.015:
            return True
        # chest / spine robe on the back (close to body)
        if dw.dist_seg(p, *dw.bone_pts(arm, "chest")) < 0.11 and p.y < 0.090:
            return True
        if dw.dist_seg(p, *dw.bone_pts(arm, "shoulder.L")) < 0.048:
            return True
        return False
    prot = bone_protect_set(arm, body, radii, extra)
    worlds = world_cos(body)
    seeds = []
    for i, p in enumerate(worlds):
        if i in prot:
            continue
        # protruding sheath on the back
        if p.x < -0.04 and p.y > 0.085 and 1.12 < p.z < 1.58:
            seeds.append(i)
            continue
        # hilt / tassel poking over the shoulder (may have y near 0 or slightly front)
        if p.x < -0.10 and p.z > 1.28 and p.z < 1.60 and dw.dist_seg(p, *dw.bone_pts(arm, "head")) > 0.14:
            seeds.append(i)
    sel = flood_indices(body, seeds, prot)
    print(f"  shenyan old-sword verts {len(sel)}")
    return sel


def mask_dashou_banana(arm, body):
    # Banana is in hand.L (world -X, image left, visual right). Keep that side.
    # Tight seeds: club goes forward-down from a slightly back-set hand (y=+0.165).
    h, t = dw.bone_pts(arm, "hand.L")
    radii = {
        "hips": 0.18, "spine": 0.16, "chest": 0.17, "neck": 0.11, "head": 0.15,
        "shoulder.L": 0.11, "upper_arm.L": 0.13, "forearm.L": 0.11,
        "shoulder.R": 0.11, "upper_arm.R": 0.13, "forearm.R": 0.10, "hand.R": 0.09,
        "thigh.L": 0.16, "shin.L": 0.15, "foot.L": 0.16,
        "thigh.R": 0.15, "shin.R": 0.14, "foot.R": 0.15,
    }
    def extra(p):
        if dw.dist_seg(p, h, t) < 0.068:
            return True
        if p.x > -0.18:
            return True
        return False
    prot = bone_protect_set(arm, body, radii, extra)
    worlds = world_cos(body)
    seeds = []
    for i, p in enumerate(worlds):
        if i in prot:
            continue
        if p.x < -0.22 and p.y < 0.12 and p.z < h.z - 0.04:
            dhand = dw.dist_seg(p, h, t)
            if 0.09 < dhand < 0.52:
                seeds.append(i)
    sel = flood_indices(body, seeds, prot)
    print(f"  dashou banana verts {len(sel)}")
    return sel


def mask_liheng_old_dao(arm, body):
    # Old 4-hole dao is in hand.L (world -X, image left = character's right).
    # Backup has intact feet and no T-ghost; do not touch +X at all.
    h, t = dw.bone_pts(arm, "hand.L")
    radii = {
        "hips": 0.18, "spine": 0.16, "chest": 0.17, "neck": 0.11, "head": 0.15,
        "shoulder.L": 0.11, "upper_arm.L": 0.12, "forearm.L": 0.10,
        "shoulder.R": 0.11, "upper_arm.R": 0.12, "forearm.R": 0.10, "hand.R": 0.09,
        "thigh.L": 0.16, "shin.L": 0.15, "foot.L": 0.16,
        "thigh.R": 0.16, "shin.R": 0.15, "foot.R": 0.16,
    }
    def extra(p):
        if dw.dist_seg(p, h, t) < 0.062:
            return True
        if p.x > -0.12:  # never the image-right / left-foot side
            return True
        if p.z < 0.12 and dw.dist_seg(p, *dw.bone_pts(arm, "foot.L")) < 0.22:
            return True
        return False
    prot = bone_protect_set(arm, body, radii, extra)
    worlds = world_cos(body)
    seeds = []
    for i, p in enumerate(worlds):
        if i in prot:
            continue
        # hanging blade outboard of the visual right leg
        if p.x < -0.22 and p.z < 0.95:
            seeds.append(i)
    sel = flood_indices(body, seeds, prot)
    print(f"  liheng old-dao verts {len(sel)}")
    return sel


def place_shenyan_visual_left(arm):
    """Hilt on image RIGHT of the front camera = world +X = character's left shoulder."""
    sword, tassel = dw.make_back_sword()
    mouth = Vector((0.12, 0.16, 1.34))
    pommel_dir = Vector((0.06, 0.08, 0.22)).normalized()
    dw.set_matrix(sword, mouth, pommel_dir, hint=Vector((0, 1, 0)))
    sword = dw.attach_tassel(sword, tassel, mouth, pommel_dir, 0.16)
    dw.parent_to_bone(sword, arm, "chest")
    return sword


def place_club_visual_right(arm):
    return dw.place_dashou(arm, None)[0]


def place_dao_visual_right(arm):
    """Character's right hand = hand.L (world -X, image left). Do not use the bone name."""
    dao = dw.make_dao()
    h, t = dw.bone_pts(arm, "hand.L")
    grip = h.lerp(t, 0.38)
    # Tip down, slightly back, slightly outward so the blade hangs beside the leg.
    pommel_dir = Vector((0.04, -0.08, 1.0)).normalized()
    dw.set_matrix(dao, grip, pommel_dir, hint=Vector((0, 1, 0)))
    bpy.context.view_layer.update()
    # 180 around the shaft (not world Z) so the wide face turns toward the camera.
    q = __import__("mathutils").Quaternion(pommel_dir, math.radians(180))
    T = Matrix.Translation(grip)
    dao.matrix_world = T @ q.to_matrix().to_4x4() @ T.inverted() @ dao.matrix_world
    dw.parent_to_bone(dao, arm, "hand.L")
    return dao


def process(name, height, mask_fn, place_fn, inpaint=False):
    print("=" * 60, name)
    dw.clear_scene()
    src = os.path.join(BACKUP, f"{name}.glb")
    arm, body = dw.import_glb(src)
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    print(f"  backup verts={len(body.data.vertices)} z=[{min(zs):.3f},{max(zs):.3f}] h={height}")
    indices = mask_fn(arm, body)
    uvs = collect_uvs(body, indices) if inpaint else []
    uv_fb = robe_uv_sample(body)
    if inpaint and uvs:
        inpaint_texture_gated(body, uvs, radius_px=6)
    deleted = delete_and_local_fill(body, indices, uv_fallback=uv_fb)
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    print(f"  after patch deleted={deleted} verts={len(body.data.vertices)} z=[{min(zs):.3f},{max(zs):.3f}]")
    props = place_fn(arm)
    print("  props", [p.name for p in (props if isinstance(props, list) else [props])])
    dest = os.path.join(GLB_DIR, f"{name}.glb")
    dw.export_glb(dest, arm)
    rdir = os.path.join(RENDER, name)
    os.makedirs(rdir, exist_ok=True)
    dw.set_action(arm, "idle", 1)
    dw.setup_render(os.path.join(rdir, "v"), [("front", 0), ("side", -90), ("45", -45), ("back", 180)], height)
    dw.set_action(arm, "walk", 1)
    dw.setup_render(os.path.join(rdir, "walk"), [("front", 0), ("side", -90)], height)
    return dest


def main():
    process("shenyan", 1.70, mask_shenyan_old, place_shenyan_visual_left, inpaint=True)
    process("yaoxing_dashou", 1.72, mask_dashou_banana, place_club_visual_right)
    process("liheng", 1.85, mask_liheng_old_dao, place_dao_visual_right)
    print("DONE")


if __name__ == "__main__":
    main()
