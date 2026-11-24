#!/usr/bin/env python3
"""第六轮优化前置巡检：读取原始 GLB 的底数，输出 JSON 证据。

统计每个模型：三角面数、顶点数、骨骼数、动画 clip、包围盒、
孤立岛数量（焊接后连通分量）、是否贴地、主贴图色彩空间抽样。

用法：
  ~/.local/bin/blender -b --python tools/optmodel/inspect_glb.py -- <glb...>
不带参数则巡检 assets/glb/ 下全部 6 个。
"""
import json
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = "/home/xiaoyan/games/godogen-shanhe-fe"
GLB_DIR = os.path.join(ROOT, "assets/glb")
OUT = os.path.join(ROOT, "tools/optmodel/out")
os.makedirs(OUT, exist_ok=True)

ALL = [
    "shenyan.glb", "shenyan_script.glb", "linzhaowan.glb",
    "liheng.glb", "gesancheng.glb", "yaoxing_dashou.glb",
]

# 设计身高（米）：与 world_builder.gd NPC_MODELS / 第三轮沈砚规格一致。
DESIGN_HEIGHT = {
    "shenyan": 1.70, "shenyan_script": 1.70, "linzhaowan": 1.63,
    "liheng": 1.85, "gesancheng": 1.65, "yaoxing_dashou": 1.72,
}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def pick(objects, types):
    return [o for o in objects if o.type in types]


def import_glb(path):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    return list(bpy.data.objects)


def island_stats(obj, weld=1e-4):
    """焊接位置后的连通分量：数量、最小顶点岛占比。"""
    mesh = obj.data
    nv = len(mesh.vertices)
    if nv == 0:
        return 0, 1.0
    lookup = {}
    rep = [0] * nv
    for i, v in enumerate(mesh.vertices):
        key = (round(v.co.x / weld), round(v.co.y / weld), round(v.co.z / weld))
        if key in lookup:
            rep[i] = lookup[key]
        else:
            lookup[key] = i
            rep[i] = i
    parent = list(range(nv))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for p in mesh.polygons:
        vs = [find(rep[i]) for i in p.vertices]
        a = vs[0]
        for b in vs[1:]:
            if find(a) != find(b):
                parent[find(b)] = find(a)
    sizes = {}
    for i in range(nv):
        r = find(rep[i])
        sizes[r] = sizes.get(r, 0) + 1
    if not sizes:
        return 0, 1.0
    biggest = max(sizes.values())
    return len(sizes), biggest / nv


def tri_vert_count(obj):
    """换算三角面数（评估用，不改网格）。"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tris = sum(max(1, len(f.verts) - 2) for f in bm.faces)
    n = len(bm.verts)
    bm.free()
    return tris, n


def sample_tex_colorspace(obj):
    """主贴图中心像素：判断 Blender pixels 是线性还是 sRGB 原值。"""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                img = n.image
                w, h = img.size
                if w == 0 or h == 0:
                    continue
                px = img.pixels
                i = ((h // 2) * w + (w // 2)) * 4
                return {
                    "name": img.name, "size": [w, h],
                    "colorspace": img.colorspace_settings.name,
                    "center_rgb_raw": [round(px[i], 3), round(px[i + 1], 3),
                                       round(px[i + 2], 3)],
                }
    return None


def inspect(name):
    path = os.path.join(GLB_DIR, name)
    objs = import_glb(path)
    meshes = pick(objs, {"MESH"})
    arms = pick(objs, {"ARMATURE"})
    arm = arms[0] if arms else None
    if arm is not None:
        arm.data.pose_position = "REST"
        bpy.context.view_layer.update()

    total_tris = 0
    total_verts = 0
    islands = 0
    biggest_frac = 1.0
    boxes = []
    has_color0 = False
    tex_info = None
    body_mesh = None
    for m in meshes:
        if body_mesh is None or len(m.data.vertices) > len(body_mesh.data.vertices):
            body_mesh = m
        t, v = tri_vert_count(m)
        total_tris += t
        total_verts += v
        ci, cf = island_stats(m)
        islands += ci
        biggest_frac = min(biggest_frac, cf)
        boxes.append(m.matrix_world @ m.bound_box) if False else None
        corners = [m.matrix_world @ __import__("mathutils").Vector(c) for c in m.bound_box]
        boxes.append(corners)
        if any(len(m.data.color_attributes) > 0 for _ in [0]):
            has_color0 = True
        if tex_info is None:
            tex_info = sample_tex_colorspace(m)

    zs = []
    if body_mesh is not None:
        for c in body_mesh.bound_box:
            zs.append((body_mesh.matrix_world @ Vector(c)).z)
    zmin = min(zs) if zs else 0.0
    zmax = max(zs) if zs else 0.0

    clips = []
    if arm is not None:
        clips = sorted(a.name for a in bpy.data.actions)

    info = {
        "file": name,
        "triangles": total_tris,
        "vertices": total_verts,
        "bones": len(arm.data.bones) if arm else 0,
        "clips": clips,
        "meshes": len(meshes),
        "islands_welded": islands,
        "biggest_island_frac": round(biggest_frac, 4),
        "body_bbox_z": [round(zmin, 3), round(zmax, 3)],
        "body_height_m": round(zmax - zmin, 3),
        "design_height_m": DESIGN_HEIGHT.get(name.replace(".glb", ""), 1.70),
        "has_color0": has_color0,
        "texture": tex_info,
        "file_bytes": os.path.getsize(path),
    }
    return info


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [os.path.basename(a) for a in argv] if argv else ALL
    out = []
    for name in names:
        try:
            info = inspect(name)
        except Exception as e:  # noqa: BLE001
            info = {"file": name, "error": str(e)}
        out.append(info)
        print(json.dumps(info, ensure_ascii=False))
    dst = os.path.join(OUT, "baseline.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("WROTE", dst)


main()
