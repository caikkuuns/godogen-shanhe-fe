class_name IdleBreath
extends SkeletonModifier3D
## Additive chest/spine breathing, reach-back, and staged fall.
## Implemented as a SkeletonModifier3D so each tick starts from the
## AnimationTree pose instead of last frame's already-offset pose.
## Adding HEIGHT*sin(t) onto a dirty pose was integrating the sine and
## stretching the torso by HEIGHT*fps/RATE ≈ 0.78 m at 60 fps, with a
## 2π/RATE ≈ 3.4 s period.

var skel: Skeleton3D
var _chest := -1
var _spine := -1
var _hips := -1
var _t := randf() * TAU
var reach_amount := 0.0
var down_phase := 0.0  # 0 = none, 1 = kneel, 2 = fall, 3 = landed (held)
var suppress_breath := false
var ticks := 0

const RATE := 1.85
# 呼吸幅度保留我们的校准（第三轮按 1.70m 人物屏高调的）；grokbot 版无注释地
# 改小到 0.009/0.022，按冲突裁决不取。其余（真跪姿/伸手向柄/down 时序）已吸收。
const HEIGHT := 0.012
const TILT := 0.030

# Standing pose captured when a fall starts, so the kneel/fall/land (and the
# hold after we travel to "down") are applied from that base, not stacked on
# the authored down clip.
var _down_base_pos: Dictionary = {}
var _down_base_rot: Dictionary = {}
var _down_cached := false

func _ready() -> void:
	process_priority = 40
	set_process(true)
	_bind_skeleton(get_skeleton())

func _skeleton_changed(_old_skeleton: Skeleton3D, new_skeleton: Skeleton3D) -> void:
	_bind_skeleton(new_skeleton)

func _bind_skeleton(s: Skeleton3D) -> void:
	skel = s
	if skel == null:
		return
	_chest = skel.find_bone("chest")
	_spine = skel.find_bone("spine")
	_hips = skel.find_bone("hips")

func _process(_delta: float) -> void:
	# Kneel / fall / land must be applied after AnimationTree, or the
	# idle/down clip writes the pose back the same tick.
	if skel == null or down_phase <= 0.001:
		return
	if not _down_cached:
		_cache_down_base()
	_apply_down(down_phase)
	skel.force_update_all_bone_transforms()

func _process_modification_with_delta(delta: float) -> void:
	if skel == null:
		skel = get_skeleton()
		_bind_skeleton(skel)
	if skel == null:
		return
	ticks += 1
	# Breath and reach stay on the modifier path so they start from this
	# tick's animation pose and do not accumulate. Skip them while down
	# is in control; the late _process pass rewrites the whole skeleton.
	if down_phase > 0.001:
		if not _down_cached:
			_cache_down_base()
		_apply_down(down_phase)
		return
	_down_cached = false
	_down_base_pos.clear()
	_down_base_rot.clear()
	if not suppress_breath:
		_t += delta * RATE
		var k := sin(_t)
		_add(_spine, Vector3(0.0, HEIGHT * 0.4 * k, 0.0), Vector3(TILT * 0.45 * k, 0.0, 0.0))
		_add(_chest, Vector3(0.0, HEIGHT * k, 0.005 * k), Vector3(TILT * k, 0.0, 0.0))
	if reach_amount > 0.001:
		_apply_reach(reach_amount)

func _add(idx: int, pos: Vector3, euler: Vector3) -> void:
	if idx < 0:
		return
	skel.set_bone_pose_position(idx, skel.get_bone_pose_position(idx) + pos)
	var q := skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, q * Quaternion.from_euler(euler))

func _apply_reach(amount: float) -> void:
	# Visual right arm is hand.L. Reach up and back toward the left-shoulder hilt.
	var a := clampf(amount, 0.0, 1.0)
	_rotate("shoulder.L", Vector3(0.35, 0.45, -0.85) * a)
	_rotate("upper_arm.L", Vector3(0.55, -0.15, -0.95) * a)
	_rotate("forearm.L", Vector3(0.15, 0.20, 0.55) * a)

func _cache_down_base() -> void:
	_down_base_pos.clear()
	_down_base_rot.clear()
	# Start from the current pose so the spine stays in character, then
	# replace limbs with the bind rest. An idle weight-shift would otherwise
	# turn into a kicked-up leg once the hips pitch 90°.
	for i in skel.get_bone_count():
		_down_base_pos[i] = skel.get_bone_pose_position(i)
		_down_base_rot[i] = skel.get_bone_pose_rotation(i)
	for name: String in [
		"hips",
		"thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R",
	]:
		var idx := skel.find_bone(name)
		if idx < 0:
			continue
		var rest := skel.get_bone_rest(idx)
		_down_base_pos[idx] = rest.origin
		_down_base_rot[idx] = rest.basis.get_rotation_quaternion()
	_down_cached = true

func _restore_down_base() -> void:
	if skel == null:
		return
	for i in skel.get_bone_count():
		if not _down_base_rot.has(i):
			continue
		skel.set_bone_pose_position(i, _down_base_pos[i])
		skel.set_bone_pose_rotation(i, _down_base_rot[i])

func _apply_down(phase: float) -> void:
	# 0–1 kneel, 1–2 fall backward, 2–3 lie supine. The whole skeleton is
	# rewritten from the standing cache; the AnimationTree clip is ignored.
	_restore_down_base()
	var kneel := clampf(phase, 0.0, 1.0)
	var fall := clampf(phase - 1.0, 0.0, 1.0)
	var land := clampf(phase - 2.0, 0.0, 1.0)
	# Soft settle: a little extra drop in the middle of the land, then rest.
	var settle := sin(land * PI) * 0.04
	# Standing hips are ~0.92 m. A true kneel keeps them at 0.45–0.50 m
	# (thighs nearly vertical, knees on the ground). The old 0.74 drop
	# sat the hips on the heels with the thighs stretched forward.
	var drop := 0.44 * kneel * (1.0 - fall) + 0.76 * fall + settle
	# Godot +X pitch bows the torso toward +Z (forward). Kneel leans
	# 15–25°; a back fall needs a negative pitch.
	var pitch := 0.35 * kneel * (1.0 - fall) - 1.57 * fall - 0.04 * land
	if _hips >= 0:
		_set_from_base(_hips, Vector3(0.0, -drop, -0.14 * fall - 0.06 * land), Vector3(pitch, 0.0, 0.0))
	# Thighs stay close to vertical (~70–80° from the ground). A large
	# negative pitch here was swinging them forward into a low sit.
	var thigh := -0.30 * kneel * (1.0 - fall) + 0.08 * land
	_set_from_base_name("thigh.L", Vector3.ZERO, Vector3(thigh, 0.0, 0.06 * kneel * (1.0 - fall)))
	_set_from_base_name("thigh.R", Vector3.ZERO, Vector3(thigh, 0.0, -0.06 * kneel * (1.0 - fall)))
	# Shins fold back to lie along the ground, then straighten on landing.
	var shin := 1.57 * kneel * (1.0 - fall) + 0.10 * land
	_set_from_base_name("shin.L", Vector3.ZERO, Vector3(shin, 0.0, 0.0))
	_set_from_base_name("shin.R", Vector3.ZERO, Vector3(shin, 0.0, 0.0))
	var foot := -0.20 * kneel * (1.0 - fall) + 0.20 * fall + 0.10 * land
	_set_from_base_name("foot.L", Vector3.ZERO, Vector3(foot, 0.0, 0.0))
	_set_from_base_name("foot.R", Vector3.ZERO, Vector3(foot, 0.0, 0.0))
	# Slight spine/chest follow of the forward lean; head nods down 10–15°.
	_set_from_base_name("spine", Vector3.ZERO, Vector3(0.08 * kneel * (1.0 - fall) - 0.04 * land, 0.0, 0.0))
	_set_from_base_name("chest", Vector3.ZERO, Vector3(0.06 * kneel * (1.0 - fall) - 0.03 * land, 0.0, 0.0))
	_set_from_base_name("neck", Vector3.ZERO, Vector3(0.12 * kneel * (1.0 - fall) + 0.10 * land, 0.0, 0.0))
	_set_from_base_name("head", Vector3.ZERO, Vector3(0.14 * kneel * (1.0 - fall) + 0.08 * land, 0.0, 0.0))
	# Arms hang in the kneel, then drop beside the torso on the ground.
	# After a -90° hip pitch, a hanging arm is horizontal; a little extra
	# X rotation lowers the hands onto the floor instead of into the air.
	var arm_out := 0.18 * kneel * (1.0 - fall) + 0.30 * fall * (1.0 - land) + 0.06 * land
	var arm_down := 0.20 * fall + 0.70 * land
	_set_from_base_name("upper_arm.L", Vector3.ZERO, Vector3(arm_down, 0.0, arm_out))
	_set_from_base_name("upper_arm.R", Vector3.ZERO, Vector3(arm_down, 0.0, -arm_out))
	var fore := 0.12 * kneel * (1.0 - fall) + 0.15 * fall + 0.10 * land
	_set_from_base_name("forearm.L", Vector3.ZERO, Vector3(fore, 0.0, 0.0))
	_set_from_base_name("forearm.R", Vector3.ZERO, Vector3(fore, 0.0, 0.0))

func _set_from_base_name(bone_name: String, pos: Vector3, euler: Vector3) -> void:
	if skel == null:
		return
	_set_from_base(skel.find_bone(bone_name), pos, euler)

func _set_from_base(idx: int, pos: Vector3, euler: Vector3) -> void:
	if idx < 0:
		return
	var base_p: Vector3 = _down_base_pos.get(idx, skel.get_bone_pose_position(idx))
	var base_r: Quaternion = _down_base_rot.get(idx, skel.get_bone_pose_rotation(idx))
	skel.set_bone_pose_position(idx, base_p + pos)
	skel.set_bone_pose_rotation(idx, base_r * Quaternion.from_euler(euler))

func _rotate(bone_name: String, euler: Vector3) -> void:
	if skel == null:
		return
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		return
	var q := skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, q * Quaternion.from_euler(euler))

static func attach_to(model: Node) -> IdleBreath:
	if model == null:
		return null
	var existing := model.find_child("IdleBreath", true, false) as IdleBreath
	if existing != null:
		return existing
	var found := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if found == null:
		return null
	var node := IdleBreath.new()
	node.name = "IdleBreath"
	node.skel = found
	found.add_child(node)
	return node
