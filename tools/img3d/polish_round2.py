#!/usr/bin/env python3
"""Second-pass animation polish on the five already-animated character GLBs.

- Plant down poses so body+props sit on the ground
- Delete dashou leftover weapon islands
- Pull 林照晚 T-sleeves in toward the hanging arms (bind-invert)
- Put 葛三秤 rod+weight in the same hand (hand.L, visual right)
- Drop stray Icosphere helpers
- Keep existing idle/walk/attack/hit/down actions

  ~/.local/bin/blender -b --python tools/img3d/polish_round2.py
"""
import math
import os
import sys
from mathutils import Vector, Matrix, Euler, Quaternion

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rebuild_anims as ra

GLB_DIR = ra.GLB_DIR
RENDER = "/tmp/rebuild_anims_r2"
os.makedirs(RENDER, exist_ok=True)


def delete_helpers():
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None and o.name.startswith("Ico"):
            print("  drop", o.name, "verts", len(o.data.vertices))
            bpy.data.objects.remove(o, do_unlink=True)
        elif o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)


def body_of():
    return max((o for o in bpy.data.objects if o.type == "MESH"),
               key=lambda o: len(o.data.vertices))


def real_props(body):
    out = []
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not body and o.parent_bone:
            out.append(o)
    return out


def ev_zmin(o):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(deps)
    me = ev.to_mesh()
    zs = [(ev.matrix_world @ v.co).z for v in me.vertices] or [0.0]
    ev.to_mesh_clear()
    return min(zs)


def ev_pts(o):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def bone_matrix(arm, name):
    pb = arm.pose.bones[name]
    return arm.matrix_world @ pb.matrix


def set_idle(arm):
    ra.set_action(arm, "idle", 1)


# ---------- dashou leftover islands ----------

def delete_dashou_islands(arm, body):
    """Drop small body islands left over from the welded banana club."""
    import bmesh
    set_idle(arm)
    # posed vertex positions (same order as data.vertices for this mesh)
    pts = ev_pts(body)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    comps = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        comp = []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                oth = e.other_vert(x)
                if oth.index not in seen:
                    seen.add(oth.index)
                    stack.append(oth)
        comps.append(comp)

    # hanging hand / club neighbourhood
    hand_m = bone_matrix(arm, "hand.L")
    hand_p = hand_m.translation
    club = next((o for o in bpy.data.objects if "Club" in o.name), None)
    club_pts = ev_pts(club) if club else []
    club_com = sum(club_pts, Vector()) / max(1, len(club_pts)) if club_pts else hand_p

    drop = set()
    for comp in comps:
        if not (3 <= len(comp) <= 180):
            continue
        rest_com = sum((body.matrix_world @ Vector(v.co) for v in comp), Vector()) / len(comp)
        posed_com = sum((pts[v.index] for v in comp), Vector()) / len(comp)
        # leftover: small island near the visual-right hand / floating in front
        near_hand = (posed_com - hand_p).length < 0.55 or (posed_com - club_com).length < 0.40
        isolated_side = rest_com.x < -0.35 and len(comp) < 130
        floating_fwd = rest_com.y < -0.20 and rest_com.x < -0.15 and len(comp) < 80
        if (near_hand and rest_com.x < -0.20 and len(comp) < 130) or isolated_side or floating_fwd:
            # don't drop if this is clearly the palm (very close to hand bone, decent size)
            if (posed_com - hand_p).length < 0.07 and len(comp) > 40:
                continue
            for v in comp:
                drop.add(v.index)
            print(f"  drop island n={len(comp)} rest=({rest_com.x:.3f},{rest_com.y:.3f},{rest_com.z:.3f}) "
                  f"posed=({posed_com.x:.3f},{posed_com.y:.3f},{posed_com.z:.3f})")
    bm.free()
    if not drop:
        print("  no leftover islands matched")
        return 0
    # also drop tiny 3-vert shards around the same neighbourhood
    # (already included if they matched)
    mesh = body.data
    # mask and build new mesh
    keep = [i for i in range(len(mesh.vertices)) if i not in drop]
    # remap faces
    old = {old: new for new, old in enumerate(keep)}
    verts = [mesh.vertices[i].co.copy() for i in keep]
    # preserve vertex groups
    group_names = [vg.name for vg in body.vertex_groups]
    weights = []
    for i in keep:
        weights.append([(g.group, g.weight) for g in mesh.vertices[i].groups])
    faces = []
    for p in mesh.polygons:
        ids = [mesh.loops[j].vertex_index for j in range(p.loop_start, p.loop_start + p.loop_total)]
        if all(k in old for k in ids):
            faces.append([old[k] for k in ids])
    # uvs
    uv_layer = mesh.uv_layers.active
    uvs_by_vert = {}
    if uv_layer:
        for p in mesh.polygons:
            for j in range(p.loop_start, p.loop_start + p.loop_total):
                vi = mesh.loops[j].vertex_index
                if vi not in uvs_by_vert:
                    uvs_by_vert[vi] = uv_layer.data[j].uv.copy()
    new = bpy.data.meshes.new(mesh.name + "_clean")
    new.from_pydata(verts, [], faces)
    new.update()
    if uv_layer:
        nuv = new.uv_layers.new(name=uv_layer.name)
        for p in new.polygons:
            for j in range(p.loop_start, p.loop_start + p.loop_total):
                vi = new.loops[j].vertex_index
                src = keep[vi]
                if src in uvs_by_vert:
                    nuv.data[j].uv = uvs_by_vert[src]
    # copy materials
    for mat in mesh.materials:
        new.materials.append(mat)
    old_mesh = body.data
    body.data = new
    # restore vgroups
    body.vertex_groups.clear()
    vgs = [body.vertex_groups.new(name=n) for n in group_names]
    for i, wts in enumerate(weights):
        for gi, w in wts:
            if 0 <= gi < len(vgs):
                vgs[gi].add([i], w, "REPLACE")
    # armature modifier should still be there
    print(f"  removed {len(drop)} leftover verts, now {len(keep)}")
    return len(drop)


# ---------- 林照晚 sleeves ----------

def _arm_deform_matrix(arm, body, vert_index):
    """Blended pose*rest_inv transform that maps rest co to posed co."""
    v = body.data.vertices[vert_index]
    M = Matrix.Scale(0.0, 4)
    total = 0.0
    rest_bones = arm.data.bones
    for g in v.groups:
        if g.weight <= 1e-6:
            continue
        name = body.vertex_groups[g.group].name
        if name not in arm.pose.bones:
            continue
        pb = arm.pose.bones[name]
        rb = rest_bones[name]
        # bone rest and pose in armature/world:
        # posed = pose_world @ rest_world.inverted() @ rest_co   (object space)
        pose_w = arm.matrix_world @ pb.matrix
        rest_w = arm.matrix_world @ rb.matrix_local
        # pb.matrix is in armature space (parented); rb.matrix_local is bone local rest.
        # Use bone matrices in armature space consistently:
        pose_a = pb.matrix
        rest_a = rb.matrix_local
        # For connected bones matrix_local is the rest in armature? In Blender,
        # Bone.matrix_local is the rest matrix in armature space. PoseBone.matrix
        # is the posed matrix in armature space. Yes.
        Mi = pose_a @ rest_a.inverted()
        M = M + g.weight * Mi
        total += g.weight
    if total <= 1e-6:
        return None
    M = (1.0 / total) * M
    return M


def fix_linzhaowan_sleeves(arm, body):
    set_idle(arm)
    bpy.context.view_layer.update()
    pts = ev_pts(body)
    # hanging arm bones in world
    def chain(side):
        names = [f"upper_arm.{side}", f"forearm.{side}", f"hand.{side}"]
        segs = []
        for n in names:
            pb = arm.pose.bones[n]
            head = (arm.matrix_world @ pb.matrix).translation
            # tail: +Y in bone space
            tail = arm.matrix_world @ (pb.matrix @ Vector((0, pb.length, 0, 1))).to_3d()
            segs.append((head, tail, n))
        return segs
    segs_L, segs_R = chain("L"), chain("R")

    def project(p, segs, radius):
        best_d = 1e9
        best_q = p
        for a, b, _n in segs:
            ab = b - a
            t = 0.0 if ab.length < 1e-6 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            q = a + ab * t
            d = (p - q).length
            if d < best_d:
                best_d = d
                # keep a sleeve radius, pull inward if farther
                if d > 1e-5:
                    dirn = (p - q).normalized()
                    best_q = q + dirn * min(d, radius)
                else:
                    best_q = q
        return best_q, best_d

    moved = 0
    new_cos = [body.data.vertices[i].co.copy() for i in range(len(body.data.vertices))]
    # body object matrix
    iw = body.matrix_world.inverted()
    # armature space vs object: body is parented to arm, matrix often identity
    arm_iw = arm.matrix_world.inverted()
    arm_bones = ("upper_arm.L", "forearm.L", "hand.L", "shoulder.L",
                 "upper_arm.R", "forearm.R", "hand.R", "shoulder.R")
    for i, p in enumerate(pts):
        # Only cloth already weighted to the arms, and only if it has flown
        # far from the hanging arm (the T-wings). Never touch the skirt.
        wts = body.data.vertices[i].groups
        arm_w = sum(g.weight for g in wts if body.vertex_groups[g.group].name in arm_bones)
        if arm_w < 0.55:
            continue
        if p.z < 0.50 or p.z > 1.20:
            continue
        rest = body.matrix_world @ body.data.vertices[i].co
        # pick the side from rest x (correct bone side)
        segs = segs_L if rest.x < 0 else segs_R
        radius = 0.10
        q, d = project(p, segs, radius)
        if d < 0.16:
            continue
        # desired posed position
        desired = q
        # if the vert swung to the wrong side, force it to the rest side of the arm
        if rest.x < 0 and desired.x > 0.05:
            desired.x = min(desired.x, -0.08)
        if rest.x > 0 and desired.x < -0.05:
            desired.x = max(desired.x, 0.08)
        if (desired - p).length < 0.01:
            continue
        M = _arm_deform_matrix(arm, body, i)
        if M is None or abs(M.determinant()) < 1e-8:
            continue
        try:
            Minv = M.inverted()
        except ValueError:
            continue
        # M is in armature space (maps armature-space rest to armature-space posed)
        rest_a = arm_iw @ body.matrix_world @ body.data.vertices[i].co
        posed_a = arm_iw @ p
        # verify M
        # desired in armature space:
        des_a = arm_iw @ desired
        new_rest_a = Minv @ des_a
        new_rest_world = arm.matrix_world @ new_rest_a
        new_cos[i] = iw @ new_rest_world
        moved += 1
    if moved:
        for i, co in enumerate(new_cos):
            body.data.vertices[i].co = co
        body.data.update()
    print(f"  sleeve verts pulled {moved}")
    return moved


# ---------- 葛三秤 one-hand scale ----------

def _long_axis_local(o):
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    d = {"X": max(xs) - min(xs), "Y": max(ys) - min(ys), "Z": max(zs) - min(zs)}
    axis = max(d, key=d.get)
    vec = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[axis]
    return axis, vec


def _world_long(o):
    axis, vec = _long_axis_local(o)
    return axis, (o.matrix_world.to_3x3() @ vec).normalized()


def _rotate_prop_to(o, target):
    axis, wlong = _world_long(o)
    if wlong.dot(target) < 0:
        wlong = -wlong
    rot = wlong.rotation_difference(target)
    mw = o.matrix_world.copy()
    o.matrix_world = Matrix.Translation(mw.translation) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-mw.translation) @ mw
    bpy.context.view_layer.update()
    loc, rq, sc = o.matrix_local.decompose()
    o.location = loc
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = rq
    o.scale = sc
    bpy.context.view_layer.update()


def fix_gesancheng_scale(arm):
    set_idle(arm)
    rod = next(o for o in bpy.data.objects if "Rod" in o.name)
    weight = next(o for o in bpy.data.objects if "Weight" in o.name)
    # both on visual-right hand
    for o in (rod, weight):
        o.parent = arm
        o.parent_type = "BONE"
        o.parent_bone = "hand.L"
        o.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    # hang the rod down and a little out (-X) so it stays off the body and the ground
    # target a 20° outward tilt from vertical
    target = Vector((-0.28, 0.05, -0.96)).normalized()
    _rotate_prop_to(rod, target)
    # if the tip goes through the floor, tilt more / shorten by raising the angle
    zmin = ev_zmin(rod)
    if zmin < 0.04:
        # rotate toward less downward: mix with world -X
        target = Vector((-0.55, 0.05, -0.83)).normalized()
        _rotate_prop_to(rod, target)
        zmin = ev_zmin(rod)
        print("  rod retitled, zmin", round(zmin, 3))
    # place the weight at the lower end of the rod, slightly below the rod axis
    pts = ev_pts(rod)
    low = min(pts, key=lambda p: p.z)
    high = max(pts, key=lambda p: p.z)
    # 15% up from the low end so it sits on the beam, not past the tip
    pos = low.lerp(high, 0.12) + Vector((-0.02, 0.0, -0.03))
    # set weight world translation, keep its current rotation roughly hanging
    mw = weight.matrix_world.copy()
    mw.translation = pos
    weight.matrix_world = mw
    bpy.context.view_layer.update()
    loc, rq, sc = weight.matrix_local.decompose()
    weight.location = loc
    weight.rotation_mode = "QUATERNION"
    weight.rotation_quaternion = rq
    weight.scale = sc
    print(f"  scale both on hand.L, rod zmin={ev_zmin(rod):.3f} weight zmin={ev_zmin(weight):.3f}")


# ---------- plant down ----------

def _shift_hips_y(action, amount):
    """Add `amount` to hips location Y (world Z) keys, scaled by t in [0,1]."""
    for fc in action.fcurves:
        if "hips" in fc.data_path and fc.data_path.endswith("location") and fc.array_index == 1:
            frs = [kp.co.x for kp in fc.keyframe_points]
            if not frs:
                continue
            f0, f1 = min(frs), max(frs)
            span = max(1.0, f1 - f0)
            for kp in fc.keyframe_points:
                t = (kp.co.x - f0) / span
                # smoothstep so the start stays planted
                k = t * t * (3.0 - 2.0 * t)
                kp.co.y += amount * k
                kp.handle_left.y += amount * k
                kp.handle_right.y += amount * k
            print(f"  hips loc Y shifted end {amount:+.3f}")
            return True
    return False


def _add_bone_euler_end(action, bone, add_xyz, frames):
    """Add degrees (add_xyz) to a bone's euler keys, scaled by t."""
    # fcurves may be quaternion after reimport! Current files were exported as
    # glTF so reimported actions are typically quaternion. Better to rebuild
    # down from rebuild_anims.down_pose than edit curves.
    return False


def plant_down(arm, body, height, weapon):
    """Re-author the down action with hands near the ground and hips planted."""
    if bpy.data.actions.get("down") is None:
        return
    # Remove only the down NLA track + action, then remake it with a safer pose.
    ad = arm.animation_data
    if ad:
        for tr in list(ad.nla_tracks):
            if tr.name == "down":
                ad.nla_tracks.remove(tr)
        ad.action = None
    act = bpy.data.actions.get("down")
    if act:
        bpy.data.actions.remove(act)

    def down_at(t):
        pose = ra.down_pose(arm, weapon, t)
        # Safer arms: reach out along the ground beside the torso, not up.
        # After the body has fallen (k~1), hands should be near z=0.1.
        k = t * t * (3.0 - 2.0 * t)
        # Aim upper arms more toward world -Z / slightly out and back, but as
        # the body rotates onto its back these directions are in WORLD space
        # via aim_euler, so "down" still means toward the ground — that would
        # put the weapon through the floor again.
        # Instead aim along the body length (+Y, head direction) and a bit out,
        # almost horizontal, so the weapon lies on the ground.
        outL = Vector((-0.55, 0.75, 0.10)).normalized()
        outR = Vector((0.55, 0.75, 0.10)).normalized()
        if k > 0.2:
            pose["upper_arm.L"] = tuple(ra.aim_euler(arm, "upper_arm.L", outL))
            pose["upper_arm.R"] = tuple(ra.aim_euler(arm, "upper_arm.R", outR))
            pose["forearm.L"] = tuple(ra.aim_euler(arm, "forearm.L", Vector((-0.35, 0.80, 0.05)).normalized()))
            pose["forearm.R"] = tuple(ra.aim_euler(arm, "forearm.R", Vector((0.35, 0.80, 0.05)).normalized()))
            pose["hand.L"] = tuple(ra.aim_euler(arm, "hand.L", Vector((-0.2, 0.9, 0.0)).normalized()))
            pose["hand.R"] = tuple(ra.aim_euler(arm, "hand.R", Vector((0.2, 0.9, 0.0)).normalized()))
        return pose

    ra.make_action(arm, "down", 37, down_at, loop=False)

    # Evaluate end pose and raise hips so the lowest body/prop point is ~2cm up.
    ra.set_action(arm, "down", 37)
    z_body = ev_zmin(body)
    props = real_props(body)
    z_prop = min((ev_zmin(p) for p in props), default=9.0)
    zmin = min(z_body, z_prop)
    print(f"  down end z body={z_body:.3f} prop={z_prop:.3f}")
    # If a long weapon still dives, we only plant to the BODY so the character
    # doesn't float; then do a second arm pass if prop is still low.
    target = 0.02
    lift = target - z_body
    if abs(lift) > 0.005:
        act = bpy.data.actions.get("down")
        if not _shift_hips_y(act, lift):
            print("  WARN could not shift hips")
        ra.set_action(arm, "down", 37)
        z_body = ev_zmin(body)
        z_prop = min((ev_zmin(p) for p in props), default=9.0)
        print(f"  after plant z body={z_body:.3f} prop={z_prop:.3f}")


def export_one(path, arm):
    delete_helpers()
    ra.export_glb(path, arm)


def process(name, height, combat, weapon):
    src = os.path.join(GLB_DIR, f"{name}.glb")
    print("=" * 60, "polish", name)
    ra.clear_scene()
    bpy.context.scene.render.fps = 24
    arm, body, props = ra.import_glb(src)
    delete_helpers()
    # re-collect after helper drop
    body = body_of()
    props = real_props(body)
    print("  body", body.name, "verts", len(body.data.vertices), "props", [(p.name, p.parent_bone) for p in props])

    if name == "yaoxing_dashou":
        delete_dashou_islands(arm, body)
        body = body_of()
    if name == "linzhaowan":
        fix_linzhaowan_sleeves(arm, body)
    if name == "gesancheng":
        fix_gesancheng_scale(arm)
        props = real_props(body)

    if combat:
        plant_down(arm, body, height, weapon)

    dest = os.path.join(GLB_DIR, f"{name}.glb")
    export_one(dest, arm)

    rdir = os.path.join(RENDER, name)
    os.makedirs(rdir, exist_ok=True)
    ra.set_action(arm, "idle", 1)
    ra.setup_render(os.path.join(rdir, "idle"), [("front", 0), ("side", -90)], height)
    if name in ("linzhaowan", "gesancheng"):
        ra.set_action(arm, "walk", 1)
        ra.setup_render(os.path.join(rdir, "walk1"), [("front", 0), ("side", -90)], height)
    if combat:
        ra.set_action(arm, "down", 37)
        ra.setup_render(os.path.join(rdir, "down"), [("front", 0), ("side", -90)], height)
        ra.set_action(arm, "attack", 10)
        ra.setup_render(os.path.join(rdir, "attack"), [("front", 0)], height)
    # log planted z
    if combat:
        ra.set_action(arm, "down", 37)
        zb = ev_zmin(body)
        zp = min((ev_zmin(p) for p in real_props(body)), default=9)
        print(f"  FINAL down z body={zb:.3f} prop={zp:.3f}")
    return dest


def main():
    for ch in ra.CHARS:
        process(ch["name"], ch["height"], ch["combat"], ch["weapon"])
    print("DONE")


if __name__ == "__main__":
    main()
