class_name CharacterAnim
extends RefCounted
## AnimationTree state machine over a TripoSR character's AnimationPlayer.
## idle/walk loop with 0.2s crossfade; attack/hit are one-shots that return to
## idle; down stays down.

const XFADE := 0.32
const LOOPING: Array[String] = ["idle", "walk"]
const ONESHOTS: Array[String] = ["attack", "hit", "down"]

var _host: Node
var _player: AnimationPlayer
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _busy := false
var _current := ""
var _model: Node
var _skeleton: Skeleton3D
var _combat := false
var _drawn := false
var _sword: Node3D
var _sheath_attach: Node3D
var _hand_attach: BoneAttachment3D
var _sheath_transform := Transform3D.IDENTITY
var _walk_scale := 1.0
var _sword_tween: Tween
const SWORD_TWEEN := 0.25
const REACH_TIME := 0.22
const FOLLOW_TIME := 0.18
var _breath: IdleBreath
var _foot_lock: FootLock

func attach(host: Node, model: Node) -> void:
	_host = host
	if model == null:
		return
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		return
	for anim_name: String in _player.get_animation_list():
		var clip := _player.get_animation(anim_name)
		if clip == null:
			continue
		if anim_name in LOOPING:
			clip.loop_mode = Animation.LOOP_LINEAR
		else:
			clip.loop_mode = Animation.LOOP_NONE
	_model = model
	_build_tree(model)
	_bind_sword(model)
	_breath = IdleBreath.attach_to(model)
	_foot_lock = FootLock.attach_to(model)
	set_walk_move_speed(2.25)
	travel("idle")

func _build_tree(model: Node) -> void:
	var sm := AnimationNodeStateMachine.new()
	var names: Array[String] = []
	for anim_name: String in ["idle", "walk", "attack", "hit", "down"]:
		if _player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			var node: AnimationRootNode = anim_node
			if anim_name == "walk":
				var bt := AnimationNodeBlendTree.new()
				bt.add_node("anim", anim_node, Vector2(0.0, 0.0))
				var ts := AnimationNodeTimeScale.new()
				bt.add_node("scale", ts, Vector2(220.0, 0.0))
				bt.connect_node("scale", 0, "anim")
				bt.connect_node("output", 0, "scale")
				node = bt
			sm.add_node(anim_name, node, Vector2(200.0 * names.size(), 80.0))
			names.append(anim_name)
	if names.is_empty():
		return
	_add_transition(sm, "Start", "idle", 0.0, true, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	if "walk" in names:
		_add_transition(sm, "idle", "walk", XFADE, false, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
		_add_transition(sm, "walk", "idle", XFADE, false, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	for one: String in ["attack", "hit"]:
		if one in names:
			for src: String in ["idle", "walk", "attack", "hit"]:
				if src in names and src != one:
					_add_transition(sm, src, one, XFADE, false, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
			_add_transition(sm, one, "idle", XFADE, true, AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END)
	if "down" in names:
		for src: String in names:
			if src != "down":
				_add_transition(sm, src, "down", 0.30, false, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	_tree = AnimationTree.new()
	_tree.name = "AnimTree"
	_tree.process_priority = -20
	model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.tree_root = sm
	_tree.active = true
	_player.active = false
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if "walk" in names and _walk_scale > 0.0:
		_tree.set("parameters/walk/scale/scale", _walk_scale)

func _add_transition(sm: AnimationNodeStateMachine, from_node: String, to_node: String, fade: float, auto_advance: bool, mode: AnimationNodeStateMachineTransition.SwitchMode) -> void:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = fade
	tr.switch_mode = mode
	tr.advance_mode = (
		AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		if auto_advance
		else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	)
	sm.add_transition(from_node, to_node, tr)

func is_ready() -> bool:
	return _playback != null

func travel(state: String) -> void:
	if _playback == null:
		return
	if state == _current and state in LOOPING:
		return
	if _player != null and not _player.has_animation(state):
		return
	_current = state
	if state in LOOPING:
		sheathe_sword()
	_playback.travel(state)
	if _foot_lock != null:
		_foot_lock.walking = state == "walk"

func set_moving(moving: bool) -> void:
	if _busy:
		return
	travel("walk" if moving else "idle")

func clip_length(state: String) -> float:
	if _player == null or not _player.has_animation(state):
		return 0.6
	return maxf(0.35, _player.get_animation(state).length)

func play_and_wait(state: String) -> void:
	if _host == null or _host.get_tree() == null:
		play_oneshot(state)
		return
	if _player == null or not _player.has_animation(state):
		return
	if state == "attack":
		await _reach_then_draw()
		travel("attack")
		var wait := clip_length("attack") + FOLLOW_TIME - XFADE * 0.25
		await _host.get_tree().create_timer(maxf(0.25, wait)).timeout
		_busy = false
		travel("idle")
		return
	if state == "down":
		await _play_staged_down()
		return
	play_oneshot(state)
	var wait := clip_length(state) - XFADE * 0.25
	await _host.get_tree().create_timer(maxf(0.2, wait)).timeout
	if state != "down":
		_busy = false
		travel("idle")

func reset_idle() -> void:
	_busy = false
	if _breath != null:
		_breath.down_phase = 0.0
		_breath.reach_amount = 0.0
		_breath.suppress_breath = false
	travel("idle")

func set_combat(active: bool) -> void:
	_combat = active
	if not active:
		sheathe_sword()

func play_oneshot(state: String) -> void:
	if _playback == null or _player == null or not _player.has_animation(state):
		return
	_busy = true
	if state == "attack":
		draw_sword()
	travel(state)

func _reach_then_draw() -> void:
	_busy = true
	if _breath != null:
		_breath.suppress_breath = true
		var t := 0.0
		while t < REACH_TIME and _host != null and _host.get_tree() != null:
			t += 1.0 / 60.0
			_breath.reach_amount = clampf(t / REACH_TIME, 0.0, 1.0)
			await _host.get_tree().create_timer(1.0 / 60.0).timeout
		draw_sword()
		# Ease the arm back down; a hard reset snapped the hand in 3 frames.
		var fade := 0.0
		while fade < 0.22 and _host != null and _host.get_tree() != null:
			fade += 1.0 / 60.0
			_breath.reach_amount = clampf(1.0 - fade / 0.22, 0.0, 1.0)
			await _host.get_tree().create_timer(1.0 / 60.0).timeout
		_breath.reach_amount = 0.0
		_breath.suppress_breath = false
	else:
		draw_sword()

func _play_staged_down() -> void:
	_busy = true
	if _breath != null:
		_breath.suppress_breath = true
		# Do not travel("down"): that clip fights the procedural pose and
		# froze the landing in an arched bridge.
		# 0.35 s down into a kneel, hold 0.45 s so it reads, then fall and lie.
		var dropped := false
		var t := 0.0
		while t < 0.35 and _host != null and _host.get_tree() != null:
			t += 1.0 / 60.0
			_breath.down_phase = clampf(t / 0.35, 0.0, 1.0)
			await _host.get_tree().create_timer(1.0 / 60.0).timeout
		_breath.down_phase = 1.0
		drop_held_props()
		dropped = true
		t = 0.0
		while t < 0.45 and _host != null and _host.get_tree() != null:
			t += 1.0 / 60.0
			_breath.down_phase = 1.0
			await _host.get_tree().create_timer(1.0 / 60.0).timeout
		for step_i in [1, 2]:
			var dur: float = 0.40 if step_i == 1 else 0.32
			t = 0.0
			while t < dur and _host != null and _host.get_tree() != null:
				t += 1.0 / 60.0
				_breath.down_phase = float(step_i) + clampf(t / dur, 0.0, 1.0)
				await _host.get_tree().create_timer(1.0 / 60.0).timeout
		_breath.down_phase = 3.0
		if not dropped:
			drop_held_props()
		# Hold the landed pose; the modifier keeps rewriting every bone.
	else:
		travel("down")

func set_walk_move_speed(move_speed: float) -> void:
	_walk_scale = _measure_walk_scale(move_speed)
	if _tree != null and _player != null and _player.has_animation("walk"):
		_tree.set("parameters/walk/scale/scale", _walk_scale)

func walk_scale() -> float:
	return _walk_scale

func _measure_walk_scale(move_speed: float) -> float:
	# Plant-to-plant distance of one foot is one full cycle of forward travel.
	# Scale playback so that distance in clip.length seconds matches move_speed.
	# Fallback stride 0.83 m over 32 frames at 24 fps (Shenyan, SPEED 2.25).
	var fallback := move_speed * (32.0 / 24.0) / 1.66
	if _player == null or not _player.has_animation("walk") or _model == null:
		return clampf(fallback, 0.4, 2.2)
	var skel := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	var foot := -1
	if skel != null:
		foot = skel.find_bone("foot.L")
	if skel == null or foot < 0:
		return clampf(fallback, 0.4, 2.2)
	var clip := _player.get_animation("walk")
	var was_tree := _tree != null and _tree.active
	var was_player := _player.active
	if _tree != null:
		_tree.active = false
	_player.active = true
	_player.play("walk")
	var samples := 48
	var pts: Array[Vector3] = []
	var ys: Array[float] = []
	for i in samples:
		_player.seek(clip.length * float(i) / float(samples), true)
		_player.advance(0.0)
		skel.force_update_all_bone_transforms()
		var p := (skel.global_transform * skel.get_bone_global_pose(foot)).origin
		pts.append(p)
		ys.append(p.y)
	_player.stop()
	_player.active = was_player
	if _tree != null:
		_tree.active = was_tree
	# The clip is in-place, so same-foot plants land on the same spot.
	# During a plant the foot slides backward in body space by one step;
	# that travel is what the body must cover so the sole stays put.
	var min_y := 1e9
	for y in ys:
		min_y = minf(min_y, float(y))
	var plant_travel := 0.0
	var first := -1
	for i in samples:
		var planted: bool = ys[i] <= min_y + 0.03
		if planted and first < 0:
			first = i
		elif (not planted) and first >= 0:
			var a := pts[first]
			var b := pts[i - 1]
			plant_travel = maxf(plant_travel, Vector2(a.x - b.x, a.z - b.z).length())
			first = -1
	if first >= 0:
		var a := pts[first]
		var b := pts[samples - 1]
		plant_travel = maxf(plant_travel, Vector2(a.x - b.x, a.z - b.z).length())
	var extrema := 0.0
	for a in pts:
		for b in pts:
			extrema = maxf(extrema, Vector2(a.x - b.x, a.z - b.z).length())
	var cycle_dist := plant_travel * 2.0
	if cycle_dist < 0.35:
		cycle_dist = extrema * 2.0
	if cycle_dist < 0.2 or clip.length < 0.2:
		return clampf(fallback, 0.4, 2.2)
	return clampf(move_speed * clip.length / cycle_dist, 0.4, 2.2)

func _bind_sword(model: Node) -> void:
	_sword = _find_named_mesh(model, "Sword")
	if _sword == null:
		_sword = _find_named_mesh(model, "sword")
	if _sword == null:
		return
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		return
	_hand_attach = _ensure_attach("hand.L")
	# Do not parent to spine/chest: those bones twist, and a bone-local
	# "back" offset swings the scabbard to the front or the side. Follow
	# the chest *position* only, with the character's own model axes
	# (Godot +X left, +Y up, −Z back).
	var follow := SheathFollow.new()
	follow.name = "SheathFollow"
	follow.model = model as Node3D
	follow.skeleton = _skeleton
	model.add_child(follow)
	_sheath_attach = follow
	var parent := _sword.get_parent()
	if parent != _sheath_attach:
		if parent != null:
			parent.remove_child(_sword)
		_sheath_attach.add_child(_sword)
	_sword.transform = Transform3D.IDENTITY
	_sheath_transform = Transform3D.IDENTITY
	_ensure_tassel()

func _find_named_mesh(root: Node, token: String) -> Node3D:
	if root is Node3D and token in root.name:
		# Prefer the actual sword mesh, not a random node.
		if root is MeshInstance3D:
			return root
	for child in root.get_children():
		var found := _find_named_mesh(child, token)
		if found != null:
			return found
	return null

func _ensure_attach(bone_name: String) -> BoneAttachment3D:
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		return null
	for child in _skeleton.get_children():
		if child is BoneAttachment3D and (child as BoneAttachment3D).bone_name == bone_name:
			return child
	var att := BoneAttachment3D.new()
	att.name = "Attach_%s" % bone_name
	att.bone_name = bone_name
	_skeleton.add_child(att)
	return att

func draw_sword() -> void:
	if _sword == null or _hand_attach == null or _drawn:
		return
	_drawn = true
	_set_sheath_following(false)
	_tween_sword(true)

func sheathe_sword() -> void:
	if _sword == null or _sheath_attach == null or not _drawn:
		return
	_drawn = false
	_tween_sword(false)
	if _breath != null and _host != null and _host.has_method("create_tween"):
		# Hand guides the scabbard over the shoulder, then settles.
		_breath.reach_amount = 0.7
		var tw: Tween = _host.create_tween()
		tw.tween_interval(SWORD_TWEEN * 0.45)
		tw.tween_property(_breath, "reach_amount", 0.0, 0.28)

func _set_sheath_following(on: bool) -> void:
	if _sheath_attach is SheathFollow:
		(_sheath_attach as SheathFollow).following = on

func _kill_sword_tween() -> void:
	if _sword_tween != null:
		_sword_tween.kill()
		_sword_tween = null

func _tween_sword(drawing: bool) -> void:
	if _sword == null or _model == null or _host == null:
		_snap_sword(drawing)
		return
	_kill_sword_tween()
	var start := _sword.global_transform
	var parent := _sword.get_parent()
	if parent != _model:
		if parent != null:
			parent.remove_child(_sword)
		_model.add_child(_sword)
		_sword.global_transform = start
	if not _host.has_method("create_tween"):
		_snap_sword(drawing)
		return
	_sword_tween = _host.create_tween()
	_sword_tween.tween_method(
		_lerp_sword.bind(drawing, start),
		0.0,
		1.0,
		SWORD_TWEEN
	)
	_sword_tween.tween_callback(_finish_sword.bind(drawing))

func _sword_target(drawing: bool) -> Transform3D:
	if drawing:
		if _hand_attach == null:
			return _sword.global_transform
		return _hand_attach.global_transform * _held_sword_transform()
	if _sheath_attach == null:
		return _sword.global_transform
	return _sheath_attach.global_transform * _sheath_transform

func _lerp_sword(t: float, drawing: bool, start: Transform3D) -> void:
	# tween_method passes the interpolated value first; bind() appends after it.
	if _sword == null:
		return
	var e := t * t * (3.0 - 2.0 * t)
	var dest := _sword_target(drawing)
	# Arc over the left shoulder so the blade does not cut through the waist
	# or swing around the head. Midpoint is high and behind the torso.
	var mid := (start.origin + dest.origin) * 0.5
	mid.y = maxf(mid.y, maxf(start.origin.y, dest.origin.y)) + 0.28
	if _model != null:
		var back: Vector3 = -_model.global_transform.basis.z
		var left: Vector3 = -_model.global_transform.basis.x
		mid += back * 0.16 + left * 0.08
	# Linear blend plus a bulge through the shoulder mid-point (peaks at e=0.5).
	var o := start.origin.lerp(dest.origin, e)
	o = o.lerp(mid, 2.0 * e * (1.0 - e))
	var q0 := start.basis.get_rotation_quaternion()
	var q1 := dest.basis.get_rotation_quaternion()
	var xf := Transform3D(Basis(q0.slerp(q1, e)).orthonormalized(), o)
	_sword.global_transform = xf

func _finish_sword(drawing: bool) -> void:
	_sword_tween = null
	_snap_sword(drawing)

func _snap_sword(drawing: bool) -> void:
	if _sword == null:
		return
	var dest := _hand_attach if drawing else _sheath_attach
	if dest == null:
		return
	var gt := _sword_target(drawing)
	var parent := _sword.get_parent()
	if parent != dest:
		if parent != null:
			parent.remove_child(_sword)
		dest.add_child(_sword)
	_sword.transform = _held_sword_transform() if drawing else _sheath_transform
	# Keep the last tweened pose if the bone has moved; prefer the authored local.
	if drawing:
		_sword.transform = _held_sword_transform()
	else:
		_sword.transform = _sheath_transform
		_set_sheath_following(true)


func _ensure_tassel() -> void:
	if _sword == null or _sword.find_child("SwordTasselPivot", true, false) != null:
		return
	# Hide the stiff tassel that is baked into ShenyanBackSword (surface
	# "tassel_mat") so only the soft procedural cord is visible.
	if _sword is MeshInstance3D and (_sword as MeshInstance3D).mesh != null:
		var mesh: Mesh = (_sword as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var smat := mesh.surface_get_material(s)
			if smat != null and "tassel" in smat.resource_name.to_lower():
				var hide := StandardMaterial3D.new()
				hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				hide.albedo_color = Color(0, 0, 0, 0)
				hide.cull_mode = BaseMaterial3D.CULL_DISABLED
				(_sword as MeshInstance3D).set_surface_override_material(s, hide)
	var pivot := TasselHang.new()
	pivot.name = "SwordTasselPivot"
	# Pommel cluster (max-Y verts), not the scabbard mouth at the origin.
	pivot.position = Vector3(0.0468, 0.1854, -0.0605)
	_sword.add_child(pivot)
	# A small knot at the pommel so the tassel's attachment is readable.
	var knot_mat := StandardMaterial3D.new()
	knot_mat.albedo_color = Color(0.32, 0.46, 0.78)
	knot_mat.roughness = 0.7
	knot_mat.metallic = 0.0
	knot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var knot := MeshInstance3D.new()
	knot.name = "SwordTasselKnot"
	var ball := SphereMesh.new()
	ball.radius = 0.012
	ball.height = 0.024
	knot.mesh = ball
	knot.material_override = knot_mat
	pivot.add_child(knot)
	# Three tapered segments (~0.27 m). The hang script leans the top
	# out and droops the lower ones so the cord reads as a soft J, not a rod.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.48, 0.80)
	mat.roughness = 0.8
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var prev: Node3D = pivot
	var heights := [0.08, 0.09, 0.10]
	var top_r := [0.005, 0.006, 0.005]
	var bot_r := [0.006, 0.007, 0.010]
	for i in 3:
		var seg := MeshInstance3D.new()
		seg.name = "SwordTasselSeg%d" % i
		var cap := CylinderMesh.new()
		cap.top_radius = top_r[i]
		cap.bottom_radius = bot_r[i]
		cap.height = heights[i]
		cap.radial_segments = 8
		seg.mesh = cap
		seg.material_override = mat
		seg.position = Vector3(0.0, -heights[i] * 0.5, 0.0)
		prev.add_child(seg)
		prev = seg

func _held_sword_transform() -> Transform3D:
	# Sword local +Z points toward the hilt, -Z toward the tip (measured in Blender).
	# Align -Z with the hand bone's +Y (along the fingers) so the blade extends
	# from the visual right hand. Hilt (local z ≈ 0.185) sits in the palm.
	var rot := Quaternion(Vector3(0, 0, 1), Vector3(0, -1, 0))
	var hilt := Vector3(0.0, 0.0, 0.185)
	var origin := -(rot * hilt) + Vector3(0.0, 0.04, 0.0)
	return Transform3D(Basis(rot), origin)


const HELD_PROP_NAMES: Array[String] = ["YaoXingClub", "LiHengDao", "GeSanChengRod"]

## Let held weapons leave the hand and come to rest on the ground.
func drop_held_props() -> void:
	if _model == null:
		return
	for prop_name: String in HELD_PROP_NAMES:
		var prop := _model.find_child(prop_name, true, false) as Node3D
		if prop != null:
			_drop_prop_to_ground(prop)
	if _drawn and _sword != null:
		_kill_sword_tween()
		_drop_prop_to_ground(_sword)
		_drawn = false
		_sword = null


func _drop_prop_to_ground(prop: Node3D) -> void:
	if prop == null:
		return
	var gt := prop.global_transform
	var dest := _host as Node
	if dest == null:
		dest = _model.get_parent() if _model != null else null
	if dest == null:
		return
	var parent := prop.get_parent()
	if parent != dest:
		if parent != null:
			parent.remove_child(prop)
		dest.add_child(prop)
	prop.global_transform = gt
	var land := gt
	var origin := land.origin
	origin.y = 0.04
	land.origin = origin
	# Lay the long axis roughly along the ground instead of standing up.
	var flat := Basis.from_euler(Vector3(0.5 * PI, land.basis.get_euler().y, 0.0))
	land.basis = flat
	if _host != null and _host.has_method("create_tween"):
		var tw: Tween = _host.create_tween()
		tw.tween_property(prop, "global_transform", land, 0.22)
	else:
		prop.global_transform = land
