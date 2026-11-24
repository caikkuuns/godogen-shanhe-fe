class_name WorldNpc
extends Node3D
## 探索态 NPC：3D 卡通模型（轮换自现有 GLB）+ 姓名牌 + 慢游走 + LOD 休眠。
## 人物视觉全部交给 CharacterModel；2D 立绘只用于对话/HUD 头像。

var npc_id := ""
var display_name := ""
var interact_point := ""
## 旧 WorldBuilder 兼容字段（探索主路径不再使用 Sprite3D）。
var dirs: Dictionary = {}
var height_px := 414
var canvas := Vector2(420.0, 500.0)
var foot_anchor := Vector2(210.0, 476.0)
var model_path := ""
var model_height := 0.0
var model_tint := 1.0

var sprite_id := "shenyan"
var sprite_tint := Color.WHITE
var height_m := 1.68
## 固定模型：linzhaowan / gesancheng / yaoxing_dashou / liheng。
var model_key := ""
## 色相/明度微调后的基础色（区域色温再乘上去）。
var variant_tint := Color.WHITE
var variant_seed := 0
var interact_label := "交谈"
var personality := "plain"
var identity := "villager"
var identity_label := "路人"
var region := ""
var home := Vector2.ZERO
var wander_radius := 0.0
var wander_speed := 0.55
var portrait := ""
var greetings: Array = []
var idle_lines: Array = []
var player_ref: Node3D
var world_ref: Node
var body_radius := 0.5
var dormant := false

var character: CharacterModel
var _name_label: Label3D
var _prompt: Label3D
var _label_shift := 0.0
var _face_time := 0.0
var _t := 0.0
var _phase := 0.0
var _initialized := false
var _moving := false
var _facing := 0
var _tint_target := Color.WHITE
var _budget_visible := true
var _lod_distance := 0.0

func _ready() -> void:
	_phase = float(abs(hash(npc_id))) * 0.00017
	_t = _phase
	_resolve_identity()
	_tint_target = variant_tint
	_build_visuals()
	add_to_group("interactable")
	_initialized = true

func is_story() -> bool:
	return interact_point != ""

## 固定模型 + 确定性 ±8% 色相/明度 + ±5% 身高。
func _resolve_identity() -> void:
	variant_seed = abs(hash(npc_id))
	if model_key == "":
		match npc_id:
			"zhoubo":
				model_key = "gesancheng"
			"mingcheng", "linzhaowan":
				model_key = "linzhaowan"
			"liheng":
				model_key = "liheng"
			_:
				model_key = CharacterModel.NPC_POOL[variant_seed % CharacterModel.NPC_POOL.size()]
	if not CharacterModel.MODELS.has(model_key):
		model_key = "linzhaowan"
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	height_m = clampf(height_m * rng.randf_range(0.95, 1.05), 1.45, 2.05)
	variant_tint = CharacterModel.variant_tint(sprite_tint, variant_seed)

func _build_visuals() -> void:
	character = CharacterModel.new()
	character.name = "Character"
	# 剧情 NPC 保留随身武器/道具；18 个散人只留身体，控制同屏 draw call。
	var keep_props := not npc_id.begins_with("npc.gen.")
	# procedural=true：按固定 seed 加程序化配饰（斗笠/头巾/背篓/围巾/腰带/提灯）。
	character.setup(model_key, height_m, variant_tint, variant_seed, keep_props, true)
	add_child(character)

	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = display_name
	_name_label.font = UiTheme.body_font()
	_name_label.font_size = 34
	_name_label.pixel_size = 0.0038
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0, 0, 0, 0.82)
	_name_label.modulate = Color(0.98, 0.94, 0.86, 0.95)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 验收要求：NPC 姓名牌 12m 外不再绘制。
	_name_label.visibility_range_end = 12.0
	_name_label.position = Vector3(0.0, height_m + 0.18, 0.0)
	add_child(_name_label)

	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.text = "E · " + interact_label
	_prompt.font = UiTheme.body_font()
	_prompt.font_size = 40
	_prompt.pixel_size = 0.0048
	_prompt.outline_size = 10
	_prompt.outline_modulate = Color(0, 0, 0, 0.9)
	_prompt.modulate = Color(0.96, 0.82, 0.52, 1.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.visibility_range_end = 12.0
	_prompt.position = Vector3(0.0, height_m + 0.52, 0.0)
	_prompt.visible = false
	add_child(_prompt)

	if display_name == "":
		_name_label.visible = false
	character.set_facing(0)

func _process(delta: float) -> void:
	if not _initialized or dormant or not _budget_visible:
		return
	# 20m 外：不走路、不更新动画；模型本身也被 CharacterModel 隐藏。
	_lod_distance = 999.0
	if player_ref != null and is_instance_valid(player_ref):
		var to_player := player_ref.global_position - global_position
		to_player.y = 0.0
		_lod_distance = to_player.length()
	character.apply_lod(_lod_distance, _budget_visible)
	if _lod_distance > CharacterModel.HIDE_DISTANCE:
		_moving = false
		character.set_moving(false)
		return
	_t += delta
	var player_near := false
	if player_ref != null and is_instance_valid(player_ref):
		var to_player2 := player_ref.global_position - global_position
		to_player2.y = 0.0
		player_near = to_player2.length() < 3.0
		if player_near:
			character.set_direction(to_player2)
			_facing = character.facing
	_face_time += delta
	if _face_time > 0.25:
		_face_time = 0.0
		_keep_labels_clear_of_hud()
	_moving = false
	# 15m 外冻结骨骼动画，但位置/朝向仍可在 15–20m 之间走近时更新。
	if _lod_distance <= CharacterModel.FREEZE_DISTANCE and not player_near and wander_radius > 0.0:
		_wander(delta)
	character.set_moving(_moving and _lod_distance <= CharacterModel.FREEZE_DISTANCE)

func _wander(delta: float) -> void:
	var t := _t * 0.22 + _phase
	var target := home + Vector2(cos(t) * wander_radius, sin(t * 0.83) * wander_radius)
	var flat := Vector2(global_position.x, global_position.z)
	var to := target - flat
	if to.length() < 0.12:
		return
	var dir := to.normalized()
	var next := flat + dir * wander_speed * delta
	global_position.x = next.x
	global_position.z = next.y
	if world_ref != null and world_ref.has_method("ground_height_at"):
		global_position.y = float(world_ref.call("ground_height_at", next.x, next.y))
	character.set_direction(Vector3(dir.x, 0.0, dir.y))
	character.set_speed(wander_speed)
	_facing = character.facing
	_moving = true

func _keep_labels_clear_of_hud() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var mid_x := get_viewport().get_visible_rect().size.x * 0.5
	var left_rects: Array[Rect2] = []
	var right_rects: Array[Rect2] = []
	for n: Node in get_tree().get_nodes_in_group("hud_persistent"):
		var c := n as Control
		if c != null and c.is_visible_in_tree():
			var r := c.get_global_rect().grow(16.0)
			if r.get_center().x < mid_x:
				left_rects.append(r)
			else:
				right_rects.append(r)
	var right := cam.global_transform.basis.x
	var need_right := 0.0
	var need_left := 0.0
	for label: Label3D in [_name_label, _prompt]:
		if label == null or not label.visible:
			continue
		var base := global_position + Vector3(0.0, label.position.y, 0.0)
		if cam.is_position_behind(base):
			continue
		var p := cam.unproject_position(base)
		var ppm := absf(cam.unproject_position(base + right).x - p.x)
		if ppm <= 0.001:
			continue
		var half_w := label.get_aabb().size.x * 0.5 * ppm
		var half_h := label.get_aabb().size.y * 0.5 * ppm
		var box := Rect2(p - Vector2(half_w, half_h), Vector2(half_w, half_h) * 2.0)
		for r: Rect2 in left_rects:
			if r.intersects(box):
				need_right = maxf(need_right, (r.end.x - box.position.x) / ppm)
		for r: Rect2 in right_rects:
			if r.intersects(box):
				need_left = maxf(need_left, (box.end.x - r.position.x) / ppm)
	if need_right >= need_left:
		_label_shift = clampf(need_right, 0.0, 4.0)
	else:
		_label_shift = clampf(-need_left, -4.0, 0.0)
	var offset := right * _label_shift
	offset.y = 0.0
	var local := global_transform.basis.inverse() * offset
	_name_label.position.x = local.x
	_name_label.position.z = local.z
	_prompt.position.x = local.x
	_prompt.position.z = local.z

func set_prompt_visible(value: bool) -> void:
	if _prompt != null:
		_prompt.visible = value and not dormant and _budget_visible

func set_dormant(value: bool) -> void:
	dormant = value
	visible = not value
	if value:
		remove_from_group("interactable")
		set_prompt_visible(false)
	elif not is_in_group("interactable"):
		add_to_group("interactable")
	var body := get_node_or_null("Collider") as CollisionObject3D
	if body != null:
		body.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT

## OpenWorld 每 0.2s 调一次：同屏最多 10 个 NPC 渲染/更新。
func set_scene_budget(visible_in_budget: bool, distance: float) -> void:
	if _budget_visible == visible_in_budget and is_equal_approx(_lod_distance, distance):
		return
	_budget_visible = visible_in_budget
	_lod_distance = distance
	if character != null:
		character.apply_lod(distance, visible_in_budget)
	if _name_label != null:
		_name_label.visible = visible_in_budget and display_name != ""
	if _prompt != null and not visible_in_budget:
		_prompt.visible = false
	if not visible_in_budget:
		_moving = false
		if character != null:
			character.set_moving(false)

func face_towards(pos: Vector3) -> void:
	character.set_direction(pos - global_position)
	_facing = character.facing

func set_region_tint(color: Color) -> void:
	_tint_target = color
	if character != null:
		character.set_tint(color)
