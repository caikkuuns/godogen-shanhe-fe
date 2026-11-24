#!/usr/bin/env python3
"""Local back-torso patch for Shenyan's remaining right-back tear.

Does not force-sew the shredded mesh. Builds a small robe panel over the
back, filling only between the leftmost and rightmost good back-surface
hits on each row so it cannot grow past the silhouette. Weighted to
chest/spine. Leaves bone rotation modes and existing actions alone.

  ~/.local/bin/blender -b --python tools/img3d/fix_shenyan_back_patch.py
"""
import os
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import bmesh
import bpy

SRC = "/tmp/glb_backup_pre_round5/shenyan.glb"
DST_TMP = "/tmp/shenyan_patched.glb"
RENDER = "/tmp/fix_back_patch"
os.makedirs(RENDER, exist_ok=True)

# Tight back-torso window in rest/model space (character faces -Y, back is +Y,
# character's right is -X). Covers the large through-tear on the upper right
# back (the F-region around x -0.25..0.0, z 1.05..1.38) and nearby mid-back
# holes. Does not grow past the silhouette.
X0, X1 = -0.28, 0.22
Z0, Z1 = 0.96, 1.34
NX, NZ = 40, 44
OFFSET = 0.005


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


def make_solid_tex_mat(name, color):
    """Packed constant robe texture so Godot's ToonModel treats the patch
    as textured (no inverted-hull) and the colour survives glTF export."""
    img = bpy.data.images.new(name + "Tex", 8, 8, alpha=True)
    pix = [float(color[0]), float(color[1]), float(color[2]), 1.0] * 64
    img.pixels.foreach_set(pix)
    img.update()
    img.pack()
    print("  ", name, "tex px", [round(c, 3) for c in list(img.pixels)[:4]])
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    mat.diffuse_color = (color[0], color[1], color[2], 1.0)
    return mat


def sample_back_robe_color(body):
    """Median mid-tone colour from intact back-robe texels, skipping belt/holes."""
    fallback = (0.78, 0.78, 0.82)
    uv = body.data.uv_layers.active
    img = None
    if body.data.materials and body.data.materials[0].use_nodes:
        for n in body.data.materials[0].node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 64:
                img = n.image
                break
    if img is None or uv is None:
        return fallback
    w, h, ch = img.size[0], img.size[1], img.channels
    px = list(img.pixels)
    samples = []
    for poly in body.data.polygons:
        vs = [body.matrix_world @ body.data.vertices[vi].co for vi in poly.vertices]
        c = sum(vs, Vector()) / len(vs)
        if not (0.04 < c.y < 0.22 and 0.92 < c.z < 1.22 and abs(c.x) < 0.16):
            continue
        for li in poly.loop_indices:
            u, v = uv.data[li].uv
            x = int(max(0, min(w - 1, u * w)))
            y = int(max(0, min(h - 1, v * h)))
            i = (y * w + x) * ch
            r, g, b = px[i], px[i + 1], px[i + 2]
            lum = 0.3 * r + 0.59 * g + 0.11 * b
            chroma = max(r, g, b) - min(r, g, b)
            if lum < 0.55 or lum > 0.92 or chroma > 0.16:
                continue
            samples.append((r, g, b))
    if len(samples) < 8:
        print("  robe sample fallback, n", len(samples))
        return fallback
    samples.sort(key=lambda t: 0.3 * t[0] + 0.59 * t[1] + 0.11 * t[2])
    # 80th percentile: match the lit pale robe, not the purple fold shadows.
    mid = samples[int(len(samples) * 0.80)]
    print("  patch robe color", tuple(round(c, 3) for c in mid), "n", len(samples))
    return mid


def build_patch(body, arm):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.transform(body.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()

    def ray(x, z):
        hit = tree.ray_cast(Vector((x, 0.55, z)), Vector((0.0, -1.0, 0.0)), 1.1)
        return hit[0] if hit and hit[0] is not None else None

    hits = [[None] * NX for _ in range(NZ)]
    inside = [[False] * NX for _ in range(NZ)]
    good_n = 0
    for iz in range(NZ):
        z = Z0 + (Z1 - Z0) * iz / (NZ - 1)
        for ix in range(NX):
            x = X0 + (X1 - X0) * ix / (NX - 1)
            # Stay on the torso: skip the shoulder / armpit wings.
            if abs(x) > 0.20 and z > 1.26:
                continue
            if abs(x) > 0.24:
                continue
            p = ray(x, z)
            if p is not None and 0.035 < p.y < 0.22:
                hits[iz][ix] = p
                inside[iz][ix] = True
                good_n += 1
            elif p is not None and p.y <= 0.035:
                inside[iz][ix] = True
    print("  good back hits", good_n, "/", NX * NZ)

    hole = [[False] * NX for _ in range(NZ)]
    for iz in range(NZ):
        cols = [ix for ix in range(NX) if inside[iz][ix]]
        if not cols:
            continue
        lo, hi = min(cols), max(cols)
        for ix in range(lo, hi + 1):
            if hits[iz][ix] is None and inside[iz][ix]:
                hole[iz][ix] = True
        # misses strictly between silhouette edges are also holes
        for ix in range(lo, hi + 1):
            if hits[iz][ix] is None:
                hole[iz][ix] = True

    cover = [row[:] for row in hole]
    for iz in range(NZ):
        for ix in range(NX):
            if not hole[iz][ix]:
                continue
            for jz in range(max(0, iz - 1), min(NZ, iz + 2)):
                for jx in range(max(0, ix - 1), min(NX, ix + 2)):
                    if hits[jz][jx] is not None:
                        cover[jz][jx] = True

    def interp_y(iz, ix):
        acc, wt = 0.0, 0.0
        for jz in range(max(0, iz - 6), min(NZ, iz + 7)):
            for jx in range(max(0, ix - 6), min(NX, ix + 7)):
                q = hits[jz][jx]
                if q is None:
                    continue
                d2 = (jx - ix) ** 2 + (jz - iz) ** 2
                w = 1.0 / max(d2, 0.25)
                acc += q.y * w
                wt += w
        return (acc / wt) if wt else 0.10

    verts = []
    idx_of = [[None] * NX for _ in range(NZ)]
    filled = 0
    seam = 0
    xs, zs = [], []
    for iz in range(NZ):
        z = Z0 + (Z1 - Z0) * iz / (NZ - 1)
        for ix in range(NX):
            if not cover[iz][ix]:
                continue
            x = X0 + (X1 - X0) * ix / (NX - 1)
            if hits[iz][ix] is not None:
                y = hits[iz][ix].y + OFFSET
                seam += 1
            else:
                y = interp_y(iz, ix) + OFFSET
                filled += 1
            idx_of[iz][ix] = len(verts)
            verts.append((x, y, z))
            xs.append(x)
            zs.append(z)
    faces = []
    for iz in range(NZ - 1):
        for ix in range(NX - 1):
            a = idx_of[iz][ix]
            b = idx_of[iz][ix + 1]
            c = idx_of[iz + 1][ix + 1]
            d = idx_of[iz + 1][ix]
            if None not in (a, b, c, d):
                # Wind CCW when viewed from +Y (back, outside) so the normal
                # points out of the back. (a,b,c,d) was clockwise and the
                # exported normals faced +Z / inward, so Godot CULL_BACK hid the patch.
                faces.append((a, d, c, b))
    print("  patch verts", len(verts), "faces", len(faces),
          "filled holes", filled, "seam", seam)
    if xs:
        print("  patch x", round(min(xs), 3), round(max(xs), 3),
              "z", round(min(zs), 3), round(max(zs), 3))
    if not faces:
        print("  ABORT no patch faces")
        return None

    mesh = bpy.data.meshes.new("BackPatch")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for p in mesh.polygons:
        p.use_smooth = True
    cover = bpy.data.objects.new("BackPatch", mesh)
    bpy.context.scene.collection.objects.link(cover)
    color = sample_back_robe_color(body)
    # Solid colour only. Packed 8x8 images rendered white in EEVEE/export;
    # ToonModel no longer adds a hull, so an untextured robe colour is safe.
    mat = bpy.data.materials.new("BackPatchMat")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.95
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    mat.diffuse_color = (color[0], color[1], color[2], 1.0)
    cover.data.materials.append(mat)
    # Do not shrinkwrap: nearest-surface snaps through the tear onto the
    # front of the robe. Y is already interpolated from intact back hits.
    # Light Laplacian on Y only, no bpy.ops (those left the pose/context messy).
    verts = cover.data.vertices
    nbrs = [[] for _ in verts]
    for poly in cover.data.polygons:
        vs = list(poly.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            nbrs[a].append(b)
            nbrs[b].append(a)
    for _ in range(4):
        new_co = [v.co.copy() for v in verts]
        for i, v in enumerate(verts):
            if not nbrs[i]:
                continue
            avg = sum((verts[j].co for j in nbrs[i]), Vector()) / len(nbrs[i])
            # Relax x/z just enough to round the stair-steps; keep most of the
            # coverage so the tear does not reopen.
            new_co[i].x = 0.72 * v.co.x + 0.28 * avg.x
            new_co[i].y = 0.55 * v.co.y + 0.45 * avg.y
            new_co[i].z = 0.72 * v.co.z + 0.28 * avg.z
        for i, v in enumerate(verts):
            v.co = new_co[i]
    cover.data.update()
    cover.parent = arm
    cover.parent_type = "OBJECT"
    for g in body.vertex_groups:
        cover.vertex_groups.new(name=g.name)
    uvl = cover.data.uv_layers.new(name="UVMap")
    for poly in cover.data.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = Vector((0.5, 0.5))

    def weights_of(i):
        out = []
        for g in body.vertex_groups:
            try:
                w = g.weight(i)
                if w > 1e-5:
                    out.append((g.name, w))
            except RuntimeError:
                pass
        return out

    buckets = {}
    def key(p):
        return (int(p.x * 20), int(p.y * 20), int(p.z * 20))
    body_pts = [(i, body.matrix_world @ v.co) for i, v in enumerate(body.data.vertices)]
    for i, p in body_pts:
        buckets.setdefault(key(p), []).append((i, p))

    def nearest(p):
        best, bestd = 0, 1e9
        kx, ky, kz = key(p)
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                for dz in range(-2, 3):
                    for i, q in buckets.get((kx + dx, ky + dy, kz + dz), []):
                        d = (p - q).length_squared
                        if d < bestd:
                            bestd, best = d, i
        return best

    for i, v in enumerate(cover.data.vertices):
        p = Vector(v.co)
        ws = weights_of(nearest(p))
        torso = [(n, w) for n, w in ws if n in {"chest", "spine", "hips"}]
        if not torso:
            t = (p.z - 0.86) / 0.46
            torso = [("hips", max(0.0, 0.35 - t)), ("spine", 0.35), ("chest", max(0.0, t))]
            torso = [(n, w) for n, w in torso if w > 0]
        s = sum(w for _, w in torso) or 1.0
        for name, w in torso:
            cover.vertex_groups[name].add([i], w / s, "REPLACE")

    am = cover.modifiers.new("arm", "ARMATURE")
    am.object = arm
    print("  patch ready")
    return cover


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


def main():
    print("SRC", SRC)
    clear_scene()
    arm, body, props = import_keep_anims(SRC)
    print("body", body.name, "v", len(body.data.vertices), "props", [p.name for p in props],
          "actions", [a.name for a in bpy.data.actions])
    cover = build_patch(body, arm)
    if cover is None:
        return
    apply_idle(arm)
    setup_preview()
    render_one(os.path.join(RENDER, "after_back.png"), (0.0, 2.4, 1.15), (0.0, 0.0, 1.05), "cb")
    render_one(os.path.join(RENDER, "after_backclose.png"), (-0.2, 1.4, 1.2), (0.0, 0.05, 1.1), "cc")
    export_keep_anims(DST_TMP, arm)
    print("DONE", DST_TMP)


if __name__ == "__main__":
    main()
