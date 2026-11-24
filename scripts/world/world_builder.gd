class_name WorldBuilder
extends Node3D
## Builds the vertical slice's 3D village + mountain gate + bamboo grove at runtime.
## All geometry is procedural or built-in primitives (Mobile renderer, MultiMesh foliage).
## 【废弃】第十轮核查：探索主路径走 OpenWorld + ChunkBuilder，全仓库无任何引用；
## 保留仅为存档。地面亮度补偿（顶点色×0.62 × shader×2.2）自成体系，勿单独改动。

const PLAYER_SPAWN := Vector3(0.0, 0.0, 18.4)
const BAMBOO_COUNT := 128
const PROP_ROOT := "res://assets/props/"
const PAINTED_ROOT := "res://assets/imported/scenery/"
const PROP_PIXEL_SIZE := 0.00386
## Round-4 prop cards: canvas px + foot anchor px from round4.json.
const PROPS := {
	# 石灯幢 r4b：第八轮换图——r4 顶盖被美术评审认为偏日式，r4b 改中式亭顶。
	# 画布/锚点/实物高度与 r4 完全一致（round4b.json），纯换图替换。
	"stonelantern": {
		"file": "prop_stonelantern_r4b.png", "shadow": "prop_stonelantern_shadow_r4b.png",
		"size": [506, 625], "anchor": [125, 406],
	},
	"fence": {
		"file": "prop_fence_r4.png", "shadow": "prop_fence_shadow_r4.png",
		"size": [886, 726], "anchor": [334, 405],
	},
	"crate": {
		"file": "prop_crate_r4.png", "shadow": "prop_crate_shadow_r4.png",
		"size": [557, 476], "anchor": [149, 225],
	},
	"signpost": {
		"file": "prop_signpost_r4.png", "shadow": "prop_signpost_shadow_r4.png",
		"size": [552, 700], "anchor": [150, 455],
	},
	"well": {
		"file": "prop_well_r4.png", "shadow": "prop_well_shadow_r4.png",
		"size": [830, 928], "anchor": [284, 602],
	},
}

var player: ExplorerPlayer
var camera: PlayerCamera
var npcs: Dictionary = {}
var environment: Environment

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _mat: Dictionary = {}
var _unit_box: BoxMesh
var _unit_cyl: CylinderMesh
var _unit_sphere: SphereMesh
var _unit_cone: CylinderMesh
var _mist_nodes: Array[MeshInstance3D] = []
var _mist_bases: Array[Vector3] = []
var _lantern_lights: Array[OmniLight3D] = []
var _houses_data: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 20261110
	_houses_data = [
		{"pos": Vector3(-8.8, 0.0, 14.5), "yaw": 90.0, "w": 5.2, "d": 4.4, "h": 3.05},
		{"pos": Vector3(-9.4, 0.0, 7.6), "yaw": 90.0, "w": 4.4, "d": 3.8, "h": 2.75},
		{"pos": Vector3(8.6, 0.0, 13.0), "yaw": -90.0, "w": 4.8, "d": 4.2, "h": 2.9},
		{"pos": Vector3(9.2, 0.0, 4.8), "yaw": -90.0, "w": 4.0, "d": 3.6, "h": 2.6},
	]
	_make_materials()
	_make_base_meshes()
	_build_environment()
	_build_ground()
	_build_mounds()
	_build_water()
	_build_gate()
	_build_houses()
	_build_props()
	_build_rocks()
	_build_bamboo()
	_build_grass()
	_build_mist()
	_build_mountains_and_pines()
	_build_player()
	_build_npcs()
	_build_camera()
	_build_bounds()

const MIST_FAR_ALPHA := 0.52
const MIST_NEAR_ALPHA := 0.12
const MIST_FADE_NEAR := 10.0
const MIST_FADE_FAR := 20.0

func _process(delta: float) -> void:
	_time += delta
	for i in _mist_nodes.size():
		var node := _mist_nodes[i]
		var base := _mist_bases[i]
		node.position = base + Vector3(sin(_time * 0.055 + float(i) * 1.7) * 1.6, sin(_time * 0.09 + float(i)) * 0.18, 0.0)
		# Near the player the mist card would sit between the camera and a
		# character (林照晚 at the bamboo path) and wash them out. Fade it
		# down; distant cards keep the original 0.52 alpha.
		var mat := node.material_override as StandardMaterial3D
		if mat != null and player != null:
			var d := Vector2(player.global_position.x - node.position.x, player.global_position.z - node.position.z).length()
			var t := clampf((d - MIST_FADE_NEAR) / (MIST_FADE_FAR - MIST_FADE_NEAR), 0.0, 1.0)
			var c := mat.albedo_color
			c.a = lerpf(MIST_NEAR_ALPHA, MIST_FAR_ALPHA, t)
			mat.albedo_color = c
	for i in _lantern_lights.size():
		var light := _lantern_lights[i]
		light.light_energy = 1.05 + sin(_time * 2.7 + float(i) * 2.1) * 0.10

# ------------------------------------------------------------------ materials

func _std(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _make_materials() -> void:
	# 第八轮：地面换草地/土路双贴图混合 shader（ COLOR.a=土路混合度，见 _build_ground）。
	var ground_shader := ShaderMaterial.new()
	ground_shader.shader = load("res://shaders/ground_blend.gdshader")
	ground_shader.set_shader_parameter("grass_tex",
		load("res://assets/imported/terrain/ground_grass_tile.png"))
	ground_shader.set_shader_parameter("dirt_tex",
		load("res://assets/imported/terrain/ground_dirt_tile.png"))
	_mat["ground"] = ground_shader
	_mat["stone"] = _std(Color("#8d8375"), 0.92)
	_mat["stone_dark"] = _std(Color("#5d5850"), 0.95)
	_mat["rock"] = _std(Color("#9b8f7c"), 0.94)
	_mat["moss"] = _std(Color("#5e6b3e"), 0.95)
	_mat["wood_dark"] = _std(Color("#3a2b25"), 0.82)
	_mat["wood_red"] = _std(Color("#5a2f26"), 0.72)
	_mat["wood_light"] = _std(Color("#6b5545"), 0.85)
	_mat["plaster"] = _std(Color("#cfc7ba"), 0.94)
	_mat["roof"] = _std(Color("#3d3835"), 0.86)
	_mat["roof_edge"] = _std(Color("#292522"), 0.88)
	_mat["bamboo"] = _std(Color("#7a8a52"), 0.55)
	_mat["bamboo_node"] = _std(Color("#4c5b34"), 0.65)
	_mat["gold"] = _std(Color("#b08d57"), 0.5, 0.35)
	_mat["cloth_red"] = _std(Color("#9d443a"), 0.9)
	_mat["cloth_red"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat["cloth_indigo"] = _std(Color("#4e6283"), 0.9)
	_mat["cloth_indigo"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat["window"] = _std(Color("#c99d5c"), 0.55)
	_mat["window"].emission_enabled = true
	_mat["window"].emission = Color("#ffc47a")
	_mat["window"].emission_energy_multiplier = 0.9
	_mat["lantern"] = _std(Color("#d06a45"), 0.55)
	_mat["lantern"].emission_enabled = true
	_mat["lantern"].emission = Color("#ff9a58")
	_mat["lantern"].emission_energy_multiplier = 2.2
	_mat["mountain"] = _std(Color("#9aa9b8"), 1.0)
	_mat["mountain"].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 清溪庵：策划色 木构 #544742、瓦 #4B4441、白墙。
	_mat["hermitage_wood"] = _std(Color("#544742"), 0.85)
	_mat["hermitage_tile"] = _std(Color("#4B4441"), 0.88)
	_mat["hermitage_wall"] = _std(Color("#e8e4d8"), 0.94)
	_mat["mound"] = _std(Color("#777c48"), 0.98)
	_mat["riverbed"] = _std(Color("#3b5560"), 1.0)
	_mat["pine"] = _std(Color("#3c4c34"), 0.95)
	_mat["trunk"] = _std(Color("#4a3a2d"), 0.9)

func _make_base_meshes() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 12
	_unit_cyl.rings = 1
	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 0.5
	_unit_sphere.height = 1.0
	_unit_sphere.radial_segments = 10
	_unit_sphere.rings = 5
	_unit_cone = CylinderMesh.new()
	_unit_cone.top_radius = 0.0
	_unit_cone.bottom_radius = 0.5
	_unit_cone.height = 1.0
	_unit_cone.radial_segments = 10
	_unit_cone.rings = 1

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _add_box(parent: Node3D, box_size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _add_mesh(parent, _unit_box, pos, mat, box_size, rot_deg)

func _add_cyl(parent: Node3D, diam: float, height: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _add_mesh(parent, _unit_cyl, pos, mat, Vector3(diam, height, diam), rot_deg)

func _add_sphere(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _add_mesh(parent, _unit_sphere, pos, mat, size, rot_deg)

func _add_cone(parent: Node3D, diam: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _add_mesh(parent, _unit_cone, pos, mat, Vector3(diam, height, diam))

func _add_collider(parent: Node3D, box_size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := BoxShape3D.new()
	shape.size = box_size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body

func _add_cylinder_collider(parent: Node3D, radius: float, height: float, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body

# ------------------------------------------------------------------ world helpers

func _path_x(z: float) -> float:
	return sin((z + 6.0) * 0.11) * 1.3

func _path_half_width(z: float) -> float:
	# 第八轮：山门段收窄（画稿门洞屏幕宽约 ±1.05m），土路从门洞里穿过。
	if z > -3.4 and z < 2.2:
		return 1.25
	if z > 3.0:
		return 3.1
	if z > -3.0:
		return 2.05
	if z > -18.0:
		return 2.55
	if z > -37.0:
		return 2.85
	return 2.2

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#9db7d4")
	sky_mat.sky_horizon_color = Color("#dbe3e8")
	sky_mat.ground_horizon_color = Color("#aeb5a8")
	sky_mat.ground_bottom_color = Color("#5c6355")
	sky_mat.sun_angle_max = 30.0
	sky_mat.sky_energy_multiplier = 0.9
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.46
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("#ccd9e4")
	env.fog_light_energy = 0.85
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.5
	env.fog_height = 1.1
	env.fog_height_density = 0.2
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.05
	environment = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -135.0, 0.0)
	sun.light_color = Color("#fff1dc")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.7
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25.0, 45.0, 0.0)
	rim.light_color = Color("#dce8f5")
	rim.light_energy = 0.42
	rim.shadow_enabled = false
	add_child(rim)

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(92.0, 132.0)
	plane.subdivide_width = 92
	plane.subdivide_depth = 92
	var arrays: Array = plane.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	var grass_a := Color("#5b6733")
	var grass_b := Color("#778145")
	var grass_c := Color("#485329")
	var dirt_a := Color("#9b825d")
	var dirt_b := Color("#b79c75")
	var bed := Color("#3b5560")
	for i in verts.size():
		var v := verts[i]
		var x := v.x
		var z := v.z
		var n := 0.5 + 0.5 * sin(x * 1.73 + z * 1.31) * cos(x * 0.41 - z * 0.77)
		var n2 := 0.5 + 0.5 * sin(x * 3.1 - z * 2.2 + 1.7)
		var grass := grass_a.lerp(grass_b, clampf(n, 0.0, 1.0))
		grass = grass.lerp(grass_c, clampf(n2 * 0.45, 0.0, 1.0))
		var dirt := dirt_a.lerp(dirt_b, clampf(n, 0.0, 1.0))
		var dist_path := absf(x - _path_x(z))
		var t := 1.0 - smoothstep(_path_half_width(z) - 1.15, _path_half_width(z) + 0.55, dist_path)
		# Village plaza and the dueling clearing are packed earth.
		var plaza := 1.0 - smoothstep(3.0, 5.4, Vector2(x, z).distance_to(Vector2(0.0, 15.0)))
		var clearing := 1.0 - smoothstep(3.4, 5.4, Vector2(x, z).distance_to(Vector2(0.3, -23.0)))
		t = maxf(t, maxf(plaza, clearing))
		var col := grass.lerp(dirt, clampf(t, 0.0, 1.0))
		# Stream bed: cool and dark under the water shader.
		if x > 11.8 and x < 18.2 and z > -33.0 and z < 15.0:
			var bed_t := 1.0 - smoothstep(1.8, 3.2, absf(x - 15.0))
			col = col.lerp(bed, clampf(bed_t, 0.0, 1.0))
		# 第八轮：alpha 承载土路混合度给 ground_blend.gdshader；土路/河床调暗，
		# 补偿"顶点色×贴图×2.2"的乘算（贴图本身比纯色亮）。
		colors[i] = Color(col.r * 0.62, col.g * 0.62, col.b * 0.62, t)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat["ground"]
	add_child(mi)
	_add_collider(self, Vector3(92.0, 1.0, 132.0), Vector3(0.0, -0.5, 0.0))

func _build_mounds() -> void:
	var spots: Array[Vector3] = [
		Vector3(-30.0, -2.5, 8.0), Vector3(31.0, -3.0, 2.0),
		Vector3(-28.0, -2.0, -28.0), Vector3(29.0, -2.5, -30.0),
		Vector3(-26.0, -2.8, -58.0), Vector3(27.0, -3.0, -60.0),
		Vector3(0.0, -3.5, -74.0),
	]
	for i in spots.size():
		var s := spots[i]
		_add_sphere(self, Vector3(34.0, 9.0 + float(i % 3) * 2.0, 30.0), s, _mat["mound"])
	# A low ridge behind the village so the skyline is not empty.
	_add_sphere(self, Vector3(44.0, 7.0, 26.0), Vector3(0.0, -2.5, 32.0), _mat["mound"])

func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.6, 46.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.5, 0.57, 0.72)
	mat.roughness = 0.12
	mat.metallic = 0.15
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = Vector3(15.0, 0.045, -9.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Bank stones.
	for i in 16:
		var z := -30.0 + float(i) * 2.9
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := 15.0 + side * (2.65 + _rng.randf_range(-0.1, 0.35))
		var s := _rng.randf_range(0.45, 1.15)
		_add_sphere(self, Vector3(s * 1.4, s, s * 1.2), Vector3(x, s * 0.22, z),
			_mat["rock"] if i % 3 != 0 else _mat["moss"], Vector3(0.0, _rng.randf() * 180.0, 10.0))

## 第八轮：村口山门改用 wuxia-team 分层画稿（assets/imported/scenery/gate_L*.png，
## 数值依据 gate_layers.json：canvas 911×886、脚线锚点 y=744、门洞屏幕中心 x≈492）。
## L0 石板铺地平铺在地面，L1 后柱、L2 前柱+屋顶为面向 +Z 的竖版面片；
## 相机固定从南面朝北看：角色在门洞以北时被 L2 前柱自然遮挡（深度缓冲），
## 门洞拱内可走。柱基阻挡区取 blocked_pillar_bases 折算的左右两组。
func _build_gate() -> void:
	var gate := Node3D.new()
	gate.name = "MountainGate"
	gate.position = Vector3(_path_x(0.0), 0.0, -0.6)
	add_child(gate)
	var s := PROP_PIXEL_SIZE * 2.6  # 缩放：门洞屏幕宽 ~2.1m，牌坊总宽 ~9.1m、总高 ~8.9m
	var arch_cx := 492.0            # 画布 x=492px（门洞屏幕中心）对齐路面中心
	var cx_off := (911.0 * 0.5 - arch_cx) * s
	var quad_size := Vector2(911.0, 886.0) * s
	# L0 石板铺地：画布"上"指向北，锚点行（py=744）落在门线 z=0。
	var ground := MeshInstance3D.new()
	var l0 := QuadMesh.new()
	l0.size = quad_size
	ground.mesh = l0
	ground.material_override = _painted_mat(PAINTED_ROOT + "gate_L0_ground.png", false)
	ground.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ground.position = Vector3(cx_off, 0.016, (886.0 * 0.5 - 744.0) * s)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(ground)
	# L1 后柱 / L2 前柱+屋顶：画布底边贴地，脚线锚点以上是"再往北"的假透视。
	var layer_z := {"gate_L1_back.png": -0.55, "gate_L2_front.png": 0.0}
	for tex_name: String in layer_z.keys():
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = quad_size
		mi.mesh = q
		mi.material_override = _painted_mat(PAINTED_ROOT + tex_name, true)
		mi.position = Vector3(cx_off, 886.0 * 0.5 * s, float(layer_z[tex_name]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate.add_child(mi)
	# 画稿自带的匾额是空的，把「山河」Label3D 贴上去（画布位置约 510,345px）。
	var plaque := Label3D.new()
	plaque.text = "山 河"
	plaque.font = UiTheme.body_font()
	plaque.font_size = 58
	plaque.pixel_size = 0.0088
	plaque.modulate = Color("#d8b77a")
	plaque.outline_size = 8
	plaque.outline_modulate = Color(0, 0, 0, 0.75)
	plaque.position = Vector3((510.0 - arch_cx) * s, (886.0 - 345.0) * s, 0.06)
	plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	gate.add_child(plaque)
	# 柱基阻挡（blocked_pillar_bases 折算到门线）：左 132..387px、右 597..802px。
	for block: Dictionary in [
		{"c": (132.0 + 387.0) * 0.5 - arch_cx, "w": (387.0 - 132.0) * s},
		{"c": (597.0 + 802.0) * 0.5 - arch_cx, "w": (802.0 - 597.0) * s},
	]:
		_add_collider(gate, Vector3(block["w"], 3.4, 1.1),
			Vector3(float(block["c"]) * s, 1.7, 0.0))
	# 影子实体：门楼整体朝东南投到进门路上。
	_shadow_proxy(gate, Vector3(8.6, 6.0, 1.2), Vector3(0.0, 3.0, -0.2))
	# 两侧矮石墙把画稿边接到地形上，避免"牌坊悬在草地上"。
	for side: float in [-1.0, 1.0]:
		var wall_x := side * (911.0 * 0.5 * s + 1.2)
		_add_box(self, Vector3(2.6, 1.15, 0.9), Vector3(wall_x, 0.575, -0.6), _mat["stone"])
		_add_collider(self, Vector3(2.6, 1.35, 0.9), Vector3(wall_x, 0.675, -0.6))
	# 保留仪仗幡杆（画稿边外）。
	for side: float in [-1.0, 1.0]:
		var pole := Node3D.new()
		pole.position = Vector3(side * 5.6, 0.0, 0.0)
		gate.add_child(pole)
		_add_cyl(pole, 0.16, 4.4, Vector3(0.0, 2.2, 0.0), _mat["wood_dark"])
		var cloth := QuadMesh.new()
		cloth.size = Vector2(0.85, 1.7)
		_add_mesh(pole, cloth, Vector3(side * 0.48, 3.25, 0.0), _mat["cloth_indigo"], Vector3.ONE, Vector3(0.0, side * 8.0, 0.0))

func _build_houses() -> void:
	for house: Dictionary in _houses_data:
		_build_house(house["pos"], float(house["yaw"]), float(house["w"]), float(house["d"]), float(house["h"]))

func _build_house(pos: Vector3, yaw: float, w: float, d: float, h: float) -> void:
	# 第八轮：民居外观换成 wuxia-team 画稿（house.png 910×849，白墙瓦顶木门格窗）。
	# 相机固定从南面朝北看，画稿正面朝 +Z 即可；画布底边贴在前墙脚线。
	# 碰撞 AABB、门口杂物保留；yaw 参数保留签名兼容（画稿统一朝南）。
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	var sc := (w + 1.8) / (910.0 * PROP_PIXEL_SIZE)  # 画宽 ≈ 墙宽 + 两侧挑檐
	var height := 849.0 * PROP_PIXEL_SIZE * sc
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(910.0, 849.0) * PROP_PIXEL_SIZE * sc
	mi.mesh = quad
	mi.material_override = _painted_mat(PAINTED_ROOT + "house.png", true)
	mi.position = Vector3(0.0, height * 0.5, d * 0.5 + 0.18)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	# 房体影子实体（SHADOWS_ONLY）：画稿不投影，但地面仍接到房子影子。
	_shadow_proxy(node, Vector3(w, h + 1.4, d), Vector3(0.0, (h + 1.4) * 0.5, 0.0))
	_add_collider(node, Vector3(w + 0.5, h + 1.8, d + 0.5), Vector3(0.0, (h + 1.8) * 0.5, 0.0))
	# A few crates and a barrel by the wall.
	if w > 4.5:
		_add_box(node, Vector3(0.62, 0.62, 0.62), Vector3(w * 0.5 + 0.35, 0.31, d * 0.5 - 0.5), _mat["wood_light"], Vector3(0.0, 14.0, 0.0))
		_add_cyl(node, 0.55, 0.75, Vector3(w * 0.5 + 0.65, 0.375, d * 0.5 - 1.3), _mat["wood_light"])

func _build_props() -> void:
	# Round-4 painted prop cards (stone lantern / fence / crate / signpost / well).
	var lantern_z: Array[float] = [2.6, 8.6]
	for z: float in lantern_z:
		for side: float in [-1.0, 1.0]:
			_add_prop("stonelantern", Vector3(_path_x(z) + side * 3.25, 0.0, z))
	_add_prop("fence", Vector3(_path_x(6.0) - 3.9, 0.0, 6.0))
	_add_prop("fence", Vector3(_path_x(10.5) + 3.9, 0.0, 10.5))
	_add_prop("fence", Vector3(_path_x(11.6) - 4.1, 0.0, 11.6))
	_add_prop("crate", Vector3(6.2, 0.0, 14.6))
	_add_prop("crate", Vector3(-6.6, 0.0, 13.0))
	_add_prop("crate", Vector3(6.4, 0.0, 6.4))
	_add_prop("signpost", Vector3(_path_x(3.0) - 2.7, 0.0, 3.0))
	_add_prop("well", Vector3(5.4, 0.0, 8.2))
	# Dueling clearing marker stones.
	for i in 6:
		var ang := float(i) * TAU / 6.0 + 0.4
		var r := 4.6
		var p := Vector3(0.3 + cos(ang) * r, 0.0, -23.0 + sin(ang) * r)
		_add_sphere(self, Vector3(1.0, 0.55, 0.8), p + Vector3(0.0, 0.16, 0.0), _mat["stone"], Vector3(0.0, ang * 57.0, 0.0))
	# A lone stone basin near the gate.
	_add_cyl(self, 1.05, 0.5, Vector3(_path_x(-4.0) - 3.2, 0.25, -4.0), _mat["stone_dark"])

## 第八轮：画稿面片公共材质（山门/民居）。无光照，与道具 Sprite3D 一致；
## 竖版单面（相机只从南面看），地版双面免得从斜上方看穿。
func _painted_mat(tex_path: String, vertical: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if vertical:
		mat.cull_mode = BaseMaterial3D.CULL_BACK
	else:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

## 只投影不显示的实体：画稿建筑没有真实体积，让地面仍接到建筑影子。
func _shadow_proxy(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(mi)

func _add_prop(prop_id: String, pos: Vector3) -> Node3D:
	var data: Dictionary = PROPS[prop_id]
	var canvas := Vector2(float(data["size"][0]), float(data["size"][1]))
	var anchor := Vector2(float(data["anchor"][0]), float(data["anchor"][1]))
	var holder := Node3D.new()
	holder.name = "Prop_" + prop_id
	holder.position = pos
	add_child(holder)

	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = load(PROP_ROOT + str(data["file"]))
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.pixel_size = PROP_PIXEL_SIZE
	# Anchor is base center: lift the canvas until the foot pixel sits on origin.
	sprite.offset = Vector2(canvas.x * 0.5 - anchor.x, anchor.y - canvas.y * 0.5)
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	holder.add_child(sprite)

	# Matching shadow PNG, laid flat on the ground with the same canvas alignment.
	var quad := QuadMesh.new()
	quad.size = canvas * PROP_PIXEL_SIZE
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = quad
	shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shadow.position = Vector3(
		(anchor.x - canvas.x * 0.5) * -PROP_PIXEL_SIZE,
		0.022,
		(anchor.y - canvas.y * 0.5) * -PROP_PIXEL_SIZE
	)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(PROP_ROOT + str(data["shadow"]))
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow.material_override = mat
	holder.add_child(shadow)

	match prop_id:
		"stonelantern":
			_add_cylinder_collider(holder, 0.3, 1.5, Vector3(0.0, 0.75, 0.0))
		"well":
			_add_collider(holder, Vector3(1.75, 1.2, 1.75), Vector3(0.0, 0.6, 0.0))
		"signpost":
			_add_cylinder_collider(holder, 0.24, 1.8, Vector3(0.0, 0.9, 0.0))
		"crate":
			_add_collider(holder, Vector3(0.8, 0.9, 0.8), Vector3(0.0, 0.45, 0.0))
		"fence":
			# Deeper than the card so the 3D hero (robe ~0.45 m wide) cannot walk into the painted plane.
			_add_collider(holder, Vector3(2.2, 1.05, 0.8), Vector3(0.0, 0.52, 0.0))
	return holder

func _build_fence(side: float, z0: float, z1: float) -> void:
	var z := z0
	while z < z1:
		var x := _path_x(z) + side * (_path_half_width(z) + 0.95)
		var next_z := z + 2.0
		var next_x := _path_x(next_z) + side * (_path_half_width(next_z) + 0.95)
		_add_box(self, Vector3(0.12, 1.05, 0.12), Vector3(x, 0.52, z), _mat["wood_light"])
		var mid := Vector3((x + next_x) * 0.5, 0.78, (z + next_z) * 0.5)
		var dx := next_x - x
		var dz := next_z - z
		var yaw := atan2(dx, dz)
		_add_box(self, Vector3(0.08, 0.09, Vector2(dx, dz).length()), mid, _mat["wood_light"], Vector3(0.0, rad_to_deg(yaw), 0.0))
		_add_box(self, Vector3(0.08, 0.08, Vector2(dx, dz).length()), mid - Vector3(0.0, 0.32, 0.0), _mat["wood_light"], Vector3(0.0, rad_to_deg(yaw), 0.0))
		z = next_z

func _build_stone_lantern(pos: Vector3) -> void:
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	_add_box(node, Vector3(0.78, 0.24, 0.78), Vector3(0.0, 0.12, 0.0), _mat["stone"])
	_add_cyl(node, 0.3, 1.1, Vector3(0.0, 0.78, 0.0), _mat["stone_dark"])
	_add_box(node, Vector3(0.58, 0.12, 0.58), Vector3(0.0, 1.38, 0.0), _mat["stone"])
	_add_box(node, Vector3(0.48, 0.44, 0.48), Vector3(0.0, 1.65, 0.0), _mat["window"])
	_add_cone(node, 0.92, 0.42, Vector3(0.0, 2.08, 0.0), _mat["stone_dark"])
	_add_sphere(node, Vector3(0.18, 0.18, 0.18), Vector3(0.0, 2.34, 0.0), _mat["stone"])
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 1.66, 0.0)
	light.light_color = Color("#ffc27a")
	light.light_energy = 1.05
	light.omni_range = 5.2
	light.shadow_enabled = false
	node.add_child(light)
	_lantern_lights.append(light)
	_add_collider(node, Vector3(0.8, 2.2, 0.8), Vector3(0.0, 1.1, 0.0))

func _build_rocks() -> void:
	var boulders: Array[Vector3] = [
		Vector3(-7.2, 0.0, -6.0), Vector3(7.8, 0.0, -16.0), Vector3(-6.5, 0.0, 4.2),
		Vector3(6.9, 0.0, -3.0), Vector3(-11.5, 0.0, -15.0), Vector3(11.0, 0.0, -27.0),
	]
	for i in boulders.size():
		var p := boulders[i]
		var s := 2.4 + float(i % 3) * 0.9
		_add_sphere(self, Vector3(s * 1.25, s * 1.1, s), p + Vector3(0.0, s * 0.34, 0.0),
			_mat["rock"], Vector3(4.0 * float(i), float(i) * 41.0, 7.0))
		_add_collider(self, Vector3(s * 1.1, s, s * 0.9), p + Vector3(0.0, s * 0.5, 0.0))
	var small := MultiMesh.new()
	small.transform_format = MultiMesh.TRANSFORM_3D
	small.use_colors = true
	small.mesh = _unit_sphere
	small.instance_count = 34
	for i in 34:
		var x := _rng.randf_range(-20.0, 20.0)
		var z := _rng.randf_range(-60.0, 22.0)
		if absf(x - _path_x(z)) < _path_half_width(z) + 0.7:
			x += 4.0
		var s := _rng.randf_range(0.18, 0.62)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * 1.3, s, s))
		small.set_instance_transform(i, Transform3D(basis, Vector3(x, s * 0.18, z)))
		small.set_instance_color(i, Color(1.0, 1.0, 1.0, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = small
	mmi.material_override = _mat["rock"]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ------------------------------------------------------------------ bamboo / grass

func _can_place_bamboo(x: float, z: float) -> bool:
	if z > 24.0 or z < -64.0 or absf(x) > 23.0:
		return false
	if absf(x - _path_x(z)) < _path_half_width(z) + 1.65:
		return false
	if z > -2.4 and z < 2.4 and absf(x) < 7.6:
		return false
	if x > 11.4 and x < 18.6:
		return false
	if Vector2(x, z).distance_to(Vector2(-4.2, -12.0)) < 4.5:
		return false
	if Vector2(x, z).distance_to(Vector2(0.3, -23.0)) < 4.4:
		return false
	if Vector2(x, z).distance_to(Vector2(_path_x(-33.5), -33.5)) < 5.2:
		return false
	if Vector2(x, z).distance_to(Vector2(_path_x(-56.0), -56.0)) < 7.2:
		return false
	for house: Dictionary in _houses_data:
		if Vector2(x, z).distance_to(Vector2(house["pos"].x, house["pos"].z)) < 4.6:
			return false
	return true

func _make_stalk_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.032
	mesh.bottom_radius = 0.055
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 2
	return mesh

func _make_leaf_cluster_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var ang := float(i) * TAU / 12.0
		var lift := 0.25 + 0.35 * absf(sin(float(i) * 1.9))
		var dir := Vector3(cos(ang), lift, sin(ang)).normalized()
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * 0.13
		var base := Vector3(0.0, -0.06 - 0.04 * float(i % 3), 0.0)
		var tip := base + dir * (0.78 + 0.28 * absf(cos(float(i) * 2.3)))
		tip.y -= 0.22
		var mid := base + dir * 0.42
		st.add_vertex(base - side)
		st.add_vertex(base + side)
		st.add_vertex(mid + side * 0.6)
		st.add_vertex(mid + side * 0.6)
		st.add_vertex(mid - side * 0.6)
		st.add_vertex(tip)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh

func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var ang := float(i) * TAU / 4.0 + 0.4
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * 0.045
		var tip := Vector3(cos(ang) * 0.16, 0.48 + 0.12 * float(i % 2), sin(ang) * 0.16)
		st.add_vertex(-side)
		st.add_vertex(side)
		st.add_vertex(tip)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh

func _build_bamboo() -> void:
	var stalk_xforms: Array[Transform3D] = []
	var leaf_xforms: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var clusters: Array[Vector3] = []
	var attempts := 0
	while clusters.size() < 90 and attempts < 2000:
		attempts += 1
		var side := -1.0 if _rng.randf() < 0.55 else 1.0
		var x := side * _rng.randf_range(5.0, 22.5)
		var z := _rng.randf_range(-62.0, 23.0)
		if not _can_place_bamboo(x, z):
			continue
		clusters.append(Vector3(x, 0.0, z))
	var collision_clusters := 0
	for base: Vector3 in clusters:
		var count := _rng.randi_range(2, 4)
		var cluster_h := _rng.randf_range(7.5, 11.8)
		var near_path := absf(base.x - _path_x(base.z)) < _path_half_width(base.z) + 4.5
		if near_path and collision_clusters < 34:
			_add_cylinder_collider(self, 0.45, 4.0, base + Vector3(0.0, 2.0, 0.0))
			collision_clusters += 1
		for s in count:
			var offset := Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-1.2, 1.2))
			var h := cluster_h + _rng.randf_range(-0.8, 1.2)
			var width := _rng.randf_range(0.82, 1.18)
			var tilt := Basis(Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized(), _rng.randf_range(0.0, 0.055))
			var basis := tilt * Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(width, h, width))
			var pos := base + offset
			stalk_xforms.append(Transform3D(basis, pos))
			for f: float in [0.52, 0.72, 0.9]:
				var ls := _rng.randf_range(1.15, 2.15)
				var lb := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(ls, ls, ls))
				var lp := pos + Vector3(_rng.randf_range(-0.3, 0.3), h * f, _rng.randf_range(-0.3, 0.3))
				leaf_xforms.append(Transform3D(lb, lp))
				var tint := _rng.randf_range(0.82, 1.12)
				leaf_colors.append(Color(tint * 0.92, tint, tint * 0.86, 1.0))
	var stalk_mm := MultiMesh.new()
	stalk_mm.transform_format = MultiMesh.TRANSFORM_3D
	stalk_mm.mesh = _make_stalk_mesh()
	stalk_mm.instance_count = stalk_xforms.size()
	for i in stalk_xforms.size():
		stalk_mm.set_instance_transform(i, stalk_xforms[i])
	var stalk_mmi := MultiMeshInstance3D.new()
	stalk_mmi.multimesh = stalk_mm
	stalk_mmi.material_override = _mat["bamboo"]
	stalk_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stalk_mmi)

	var leaf_mesh := _make_leaf_cluster_mesh()
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color("#6f8a45")
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.vertex_color_is_srgb = true
	leaf_mat.roughness = 0.95
	leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var leaf_mm := MultiMesh.new()
	leaf_mm.transform_format = MultiMesh.TRANSFORM_3D
	leaf_mm.use_colors = true
	leaf_mm.mesh = leaf_mesh
	leaf_mm.instance_count = leaf_xforms.size()
	for i in leaf_xforms.size():
		leaf_mm.set_instance_transform(i, leaf_xforms[i])
		leaf_mm.set_instance_color(i, leaf_colors[i])
	var leaf_mmi := MultiMeshInstance3D.new()
	leaf_mmi.multimesh = leaf_mm
	leaf_mmi.material_override = leaf_mat
	leaf_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaf_mmi)
	# 第八轮吸收（wuxia-team/art/bamboo_v3b.png）：画稿竹丛垫在程序化竹秆脚下，
	# 补出竹林下层的枝叶质感。相机固定从南面朝北看，面片统一面向 +Z 即可；
	# 每丛 1~2 张、两张 MultiMesh（本体+落地影）共 2 个 draw call。
	var clump_xforms: Array[Transform3D] = []
	var clump_colors: Array[Color] = []
	var clump_shadow_xforms: Array[Transform3D] = []
	var clump_lift := 744.0 * PROP_PIXEL_SIZE * 0.5
	for base: Vector3 in clusters:
		var n := 1 + (_rng.randi() % 2)
		for c in n:
			var cp := base + Vector3(_rng.randf_range(-0.9, 0.9), clump_lift, _rng.randf_range(-0.6, 0.4))
			var s := _rng.randf_range(1.5, 2.2)
			clump_xforms.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)).scaled(Vector3(s, s, 1.0)), cp))
			var tint := _rng.randf_range(0.86, 1.06)
			clump_colors.append(Color(tint * 0.95, tint, tint * 0.9, 1.0))
			var sh_s := s * 0.86
			clump_shadow_xforms.append(Transform3D(
				Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(sh_s, sh_s, 1.0)),
				Vector3(cp.x, 0.02, cp.z - clump_lift)))
	if clump_xforms.size() > 0:
		var clump_quad := QuadMesh.new()
		clump_quad.size = Vector2(622.0, 744.0) * PROP_PIXEL_SIZE
		var clump_mat := StandardMaterial3D.new()
		clump_mat.albedo_texture = load("res://assets/imported/scenery/bamboo_v3b.png")
		clump_mat.vertex_color_use_as_albedo = true
		clump_mat.vertex_color_is_srgb = true
		clump_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		clump_mat.alpha_scissor_threshold = 0.33
		clump_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		clump_mat.cull_mode = BaseMaterial3D.CULL_BACK
		clump_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var clump_mm := MultiMesh.new()
		clump_mm.transform_format = MultiMesh.TRANSFORM_3D
		clump_mm.use_colors = true
		clump_mm.mesh = clump_quad
		clump_mm.instance_count = clump_xforms.size()
		for i in clump_xforms.size():
			clump_mm.set_instance_transform(i, clump_xforms[i])
			clump_mm.set_instance_color(i, clump_colors[i])
		var clump_mmi := MultiMeshInstance3D.new()
		clump_mmi.multimesh = clump_mm
		clump_mmi.material_override = clump_mat
		clump_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(clump_mmi)
		# 竹丛落地影：与道具投影同款平铺面片。
		var sh_quad := QuadMesh.new()
		sh_quad.size = Vector2(622.0, 744.0) * PROP_PIXEL_SIZE
		var sh_mat := StandardMaterial3D.new()
		sh_mat.albedo_texture = load("res://assets/imported/scenery/bamboo_v3b_shadow.png")
		sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sh_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sh_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var sh_mm := MultiMesh.new()
		sh_mm.transform_format = MultiMesh.TRANSFORM_3D
		sh_mm.mesh = sh_quad
		sh_mm.instance_count = clump_shadow_xforms.size()
		for i in clump_shadow_xforms.size():
			sh_mm.set_instance_transform(i, clump_shadow_xforms[i])
		var sh_mmi := MultiMeshInstance3D.new()
		sh_mmi.multimesh = sh_mm
		sh_mmi.material_override = sh_mat
		sh_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sh_mmi)
	# Fallen stalks and stumps for the grove floor.
	for i in 5:
		var p := Vector3(_rng.randf_range(-9.0, 9.0), 0.0, _rng.randf_range(-30.0, -4.0))
		if absf(p.x - _path_x(p.z)) < _path_half_width(p.z) + 0.8:
			continue
		_add_cyl(self, 0.13, _rng.randf_range(2.4, 3.6), p + Vector3(0.0, 0.13, 0.0), _mat["bamboo"],
			Vector3(90.0, _rng.randf() * 180.0, 0.0))

func _build_grass() -> void:
	var mesh := _make_grass_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#66793f")
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.98
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while transforms.size() < 820 and tries < 3400:
		tries += 1
		var x := _rng.randf_range(-21.0, 21.0)
		var z := _rng.randf_range(-62.0, 25.0)
		if absf(x - _path_x(z)) < _path_half_width(z) + 0.35:
			continue
		if x > 11.7 and x < 18.3:
			continue
		var s := _rng.randf_range(0.55, 1.25)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
		var tint := _rng.randf_range(0.78, 1.15)
		colors.append(Color(tint * 0.9, tint, tint * 0.85, 1.0))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 42.0
	add_child(mmi)

# ------------------------------------------------------------------ mist / skyline

func _make_cloud_texture() -> ImageTexture:
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var blobs: Array[Vector3] = []
	for i in 14:
		blobs.append(Vector3(_rng.randf_range(20.0, 236.0), _rng.randf_range(26.0, 102.0), _rng.randf_range(14.0, 40.0)))
	for y in 128:
		for x in 256:
			var a := 0.0
			for b: Vector3 in blobs:
				var d := Vector2(x - b.x, (y - b.y) * 1.7).length() / b.z
				a += maxf(0.0, 1.0 - d * d) * 0.32
			a = clampf(a, 0.0, 0.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _build_mist() -> void:
	var tex := _make_cloud_texture()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.93, 0.96, 1.0, 0.52)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.render_priority = 2
	var cards: Array[Vector3] = [
		Vector3(-8.0, 2.2, -8.0), Vector3(8.5, 2.9, -18.0),
		Vector3(-2.0, 3.4, -31.0), Vector3(-13.0, 2.0, 4.0),
	]
	for i in cards.size():
		var quad := QuadMesh.new()
		quad.size = Vector2(28.0 + float(i % 2) * 8.0, 7.5)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat.duplicate()
		mi.position = cards[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mist_nodes.append(mi)
		_mist_bases.append(cards[i])

func _build_mountains_and_pines() -> void:
	var mountain_specs: Array[Vector3] = [
		Vector3(-24.0, 0.0, -80.0), Vector3(-2.0, 0.0, -88.0), Vector3(26.0, 0.0, -82.0),
		Vector3(48.0, 0.0, -74.0), Vector3(-46.0, 0.0, -72.0),
	]
	for i in mountain_specs.size():
		var p := mountain_specs[i]
		var h := 18.0 + float(i % 3) * 7.0
		var w := 26.0 + float(i % 2) * 12.0
		_add_cone(self, w, h, p + Vector3(0.0, h * 0.5 - 1.0, 0.0), _mat["mountain"])
	# Pine silhouettes at the village edges.
	for p: Vector3 in [Vector3(-18.0, 0.0, 10.0), Vector3(18.5, 0.0, 20.0), Vector3(-19.5, 0.0, -3.0), Vector3(21.5, 0.0, -12.0)]:
		var tree := Node3D.new()
		tree.position = p
		add_child(tree)
		_add_cyl(tree, 0.36, 3.2, Vector3(0.0, 1.6, 0.0), _mat["trunk"])
		for i in 3:
			_add_cone(tree, 3.4 - float(i) * 0.7, 2.4, Vector3(0.0, 3.0 + float(i) * 1.25, 0.0), _mat["pine"])
		_add_cylinder_collider(tree, 0.3, 3.0, Vector3(0.0, 1.5, 0.0))

# ------------------------------------------------------------------ actors

func _build_player() -> void:
	player = ExplorerPlayer.new()
	player.name = "ShenYan"
	player.position = PLAYER_SPAWN
	add_child(player)
	player.set_facing(0)
	player.set_active(false)

func _build_camera() -> void:
	camera = PlayerCamera.new()
	camera.target = player
	camera.name = "FollowCamera"
	add_child(camera)
	camera.snap()

func _npc_dirs(base: String, diagonals: bool, prefix: String, diagonal_prefix: String) -> Dictionary:
	var d := {}
	for name: String in ["down", "right", "left", "up"]:
		d[name] = base + "%s_%s_0.png" % [prefix, name]
	if diagonals:
		for name: String in ["downright", "downleft", "upright", "upleft"]:
			d[name] = base + "%s_%s_0.png" % [diagonal_prefix, name]
	return d

func _lead_dirs(base: String, prefix: String) -> Dictionary:
	var d := {}
	for name: String in ["down", "downright", "right", "upright", "up", "upleft", "left", "downleft"]:
		d[name] = base + "%s_idle_%s_0.png" % [prefix, name]
	return d

## 3D character GLBs (tools/img3d TripoSR pipeline) keyed by the base NPC id;
## NPCs without an entry, or with a missing file, keep their billboards.
const NPC_MODELS := {
	# [path, height m, texture tint]
	"linzhaowan": ["res://assets/glb/linzhaowan.glb", 1.63, 0.82],
	"liheng": ["res://assets/glb/liheng.glb", 1.85, 1.0],
	"gesancheng": ["res://assets/glb/gesancheng.glb", 1.65, 1.0],
	"dashou": ["res://assets/glb/yaoxing_dashou.glb", 1.72, 1.0],
}

func _spawn_npc(npc_id: String, display: String, point: String, pos: Vector3, dirs: Dictionary,
		height_px: int, canvas: Vector2, foot: Vector2, face_dir: String) -> void:
	var npc := WorldNpc.new()
	npc.npc_id = npc_id
	npc.display_name = display
	npc.interact_point = point
	npc.dirs = dirs
	npc.height_px = height_px
	npc.canvas = canvas
	npc.foot_anchor = foot
	npc.player_ref = player
	var model_key := npc_id.get_slice("_", 0)
	if NPC_MODELS.has(model_key):
		npc.model_path = str(NPC_MODELS[model_key][0])
		npc.model_height = float(NPC_MODELS[model_key][1])
		npc.model_tint = float(NPC_MODELS[model_key][2])
	npc.position = pos
	add_child(npc)
	npc.face_towards(pos + _dir_to_vector(face_dir))
	npcs[npc_id] = npc
	var body := _add_cylinder_collider(npc, 0.42, 1.7, Vector3(0.0, 0.85, 0.0))
	body.name = "Collider"

func _dir_to_vector(dir_name: String) -> Vector3:
	match dir_name:
		"down":
			return Vector3(0.0, 0.0, 1.0)
		"downright":
			return Vector3(0.707, 0.0, 0.707)
		"right":
			return Vector3(1.0, 0.0, 0.0)
		"upright":
			return Vector3(0.707, 0.0, -0.707)
		"up":
			return Vector3(0.0, 0.0, -1.0)
		"upleft":
			return Vector3(-0.707, 0.0, -0.707)
		"left":
			return Vector3(-1.0, 0.0, 0.0)
		"downleft":
			return Vector3(-0.707, 0.0, 0.707)
	return Vector3(0.0, 0.0, 1.0)

func _build_npcs() -> void:
	_spawn_npc("zhoubo", "周伯", "village.zhoubo", Vector3(-4.8, 0.0, 10.6),
		_npc_dirs("res://docs/ref-characters-v3/npc/", true, "zhoubo_v3_idle", "zhoubo_v3b_idle"),
		414, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	_spawn_npc("mingcheng", "明澄", "village.mingcheng", Vector3(4.6, 0.0, 16.8),
		_npc_dirs("res://docs/ref-characters-v3/npc/", true, "mingcheng_v3_idle", "mingcheng_v3b_idle"),
		450, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	_spawn_npc("linzhaowan", "林照晚", "bamboo.linzhaowan", Vector3(-4.2, 0.0, -12.0),
		_lead_dirs("res://docs/ref-characters-v2/", "linzhaowan_v2"),
		422, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	_spawn_npc("liheng", "厉横", "bamboo.liheng", Vector3(0.3, 0.0, -23.0),
		_npc_dirs("res://docs/ref-characters-v3/npc/", false, "liheng_v3_idle", ""),
		479, Vector2(460.0, 540.0), Vector2(230.0, 516.0), "down")
	# Chapter 2 (v1.1) placements; shown/hidden by GameState.is_point_visible().
	_spawn_npc("liheng_gate", "厉横", "gate.liheng", Vector3(_path_x(1.6) + 1.7, 0.0, 1.6),
		_npc_dirs("res://docs/ref-characters-v3/npc/", false, "liheng_v3_idle", ""),
		479, Vector2(460.0, 540.0), Vector2(230.0, 516.0), "down")
	_spawn_npc("linzhaowan_gate", "林照晚", "gate.linzhaowan", Vector3(_path_x(1.4) - 1.8, 0.0, 1.4),
		_lead_dirs("res://docs/ref-characters-v2/", "linzhaowan_v2"),
		422, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	_build_yiting()
	# 葛三秤 uses the TripoSR GLB; if the file is missing, the 厉横 idle
	# billboard (tinted, slightly shorter) stays as fallback.
	_spawn_npc("gesancheng", "葛三秤", "yiting.gesancheng", Vector3(_path_x(-30.6) - 1.6, 0.0, -30.6),
		_npc_dirs("res://docs/ref-characters-v3/npc/", false, "liheng_v3_idle", ""),
		479, Vector2(460.0, 540.0), Vector2(230.0, 516.0), "down")
	var ge := npcs["gesancheng"] as WorldNpc
	var ge_sprite := ge.get_node_or_null("Sprite") as Sprite3D
	if ge_sprite != null:
		ge_sprite.modulate = Color(0.78, 0.72, 0.62)
		ge_sprite.scale = Vector3(0.9, 1.0, 1.0)
	_spawn_npc("linzhaowan_yiting", "林照晚", "yiting.linzhaowan", Vector3(_path_x(-30.2) + 1.8, 0.0, -30.2),
		_lead_dirs("res://docs/ref-characters-v2/", "linzhaowan_v2"),
		422, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	_build_stairs()
	_build_hermitage()
	# Chapter 3 placements north of the 驿亭; visibility is entirely
	# GameState.is_point_visible() (stair / hermitage only after ch2 completed).
	var stair_z := -44.0
	var stair_y := _north_height(stair_z)
	_spawn_npc("dashou", "药行打手", "stair.dashou",
		Vector3(_path_x(stair_z) + 0.15, stair_y, stair_z),
		_npc_dirs("res://docs/ref-characters-v3/npc/", false, "liheng_v3_idle", ""),
		479, Vector2(460.0, 540.0), Vector2(230.0, 516.0), "down")
	_spawn_npc("linzhaowan_stair", "林照晚", "stair.linzhaowan",
		Vector3(_path_x(stair_z) - 1.8, stair_y, stair_z + 0.6),
		_lead_dirs("res://docs/ref-characters-v2/", "linzhaowan_v2"),
		422, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	var herm_z := -56.0
	var herm_y := _north_height(herm_z)
	var hx := _path_x(herm_z)
	# 褚铁 / 闻素: no dedicated art yet; tinted 厉横 / 周伯 billboards as fallback.
	_spawn_npc("chutie", "褚铁", "hermitage.chutie",
		Vector3(hx + 0.2, herm_y, herm_z + 4.2),
		_npc_dirs("res://docs/ref-characters-v3/npc/", false, "liheng_v3_idle", ""),
		479, Vector2(460.0, 540.0), Vector2(230.0, 516.0), "down")
	var chu := npcs["chutie"] as WorldNpc
	var chu_sprite := chu.get_node_or_null("Sprite") as Sprite3D
	if chu_sprite != null:
		chu_sprite.modulate = Color(0.62, 0.55, 0.50)
	_spawn_npc("linzhaowan_hermitage", "林照晚", "hermitage.linzhaowan",
		Vector3(hx - 2.2, herm_y, herm_z + 3.6),
		_lead_dirs("res://docs/ref-characters-v2/", "linzhaowan_v2"),
		422, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	_spawn_npc("wensu", "闻素", "hermitage.wensu",
		Vector3(hx + 0.1, herm_y, herm_z - 1.6),
		_npc_dirs("res://docs/ref-characters-v3/npc/", true, "zhoubo_v3_idle", "zhoubo_v3b_idle"),
		414, Vector2(420.0, 500.0), Vector2(210.0, 476.0), "down")
	var wen := npcs["wensu"] as WorldNpc
	var wen_sprite := wen.get_node_or_null("Sprite") as Sprite3D
	if wen_sprite != null:
		wen_sprite.modulate = Color(0.78, 0.82, 0.88)
	apply_state()

## 驿亭: a small roadside pavilion at the north end of the bamboo path (ch2 yiting.*).
func _build_yiting() -> void:
	var root := Node3D.new()
	root.name = "Yiting"
	root.position = Vector3(_path_x(-33.5), 0.0, -33.5)
	add_child(root)
	_add_box(root, Vector3(4.2, 0.24, 3.4), Vector3(0.0, 0.12, 0.0), _mat["stone"])
	for x: float in [-1.8, 1.8]:
		for z: float in [-1.4, 1.4]:
			_add_cyl(root, 0.3, 2.7, Vector3(x, 1.59, z), _mat["wood_red"])
			_add_collider(root, Vector3(0.4, 2.8, 0.4), Vector3(x, 1.4, z))
	_add_box(root, Vector3(4.4, 0.22, 3.6), Vector3(0.0, 3.0, 0.0), _mat["wood_dark"])
	_add_box(root, Vector3(5.0, 0.3, 4.2), Vector3(0.0, 3.3, 0.0), _mat["roof"])
	_add_box(root, Vector3(3.4, 0.3, 2.6), Vector3(0.0, 3.6, 0.0), _mat["roof"])
	_add_box(root, Vector3(1.6, 0.42, 0.7), Vector3(0.0, 0.45, -0.6), _mat["wood_dark"])
	var plaque := Label3D.new()
	plaque.text = "驿亭"
	plaque.font = UiTheme.body_font()
	plaque.font_size = 64
	plaque.pixel_size = 0.006
	plaque.modulate = Color(0.95, 0.88, 0.7)
	plaque.outline_size = 10
	plaque.position = Vector3(0.0, 2.75, 1.85)
	root.add_child(plaque)

## Height of the chapter-3 north path: a gentle rise from the 驿亭 up to the 清溪庵 terrace.
func _north_height(z: float) -> float:
	const START_Z := -37.0
	const END_Z := -50.0
	const TOP := 1.5
	if z >= START_Z:
		return 0.0
	if z <= END_Z:
		return TOP
	return lerpf(0.0, TOP, (START_Z - z) / (START_Z - END_Z))

## 后山石阶: stone treads on a walkable ramp, continuing the bamboo path north of the 驿亭.
func _build_stairs() -> void:
	var root := Node3D.new()
	root.name = "Stair"
	root.position = Vector3(_path_x(-44.0), 0.0, -44.0)
	add_child(root)
	var start_z := -37.0
	var end_z := -50.0
	var top := 1.5
	var run := start_z - end_z
	var length := sqrt(run * run + top * top)
	var angle := rad_to_deg(atan2(top, run))
	var mid_z := (start_z + end_z) * 0.5
	var mid_y := top * 0.5
	# One sloped collider so the player walks smoothly (~7°).
	_add_collider(self, Vector3(5.6, 0.35, length), Vector3(_path_x(mid_z), mid_y, mid_z), Vector3(angle, 0.0, 0.0))
	var steps := 11
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var z := lerpf(start_z, end_z, t)
		var y := lerpf(0.08, top + 0.08, t)
		var w := 4.2 + float(i % 2) * 0.15
		_add_box(self, Vector3(w, 0.16, 1.25), Vector3(_path_x(z), y, z), _mat["stone"] if i % 2 == 0 else _mat["stone_dark"])
	# Low stone curbs along both sides.
	for side: float in [-2.35, 2.35]:
		for i in 6:
			var t := (float(i) + 0.5) / 6.0
			var z := lerpf(start_z, end_z, t)
			var y := _north_height(z) + 0.22
			_add_box(self, Vector3(0.28, 0.36, 2.15), Vector3(_path_x(z) + side, y, z), _mat["rock"])
	# A couple of roadside rocks.
	_add_box(self, Vector3(0.9, 0.7, 1.1), Vector3(_path_x(-41.0) - 3.1, _north_height(-41.0) + 0.28, -41.0), _mat["rock"], Vector3(0.0, 25.0, 0.0))
	_add_box(self, Vector3(1.1, 0.55, 0.8), Vector3(_path_x(-47.5) + 3.2, _north_height(-47.5) + 0.22, -47.5), _mat["stone_dark"], Vector3(0.0, -18.0, 0.0))

## 清溪庵: a small hillside courtyard (white walls, dark tile, wood gate) at the top of the stairs.
func _build_hermitage() -> void:
	var y0 := _north_height(-56.0)
	var root := Node3D.new()
	root.name = "Hermitage"
	root.position = Vector3(_path_x(-56.0), y0, -56.0)
	add_child(root)
	# Terrace under the whole compound, plus a flat collider to walk on.
	_add_box(root, Vector3(10.0, 0.28, 12.0), Vector3(0.0, -0.08, 0.0), _mat["stone"])
	_add_collider(root, Vector3(10.0, 0.28, 12.0), Vector3(0.0, -0.08, 0.0))
	# Courtyard walls, opening to the south (toward the stairs / +Z).
	_add_box(root, Vector3(9.2, 2.2, 0.28), Vector3(0.0, 1.1, -5.4), _mat["hermitage_wall"])
	_add_collider(root, Vector3(9.2, 2.2, 0.28), Vector3(0.0, 1.1, -5.4))
	for x: float in [-4.6, 4.6]:
		_add_box(root, Vector3(0.28, 2.2, 10.6), Vector3(x, 1.1, -0.2), _mat["hermitage_wall"])
		_add_collider(root, Vector3(0.28, 2.2, 10.6), Vector3(x, 1.1, -0.2))
	# South wall with a 2.4 m gate opening.
	for x: float in [-3.3, 3.3]:
		_add_box(root, Vector3(2.6, 2.2, 0.28), Vector3(x, 1.1, 5.2), _mat["hermitage_wall"])
		_add_collider(root, Vector3(2.6, 2.2, 0.28), Vector3(x, 1.1, 5.2))
	# Gate posts + a taller lintel board so the 清溪庵 sign sits on the wood
	# and does not share screen space with NPC name labels (褚铁's 铁 was
	# compositing to the right of 庵 and looked like an extra character).
	for x: float in [-1.5, 1.5]:
		_add_box(root, Vector3(0.32, 3.4, 0.32), Vector3(x, 1.7, 5.25), _mat["hermitage_wood"])
		_add_collider(root, Vector3(0.32, 3.4, 0.32), Vector3(x, 1.7, 5.25))
	_add_box(root, Vector3(4.0, 0.52, 0.42), Vector3(0.0, 3.25, 5.25), _mat["hermitage_wood"])
	# Main hall at the north end of the yard.
	_add_box(root, Vector3(6.4, 2.5, 3.6), Vector3(0.0, 1.25, -3.4), _mat["hermitage_wall"])
	_add_collider(root, Vector3(6.4, 2.5, 3.6), Vector3(0.0, 1.25, -3.4))
	_add_box(root, Vector3(7.4, 0.32, 4.4), Vector3(0.0, 2.7, -3.4), _mat["hermitage_tile"])
	_add_box(root, Vector3(5.2, 0.28, 3.0), Vector3(0.0, 3.0, -3.4), _mat["hermitage_tile"])
	# Door recess and steps.
	_add_box(root, Vector3(1.6, 2.0, 0.12), Vector3(0.0, 1.05, -1.55), _mat["hermitage_wood"])
	_add_box(root, Vector3(2.2, 0.18, 0.8), Vector3(0.0, 0.12, -1.2), _mat["stone_dark"])
	# Side wing, a small store-room.
	_add_box(root, Vector3(2.4, 1.9, 2.4), Vector3(3.0, 0.95, 0.4), _mat["hermitage_wall"])
	_add_collider(root, Vector3(2.4, 1.9, 2.4), Vector3(3.0, 0.95, 0.4))
	_add_box(root, Vector3(2.9, 0.24, 2.9), Vector3(3.0, 2.05, 0.4), _mat["hermitage_tile"])
	var plaque := Label3D.new()
	plaque.name = "Plaque"
	plaque.text = "清溪庵"
	plaque.font = UiTheme.body_font()
	plaque.font_size = 64
	plaque.pixel_size = 0.0055
	plaque.modulate = Color(0.95, 0.88, 0.7)
	plaque.outline_size = 8
	plaque.outline_modulate = Color(0, 0, 0, 0.85)
	plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	plaque.double_sided = false
	plaque.no_depth_test = false
	plaque.position = Vector3(0.0, 3.25, 5.50)
	root.add_child(plaque)

func _build_bounds() -> void:
	# Side walls lengthened, north wall moved past 清溪庵 (was z≈−39).
	_add_collider(self, Vector3(2.0, 12.0, 120.0), Vector3(-23.5, 6.0, -20.0))
	_add_collider(self, Vector3(2.0, 12.0, 120.0), Vector3(23.5, 6.0, -20.0))
	_add_collider(self, Vector3(48.0, 12.0, 2.0), Vector3(0.0, 6.0, 25.0))
	_add_collider(self, Vector3(48.0, 12.0, 2.0), Vector3(0.0, 6.0, -66.0))

## Re-query NPC visibility (call on GameState.changed and after loading).
func apply_state() -> void:
	for npc_id: String in npcs:
		var npc := npcs[npc_id] as WorldNpc
		var show := GameState.is_point_visible(npc.interact_point)
		if npc_id == "liheng":
			# Chapter-1 厉横 in the bamboo grove leaves once beaten / once he waits at the gate.
			show = show and not GameState.is_flag_true("battle.liheng.won") \
				and not GameState.is_point_visible("gate.liheng")
		if npc.dormant == show:
			npc.set_dormant(not show)

func get_npc(npc_id: String) -> WorldNpc:
	return npcs.get(npc_id, null) as WorldNpc
