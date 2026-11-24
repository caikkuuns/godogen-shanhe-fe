extends SceneTree
## 第10轮验收采集：转台 4 角度 + 背剑细节 + 近景 + 走路 8 帧。
## 用法: godot --headless --path . -s tools/accept_r10.gd -- <res://...glb> <prefix>
## 输出: captures/<prefix>_{front,right,back,left,back_detail,closeup,walk_00..07}.png
## 只读资源，不改项目。

const ToonModel := preload("res://scripts/world/toon_model.gd")
const CharacterAnim := preload("res://scripts/world/character_anim.gd")

var _path := "res://assets/glb/opt/shenyan.glb"
var _prefix := "r10"
var _world: Node3D
var _cam: Camera3D
var _model: Node3D

func _init() -> void:
	_go.call_deferred()

func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_path = args[0]
	if args.size() > 1:
		_prefix = args[1]
	_world = Node3D.new()
	_world.name = "AcceptWorld"
	root.add_child(_world)
	_setup_env()
	_setup_light()
	_floor()
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.03
	_world.add_child(_cam)
	_cam.current = true

	_model = ToonModel.instantiate(_path, 1.0, 1.70)
	if _model == null:
		print("FAIL_LOAD ", _path)
		quit(1)
		return
	_world.add_child(_model)
	_print_metrics()
	await _wait(4)

	var shots := [
		["front", Vector3(0.0, 0.95, 3.0)],
		["right", Vector3(3.0, 0.95, 0.0)],
		["back", Vector3(0.0, 0.95, -3.0)],
		["left", Vector3(-3.0, 0.95, 0.0)],
	]
	for s: Array in shots:
		_cam.position = s[1]
		_cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
		await _wait(2)
		_save(str(s[0]))

	# 背剑/剑穗细节：从右后方看左肩背剑。
	_cam.position = Vector3(1.35, 1.52, -1.45)
	_cam.look_at(Vector3(0.0, 1.22, 0.0), Vector3.UP)
	await _wait(2)
	_save("back_detail")

	# 近景：头部特写。
	var head := _head_pos()
	_cam.position = head + Vector3(0.30, 0.05, 1.00)
	_cam.look_at(head + Vector3(0.0, 0.01, 0.0), Vector3.UP)
	await _wait(2)
	_save("closeup")

	# 走路 8 帧（3/4 侧前视角，能看脚）。
	_cam.position = Vector3(2.6, 1.05, 1.8)
	_cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
	await _walk()
	quit()

func _wait(n: int) -> void:
	for _i in n:
		await process_frame

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.64, 0.72)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_world.add_child(we)

func _setup_light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, 38, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -125, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.82, 1.0)
	_world.add_child(fill)

func _floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.32, 0.31)
	mat.roughness = 1.0
	mi.material_override = mat
	_world.add_child(mi)

func _head_pos() -> Vector3:
	var sk := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk != null:
		for bn: String in ["head", "Head", "neck"]:
			var bi := sk.find_bone(bn)
			if bi >= 0:
				return (sk.global_transform * sk.get_bone_global_pose(bi)).origin
	return Vector3(0.0, 1.55, 0.0)

func _save(tag: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("NO_IMG ", tag)
		return
	var path := "res://captures/%s_%s.png" % [_prefix, tag]
	var err := img.save_png(path)
	print("SHOT ", tag, " ", img.get_width(), "x", img.get_height(), " err=", err)

func _print_metrics() -> void:
	var tris := 0
	var meshes := 0
	var min_y := 1e9
	var max_y := -1e9
	for n: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		for i in mi.mesh.get_surface_count():
			var idx: int = mi.mesh.surface_get_array_index_len(i)
			if idx > 0:
				tris += int(idx / 3)
			else:
				tris += int(mi.mesh.surface_get_array_len(i) / 3)
		var box: AABB = mi.global_transform * mi.get_aabb()
		min_y = minf(min_y, box.position.y)
		max_y = maxf(max_y, box.end.y)
	var sk := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	var bones := sk.get_bone_count() if sk != null else 0
	var bytes := 0
	if FileAccess.file_exists(_path):
		var f := FileAccess.open(_path, FileAccess.READ)
		if f != null:
			bytes = f.get_length()
			f.close()
	print("METRICS tris=", tris, " meshes=", meshes, " bones=", bones,
		" bytes=", bytes, " feet_y=", snappedf(min_y, 0.001),
		" top_y=", snappedf(max_y, 0.001),
		" height=", snappedf(max_y - min_y, 0.001))

func _walk() -> void:
	# 不挂 CharacterAnim/AnimationTree/FootLock，直接驱动 AnimationPlayer 采样，避免修改器把脚钉死。
	var ap := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null or not ap.has_animation("walk"):
		print("NO_WALK_CLIP")
		return
	var length := ap.get_animation("walk").length
	print("WALK len=", snappedf(length, 0.001))
	var sk := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	var step := length / 8.0
	var t := 0.0
	for i in 8:
		ap.play("walk")
		ap.advance(t)
		await _wait(2)
		var l := _bone_world(sk, "foot.L")
		var r := _bone_world(sk, "foot.R")
		print("WALK_FRAME ", i, " t=", snappedf(t, 0.001),
			" footL=", l, " footR=", r)
		_save("walk_%02d" % i)
		t += step

func _bone_world(sk: Skeleton3D, bone_name: String) -> Vector3:
	if sk == null:
		return Vector3.ZERO
	var bi := sk.find_bone(bone_name)
	if bi < 0:
		return Vector3.ZERO
	return (sk.global_transform * sk.get_bone_global_pose(bi)).origin
