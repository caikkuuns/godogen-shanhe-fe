extends SceneTree
## Headless check: torso length and head height stay stable across more than
## one IdleBreath cycle (period 2π/1.85 ≈ 3.4 s). Run with:
##   godot --headless --path . --fixed-fps 60 -s tests/test_idle_breath.gd

const MODEL := "res://assets/glb/shenyan.glb"
const FRAMES := 300  # 5 s at 60 fps, > one 3.4 s period
const MAX_LEN_SWING := 0.08
const MAX_HEIGHT_SWING := 0.12

var _host: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _frame := 0
var _lens: Array[float] = []
var _heights: Array[float] = []
var _chain: Array[int] = []
var _head := -1

func _initialize() -> void:
	_host = Node3D.new()
	_host.name = "BreathTest"
	root.add_child(_host)
	_model = ToonModel.instantiate(MODEL)
	if _model == null:
		_fail("could not instantiate " + MODEL)
		return
	_host.add_child(_model)
	_skel = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel == null:
		_fail("no Skeleton3D")
		return
	for name: String in ["hips", "spine", "chest", "neck", "head"]:
		var idx := _skel.find_bone(name)
		if idx >= 0:
			_chain.append(idx)
	_head = _skel.find_bone("head")
	if _head < 0:
		_head = _skel.find_bone("neck")
	if _chain.size() < 3 or _head < 0:
		_fail("missing hips/spine/chest/head bones")
		return
	var breath := _model.find_child("IdleBreath", true, false) as IdleBreath
	if breath == null:
		_fail("IdleBreath not attached")
		return
	print("BREATH_TEST start bones=", _chain.size(), " head=", _head)

func _process(_delta: float) -> bool:
	if _skel == null:
		return false
	if _skel.has_method("force_update_all_bone_transforms"):
		_skel.force_update_all_bone_transforms()
	_lens.append(_chain_length())
	_heights.append(_head_height())
	_frame += 1
	if _frame >= FRAMES:
		_finish()
		return true
	return false

func _chain_length() -> float:
	var total := 0.0
	for i in range(1, _chain.size()):
		var a := _skel.get_bone_global_pose(_chain[i - 1]).origin
		var b := _skel.get_bone_global_pose(_chain[i]).origin
		total += a.distance_to(b)
	return total

func _head_height() -> float:
	return _skel.get_bone_global_pose(_head).origin.y

func _finish() -> void:
	# Skip a few settling frames.
	var lens := _lens.slice(10)
	var heights := _heights.slice(10)
	var len_swing := _swing(lens)
	var h_swing := _swing(heights)
	var breath := _model.find_child("IdleBreath", true, false) as IdleBreath
	var ticks := 0 if breath == null else breath.ticks
	print("BREATH_TEST frames=", _frame, " ticks=", ticks, " chain_swing=", snapped(len_swing, 0.0001), " head_swing=", snapped(h_swing, 0.0001))
	if ticks < FRAMES - 10:
		_fail("modifier only ran %d times in %d frames" % [ticks, _frame])
		return
	if len_swing > MAX_LEN_SWING:
		_fail("chain length swung %.3f m (limit %.3f)" % [len_swing, MAX_LEN_SWING])
		return
	if h_swing > MAX_HEIGHT_SWING:
		_fail("head height swung %.3f m (limit %.3f)" % [h_swing, MAX_HEIGHT_SWING])
		return
	print("BREATH_TEST ok")
	# dummy 渲染器退出清理的顺序问题：先放掉 PackedScene 缓存再 quit。
	ToonModel.clear_scene_cache()
	quit()

func _swing(values: Array) -> float:
	var lo := 1e9
	var hi := -1e9
	for v in values:
		var f := float(v)
		lo = minf(lo, f)
		hi = maxf(hi, f)
	return hi - lo

func _fail(msg: String) -> void:
	push_error("BREATH_TEST FAIL " + msg)
	print("BREATH_TEST FAIL ", msg)
	quit(1)
