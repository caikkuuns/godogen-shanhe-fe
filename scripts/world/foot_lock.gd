class_name FootLock
extends SkeletonModifier3D
## While a foot is planted, hold the sole / toe world XZ so the contact
## stays put, not just the ankle bone origin.
##
## Walk clips animate foot *rotation* only, so each apply starts from the
## rest origin (a persistent translation would stretch into a long "ski").
## The supporting thigh and shin are then aimed with two-bone IK so the
## ankle can reach the locked sole without pulling the mesh.
##
## Applied in a late idle _process *and* in _physics_process. The player
## moves in physics; if we only correct in idle, a slow render tick can
## let the body drag the planted foot for several physics steps. The
## AnimationTree would also overwrite a modifier-pass write, so this
## stays a late Node process after the tree (priority 50).

var walking := false
var skel: Skeleton3D
var _left := -1
var _right := -1
var _thigh_l := -1
var _thigh_r := -1
var _shin_l := -1
var _shin_r := -1
var _lock_l: Variant = null
var _lock_r: Variant = null
var _prev_y_l := 0.0
var _prev_y_r := 0.0
var last_l := Vector3.ZERO
var last_r := Vector3.ZERO
var ticks := 0
## Local offset from the foot bone to a point on the sole / toe, in the
## bone's rest basis. Filled in _bind. Used by tests and by plant checks.
var sole_l := Vector3(0.0, 0.16, 0.0)
var sole_r := Vector3(0.0, 0.16, 0.0)
var _rest_pos_l := Vector3.ZERO
var _rest_pos_r := Vector3.ZERO
const PLANT_Y := 0.13
const LIFT_Y := 0.16


func _ready() -> void:
	# 第10轮修复：FootLock 继承 SkeletonModifier3D，骨骼写入必须走
	# _process_modification_with_delta()——那是引擎骨骼更新管线里的官方时机。
	# 之前同时开 set_process 和 set_physics_process、在里面各自 _apply()，
	# 同一帧写两次骨骼：第二次基于第一次的修正再算，行走时把支撑脚钉死在
	# 上一帧的落点（报告 P0「行走锁脚」）。这里改回单一官方通道。
	set_process(false)
	set_physics_process(false)
	_bind(get_skeleton())
	if skel == null:
		# 挂载时骨架可能还没进树；等一帧再绑，避免 test_foot_lock 的
		# 「skeleton 为空」噪音报错。
		await get_tree().process_frame
		_bind(get_skeleton())


func _skeleton_changed(_old: Skeleton3D, new_s: Skeleton3D) -> void:
	_bind(new_s)


func _bind(s: Skeleton3D) -> void:
	skel = s
	if skel == null:
		return
	_left = skel.find_bone("foot.L")
	_right = skel.find_bone("foot.R")
	_thigh_l = skel.find_bone("thigh.L")
	_thigh_r = skel.find_bone("thigh.R")
	_shin_l = skel.find_bone("shin.L")
	_shin_r = skel.find_bone("shin.R")
	if skel.process_priority < 10:
		skel.process_priority = 10
	if _left >= 0:
		sole_l = _guess_sole_local(_left)
		_rest_pos_l = skel.get_bone_rest(_left).origin
	if _right >= 0:
		sole_r = _guess_sole_local(_right)
		_rest_pos_r = skel.get_bone_rest(_right).origin


func _guess_sole_local(idx: int) -> Vector3:
	# A point near the ball of the foot: a little below the ankle bone and
	# forward along the foot, found from the rest pose so each character's
	# bone axes are handled without a hardcoded toe bone (these rigs have none).
	var rest := skel.get_bone_global_rest(idx)
	var axes: Array[Vector3] = [
		Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT
	]
	var down_local := Vector3.DOWN
	var best_down := 1.0
	var fwd_local := Vector3.FORWARD
	var best_horiz := -1.0
	for axis: Vector3 in axes:
		var world_dir: Vector3 = rest.basis * axis
		if world_dir.y < best_down:
			best_down = world_dir.y
			down_local = axis
		var flat := Vector3(world_dir.x, 0.0, world_dir.z)
		if flat.length() > best_horiz:
			best_horiz = flat.length()
			fwd_local = axis
	return down_local * 0.05 + fwd_local * 0.14


func bone_world(idx: int) -> Vector3:
	if skel == null or idx < 0:
		return Vector3.ZERO
	return (skel.global_transform * skel.get_bone_global_pose(idx)).origin


func sole_world(idx: int) -> Vector3:
	if skel == null or idx < 0:
		return Vector3.ZERO
	var gpose := skel.get_bone_global_pose(idx)
	var local := sole_l if idx == _left else sole_r
	return skel.global_transform * (gpose * local)


func _process_modification_with_delta(_delta: float) -> void:
	# 唯一写入点：动画树已求值完毕，骨骼姿态在这里定稿。
	ticks += 1
	_apply()


func _apply() -> void:
	if skel == null:
		skel = get_skeleton()
		_bind(skel)
	if skel == null or not walking:
		_lock_l = null
		_lock_r = null
		return
	if not skel.is_inside_tree():
		return
	_lock_one(_left, true)
	_lock_one(_right, false)
	skel.force_update_all_bone_transforms()


func _lock_one(idx: int, is_left: bool) -> void:
	if idx < 0:
		return
	# Walk / idle clips animate foot *rotation* only. Always start from the
	# rest origin, then apply this frame's correction on top of the current
	# (animation) rotation so a previous translation cannot accumulate.
	skel.set_bone_pose_position(idx, _rest_pos_l if is_left else _rest_pos_r)
	skel.set_bone_pose_scale(idx, Vector3.ONE)
	skel.force_update_all_bone_transforms()
	var gpose := skel.get_bone_global_pose(idx)
	var world := (skel.global_transform * gpose).origin
	var sole_local := sole_l if is_left else sole_r
	var sole: Vector3 = skel.global_transform * (gpose * sole_local)
	var height := minf(world.y, sole.y)
	var prev_y := _prev_y_l if is_left else _prev_y_r
	if is_left:
		_prev_y_l = height
	else:
		_prev_y_r = height
	var lock: Variant = _lock_l if is_left else _lock_r
	var planted := height <= PLANT_Y and height <= prev_y + 0.002
	if planted:
		if lock == null:
			lock = Vector2(sole.x, sole.z)
		var world_basis: Basis = (skel.global_transform * gpose).basis
		var sole_off: Vector3 = world_basis * sole_local
		var ankle_target := Vector3(lock.x - sole_off.x, world.y, lock.y - sole_off.z)
		var thigh_i := _thigh_l if is_left else _thigh_r
		var shin_i := _shin_l if is_left else _shin_r
		_solve_leg(thigh_i, shin_i, idx, ankle_target)
		skel.set_bone_pose_position(idx, _rest_pos_l if is_left else _rest_pos_r)
		skel.set_bone_pose_scale(idx, Vector3.ONE)
		skel.force_update_all_bone_transforms()
		gpose = skel.get_bone_global_pose(idx)
		world = (skel.global_transform * gpose).origin
		sole = skel.global_transform * (gpose * sole_local)
		# Tiny leftover (rotation vs. IK) is closed with a translation. After
		# the IK this should be millimetres, not enough to stretch the mesh.
		var corr := Vector3(lock.x - sole.x, 0.0, lock.y - sole.z)
		if corr.length() > 0.001 and corr.length() < 0.12:
			var corr_skel: Vector3 = skel.global_transform.basis.inverse() * corr
			gpose.origin += corr_skel
			var parent_i := skel.get_bone_parent(idx)
			var parent_g := Transform3D.IDENTITY
			if parent_i >= 0:
				parent_g = skel.get_bone_global_pose(parent_i)
			var local := parent_g.affine_inverse() * gpose
			skel.set_bone_pose_position(idx, local.origin)
			skel.set_bone_pose_scale(idx, Vector3.ONE)
			skel.force_update_all_bone_transforms()
			gpose = skel.get_bone_global_pose(idx)
			world = (skel.global_transform * gpose).origin
			sole = skel.global_transform * (gpose * sole_local)
	else:
		if height > LIFT_Y:
			lock = null
	if is_left:
		_lock_l = lock
		last_l = sole
	else:
		_lock_r = lock
		last_r = sole


func _solve_leg(thigh_i: int, shin_i: int, foot_i: int, ankle_world: Vector3) -> void:
	if thigh_i < 0 or shin_i < 0 or foot_i < 0:
		return
	var thigh_len: float = skel.get_bone_rest(shin_i).origin.length()
	var shin_len: float = skel.get_bone_rest(foot_i).origin.length()
	if thigh_len < 0.05 or shin_len < 0.05:
		return
	var hip_world: Vector3 = (skel.global_transform * skel.get_bone_global_pose(thigh_i)).origin
	var knee_world: Vector3 = (skel.global_transform * skel.get_bone_global_pose(shin_i)).origin
	var to_target: Vector3 = ankle_world - hip_world
	var dist: float = clampf(to_target.length(), 0.04, thigh_len + shin_len - 0.008)
	if to_target.length() < 0.001:
		return
	var axis: Vector3 = to_target.normalized()
	var pole: Vector3 = knee_world - hip_world
	var pole_flat: Vector3 = pole - axis * pole.dot(axis)
	if pole_flat.length() < 0.01:
		var side := Vector3.UP.cross(axis)
		if side.length() < 0.01:
			side = Vector3.RIGHT.cross(axis)
		pole_flat = side
	pole_flat = pole_flat.normalized()
	var cos_a: float = clampf(
		(thigh_len * thigh_len + dist * dist - shin_len * shin_len) / (2.0 * thigh_len * dist),
		-1.0, 1.0
	)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var knee_target: Vector3 = hip_world + (axis * cos_a + pole_flat * sin_a) * thigh_len
	_aim_bone(thigh_i, shin_i, knee_target)
	skel.force_update_all_bone_transforms()
	_aim_bone(shin_i, foot_i, ankle_world)
	skel.force_update_all_bone_transforms()


func _aim_bone(idx: int, child_i: int, world_target: Vector3) -> void:
	# Rotate this bone so its rest direction toward the child points at world_target.
	var rest_child: Vector3 = skel.get_bone_rest(child_i).origin
	if rest_child.length() < 0.001:
		return
	var rest_dir: Vector3 = rest_child.normalized()
	var parent_i := skel.get_bone_parent(idx)
	var parent_g := Transform3D.IDENTITY
	if parent_i >= 0:
		parent_g = skel.get_bone_global_pose(parent_i)
	var gpose := skel.get_bone_global_pose(idx)
	var origin_world: Vector3 = (skel.global_transform * gpose).origin
	var to_target: Vector3 = world_target - origin_world
	if to_target.length() < 0.001:
		return
	var want_dir: Vector3 = to_target.normalized()
	var current_dir: Vector3 = (skel.global_transform.basis * gpose.basis * rest_dir).normalized()
	var rot := Quaternion(current_dir, want_dir)
	var new_world := Transform3D(Basis(rot) * (skel.global_transform.basis * gpose.basis), origin_world)
	var new_skel: Transform3D = skel.global_transform.affine_inverse() * new_world
	var local := parent_g.affine_inverse() * new_skel
	skel.set_bone_pose_rotation(idx, local.basis.get_rotation_quaternion())
	skel.set_bone_pose_scale(idx, Vector3.ONE)


static func attach_to(model: Node) -> FootLock:
	if model == null:
		return null
	var existing := model.find_child("FootLock", true, false) as FootLock
	if existing != null:
		return existing
	var found := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if found == null:
		return null
	if found.process_priority < 10:
		found.process_priority = 10
	var node := FootLock.new()
	node.name = "FootLock"
	found.add_child(node)
	node.skel = found
	node._bind(found)
	return node
