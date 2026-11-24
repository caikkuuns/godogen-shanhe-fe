#!/usr/bin/env python3
"""校验优化后的 GLB：三角面/骨骼/动画/孤立岛/包围盒/贴图尺寸/文件体积

用法：blender -b -P tools/optmodel/verify_glb.py -- <file.glb>
输出：单行 `VERIFY_JSON {...}`，方便 shell 抓取。
"""
import bpy
import bmesh
import json
import os
import sys


def islands_of(mesh_obj):
    bm = bmesh.new()
    bm.from_mesh(mesh_obj.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    comps = 0
    for v in bm.verts:
        if v.index in seen:
            continue
        comps += 1
        stack = [v]
        while stack:
            x = stack.pop()
            if x.index in seen:
                continue
            seen.add(x.index)
            for e in x.link_edges:
                ov = e.other_vert(x)
                if ov.index not in seen:
                    stack.append(ov)
    bm.free()
    return comps


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        print("usage: blender -b -P verify_glb.py -- <file.glb>")
        sys.exit(2)
    path = argv[0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    tris = 0
    verts = 0
    for o in meshes:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        verts += len(o.data.vertices)

    # 包围盒
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ __import__("mathutils").Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    height = mx[2] - mn[2]

    # 贴图
    tex = []
    for img in bpy.data.images:
        if img.name in ("Render Result", "Viewer Node"):
            continue
        tex.append({"name": img.name, "size": list(img.size)})

    clips = [a.name for a in bpy.data.actions]
    islands = sum(islands_of(o) for o in meshes)

    data = {
        "file": os.path.basename(path),
        "bytes": os.path.getsize(path),
        "mb": round(os.path.getsize(path) / 1048576.0, 2),
        "triangles": tris,
        "vertices": verts,
        "meshes": len(meshes),
        "bones": len(arm.data.bones) if arm else 0,
        "clips": clips,
        "has_idle": any("idle" in c.lower() for c in clips),
        "has_walk": any("walk" in c.lower() for c in clips),
        "islands": islands,
        "bbox_min": [round(v, 3) for v in mn],
        "bbox_max": [round(v, 3) for v in mx],
        "height_m": round(height, 3),
        "feet_at_ground": abs(mn[2]) < 0.05,
        "textures": tex,
    }
    print("VERIFY_JSON " + json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
