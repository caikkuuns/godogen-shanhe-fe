#!/usr/bin/env python3
"""Rebuild idle/walk (and combat) actions on the five TripoSR character GLBs.

Arms hang at the sides instead of the bind A-pose. Props stay parented to the
same bones. hand.L is the visual right hand (world -X, image left).

  ~/.local/bin/blender -b --python tools/img3d/rebuild_anims.py
"""
import math
import os
import shutil

import bpy
from mathutils import Vector, Matrix, Euler, Quaternion

GLB_DIR = "/workspace/godogen-shanhe-fe/assets/glb"
RENDER = "/tmp/rebuild_anims_r3"
os.makedirs(RENDER, exist_ok=True)

CHARS = [
    {"name": "shenyan", "height": 1.70, "combat": True, "weapon": "sword_back"},
    {"name": "linzhaowan", "height": 1.63, "combat": False, "weapon": "hip"},
    {"name": "liheng", "height": 1.85, "combat": True, "weapon": "dao"},
    {"name": "gesancheng", "height": 1.65, "combat": False, "weapon": "scale"},
    {"name": "yaoxing_dashou", "height": 1.72, "combat": True, "weapon": "club"},
]

FPS = 24
R = math.radians


def hips_loc(world_x, world_y, world_z_off):
    """Hips bone: local X=world X, local Y=world Z, local Z=-world Y."""
    return (world_x, world_z_off, -world_y)


def world_rot_euler(arm, name, rx, ry=0.0, rz=0.0):
    """Pose-space euler for a rotation around world axes, from rest."""
    pb = arm.pose.bones[name]
    Rw = Euler((rx, ry, rz), "XYZ").to_matrix()
    M = pb.bone.matrix_local.to_3x3()
    return (M.inverted() @ Rw @ M).to_euler("XYZ")



def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
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
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    return arm, body, props


def bone_world_dir(arm, name):
    pb = arm.pose.bones[name]
    mat = arm.matrix_world @ pb.bone.matrix_local
    return (mat.to_3x3() @ Vector((0, 1, 0))).normalized()


def aim_euler(arm, name, target_dir):
    """Pose-space XYZ euler that aims the bone's rest +Y at target_dir (world/armature)."""
    pb = arm.pose.bones[name]
    rest_dir = bone_world_dir(arm, name)
    tgt = Vector(target_dir).normalized()
    if rest_dir.length < 1e-8 or tgt.length < 1e-8:
        return Euler((0, 0, 0), "XYZ")
    rot = rest_dir.rotation_difference(tgt)
    M = pb.bone.matrix_local.to_3x3()
    L = M.inverted() @ rot.to_matrix() @ M
    return L.to_euler("XYZ")


def add_euler(a, b):
    return Euler((a[0] + b[0], a[1] + b[1], a[2] + b[2]), "XYZ")


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)


def apply_pose(arm, pose):
    """pose: {bone: Euler or (x,y,z) radians, '_hipsloc': (x,y,z)}"""
    reset_pose(arm)
    loc = pose.get("_hipsloc", (0, 0, 0))
    arm.pose.bones["hips"].location = Vector(loc)
    for name, eul in pose.items():
        if name.startswith("_"):
            continue
        if name not in arm.pose.bones:
            continue
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler(tuple(eul), "XYZ")


def hang_dirs(weapon, k=1.0):
    """Return upper/forearm/hand aim directions for a relaxed hang.
    k is height/1.70 scale, unused for directions. weapon tweaks clearance.
    """
    # Visual right = .L (world -X). Arms hang close to the torso, slight forward.
    # upper: mostly down, a little out and a little forward (-Y)
    uL = Vector((-0.16, -0.10, -1.0)).normalized()
    uR = Vector((0.16, -0.10, -1.0)).normalized()
    fL = Vector((-0.08, -0.06, -1.0)).normalized()
    fR = Vector((0.08, -0.06, -1.0)).normalized()
    # hand: slight palmar drop, keep a natural wrist
    hL = Vector((-0.05, -0.15, -1.0)).normalized()
    hR = Vector((0.05, -0.15, -1.0)).normalized()
    if weapon == "dao":
        # Keep the visual-right hand higher / more out so the hanging dao
        # does not go through the ground. Blade stays nearly down.
        uL = Vector((-0.42, 0.05, -0.95)).normalized()
        fL = Vector((-0.35, 0.02, -1.0)).normalized()
        hL = Vector((-0.25, 0.25, -0.9)).normalized()  # tip slightly back and out
    if weapon == "scale":
        # Walking stick / weight: hands a touch forward so the rod stays off the shin.
        uL = Vector((-0.20, -0.18, -1.0)).normalized()
        fL = Vector((-0.10, -0.16, -1.0)).normalized()
        uR = Vector((0.20, -0.14, -1.0)).normalized()
        fR = Vector((0.10, -0.12, -1.0)).normalized()
    if weapon == "club":
        uL = Vector((-0.30, -0.05, -1.0)).normalized()
        fL = Vector((-0.18, 0.05, -1.0)).normalized()
        hL = Vector((-0.12, 0.20, -1.0)).normalized()
    return {
        "upper_arm.L": uL, "upper_arm.R": uR,
        "forearm.L": fL, "forearm.R": fR,
        "hand.L": hL, "hand.R": hR,
    }


def hang_pose(arm, weapon, extras=None):
    """Base idle hang eulers, plus optional additive extras {bone: (dx,dy,dz)}."""
    pose = {}
    for name, d in hang_dirs(weapon).items():
        if name in arm.pose.bones:
            pose[name] = tuple(aim_euler(arm, name, d))
    # slight natural elbow bend via a small extra forearm pitch
    extras = extras or {}
    for name, add in extras.items():
        if name in pose:
            pose[name] = tuple(add_euler(pose[name], add))
        elif name.startswith("_"):
            pose[name] = add
        elif name in arm.pose.bones:
            pose[name] = add
    return pose


def swing_dir(base, pitch_deg, yaw_deg=0.0):
    """Pitch a hanging direction forward/back (around world X) and a little out (Y)."""
    v = Vector(base).normalized()
    e = Euler((R(pitch_deg), R(yaw_deg), 0.0), "XYZ")
    return (e.to_matrix() @ v).normalized()


def walk_pose(arm, weapon, phase, height):
    """phase in [-1, 1]: +1 = left foot forward / right foot back (contact).
    phase 0 = passing (feet under hips).
    """
    # Legs: ±32° thigh, shin curls when the leg is swinging forward (phase for that side > 0)
    # Negative world/local X swings the foot toward -Y (forward).
    A = 40.0
    shin_curl = 40.0
    pose = {}
    pose["thigh.L"] = tuple(world_rot_euler(arm, "thigh.L", R(-A * phase)))
    pose["thigh.R"] = tuple(world_rot_euler(arm, "thigh.R", R(A * phase)))
    # Shin curls when that leg is behind (swing/lift). L is behind when phase < 0.
    pose["shin.L"] = tuple(world_rot_euler(arm, "shin.L", R(-shin_curl * max(0.0, -phase) - 8.0 * (1.0 - abs(phase)))))
    pose["shin.R"] = tuple(world_rot_euler(arm, "shin.R", R(-shin_curl * max(0.0, phase) - 8.0 * (1.0 - abs(phase)))))
    # Feet: slight toe lift when swinging (leg behind).
    pose["foot.L"] = tuple(world_rot_euler(arm, "foot.L", R(12.0 * max(0.0, -phase) - 4.0 * max(0.0, phase))))
    pose["foot.R"] = tuple(world_rot_euler(arm, "foot.R", R(12.0 * max(0.0, phase) - 4.0 * max(0.0, -phase))))

    # Hip bob / sway / yaw. Contact (|phase|=1) is low; passing (0) is high.
    bob = 0.020 * (1.0 - phase * phase) * (height / 1.70)
    bob -= 0.008 * phase * phase * (height / 1.70)
    sway = -0.02 * phase * (height / 1.70)
    yaw = R(-6.0 * phase)
    pose["hips"] = tuple(world_rot_euler(arm, "hips", R(2.0 * (1.0 - abs(phase))), yaw, R(3.0 * phase)))
    pose["_hipsloc"] = hips_loc(sway, 0.0, bob)

    # Torso counter-rotate
    pose["spine"] = (R(-1.5 * (1.0 - abs(phase))), R(5.0 * phase), 0)
    pose["chest"] = (R(1.0), R(4.0 * phase), 0)
    pose["head"] = (0, R(-4.0 * phase), 0)

    # Arms from hang, opposite to legs: left arm back when left leg forward (phase>0).
    # Pitch around X: negative pitch swings toward -Y (forward) for a downward arm.
    # We'll set empirically after first render; start with: L arm pitch = +22*phase
    # (positive phase, left arm back).
    hd = hang_dirs(weapon)
    arm_amp = 22.0
    if weapon == "dao":
        arm_amp = 14.0  # smaller so the blade doesn't sweep the ground / legs
    if weapon == "scale":
        arm_amp = 12.0
    if weapon == "club":
        arm_amp = 18.0
    # left arm (visual right) opposite to left leg
    pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", swing_dir(hd["upper_arm.L"], arm_amp * phase, 0)))
    pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", swing_dir(hd["upper_arm.R"], -arm_amp * phase, 0)))
    # elbow bends more when the arm is back
    elL = 12.0 + 16.0 * max(0.0, phase)
    elR = 12.0 + 16.0 * max(0.0, -phase)
    pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", swing_dir(hd["forearm.L"], arm_amp * phase * 0.5, 0)))
    pose["forearm.R"] = tuple(aim_euler(arm, "forearm.R", swing_dir(hd["forearm.R"], -arm_amp * phase * 0.5, 0)))
    # add a little local X curl on the forearm
    pose["forearm.L"] = tuple(add_euler(pose["forearm.L"], (R(elL * 0.15), 0, 0)))
    pose["forearm.R"] = tuple(add_euler(pose["forearm.R"], (R(elR * 0.15), 0, 0)))
    pose["hand.L"] = tuple(aim_euler(arm, "hand.L", hd["hand.L"]))
    pose["hand.R"] = tuple(aim_euler(arm, "hand.R", hd["hand.R"]))
    return pose


def idle_pose(arm, weapon, t):
    """t in [0,1] over the loop. One slow breath."""
    s = math.sin(t * 2.0 * math.pi)
    c = math.cos(t * 2.0 * math.pi)
    extras = {
        "chest": (R(-1.6 * s), 0, 0),
        "spine": (R(-0.6 * s), 0, 0),
        "head": (R(1.1 * s), R(0.6 * c), 0),
        "neck": (R(0.4 * s), 0, 0),
        "_hipsloc": hips_loc(0.0, 0.0, 0.006 * s),
        "hips": (R(0.4 * s), 0, 0),
    }
    # tiny shoulder / arm settle
    hd = hang_dirs(weapon)
    pose = hang_pose(arm, weapon, extras)
    pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", swing_dir(hd["upper_arm.L"], 1.5 * s, 0)))
    pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", swing_dir(hd["upper_arm.R"], 1.5 * s, 0)))
    pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", hd["forearm.L"]))
    pose["forearm.R"] = tuple(aim_euler(arm, "forearm.R", hd["forearm.R"]))
    return pose


def _attack_stages(t):
    if t < 0.28:
        return "wind", t / 0.28
    if t < 0.48:
        return "strike", (t - 0.28) / 0.20
    if t < 0.75:
        return "follow", (t - 0.48) / 0.27
    return "recover", (t - 0.75) / 0.25


def club_attack_pose(arm, t):
    """Side / overhead chop. The club stays on the visual-right (-X) of the body
    so it never swings through the back or chest."""
    hd = hang_dirs("club")
    stage, k = _attack_stages(t)
    pose = hang_pose(arm, "club")
    if stage == "wind":
        # Further out (-X) and back (+Y), less up, so the club rises beside
        # the head instead of grazing the cheek.
        pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((-0.98, 0.30, 0.18)).normalized()))
        pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((-0.96, 0.32, 0.22)).normalized()))
        pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((-0.94, 0.28, 0.26)).normalized()))
        pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", swing_dir(hd["upper_arm.R"], -6, 0)))
        pose["chest"] = (R(-4), R(-12 * k), 0)
        pose["spine"] = (R(-3), R(-8 * k), 0)
        pose["hips"] = (0, R(-6 * k), 0)
        pose["_hipsloc"] = hips_loc(-0.02 * k, 0.02 * k, 0.0)
    elif stage == "strike":
        pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((-0.50, -0.78, -0.18)).normalized()))
        pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((-0.40, -0.82, -0.30)).normalized()))
        pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((-0.30, -0.88, -0.25)).normalized()))
        pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", swing_dir(hd["upper_arm.R"], 10, 0)))
        pose["chest"] = (R(6), R(10), 0)
        pose["spine"] = (R(3), R(6), 0)
        pose["hips"] = (R(3), R(6), 0)
        pose["thigh.L"] = tuple(world_rot_euler(arm, "thigh.L", R(-12)))
        pose["_hipsloc"] = hips_loc(-0.03, -0.05, 0.0)
    elif stage == "follow":
        pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((-0.45, -0.55, -0.50)).normalized()))
        pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((-0.35, -0.40, -0.75)).normalized()))
        pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((-0.25, -0.35, -0.85)).normalized()))
        pose["chest"] = (R(3), R(6), 0)
        pose["spine"] = (R(2), R(4), 0)
        pose["hips"] = (R(1), R(4), 0)
        pose["_hipsloc"] = hips_loc(-0.02, -0.03, 0.0)
    else:
        hang = hang_pose(arm, "club")
        return hang if k > 0.85 else pose
    return pose


def attack_pose(arm, weapon, t):
    """t in [0,1]: windup 0-0.28, strike 0.28-0.48, follow 0.48-0.75, recover 0.75-1."""
    if weapon == "club":
        return club_attack_pose(arm, t)
    hd = hang_dirs(weapon)
    # Ease segments
    if t < 0.28:
        k = t / 0.28  # 0..1 windup
        stage = "wind"
    elif t < 0.48:
        k = (t - 0.28) / 0.20  # strike
        stage = "strike"
    elif t < 0.75:
        k = (t - 0.48) / 0.27
        stage = "follow"
    else:
        k = (t - 0.75) / 0.25
        stage = "recover"

    pose = hang_pose(arm, weapon)
    if stage == "wind":
        # Visual right arm (.L) reaches to the left shoulder / back, where
        # 沈砚's sword is sheathed, then the Godot tween puts the blade in the hand.
        if weapon == "sword_back":
            pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((0.55, 0.75, 0.25)).normalized()))
            pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((0.45, 0.80, 0.15)).normalized()))
            pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((0.35, 0.85, 0.10)).normalized()))
        else:
            pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((-0.25, 0.85, 0.15)).normalized()))
            pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((-0.15, 0.4, -0.9)).normalized()))
            pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((-0.1, 0.2, -1)).normalized()))
        pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", swing_dir(hd["upper_arm.R"], -8, 0)))
        pose["chest"] = (R(-6), R(-25 * k), 0)
        pose["spine"] = (R(-4), R(-12 * k), 0)
        pose["hips"] = (0, R(-10 * k), 0)
        pose["head"] = (R(-4), R(8 * k), 0)
        pose["_hipsloc"] = hips_loc(0.0, 0.04 * k, 0.0)
        # Blend from hang
        if k < 0.5:
            # already set as target; blender keys will interpolate from previous
            pass
    elif stage == "strike":
        # Slash across the front: arm goes to forward-across (toward +X, -Y, down)
        pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((0.55, -0.80, -0.15)).normalized()))
        pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((0.70, -0.60, -0.20)).normalized()))
        pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((0.4, -0.8, -0.3)).normalized()))
        pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", swing_dir(hd["upper_arm.R"], 12, 0)))
        pose["chest"] = (R(8), R(22), 0)
        pose["spine"] = (R(4), R(14), 0)
        pose["hips"] = (R(4), R(12), 0)
        pose["head"] = (R(-2), R(-6), 0)
        pose["thigh.L"] = tuple(world_rot_euler(arm, "thigh.L", R(-14)))  # visual-right step forward
        pose["_hipsloc"] = hips_loc(0.02, -0.06, 0.0)
    elif stage == "follow":
        pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((0.65, -0.50, -0.40)).normalized()))
        pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((0.50, -0.30, -0.70)).normalized()))
        pose["chest"] = (R(4), R(16), 0)
        pose["spine"] = (R(2), R(8), 0)
        pose["hips"] = (R(2), R(8), 0)
        pose["thigh.L"] = tuple(world_rot_euler(arm, "thigh.L", R(-8)))
        pose["_hipsloc"] = hips_loc(0.01, -0.04, 0.0)
    else:
        # recover toward hang (keys interpolate to idle when blended in Godot;
        # here we actually ease back so the clip can also hold)
        hang = hang_pose(arm, weapon)
        # use hang fully at k=1
        return hang if k > 0.85 else pose
    return pose


def hit_pose(arm, weapon, t):
    hd = hang_dirs(weapon)
    k = min(1.0, t / 0.30) if t < 0.55 else max(0.0, 1.0 - (t - 0.55) / 0.45)
    pose = hang_pose(arm, weapon)
    # Flinch back, arms come up to guard, head turns
    pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((-0.4, 0.15, -0.6)).normalized()))
    pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", Vector((0.4, 0.15, -0.6)).normalized()))
    pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((-0.15, -0.3, -0.9)).normalized()))
    pose["forearm.R"] = tuple(aim_euler(arm, "forearm.R", Vector((0.15, -0.3, -0.9)).normalized()))
    pose["chest"] = tuple(world_rot_euler(arm, "chest", R(10 * k), R(12 * k), 0))
    pose["spine"] = tuple(world_rot_euler(arm, "spine", R(8 * k), R(8 * k), 0))
    pose["head"] = tuple(world_rot_euler(arm, "head", R(-14 * k), R(-18 * k), 0))
    pose["hips"] = tuple(world_rot_euler(arm, "hips", R(-6 * k), R(8 * k), 0))
    pose["_hipsloc"] = hips_loc(0.0, 0.10 * k, -0.02 * k)
    pose["thigh.L"] = tuple(world_rot_euler(arm, "thigh.L", R(8 * k)))
    pose["thigh.R"] = tuple(world_rot_euler(arm, "thigh.R", R(-12 * k)))
    if t > 0.85:
        return hang_pose(arm, weapon)
    return pose


def down_pose(arm, weapon, t):
    """Fall backward onto the back. t=1 holds the lying pose. Empirically tuned
    so the head is back (+Y) and the feet stay near the ground."""
    hang = hang_pose(arm, weapon)
    k = t * t * (3.0 - 2.0 * t)  # smoothstep
    pose = dict(hang)
    pose["hips"] = tuple(world_rot_euler(arm, "hips", R(-78.0 * k)))
    pose["_hipsloc"] = hips_loc(0.0, 0.38 * k, -0.58 * k)
    pose["spine"] = tuple(world_rot_euler(arm, "spine", R(-8.0 * k)))
    pose["chest"] = tuple(world_rot_euler(arm, "chest", R(-4.0 * k)))
    pose["head"] = tuple(world_rot_euler(arm, "head", R(6.0 * k)))
    # Local thigh/shin eulers (parented to the already-rotated hips) plant the feet.
    pose["thigh.L"] = (R(30.0 * k), 0, R(-6 * k))
    pose["thigh.R"] = (R(28.0 * k), 0, R(6 * k))
    pose["shin.L"] = (R(-45.0 * k), 0, 0)
    pose["shin.R"] = (R(-42.0 * k), 0, 0)
    pose["foot.L"] = (R(8.0 * k), 0, 0)
    pose["foot.R"] = (R(6.0 * k), 0, 0)
    # Hands reach along the ground (world +Y / out) so a long dao or club
    # lies on the floor instead of hanging through it.
    pose["upper_arm.L"] = tuple(aim_euler(arm, "upper_arm.L", Vector((-0.55, 0.75, 0.10)).normalized()))
    pose["upper_arm.R"] = tuple(aim_euler(arm, "upper_arm.R", Vector((0.55, 0.75, 0.10)).normalized()))
    pose["forearm.L"] = tuple(aim_euler(arm, "forearm.L", Vector((-0.35, 0.80, 0.05)).normalized()))
    pose["forearm.R"] = tuple(aim_euler(arm, "forearm.R", Vector((0.35, 0.80, 0.05)).normalized()))
    pose["hand.L"] = tuple(aim_euler(arm, "hand.L", Vector((-0.2, 0.9, 0.0)).normalized()))
    pose["hand.R"] = tuple(aim_euler(arm, "hand.R", Vector((0.2, 0.9, 0.0)).normalized()))
    return pose


def insert_keys(arm, frame):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.keyframe_insert("rotation_euler", frame=frame)
        if pb.name == "hips":
            pb.keyframe_insert("location", frame=frame)


def clear_old_actions(arm, keep_none=True):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = None
    tracks = list(arm.animation_data.nla_tracks)
    for tr in tracks:
        arm.animation_data.nla_tracks.remove(tr)
    # remove leftover actions so export is clean
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


def make_action(arm, name, frames, pose_at, loop=True):
    """frames includes the wrap frame (e.g. 49 for a 48-frame loop 1..49)."""
    if arm.animation_data is None:
        arm.animation_data_create()
    # Mute existing NLA so evaluation cannot overwrite a just-applied pose.
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    a = bpy.data.actions.new(name)
    arm.animation_data.action = a
    # Key every frame: first/last match for loops, no bezier overshoot.
    ks = list(range(1, frames + 1))
    for f in ks:
        t = 0.0 if frames <= 1 else (f - 1) / float(frames - 1)
        if loop and f == frames:
            t = 0.0  # wrap to first pose
        apply_pose(arm, pose_at(t))
        insert_keys(arm, f)
    if loop:
        apply_pose(arm, pose_at(0.0))
        insert_keys(arm, 1)
        insert_keys(arm, frames)
    for fc in a.fcurves:
        for kp in fc.keyframe_points:
            if loop:
                kp.interpolation = "LINEAR"
            else:
                kp.interpolation = "BEZIER"
                kp.handle_left_type = "AUTO_CLAMPED"
                kp.handle_right_type = "AUTO_CLAMPED"
    a.use_fake_user = True
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    tr.mute = True
    tr.strips.new(name, 1, a)
    arm.animation_data.action = None
    print("  action", name, "keys", ks[0], "..", ks[-1], "n", len(ks), "fcurves", len(a.fcurves))
    return a


def export_glb(path, arm):
    # Leave pose_position as POSE and the action cleared so NLA strips are
    # exported as authored. Forcing REST made the glTF exporter write identity
    # keyframes. Bind pose remains the armature rest (A-pose).
    if arm.animation_data:
        arm.animation_data.action = None
        for tr in arm.animation_data.nla_tracks:
            tr.mute = False
    bpy.context.scene.frame_start = 1
    bpy.context.scene.render.fps = FPS
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


def setup_render(path_prefix, views, height):
    sc = bpy.context.scene
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
    k = height / 1.70
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x = 600
    sc.render.resolution_y = 900
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background") or w.node_tree.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (0.95, 0.95, 0.95, 1)
    bg.inputs[1].default_value = 1.0
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 85
    light = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    sc.collection.objects.link(light)
    light.data.energy = 3.0
    light.rotation_euler = (R(50), R(15), R(-20))
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    sc.collection.objects.link(fill)
    fill.data.energy = 0.8
    fill.rotation_euler = (R(20), R(-30), 0)
    mid = Vector((0, 0, 0.55 * height))
    dist = 3.6 * k
    if "_down" in path_prefix or path_prefix.endswith("down"):
        mid = Vector((0, 0.15 * height, 0.22 * height))
        dist = 5.2 * k
    for name, yaw in views:
        ang = R(yaw)
        # yaw 0 = camera at -Y looking +Y (front)
        z = 0.85 * height if ("_down" in path_prefix or path_prefix.endswith("down")) else 0.62 * height
        loc = Vector((math.sin(ang) * dist, -math.cos(ang) * dist, z))
        cam.location = loc
        direction = mid - loc
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{path_prefix}_{name}.png"
        sc.render.image_settings.file_format = "PNG"
        bpy.ops.render.render(write_still=True)
        print("  render", sc.render.filepath)


def set_action(arm, name, frame):
    arm.data.pose_position = "POSE"
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.get(name)
    arm.animation_data.action = act
    if arm.animation_data.nla_tracks:
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def prop_zmin(props):
    z = 9e9
    for o in props:
        for v in o.data.vertices:
            z = min(z, (o.matrix_world @ v.co).z)
    return z if props else 0.0


def align_prop_down(prop, arm):
    """Rotate a bone-parented prop so its long axis hangs world -Z at the current pose.
    Used for the 打手 club, which was authored across the palm in bind pose.
    """
    if prop is None:
        return
    xs = [v.co.x for v in prop.data.vertices]
    ys = [v.co.y for v in prop.data.vertices]
    zs = [v.co.z for v in prop.data.vertices]
    d = {"X": max(xs) - min(xs), "Y": max(ys) - min(ys), "Z": max(zs) - min(zs)}
    axis = max(d, key=d.get)
    vec = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[axis]
    wlong = (prop.matrix_world.to_3x3() @ vec).normalized()
    target = Vector((0, 0, -1))
    if wlong.dot(target) < 0:
        wlong = -wlong
    rot = wlong.rotation_difference(target)
    mw = prop.matrix_world.copy()
    prop.matrix_world = Matrix.Translation(mw.translation) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-mw.translation) @ mw
    bpy.context.view_layer.update()
    loc, rq, sc = prop.matrix_local.decompose()
    prop.location = loc
    prop.rotation_mode = "QUATERNION"
    prop.rotation_quaternion = rq
    prop.scale = sc
    print("  aligned", prop.name, "long", axis, "to world -Z")


def ev_zmin(o):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(deps)
    me = ev.to_mesh()
    zs = [(ev.matrix_world @ v.co).z for v in me.vertices] or [0.0]
    ev.to_mesh_clear()
    return min(zs)


def drop_helpers():
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None and o.name.startswith("Ico"):
            print("  drop", o.name)
            bpy.data.objects.remove(o, do_unlink=True)


def plant_down_action(arm, body, props):
    """Raise the down clip so the body (and if possible the prop) sits on the ground."""
    act = bpy.data.actions.get("down")
    if act is None:
        return
    set_action(arm, "down", 37)
    z_body = ev_zmin(body)
    z_prop = min((ev_zmin(p) for p in props), default=9.0)
    print("  down end z body=%.3f prop=%.3f" % (z_body, z_prop))
    lift = 0.02 - z_body
    if abs(lift) < 0.005:
        return
    for fc in act.fcurves:
        if "hips" in fc.data_path and fc.data_path.endswith("location") and fc.array_index == 1:
            frs = [kp.co.x for kp in fc.keyframe_points]
            if not frs:
                continue
            f0, f1 = min(frs), max(frs)
            span = max(1.0, f1 - f0)
            for kp in fc.keyframe_points:
                t = (kp.co.x - f0) / span
                k = t * t * (3.0 - 2.0 * t)
                kp.co.y += lift * k
                kp.handle_left.y += lift * k
                kp.handle_right.y += lift * k
            print("  hips loc Y end %+0.3f" % lift)
    set_action(arm, "down", 37)
    print("  after plant z body=%.3f prop=%.3f" % (
        ev_zmin(body), min((ev_zmin(p) for p in props), default=9.0)))


def drop_dashou_floaters(arm, body):
    """Only the leftover banana shards floating in front of the visual-right hip."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    drop = set()
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
        if not (3 <= len(comp) <= 30):
            continue
        com = sum((body.matrix_world @ v2.co.copy() for v2 in comp), Vector()) / len(comp)
        # The visible fragment in the side view sat in front of the hip (y < -0.25).
        if com.y < -0.25 and com.x < -0.15:
            for v2 in comp:
                drop.add(v2.index)
            print("  drop floater n=%d com=(%.3f,%.3f,%.3f)" % (len(comp), com.x, com.y, com.z))
    bm.free()
    if not drop:
        print("  no floaters")
        return
    mesh = body.data
    keep = [i for i in range(len(mesh.vertices)) if i not in drop]
    # hide by collapsing to the nearest kept vertex? Safer: just leave them
    # if remeshing is risky. 30 verts: collapse into the body origin of the
    # closest kept vert, no topology change.
    # Actually delete faces only and loose verts via bmesh.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    for v in list(bm.verts):
        if v.index in drop:
            bm.verts.remove(v)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print("  removed %d floater verts, now %d" % (len(drop), len(mesh.vertices)))


def shift_prop_world(prop, delta):
    if prop is None:
        return
    mw = prop.matrix_world.copy()
    mw.translation = mw.translation + Vector(delta)
    prop.matrix_world = mw
    bpy.context.view_layer.update()
    loc, rq, sc = prop.matrix_local.decompose()
    prop.location = loc
    prop.rotation_mode = "QUATERNION"
    prop.rotation_quaternion = rq
    prop.scale = sc


def offset_dao_outward(props):
    """Nudge 厉横's dao off the midline, out along world -X (visual right)."""
    dao = next((p for p in props if "Dao" in p.name or "dao" in p.name or "Blade" in p.name or "sword" in p.name.lower() or "Sword" in p.name or "Knife" in p.name), None)
    if dao is None and props:
        dao = props[0]
    if dao is None:
        print("  no dao prop to offset")
        return
    shift_prop_world(dao, (-0.09, -0.03, 0.02))
    print("  dao offset out", dao.name, "zmin", round(ev_zmin(dao), 3))


def one_hand_scale(arm, props):
    """Parent rod and weight to hand.L and hang them beside the visual-right leg."""
    set_action(arm, "idle", 1)
    rod = next((p for p in props if "Rod" in p.name), None)
    weight = next((p for p in props if "Weight" in p.name), None)
    if rod is None or weight is None:
        return
    for o in (rod, weight):
        mw = o.matrix_world.copy()
        o.parent = arm
        o.parent_type = "BONE"
        o.parent_bone = "hand.L"
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_world = mw
        bpy.context.view_layer.update()
        loc, rq, sc = o.matrix_local.decompose()
        o.location = loc
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = rq
        o.scale = sc
    bpy.context.view_layer.update()
    # Hang the rod down and slightly out, rotation about the current origin (the hand).
    align_prop_down(rod, arm)
    zmin = ev_zmin(rod)
    if zmin < 0.05:
        # already vertical; if it hits the floor, tilt it out more by a slight extra yaw
        print("  rod zmin", round(zmin, 3), "tilting out")
        # rotate 25 deg around world Y so the tip comes out to -X and up
        mw = rod.matrix_world.copy()
        tilt = Euler((0, math.radians(-25), 0), "XYZ").to_matrix().to_4x4()
        rod.matrix_world = Matrix.Translation(mw.translation) @ tilt @ Matrix.Translation(-mw.translation) @ mw
        bpy.context.view_layer.update()
        loc, rq, sc = rod.matrix_local.decompose()
        o = rod
        o.location = loc
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = rq
        o.scale = sc
    pts = [rod.matrix_world @ v.co for v in rod.data.vertices]
    low = min(pts, key=lambda p: p.z)
    high = max(pts, key=lambda p: p.z)
    pos = low.lerp(high, 0.12)
    mw = weight.matrix_world.copy()
    mw.translation = pos
    weight.matrix_world = mw
    bpy.context.view_layer.update()
    loc, rq, sc = weight.matrix_local.decompose()
    weight.location = loc
    weight.rotation_mode = "QUATERNION"
    weight.rotation_quaternion = rq
    weight.scale = sc
    # Push the rod and weight further out (-X) and a little forward (-Y)
    # so they clear the thigh during the walk.
    shift_prop_world(rod, (-0.08, -0.07, 0.0))
    shift_prop_world(weight, (-0.08, -0.07, 0.0))
    print("  scale on hand.L rod zmin=%.3f weight zmin=%.3f" % (ev_zmin(rod), ev_zmin(weight)))


def ev_pts(o):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def _arm_deform_matrix(arm, body, vert_index):
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
        pose_a = pb.matrix
        rest_a = rb.matrix_local
        Mi = pose_a @ rest_a.inverted()
        M = M + g.weight * Mi
        total += g.weight
    if total <= 1e-6:
        return None
    return (1.0 / total) * M


def fix_linzhaowan_sleeves(arm, body):
    """Pull T-wing sleeve cloth onto the hanging arms. Skirt is left alone."""
    apply_pose(arm, hang_pose(arm, "hip"))
    bpy.context.view_layer.update()
    pts = ev_pts(body)
    # sanity bbox before
    def aabb(plist):
        xs, ys, zs = [p.x for p in plist], [p.y for p in plist], [p.z for p in plist]
        return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))
    before = aabb(pts)
    def chain(side):
        segs = []
        for n in (f"upper_arm.{side}", f"forearm.{side}", f"hand.{side}"):
            pb = arm.pose.bones[n]
            head = (arm.matrix_world @ pb.matrix).translation
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
                if d > 1e-5:
                    best_q = q + (p - q).normalized() * min(d, radius)
                else:
                    best_q = q
        return best_q, best_d

    moved = 0
    backup = [v.co.copy() for v in body.data.vertices]
    new_cos = [v.co.copy() for v in body.data.vertices]
    iw = body.matrix_world.inverted()
    arm_iw = arm.matrix_world.inverted()
    arm_bones = ("upper_arm.L", "forearm.L", "hand.L", "shoulder.L",
                 "upper_arm.R", "forearm.R", "hand.R", "shoulder.R")
    for i, p in enumerate(pts):
        wts = body.data.vertices[i].groups
        arm_w = sum(g.weight for g in wts if body.vertex_groups[g.group].name in arm_bones)
        if arm_w < 0.55:
            continue
        if p.z < 0.55 or p.z > 1.15:
            continue
        rest = body.matrix_world @ body.data.vertices[i].co
        segs = segs_L if rest.x < 0 else segs_R
        q, d = project(p, segs, 0.10)
        if d < 0.16:
            continue
        desired = q.copy()
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
        des_a = arm_iw @ desired
        new_rest_world = arm.matrix_world @ (Minv @ des_a)
        new_cos[i] = iw @ new_rest_world
        moved += 1
    if not moved:
        print("  sleeve verts pulled 0")
        return 0
    for i, co in enumerate(new_cos):
        body.data.vertices[i].co = co
    body.data.update()
    bpy.context.view_layer.update()
    after = aabb(ev_pts(body))
    # Revert if the dress exploded (extent grew a lot, or a coord went wild).
    def span(bb):
        return (bb[1]-bb[0], bb[3]-bb[2], bb[5]-bb[4])
    sb, sa = span(before), span(after)
    exploded = any(sa[k] > sb[k] * 1.35 + 0.15 for k in range(3)) or after[4] < -0.4 or after[5] > 2.4
    print("  sleeve verts pulled", moved, "aabb", tuple(round(x,3) for x in after), "exploded", exploded)
    if exploded:
        for i, co in enumerate(backup):
            body.data.vertices[i].co = co
        body.data.update()
        print("  sleeve change reverted")
        return 0
    return moved


def shrink_sleeves_rest(arm, body):
    """Move the hanging A-pose sleeve flaps onto a tube around the rest arms.

    The T-wings live at rest z ≈ 0.42 (already drooping from the A-pose arms).
    Project each flap onto the arm in XY (ignore the drop in Z) so the cloth
    wraps the forearm instead of hanging, then hanging the arms in pose keeps
    the sleeves around the arms. Skirt verts are left alone.
    """
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    chains = {}
    for side in ("L", "R"):
        segs = []
        for n in (f"upper_arm.{side}", f"forearm.{side}", f"hand.{side}"):
            rb = arm.data.bones[n]
            head = arm.matrix_world @ rb.head_local
            tail = arm.matrix_world @ rb.tail_local
            segs.append((head, tail, n))
        chains[side] = segs
    allowed = {"forearm.L", "forearm.R", "hand.L", "hand.R"}
    skirt = {"hips", "spine", "thigh.L", "thigh.R", "shin.L", "shin.R"}
    radius = 0.108
    moved = 0
    iw = body.matrix_world.inverted()
    backup = [v.co.copy() for v in body.data.vertices]

    def project_xy(p, segs):
        pxy = Vector((p.x, p.y))
        best_d = 1e9
        best_q = None
        for a, b, _n in segs:
            axy, bxy = Vector((a.x, a.y)), Vector((b.x, b.y))
            ab = bxy - axy
            t = 0.0 if ab.length < 1e-6 else max(0.0, min(1.0, (pxy - axy).dot(ab) / ab.length_squared))
            qxy = axy + ab * t
            d = (pxy - qxy).length
            q = a + (b - a) * t
            if d < best_d:
                best_d = d
                best_q = q
        return best_q, best_d

    for v in body.data.vertices:
        best_n, best_w = "", 0.0
        skirt_w = 0.0
        for g in v.groups:
            n = body.vertex_groups[g.group].name
            if n in skirt:
                skirt_w += g.weight
            if g.weight > best_w:
                best_n, best_w = n, g.weight
        if best_n not in allowed or best_w < 0.45 or skirt_w >= 0.25:
            continue
        p = body.matrix_world @ v.co
        if p.z < 0.30 or p.z > 1.35:
            continue
        q, dxy = project_xy(p, chains[best_n[-1]])
        if q is None:
            continue
        # Flap: dropped well below the arm, or standing far in XY.
        if (q.z - p.z) < 0.10 and dxy <= 0.13:
            continue
        radial = Vector((p.x - q.x, p.y - q.y, 0.0))
        if radial.length < 1e-5:
            radial = Vector((0.0, 1.0, 0.0))
        desired = q + radial.normalized() * radius
        if (desired - p).length > 0.85:
            desired = p.lerp(desired, 0.85 / (desired - p).length)
        v.co = iw @ desired
        moved += 1
    body.data.update()
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    xs = [p.x for p in pts]; ys = [p.y for p in pts]; zs = [p.z for p in pts]
    bb = (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))
    exploded = (bb[1]-bb[0] > 1.4) or (bb[3]-bb[2] > 1.2) or bb[4] < -0.3 or bb[5] > 2.3
    print("  rest-wrap sleeves", moved, "aabb", tuple(round(x, 3) for x in bb), "exploded", exploded)
    if exploded or moved == 0:
        for i, co in enumerate(backup):
            body.data.vertices[i].co = co
        body.data.update()
        print("  rest-wrap reverted")
        moved = 0
    arm.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    return moved



def process(ch):
    name, height, combat, weapon = ch["name"], ch["height"], ch["combat"], ch["weapon"]
    src = os.path.join(GLB_DIR, f"{name}.glb")
    print("=" * 60, name, "h", height, "weapon", weapon)
    clear_scene()
    bpy.context.scene.render.fps = FPS
    arm, body, props = import_glb(src)
    drop_helpers()
    print("  props", [(p.name, p.parent_bone) for p in props], "body verts", len(body.data.vertices))
    if name == "yaoxing_dashou":
        drop_dashou_floaters(arm, body)
    clear_old_actions(arm)
    # Sleeve rest-wrap in round 3 turned the T-flaps into hard fan shards
    # (2235 verts). Skipped; the hanging-sleeve bind is still unsolved.
    # if name == "linzhaowan":
    #     shrink_sleeves_rest(arm, body)

    def idle_at(t):
        return idle_pose(arm, weapon, t)

    def walk_at(t):
        # t 0..1, phase: 1 -> -1 -> 1 over the cycle (cos)
        # t=0 and t=1: phase = +1 (left foot forward)
        phase = math.cos(t * 2.0 * math.pi)
        return walk_pose(arm, weapon, phase, height)

    make_action(arm, "idle", 49, idle_at, loop=True)
    make_action(arm, "walk", 33, walk_at, loop=True)
    if combat:
        make_action(arm, "attack", 29, lambda t: attack_pose(arm, weapon, t), loop=False)
        make_action(arm, "hit", 17, lambda t: hit_pose(arm, weapon, t), loop=False)
        make_action(arm, "down", 37, lambda t: down_pose(arm, weapon, t), loop=False)
        plant_down_action(arm, body, props)

    # clearance check on idle
    set_action(arm, "idle", 1)
    if weapon == "club":
        for p in props:
            align_prop_down(p, arm)
        set_action(arm, "idle", 1)
    if weapon == "scale":
        one_hand_scale(arm, props)
        set_action(arm, "idle", 1)
    if weapon == "dao":
        offset_dao_outward(props)
        set_action(arm, "idle", 1)
    zmin = prop_zmin(props)
    print("  idle prop zmin", round(zmin, 3))

    dest = os.path.join(GLB_DIR, f"{name}.glb")
    export_glb(dest, arm)

    rdir = os.path.join(RENDER, name)
    os.makedirs(rdir, exist_ok=True)
    set_action(arm, "idle", 1)
    setup_render(os.path.join(rdir, "idle"), [("front", 0), ("side", -90), ("back", 180)], height)
    def _foot(fr):
        set_action(arm, "walk", fr)
        def loc(bn):
            pb = arm.pose.bones[bn]
            v = (arm.matrix_world @ pb.matrix).translation
            return (round(v.x, 3), round(v.y, 3), round(v.z, 3))
        print("  walk f%s foot.L" % fr, loc("foot.L"), "foot.R", loc("foot.R"), "hand.L", loc("hand.L"))
    for fr in (1, 9, 17, 25, 33):
        _foot(fr)
    set_action(arm, "walk", 1)
    setup_render(os.path.join(rdir, "walk1"), [("front", 0), ("side", -90)], height)
    set_action(arm, "walk", 17)
    setup_render(os.path.join(rdir, "walk9"), [("front", 0), ("side", -90)], height)
    if combat:
        set_action(arm, "attack", 8)
        setup_render(os.path.join(rdir, "attack_wind"), [("front", 0), ("side", -90)], height)
        set_action(arm, "attack", 14)
        setup_render(os.path.join(rdir, "attack"), [("front", 0), ("side", -90)], height)
        set_action(arm, "attack", 22)
        setup_render(os.path.join(rdir, "attack_follow"), [("front", 0), ("side", -90)], height)
        set_action(arm, "hit", 6)
        setup_render(os.path.join(rdir, "hit"), [("front", 0)], height)
        set_action(arm, "down", 37)
        setup_render(os.path.join(rdir, "down"), [("front", 0), ("side", -90)], height)
    return dest


def main():
    import sys
    want = [a for a in sys.argv[1:] if not a.startswith("-")]
    # argv after `--` still includes blender flags sometimes; only keep known names
    names = {c["name"] for c in CHARS}
    want = [a for a in want if a in names]
    for ch in CHARS:
        if want and ch["name"] not in want:
            continue
        process(ch)
    print("DONE")


if __name__ == "__main__":
    main()
