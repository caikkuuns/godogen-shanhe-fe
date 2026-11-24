class_name EncounterNode
extends Node3D
## 一个可选的机缘点：地面光环 + 漂浮标记 + Label3D。
## 走近只显示提示，主键才触发；没有任何强制弹窗/切场景。
## 与 WorldNpc 共享 interactable 接口（set_prompt_visible / interact_label）。

var record: Dictionary = {}
var region_id := ""
var display_title := ""
var interact_label := "察看"
var player_ref: Node3D
var used := false

var _marker: MeshInstance3D
var _ring: MeshInstance3D
var _title_label: Label3D
var _prompt: Label3D
var _t := 0.0
var _base_y := 0.0
var _near := false

func setup(enc_record: Dictionary, region: String, player: Node3D) -> void:
	record = enc_record
	region_id = region
	player_ref = player
	var payload: Dictionary = record.get("payload", {})
	display_title = str(payload.get("title", "机缘"))
	interact_label = str(payload.get("prompt", "察看"))
	_base_y = position.y

func is_encounter() -> bool:
	return true

func rarity() -> String:
	return str(record.get("rarity", "common"))

func _ready() -> void:
	_t = float(abs(hash(str(record.get("id", ""))))) * 0.0001
	add_to_group("interactable")
	_build()

func _build() -> void:
	var tint := _rarity_color()
	# 地面光环
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.38
	torus.rings = 16
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = _glow_material(tint, 1.1)
	_ring.position = Vector3(0.0, 0.035, 0.0)
	_ring.scale = Vector3(1.0, 0.35, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# 漂浮标记
	_marker = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.11
	orb.height = 0.30
	orb.radial_segments = 8
	orb.rings = 4
	_marker.mesh = orb
	_marker.material_override = _glow_material(tint, 1.6 if rarity() == "common" else 2.2)
	_marker.position = Vector3(0.0, 0.95, 0.0)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	# 名字/提示
	_title_label = Label3D.new()
	_title_label.name = "Title"
	_title_label.text = display_title
	_title_label.font = UiTheme.body_font()
	_title_label.font_size = 38
	_title_label.pixel_size = 0.0047
	_title_label.outline_size = 10
	_title_label.outline_modulate = Color(0, 0, 0, 0.82)
	_title_label.modulate = tint
	_title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_title_label.position = Vector3(0.0, 1.35, 0.0)
	_title_label.visible = false
	add_child(_title_label)
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.text = "E · " + interact_label
	_prompt.font = UiTheme.body_font()
	_prompt.font_size = 42
	_prompt.pixel_size = 0.0052
	_prompt.outline_size = 12
	_prompt.outline_modulate = Color(0, 0, 0, 0.9)
	_prompt.modulate = Color(0.96, 0.84, 0.55, 1.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.position = Vector3(0.0, 1.72, 0.0)
	_prompt.visible = false
	add_child(_prompt)
	if rarity() == "legendary":
		var light := OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 0.7
		light.omni_range = 4.0
		light.position = Vector3(0.0, 1.0, 0.0)
		light.shadow_enabled = false
		add_child(light)

func _rarity_color() -> Color:
	match rarity():
		"legendary":
			return Color("#ffcf7a")
		"rare":
			return Color("#e0b96a")
	return Color("#d7e1d8")

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.9
	return m

func _process(delta: float) -> void:
	if used:
		return
	# 25m 外的机缘不渲染环/光点，也不做上下浮动；仍保留 _process 以便走近恢复。
	if player_ref != null and is_instance_valid(player_ref):
		var d := player_ref.global_position.distance_to(global_position)
		var show := d <= 25.0
		if visible != show:
			visible = show
		if not show:
			return
		_t += delta
		_marker.position.y = 0.95 + sin(_t * 1.7) * 0.08
		_ring.rotation.y += delta * 0.6
		# 走近 6m 显示小标题；真正的交互提示由主场景 focus 打开。
		if (d < 6.0) != _near:
			_near = d < 6.0
			_title_label.visible = _near and not used
	else:
		_t += delta
		_marker.position.y = 0.95 + sin(_t * 1.7) * 0.08
		_ring.rotation.y += delta * 0.6

func set_prompt_visible(value: bool) -> void:
	if _prompt != null:
		_prompt.visible = value and not used

func mark_used() -> void:
	used = true
	remove_from_group("interactable")
	if _prompt != null:
		_prompt.visible = false
	if _title_label != null:
		_title_label.visible = false
