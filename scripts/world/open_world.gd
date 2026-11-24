class_name OpenWorld
extends Node3D
## 开放世界入口：240m×240m，60m 分块，8 个具名区块 + 8 个远岭块。
## 只保持玩家周围 3×3 区块；进入 add、离开 queue_free。
## 环境：Filmic + glow + depth/height fog + 暗角颗粒；Mobile 渲染器，
## 无 SSAO/SSR/SDFGI/体积雾。

const REGIONS_PATH := "res://data/regions.json"
const CHUNK_SIZE := 60.0
const WORLD_SIZE := 240.0
const CHUNK_RADIUS := 1
const PLAYER_SPEED_TINT := 4.0
## 同屏最多渲染 10 个 NPC；20m 外隐藏，15m 外冻结骨骼动画。
const NPC_RENDER_BUDGET := 10
## 对话/HUD 的 2D 立绘头像继续用（3D 模型只负责探索态人物）。
const PORTRAITS := {
	"shenyan": "res://docs/ref-characters-v3/shenyan_portrait_v2.png",
	"linzhaowan": "res://docs/ref-characters-v3/linzhaowan_portrait_v2.png",
	"zhoubo": "res://docs/ref-characters-v3/npc/zhoubo_portrait_v3.png",
	"mingcheng": "res://docs/ref-characters-v3/npc/mingcheng_portrait_v3.png",
	"liheng": "res://docs/ref-characters-v3/npc/liheng_portrait_v3.png",
}

var regions_cfg: Dictionary = {}
var world_cfg: Dictionary = {}
var regions: Array[Dictionary] = []
var roads: Array = []
var region_by_chunk: Dictionary = {}
var loaded_regions: Dictionary = {}
var spawn := Vector3(-30.0, 0.0, 48.0)
var spawn_facing := 4

var player: ExplorerPlayer
var camera: PlayerCamera
var npcs: Dictionary = {}
var encounter_manager: EncounterManager
var environment: Environment
var factory: BuildingFactory
var terrain: ChunkBuilder

var _chunks: Dictionary = {}
var _loaded_region_counts: Dictionary = {}
var _current_chunk := Vector2i(-99, -99)
## 第四轮：跨区块静态合批。区块内先按材质合，再全局按材质+投影合成 1 个
## MeshInstance，9 区块的静态道具从 ~66 个渲染对象降到 ~12–20 个。
var _static_root: Node3D
var _static_dirty := true
var _update_acc := 0.0
var _tint_acc := 0.0
var _mist: Array[MeshInstance3D] = []
var _mist_bases: Array[Vector3] = []
var _t := 0.0
var _road_segments: Array = []
var _post_layer: CanvasLayer

func _ready() -> void:
	if not _load_regions():
		push_error("OpenWorld: " + str(regions_cfg.get("_error", "regions load failed")))
	factory = BuildingFactory.new(20261121)
	terrain = ChunkBuilder.new(self, factory)
	_static_root = Node3D.new()
	_static_root.name = "GlobalStaticBatches"
	add_child(_static_root)
	_build_environment()
	_build_far_scenery()
	_build_depth_layers()
	_build_foreground()
	_build_mist()
	_build_player()
	_build_npcs()
	_build_camera()
	_build_encounters()
	_build_post_fx()
	if GameState.changed.is_connected(apply_state) == false:
		GameState.changed.connect(apply_state)
	update_chunks(true)
	apply_state()
	_update_npc_budget()

func _exit_tree() -> void:
	ToonModel.clear_scene_cache()

func _process(delta: float) -> void:
	_t += delta
	_update_acc += delta
	_tint_acc += delta
	if _update_acc >= 0.2:
		_update_acc = 0.0
		update_chunks(false)
		_update_npc_budget()
	if _tint_acc >= 0.35:
		_tint_acc = 0.0
		_update_region_tint()
	for i in _mist.size():
		var node := _mist[i]
		var base := _mist_bases[i]
		node.position = base + Vector3(sin(_t * 0.045 + float(i) * 1.7) * 1.7,
			sin(_t * 0.07 + float(i)) * 0.15, 0.0)

# ------------------------------------------------------------------ 数据

func _load_regions() -> bool:
	var f := FileAccess.open(REGIONS_PATH, FileAccess.READ)
	if f == null:
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return false
	f.close()
	if typeof(json.data) != TYPE_DICTIONARY:
		return false
	regions_cfg = json.data
	world_cfg = regions_cfg.get("world", {})
	spawn = _vec3(world_cfg.get("spawn", [-30.0, 0.0, 48.0]))
	spawn_facing = int(world_cfg.get("spawnFacing", 4))
	regions = []
	region_by_chunk = {}
	for entry: Variant in regions_cfg.get("regions", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region: Dictionary = entry
		var chunk_raw: Variant = region.get("chunk", [0, 0])
		if typeof(chunk_raw) != TYPE_ARRAY:
			continue
		var chunk := Vector2i(int((chunk_raw as Array)[0]), int((chunk_raw as Array)[1]))
		region["_chunk"] = chunk
		regions.append(region)
		region_by_chunk[chunk] = region
	roads = regions_cfg.get("roads", [])
	_road_segments = []
	for road: Variant in roads:
		if typeof(road) != TYPE_ARRAY or (road as Array).size() < 2:
			continue
		for i in (road as Array).size() - 1:
			var a: Variant = (road as Array)[i]
			var b: Variant = (road as Array)[i + 1]
			if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
				_road_segments.append([
					Vector2(float((a as Array)[0]), float((a as Array)[1])),
					Vector2(float((b as Array)[0]), float((b as Array)[1])),
				])
	return not regions.is_empty()

func _vec3(raw: Variant) -> Vector3:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return Vector3.ZERO

func chunk_center(chunk: Vector2i) -> Vector2:
	return Vector2(-WORLD_SIZE * 0.5 + (float(chunk.x) + 0.5) * CHUNK_SIZE,
		-WORLD_SIZE * 0.5 + (float(chunk.y) + 0.5) * CHUNK_SIZE)

func chunk_coord_for_pos(pos: Vector3) -> Vector2i:
	var cells := int(world_cfg.get("cells", 4))
	return Vector2i(
		clampi(int(floor((pos.x + WORLD_SIZE * 0.5) / CHUNK_SIZE)), 0, cells - 1),
		clampi(int(floor((pos.z + WORLD_SIZE * 0.5) / CHUNK_SIZE)), 0, cells - 1)
	)

func region_for_point(x: float, z: float) -> Dictionary:
	var chunk := chunk_coord_for_pos(Vector3(x, 0.0, z))
	return (region_by_chunk.get(chunk, {}) as Dictionary)

func ground_height_at(x: float, z: float) -> float:
	var region := region_for_point(x, z)
	if region.is_empty():
		return 0.0
	return terrain.height_at(x, z, region)

func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1.0e9
	for seg: Array in _road_segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

func region_at_player() -> Dictionary:
	return region_for_point(player.global_position.x, player.global_position.z)

# ------------------------------------------------------------------ 环境

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#a9c0d8")
	sky_mat.sky_horizon_color = Color("#efe5d2")
	sky_mat.ground_horizon_color = Color("#cbbfa8")
	sky_mat.ground_bottom_color = Color("#5c6258")
	sky_mat.sun_angle_max = 24.0
	sky_mat.sky_energy_multiplier = 0.8
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.82
	env.tonemap_white = 8.0
	# glow：只给雾/白衣一点光晕，不让白衣炸开。
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_strength = 1.0
	# DEPTH 雾 16~58m：只雾远景，近景保住对比，不再全局发灰。
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 16.0
	env.fog_depth_end = 58.0
	env.fog_depth_curve = 1.0
	env.fog_light_color = Color("#dce6ee")
	env.fog_light_energy = 0.9
	# height 雾只留薄薄一层；0.5 会把近景地面糊成灰白。
	env.fog_density = 0.40
	env.fog_sky_affect = 0.55
	env.fog_aerial_perspective = 0.45
	env.fog_height = 0.9
	env.fog_height_density = 0.06
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.10
	env.adjustment_brightness = 1.0
	environment = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 主光：暖色低角度，从镜头左前方打，3D 人物的脸/衣褶要吃到光；
	# 影子落向画面右后方，blob 影补脚底接触暗部。
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, -48.0, 0.0)
	sun.light_color = Color("#ffd9a8")
	sun.light_energy = 1.28
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 42.0
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 0.9
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	add_child(sun)

	# 冷色补光：从右前方托住脸和衣褶，不投影；与暖主光形成双色。
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-20.0, 35.0, 0.0)
	fill.light_color = Color("#7fa6c9")
	fill.light_energy = 0.42
	fill.shadow_enabled = false
	add_child(fill)

func _build_far_scenery() -> void:
	# 世界边缘的兜底地面，避免雾缝里看到虚空。
	var under := PlaneMesh.new()
	under.size = Vector2(420.0, 420.0)
	var umi := MeshInstance3D.new()
	umi.mesh = under
	var umat := StandardMaterial3D.new()
	umat.albedo_color = Color("#5d6451")
	umat.roughness = 1.0
	umi.material_override = umat
	umi.position = Vector3(0.0, -1.6, 0.0)
	umi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(umi)
	# 远山剪影：低模锥体，雾里只留轮廓。12 座山合并成 1 个 MultiMesh。
	var mountain_mat := StandardMaterial3D.new()
	mountain_mat.albedo_color = Color("#9aa9b8")
	mountain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var specs := [
		Vector3(-118.0, 0.0, -96.0), Vector3(-62.0, 0.0, -132.0),
		Vector3(12.0, 0.0, -138.0), Vector3(78.0, 0.0, -124.0),
		Vector3(132.0, 0.0, -78.0), Vector3(142.0, 0.0, -8.0),
		Vector3(136.0, 0.0, 68.0), Vector3(86.0, 0.0, 128.0),
		Vector3(8.0, 0.0, 142.0), Vector3(-72.0, 0.0, 132.0),
		Vector3(-136.0, 0.0, 74.0), Vector3(-142.0, 0.0, -12.0),
	]
	var mountain_mesh := CylinderMesh.new()
	mountain_mesh.top_radius = 0.0
	mountain_mesh.bottom_radius = 0.5
	mountain_mesh.height = 1.0
	mountain_mesh.radial_segments = 7
	mountain_mesh.rings = 1
	var mountain_xforms: Array[Transform3D] = []
	for i in specs.size():
		var h := 30.0 + float(i % 4) * 9.0
		var w := 44.0 + float(i % 3) * 14.0
		mountain_xforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(w, h, w)),
			specs[i] + Vector3(0.0, h * 0.5 - 2.0, 0.0)))
	_make_multimesh(mountain_mesh, mountain_mat, mountain_xforms, "FarMountains")

## 2–3 层远景剪影：竹/山，雾里只留轮廓，给画面顶部与纵深。
func _build_depth_layers() -> void:
	var layers := [
		{"color": Color("#54685a"), "z": 31.0, "height": 6.0, "xs": [-44.0, -24.0, -16.0]},
		{"color": Color("#5d7364"), "z": 25.0, "height": 5.0, "xs": [-38.0, -20.0]},
		{"color": Color("#667c6c"), "z": 19.0, "height": 4.0, "xs": [-46.0, -12.0]},
	]
	for layer: Dictionary in layers:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = layer["color"]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.roughness = 1.0
		var xs: Array = layer["xs"]
		var stalk_mesh := CylinderMesh.new()
		stalk_mesh.top_radius = 0.035
		stalk_mesh.bottom_radius = 0.09
		stalk_mesh.height = 1.0
		stalk_mesh.radial_segments = 5
		var leaf_mesh := BoxMesh.new()
		leaf_mesh.size = Vector3(1.6, 0.08, 0.4)
		var stalk_xforms: Array[Transform3D] = []
		var leaf_xforms: Array[Transform3D] = []
		for i in xs.size():
			var clump_pos := Vector3(xs[i] + float(i % 2) * 2.2, 0.0,
				float(layer["z"]) + float(i % 3) * 2.0)
			for s in 3:
				var h := float(layer["height"]) + float(s) * 1.1
				var stalk_pos := clump_pos + Vector3(float(s - 1) * 0.55, h * 0.5, float(s) * 0.3)
				var stalk_basis := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(float(s - 1) * 3.0)))
				stalk_basis = stalk_basis.scaled(Vector3(1.0, h, 1.0))
				stalk_xforms.append(Transform3D(stalk_basis, stalk_pos))
				# 顶部叶簇：用交叉长条压出竹梢轮廓。
				for k in 3:
					var leaf_pos := clump_pos + Vector3(
						float(s - 1) * 0.55 + float(k - 1) * 0.5,
						h - 0.6 + float(k) * 0.22,
						float(s) * 0.3)
					var leaf_basis := Basis.from_euler(Vector3(
						0.0, deg_to_rad(float(k) * 47.0), deg_to_rad(float(k - 1) * 14.0)))
					leaf_xforms.append(Transform3D(leaf_basis, leaf_pos))
		_make_multimesh(stalk_mesh, mat, stalk_xforms, "DepthStalks_%d" % int(layer["z"]))
		_make_multimesh(leaf_mesh, mat, leaf_xforms, "DepthLeaves_%d" % int(layer["z"]))

## 近景遮挡：只在画面上缘放斜枝与竹叶，不在画面中间拉竖柱。
func _build_foreground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3f5137")
	mat.roughness = 0.95
	var branch_mesh := CylinderMesh.new()
	branch_mesh.top_radius = 0.018
	branch_mesh.bottom_radius = 0.045
	branch_mesh.height = 2.4
	branch_mesh.radial_segments = 5
	var fg_leaf_mesh := BoxMesh.new()
	fg_leaf_mesh.size = Vector3(1.0, 0.03, 0.22)
	var branch_xforms: Array[Transform3D] = []
	var fg_leaf_xforms: Array[Transform3D] = []
	for spec: Array in [[-2.3, 54.8, -1.0], [2.3, 55.0, 1.0]]:
		var root_pos := Vector3(-30.0 + float(spec[0]), 0.0, float(spec[1]))
		# 一小段斜枝，从画面上缘伸入；不落地。
		var branch_basis := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(float(spec[2]) * 58.0)))
		branch_xforms.append(Transform3D(branch_basis,
			root_pos + Vector3(float(spec[2]) * 0.6, 6.0, 0.1)))
		for k in 8:
			var leaf_pos := root_pos + Vector3(
				float(spec[2]) * (0.20 + float(k) * 0.16),
				5.3 + float(k % 4) * 0.26,
				0.1 + float(k % 3) * 0.16)
			var leaf_basis := Basis.from_euler(Vector3(
				0.0, deg_to_rad(float(k) * 43.0), deg_to_rad(float(k % 2) * 14.0)))
			fg_leaf_xforms.append(Transform3D(leaf_basis, leaf_pos))
	_make_multimesh(branch_mesh, mat, branch_xforms, "ForegroundBranches")
	_make_multimesh(fg_leaf_mesh, mat, fg_leaf_xforms, "ForegroundLeaves")

## 远景/前景静态装饰统一走 MultiMesh：同材质同网格只占 1 个渲染对象。
func _make_multimesh(mesh: Mesh, material: Material, xforms: Array[Transform3D],
		node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func _make_mist_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	var img := Image.create(192, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var blobs: Array[Vector3] = []
	for i in 12:
		blobs.append(Vector3(rng.randf_range(12.0, 180.0), rng.randf_range(20.0, 76.0),
			rng.randf_range(12.0, 34.0)))
	for y in 96:
		for x in 192:
			var a := 0.0
			for b: Vector3 in blobs:
				var d := Vector2(x - b.x, (y - b.y) * 1.8).length() / b.z
				a += maxf(0.0, 1.0 - d * d) * 0.32
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 0.72)))
	return ImageTexture.create_from_image(img)

func _build_mist() -> void:
	var tex := _make_mist_texture()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.93, 0.96, 1.0, 0.30)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.render_priority = 2
	var cards := [
		Vector3(-33.0, 2.2, 19.0), Vector3(-51.0, 2.6, 13.0),
		Vector3(-14.0, 2.4, 10.0), Vector3(-42.0, 1.8, 26.0),
	]
	for i in 4:
		var quad := QuadMesh.new()
		quad.size = Vector2(30.0 + float(i % 2) * 8.0, 6.5)
		var mi := MeshInstance3D.new()
		mi.name = "Mist"
		mi.mesh = quad
		mi.material_override = mat.duplicate()
		mi.position = cards[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mist.append(mi)
		_mist_bases.append(cards[i])

func _build_post_fx() -> void:
	if not ResourceLoader.exists("res://shaders/ink_post.gdshader"):
		return
	_post_layer = CanvasLayer.new()
	_post_layer.name = "InkPost"
	_post_layer.layer = 5
	add_child(_post_layer)
	var rect := ColorRect.new()
	rect.name = "PostRect"
	rect.position = Vector2.ZERO
	rect.size = get_viewport().get_visible_rect().size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(rect):
			rect.size = get_viewport().get_visible_rect().size
	)
	var shader := load("res://shaders/ink_post.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	_post_layer.add_child(rect)

# ------------------------------------------------------------------ 玩家 / 相机

func _build_player() -> void:
	player = ExplorerPlayer.new()
	player.name = "ShenYan"
	var y := ground_height_at(spawn.x, spawn.z)
	player.position = Vector3(spawn.x, y + 0.1, spawn.z)
	add_child(player)
	player.set_facing(spawn_facing)
	player.set_active(false)

func _build_camera() -> void:
	camera = PlayerCamera.new()
	camera.target = player
	camera.name = "FollowCamera"
	add_child(camera)
	camera.snap()

# ------------------------------------------------------------------ NPC

func _spawn_story_npc(npc_id: String, display: String, point: String, region_id: String,
		pos: Vector2, sprite_id: String, tint: Color, height_m: float, personality: String = "plain") -> void:
	var npc := WorldNpc.new()
	npc.npc_id = npc_id
	npc.display_name = display
	npc.interact_point = point
	npc.sprite_id = sprite_id
	npc.sprite_tint = tint
	npc.height_m = height_m
	npc.personality = personality
	npc.identity = "story"
	npc.portrait = str(PORTRAITS.get(npc_id, PORTRAITS.get(sprite_id, "")))
	npc.identity_label = "故人"
	npc.region = region_id
	npc.home = pos
	npc.wander_radius = 0.0
	npc.player_ref = player
	npc.world_ref = self
	npc.position = Vector3(pos.x, ground_height_at(pos.x, pos.y), pos.y)
	add_child(npc)
	_add_npc_collider(npc)
	npcs[npc_id] = npc

func _spawn_generated_npc(data: Dictionary) -> void:
	var npc := WorldNpc.new()
	npc.npc_id = str(data.get("id", ""))
	npc.display_name = str(data.get("name", "路人"))
	npc.interact_point = ""
	npc.sprite_id = str(data.get("sprite", "shenyan"))
	npc.sprite_tint = Color.from_string(str(data.get("tint", "#ffffff")), Color.WHITE)
	npc.height_m = float(data.get("height_m", 1.68))
	npc.personality = str(data.get("personality", "plain"))
	npc.identity = str(data.get("identity", "villager"))
	npc.identity_label = str(data.get("identity_label", "村民"))
	npc.region = str(data.get("region", ""))
	npc.portrait = str(data.get("portrait", ""))
	npc.greetings = data.get("greetings", [])
	npc.idle_lines = data.get("idle_lines", [])
	var home_raw: Variant = data.get("home", [0.0, 0.0])
	var home := Vector2(float((home_raw as Array)[0]), float((home_raw as Array)[1]))
	npc.home = home
	npc.wander_radius = float(data.get("radius", 3.0))
	npc.player_ref = player
	npc.world_ref = self
	npc.position = Vector3(home.x, ground_height_at(home.x, home.y), home.y)
	add_child(npc)
	_add_npc_collider(npc)
	npcs[npc.npc_id] = npc

func _add_npc_collider(npc: WorldNpc) -> void:
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(0.0, 0.85, 0.0)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 1.6
	cs.shape = shape
	body.add_child(cs)
	npc.add_child(body)

func _build_npcs() -> void:
	# 剧情锚点：周伯 / 明澄 / 林照晚 / 厉横（沿用现有 dialogue-v1）。
	_spawn_story_npc("zhoubo", "周伯", "village.zhoubo", "village",
		Vector2(-36.0, 40.0), "zhoubo", Color("#d9c7a8"), 1.60, "plain")
	_spawn_story_npc("mingcheng", "明澄", "village.mingcheng", "village",
		Vector2(-24.0, 38.0), "mingcheng", Color("#d8dde4"), 1.74, "warm")
	_spawn_story_npc("linzhaowan", "林照晚", "bamboo.linzhaowan", "bamboo",
		Vector2(-40.0, -20.0), "linzhaowan", Color("#ead7da"), 1.63, "plain")
	_spawn_story_npc("liheng", "厉横", "bamboo.liheng", "bamboo",
		Vector2(-21.0, -36.0), "liheng", Color("#c7d0da"), 1.85, "gruff")
	# 模板池散人：18 个，确定性分布到 8 个区块。
	var generated := NpcDB.generate()
	for data: Dictionary in generated:
		_spawn_generated_npc(data)

func _add_dynamic_npc(data: Dictionary) -> void:
	if npcs.has(str(data.get("id", ""))):
		return
	_spawn_generated_npc(data)

# ------------------------------------------------------------------ 机缘

func _build_encounters() -> void:
	encounter_manager = EncounterManager.new()
	encounter_manager.name = "Encounters"
	add_child(encounter_manager)
	encounter_manager.setup(self, player, regions)

# ------------------------------------------------------------------ 分块加载

func update_chunks(force: bool = false) -> void:
	var coord := chunk_coord_for_pos(player.global_position)
	if not force and coord == _current_chunk:
		return
	_current_chunk = coord
	var cells := int(world_cfg.get("cells", 4))
	var wanted: Dictionary = {}
	for dz in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
		for dx in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			var c := Vector2i(coord.x + dx, coord.y + dz)
			if c.x < 0 or c.y < 0 or c.x >= cells or c.y >= cells:
				continue
			wanted[c] = true
	var changed := false
	for existing: Vector2i in _chunks.keys():
		if not wanted.has(existing):
			_unload_chunk(existing)
			changed = true
	for c: Vector2i in wanted.keys():
		if not _chunks.has(c):
			_load_chunk(c)
			changed = true
	if changed or _static_dirty:
		_static_dirty = false
		_rebuild_static_batches()
	_sync_npcs()
	_update_region_tint()

func _load_chunk(coord: Vector2i) -> void:
	var region: Dictionary = region_by_chunk.get(coord, {})
	if region.is_empty():
		return
	var node := terrain.build(region, coord)
	add_child(node)
	_chunks[coord] = node
	var region_id := str(region.get("id", ""))
	var count := int(_loaded_region_counts.get(region_id, 0)) + 1
	_loaded_region_counts[region_id] = count
	loaded_regions[region_id] = true
	if count == 1 and encounter_manager != null:
		encounter_manager.on_region_loaded(region)

func _unload_chunk(coord: Vector2i) -> void:
	var node: Node3D = _chunks.get(coord, null)
	if node == null:
		return
	_chunks.erase(coord)
	node.queue_free()
	var region: Dictionary = region_by_chunk.get(coord, {})
	var region_id := str(region.get("id", ""))
	var count := maxi(0, int(_loaded_region_counts.get(region_id, 0)) - 1)
	_loaded_region_counts[region_id] = count
	if count == 0:
		loaded_regions.erase(region_id)
		if encounter_manager != null:
			encounter_manager.on_region_unloaded(region_id)

## 把当前已加载区块里的静态几何做跨区块全局批处理：
## 1) StaticBatch_* MeshInstance 按“材质 + 投影”合成 1 个 MeshInstance；
## 2) 草丛/石子/花/竹叶等 MultiMesh 按“mesh + 材质 + 投影 + 可见距离”
##    把 9 个区块的实例合成 1 个 MultiMesh。
## StaticBatch 节点只隐藏；MultiMesh 节点先降级为 chunk meta 数据再释放，
## 避免树里的 MultiMesh 实例数翻倍。区块卸载时数据随区块一起 free。
func _rebuild_static_batches() -> void:
	if _static_root == null:
		return
	for child: Node in _static_root.get_children():
		_static_root.remove_child(child)
		child.free()
	_merge_static_meshes()
	_merge_multimeshes()

func _merge_static_meshes() -> void:
	var groups: Dictionary = {}
	# 所有静态投影合并成 1 个 SHADOWS_ONLY 网格：主几何不再各带 2 个
	# shadow split 对象，阴影贴图深度完全一致。
	var shadow_st := SurfaceTool.new()
	shadow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shadow_any := false
	for coord: Vector2i in _chunks.keys():
		var chunk := _chunks[coord] as Node3D
		if chunk == null or not is_instance_valid(chunk):
			continue
		for child: Node in chunk.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null or mi.material_override == null:
				continue
			if not mi.name.begins_with("StaticBatch_"):
				continue
			# 主几何按材质合并（投影状态不再进 key：主几何统一不投影）。
			var key := int(mi.material_override.get_instance_id())
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append([mi, chunk.transform])
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				for s in mi.mesh.get_surface_count():
					shadow_st.append_from(mi.mesh, s, chunk.transform)
				shadow_any = true
			mi.visible = false
	for key: int in groups.keys():
		var items: Array = groups[key]
		var mat: Material = (items[0][0] as MeshInstance3D).material_override
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for item: Array in items:
			var src := item[0] as MeshInstance3D
			var xf: Transform3D = item[1]
			for s in src.mesh.get_surface_count():
				st.append_from(src.mesh, s, xf)
		var merged := st.commit()
		if merged == null or merged.get_surface_count() == 0:
			continue
		var out := MeshInstance3D.new()
		out.name = "StaticGlobal_%d" % key
		out.mesh = merged
		out.material_override = mat
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.visibility_range_end = 90.0
		_static_root.add_child(out)
	if shadow_any:
		var shadow_mesh := shadow_st.commit()
		if shadow_mesh != null and shadow_mesh.get_surface_count() > 0:
			var shadow_mi := MeshInstance3D.new()
			shadow_mi.name = "StaticShadowCaster"
			shadow_mi.mesh = shadow_mesh
			var shadow_mat := StandardMaterial3D.new()
			shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			shadow_mat.cull_mode = BaseMaterial3D.CULL_BACK
			shadow_mi.material_override = shadow_mat
			shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_static_root.add_child(shadow_mi)

## 区块 MultiMesh 先“降级”为纯数据（chunk meta "mm_data"），再释放节点：
## 这样树里不会同时存在区块原实例和全局合并实例，MultiMesh 实例预算不翻倍。
func _merge_multimeshes() -> void:
	var groups: Dictionary = {}
	for coord: Vector2i in _chunks.keys():
		var chunk := _chunks[coord] as Node3D
		if chunk == null or not is_instance_valid(chunk):
			continue
		var entries: Array = []
		if chunk.has_meta("mm_data"):
			entries = chunk.get_meta("mm_data")
		else:
			for child: Node in chunk.get_children():
				var mmi := child as MultiMeshInstance3D
				if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count == 0:
					continue
				var src := mmi.multimesh
				if src.mesh == null or mmi.material_override == null:
					continue
				var entry := {
					"mesh": src.mesh,
					"mat": mmi.material_override,
					"shadow": mmi.cast_shadow,
					"range": mmi.visibility_range_end,
					"name": mmi.name,
					"format": src.transform_format,
					"use_colors": src.use_colors,
					"use_custom": src.use_custom_data,
					"xforms": [],
					"colors": [],
					"custom": [],
				}
				var xforms: Array = entry["xforms"]
				var colors: Array = entry["colors"]
				var custom: Array = entry["custom"]
				for i in src.instance_count:
					xforms.append(src.get_instance_transform(i))
					if src.use_colors:
						colors.append(src.get_instance_color(i))
					if src.use_custom_data:
						custom.append(src.get_instance_custom_data(i))
				entries.append(entry)
				mmi.free()
			chunk.set_meta("mm_data", entries)
		for entry_variant: Variant in entries:
			var entry: Dictionary = entry_variant
			var key := "%d:%d:%d:%.1f" % [
				(entry["mesh"] as Mesh).get_instance_id(),
				(entry["mat"] as Material).get_instance_id(),
				int(entry["shadow"]), float(entry["range"]),
			]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append([entry, chunk.transform])
	for key: String in groups.keys():
		var items: Array = groups[key]
		var first: Dictionary = items[0][0]
		var total := 0
		for item: Array in items:
			total += (item[0]["xforms"] as Array).size()
		if total == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = int(first["format"])
		mm.use_colors = bool(first["use_colors"])
		mm.use_custom_data = bool(first["use_custom"])
		mm.mesh = first["mesh"] as Mesh
		mm.instance_count = total
		var k := 0
		for item: Array in items:
			var entry: Dictionary = item[0]
			var xf: Transform3D = item[1]
			var xforms: Array = entry["xforms"]
			var colors: Array = entry["colors"]
			var custom: Array = entry["custom"]
			for i in xforms.size():
				mm.set_instance_transform(k, xf * (xforms[i] as Transform3D))
				if mm.use_colors:
					mm.set_instance_color(k, colors[i] as Color)
				if mm.use_custom_data:
					mm.set_instance_custom_data(k, custom[i] as Color)
				k += 1
		var out := MultiMeshInstance3D.new()
		out.name = "MMGlobal_%s" % str(first["name"])
		out.multimesh = mm
		out.material_override = first["mat"] as Material
		out.cast_shadow = int(first["shadow"])
		out.visibility_range_end = float(first["range"])
		_static_root.add_child(out)

func loaded_chunk_count() -> int:
	return _chunks.size()

func loaded_chunk_ids() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key: Vector2i in _chunks.keys():
		out.append(key)
	out.sort()
	return out

func is_region_loaded(region_id: String) -> bool:
	return loaded_regions.has(region_id)

# ------------------------------------------------------------------ 状态/色调

func _sync_npcs() -> void:
	for npc_id: String in npcs:
		var npc := npcs[npc_id] as WorldNpc
		if npc == null:
			continue
		var active := is_region_loaded(npc.region)
		if npc.is_story():
			active = active and GameState.is_point_visible(npc.interact_point)
		var should_dormant := not active
		if npc.dormant != should_dormant:
			npc.set_dormant(should_dormant)

func apply_state() -> void:
	_sync_npcs()

func _update_region_tint() -> void:
	var region := region_at_player()
	if region.is_empty() or player == null:
		return
	var tint_raw: Variant = (region.get("palette", {}) as Dictionary).get("tint", [1.0, 1.0, 1.0])
	var tint := Color(1.0, 1.0, 1.0)
	if typeof(tint_raw) == TYPE_ARRAY and (tint_raw as Array).size() >= 3:
		# 幅度限制在 ±8%，避免角色被环境色染脏。
		tint = Color(
			clampf(float((tint_raw as Array)[0]), 0.92, 1.08),
			clampf(float((tint_raw as Array)[1]), 0.92, 1.08),
			clampf(float((tint_raw as Array)[2]), 0.92, 1.08)
		)
	player.set_region_tint(tint)
	for npc_id: String in npcs:
		var npc := npcs[npc_id] as WorldNpc
		if npc == null or npc.dormant:
			continue
		# NPC 的基础色（含 ±8% 微调）在 CharacterModel 内部，这里只传区域色温。
		npc.set_region_tint(tint)

## 同屏 NPC 预算：按距离排序，只让最近的 10 个渲染/更新。
func _update_npc_budget() -> void:
	if player == null:
		return
	var candidates: Array = []
	var p := player.global_position
	for npc_id: String in npcs:
		var npc := npcs[npc_id] as WorldNpc
		if npc == null or npc.dormant:
			continue
		var d := npc.global_position.distance_to(p)
		candidates.append([d, npc])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in candidates.size():
		var item: Array = candidates[i]
		var npc := item[1] as WorldNpc
		npc.set_scene_budget(i < NPC_RENDER_BUDGET, float(item[0]))

func get_npc(npc_id: String) -> WorldNpc:
	return npcs.get(npc_id, null) as WorldNpc
