extends SceneTree
## Planted foot *sole / toe* world-XZ slip stays within 2 cm while the
## body actually walks forward. Covers Shenyan and the walking NPCs.
## Samples the skeleton after FootLock has run. Measuring only the ankle
## bone origin can pass while the on-screen toe still travels with the
## pelvis; this test therefore asserts on the sole contact point.
##   godot --headless --path . --fixed-fps 60 -s tests/test_foot_lock.gd

const SUBJECTS: Array = [
	["shenyan", "res://assets/glb/shenyan.glb"],
	["yaoxing_dashou", "res://assets/glb/yaoxing_dashou.glb"],
	["linzhaowan", "res://assets/glb/linzhaowan.glb"],
	["liheng", "res://assets/glb/liheng.glb"],
	["gesancheng", "res://assets/glb/gesancheng.glb"],
]
const SPEED := 2.25
const FRAMES := 180
const MAX_SLIP := 0.02
const PLANT_Y := 0.13
const LIFT_Y := 0.16
const MIN_PLANT := 20
const MIN_TRAVEL := 6.0

var _subject := 0
var _name := ""
var _host: Node3D
var _skel: Skeleton3D
var _anim: CharacterAnim
var _lock_mod: FootLock
var _left := -1
var _right := -1
var _frame := 0
var _lock_l: Variant = null
var _lock_r: Variant = null
var _ankle_lock_l: Variant = null
var _ankle_lock_r: Variant = null
var _prev_y_l := 999.0
var _prev_y_r := 999.0
var _max_slip := 0.0
var _max_slip_ankle := 0.0
var _plant_frames := 0
var _start_pos := Vector3.ZERO
var _failed := false
var _results: Array = []


class Mover extends Node:
	# Move on the physics tick, same clock as the player, so a FootLock that
	# only patched the idle pose cannot hide a planted sole dragged by
	# move_and_slide.
	var test: SceneTree
	func _physics_process(delta: float) -> void:
		if test != null:
			test.call("_on_move", delta)


class Sampler extends Node:
	var test: SceneTree
	func _process(_delta: float) -> void:
		if test != null:
			test.call("_on_sample")


func _initialize() -> void:
	if not _start_subject():
		return


func _clear_subject() -> void:
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null
	_skel = null
	_anim = null
	_lock_mod = null


func _start_subject() -> bool:
	_clear_subject()
	if _subject >= SUBJECTS.size():
		_all_done()
		return false
	_name = String(SUBJECTS[_subject][0])
	var path := String(SUBJECTS[_subject][1])
	_frame = 0
	_lock_l = null
	_lock_r = null
	_ankle_lock_l = null
	_ankle_lock_r = null
	_prev_y_l = 999.0
	_prev_y_r = 999.0
	_max_slip = 0.0
	_max_slip_ankle = 0.0
	_plant_frames = 0
	_host = Node3D.new()
	_host.name = "FootLockTest_%s" % _name
	root.add_child(_host)
	var model := ToonModel.instantiate(path)
	if model == null:
		_fail("could not instantiate " + path)
		return false
	_host.add_child(model)
	_skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel == null:
		_fail("%s: no Skeleton3D" % _name)
		return false
	_left = _skel.find_bone("foot.L")
	_right = _skel.find_bone("foot.R")
	if _left < 0 or _right < 0:
		_fail("%s: missing foot.L/foot.R" % _name)
		return false
	_anim = CharacterAnim.new()
	_anim.attach(_host, model)
	_anim.set_walk_move_speed(SPEED)
	_anim.set_moving(true)
	_lock_mod = model.find_child("FootLock", true, false) as FootLock
	if _lock_mod == null:
		_fail("%s: FootLock not attached" % _name)
		return false
	_start_pos = _host.global_position
	var mover := Mover.new()
	mover.name = "Mover"
	mover.test = self
	mover.process_priority = -100
	mover.process_physics_priority = -100
	_host.add_child(mover)
	var sampler := Sampler.new()
	sampler.name = "Sampler"
	sampler.test = self
	sampler.process_priority = 100
	_host.add_child(sampler)
	print(
		"FOOT_LOCK_TEST start ", _name,
		" scale=", snapped(_anim.walk_scale(), 0.0001),
		" sole_l=", _lock_mod.sole_l, " sole_r=", _lock_mod.sole_r,
	)
	return true


func _on_move(delta: float) -> void:
	if _failed or _host == null:
		return
	_host.position += Vector3(0.0, 0.0, SPEED * delta)


func _on_sample() -> void:
	if _failed or _skel == null or not is_instance_valid(_skel) or _lock_mod == null:
		return
	# Skip the first ticks so the walk pose and FootLock have started.
	_frame += 1
	if _frame < 4:
		return
	_skel.force_update_all_bone_transforms()
	if _frame == 4:
		print(
			"FOOT_LOCK_TEST sole_offsets ", _name,
			" sole_l=", _lock_mod.sole_l, " sole_r=", _lock_mod.sole_r,
		)
	_sample_bone(_left, true)
	_sample_bone(_right, false)
	if _frame >= FRAMES:
		_finish_subject()


func _sample_bone(idx: int, is_left: bool) -> void:
	if idx < 0 or _lock_mod == null:
		return
	var sole := _lock_mod.sole_world(idx)
	var ankle := _lock_mod.bone_world(idx)
	var height := minf(ankle.y, sole.y)
	var prev_y := _prev_y_l if is_left else _prev_y_r
	if is_left:
		_prev_y_l = height
	else:
		_prev_y_r = height
	var lock: Variant = _lock_l if is_left else _lock_r
	var ankle_lock: Variant = _ankle_lock_l if is_left else _ankle_lock_r
	var planted := height <= PLANT_Y and height <= prev_y + 0.002
	if planted:
		_plant_frames += 1
		if lock == null:
			lock = Vector2(sole.x, sole.z)
		else:
			var slip := Vector2(sole.x - lock.x, sole.z - lock.y).length()
			if slip > _max_slip:
				_max_slip = slip
		if ankle_lock == null:
			ankle_lock = Vector2(ankle.x, ankle.z)
		else:
			var ankle_slip := Vector2(ankle.x - ankle_lock.x, ankle.z - ankle_lock.y).length()
			if ankle_slip > _max_slip_ankle:
				_max_slip_ankle = ankle_slip
	else:
		if height > LIFT_Y:
			lock = null
			ankle_lock = null
	if is_left:
		_lock_l = lock
		_ankle_lock_l = ankle_lock
	else:
		_lock_r = lock
		_ankle_lock_r = ankle_lock


func _finish_subject() -> void:
	var travel := (_host.global_position - _start_pos).length() if _host != null else 0.0
	var line := "%s frames=%d plant_frames=%d max_slip_sole=%.4f max_slip_ankle=%.4f travel=%.3f scale=%s" % [
		_name, _frame, _plant_frames, _max_slip, _max_slip_ankle, travel,
		str(snapped(_anim.walk_scale() if _anim != null else 0.0, 0.0001)),
	]
	print("FOOT_LOCK_TEST ", line)
	if travel < MIN_TRAVEL:
		_fail("%s: body only traveled %.3f m (need >= %.1f)" % [_name, travel, MIN_TRAVEL])
		return
	if _plant_frames < MIN_PLANT:
		_fail("%s: too few planted frames (%d)" % [_name, _plant_frames])
		return
	if _max_slip > MAX_SLIP:
		_fail("%s: planted sole slipped %.4f m (limit %.2f)" % [_name, _max_slip, MAX_SLIP])
		return
	_results.append(line)
	_subject += 1
	# Do not free the host from inside the sampler's _process.
	call_deferred("_start_subject")


func _all_done() -> void:
	print("FOOT_LOCK_TEST ok subjects=", _results.size())
	for line in _results:
		print("FOOT_LOCK_TEST   ", line)
	quit()


func _fail(msg: String) -> void:
	_failed = true
	printerr("FOOT_LOCK_TEST FAIL ", msg)
	quit(1)
