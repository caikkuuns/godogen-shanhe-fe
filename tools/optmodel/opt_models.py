#!/usr/bin/env python3
"""《山河剑行》角色 GLB 优化器（Blender headless）

用法：
  blender -b -P tools/optmodel/opt_models.py -- <输入.glb> <输出.glb> [目标三角面]

做四件事，且**不破坏骨骼蒙皮与动画**：
  1. 去除孤立碎片（按顶点数累计覆盖 99.5% 保留，删掉零碎小岛）
  2. Decimate 收敛到目标三角面（默认 6000），保留顶点组/权重
  3. 贴图降到 512×512（体积主因是 2048² 贴图）
  4. 只读导出 GLB

注意：
  - **不要**对 MeshInstance 做 object.scale（会破坏骨骼绑定），身高校正由游戏侧
    CharacterModel 统一处理（已有 1.70m 逻辑），或原模型本身已是 1.70m。
  - 原始 assets/glb/*.glb 绝不修改，输出到 assets/glb/opt/。
"""
import bpy
import bmesh
import os
import sys

TARGET_TRIS = 6000
TEX_MAX = 1024
ISLAND_COVER = 0.995


def tri_count(objs):
    total = 0
    for o in objs:
        o.data.calc_loop_triangles()
        total += len(o.data.loop_triangles)
    return total


def strip_islands(objs):
    """删除小岛：按顶点数降序累计，保留覆盖 99.5% 的岛。"""
    removed = 0
    kept_islands = 0
    dropped_islands = 0
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.verts.ensure_lookup_table()
        seen = set()
        comps = []
        for v in bm.verts:
            if v.index in seen:
                continue
            stack = [v]
            comp = []
            while stack:
                x = stack.pop()
                if x.index in seen:
                    continue
                seen.add(x.index)
                comp.append(x)
                for e in x.link_edges:
                    ov = e.other_vert(x)
                    if ov.index not in seen:
                        stack.append(ov)
            comps.append(comp)
        comps.sort(key=len, reverse=True)
        total = sum(len(c) for c in comps)
        if total == 0:
            bm.free()
            continue
        acc = 0
        keep_ids = set()
        for c in comps:
            keep_ids.add(id(c))
            acc += len(c)
            if acc / total >= ISLAND_COVER:
                break
        for c in comps:
            if id(c) in keep_ids:
                kept_islands += 1
            else:
                bmesh.ops.delete(bm, geom=c, context='VERTS')
                removed += len(c)
                dropped_islands += 1
        bm.to_mesh(o.data)
        bm.free()
    return removed, kept_islands, dropped_islands


def weld_meshes(objs, dist=0.0015):
    """焊接重叠顶点：TripoSR 导出是三角面碎片，不焊接直接减面会打穿薄壳。"""
    welded = 0
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        before = len(bm.verts)
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
        welded += before - len(bm.verts)
        bm.to_mesh(o.data)
        bm.free()
    return welded


def decimate(objs, target):
    before = tri_count(objs)
    ratio = min(1.0, float(target) / max(before, 1))
    if ratio >= 0.999:
        return before, before
    for o in objs:
        bpy.context.view_layer.objects.active = o
        m = o.modifiers.new(name="opt_dec", type='DECIMATE')
        m.decimate_type = 'COLLAPSE'
        m.ratio = ratio
        m.use_collapse_triangulate = True
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as e:
            print("[warn] decimate apply failed on %s: %s" % (o.name, e))
    return before, tri_count(objs)


def shrink_textures(max_size):
    changed = []
    for img in bpy.data.images:
        if not img.size[0] or not img.size[1]:
            continue
        if img.size[0] <= max_size and img.size[1] <= max_size:
            continue
        w, h = img.size
        scale = float(max_size) / max(w, h)
        nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
        img.scale(nw, nh)
        changed.append((img.name, (w, h), (nw, nh)))
    return changed


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) < 2:
        print("usage: blender -b -P opt_models.py -- <in.glb> <out.glb> [target_tris]")
        sys.exit(2)
    src, dst = argv[0], argv[1]
    target = int(argv[2]) if len(argv) > 2 else TARGET_TRIS
    if not os.path.exists(src):
        print("[error] 找不到输入:", src)
        sys.exit(1)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    clips = [a.name for a in bpy.data.actions]
    bones = len(arm.data.bones) if arm else 0

    tris_in = tri_count(meshes)
    removed, kept, dropped = strip_islands(meshes)
    welded = weld_meshes(meshes)
    tris_mid, tris_out = decimate(meshes, target)
    tex = shrink_textures(TEX_MAX)

    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format='GLB',
        export_animations=True,
        export_skins=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_yup=True,
    )
    size = os.path.getsize(dst)
    print(">>> RESULT %s" % dst)
    print("    tris_in=%d tris_after_islands=%d tris_out=%d" % (tris_in, tris_mid, tris_out))
    print("    bones=%d clips=%d islands_removed=%d verts_removed=%d welded=%d" % (bones, len(clips), dropped, removed, welded))
    print("    textures_resized=%d" % len(tex))
    print("    bytes=%d (%.2f MB)" % (size, size / 1048576.0))


if __name__ == "__main__":
    main()
