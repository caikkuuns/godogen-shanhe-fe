class_name ToonModel
extends RefCounted
## Shared look for textured TripoSR character GLBs (see tools/img3d/): soft toon
## that keeps the painted texture colours, no specular, thin inverted-hull
## outline and real sun shadows.
##
## 第三轮起探索态也直接用这些 GLB：同一套材质给玩家与 NPC，避免“纸片人”。
## PackedScene / 贴图全部静态缓存，22 个 NPC 不会各自重新 load 一遍。

## 描边宽度按屏幕像素反推：屏幕宽 ≈ (grow + dist_scale·depth) · f/depth。
## grow=0.0025、dist_scale=0.0009 时，8–15m 约 0.8–1.2px。
const OUTLINE_GROW := 0.0025
const OUTLINE_DIST_SCALE := 0.0009
const OUTLINE_DEPTH_BIAS := 0.05
const OUTLINE_MIN_DISTANCE := 2.0
const SELF_LIGHT := 0.16
## 用 preload 而不是全局 class_name 引用，避免新增脚本后 global class cache
## 尚未刷新时 headless 测试/导出报 "not declared"。
const MeshOptimizer := preload("res://scripts/world/character_mesh_optimizer.gd")

static var _scene_cache: Dictionary = {}
## 第四轮：优化后的 PackedScene（合并 surface / 扫描清理），每模型只做一次。
static var _optimized_cache: Dictionary = {}
## 手写干净低模（shenyan_script）：不做扫描清理，并且是封闭网格，省掉背面 pass。
const CLEAN_MODELS: Array[String] = ["shenyan_script"]

static func fill_color_for(path: String) -> Color:
	match path.get_file().get_basename():
		"shenyan", "shenyan_script":
			return Color(0.86, 0.86, 0.88)
		"linzhaowan":
			return Color(0.86, 0.70, 0.72)
		"gesancheng":
			return Color(0.55, 0.42, 0.32)
		"liheng":
			return Color(0.50, 0.46, 0.42)
		"yaoxing_dashou":
			return Color(0.52, 0.46, 0.40)
		_:
			return Color(0.78, 0.76, 0.74)

## 第八轮（自 grokbot fe 吸收）：内层补洞 pass 的顶点膨胀量。
## 沈砚的脸不膨胀——膨胀会把补洞色涂到横过额头/眼睛的白带上；
## 其余模型用 0.006 收小 TripoSR 网格洞（草地从缺三角处透出的问题）。
static func hole_grow_for(path: String) -> float:
	match path.get_file().get_basename():
		"shenyan", "shenyan_script":
			return 0.0
		_:
			return 0.006

## 第十轮：atlas 空隙填充（gutter）开关。
## shenyan hero 的贴图已做 UV 岛边缘扩张，岛间空隙被邻岛色填满，
## 再让 shader 按亮度瞎填只会把袍子褶皱刷成亮灰碎斑（P0-1），故关掉。
## 其余老模型贴图未处理，保持 1.0。
static func gutter_for(path: String) -> float:
	match path.get_file().get_basename():
		"shenyan", "shenyan_hero":
			return 0.0
		_:
			return 1.0

## 贴图亮度补偿：TripoSR 的 albedo 整体偏暗，黑衣服模型需要更高增益。
static func gain_for(path: String) -> float:
	match path.get_file().get_basename():
		"gesancheng":
			return 1.8
		"liheng":
			return 1.7
		"yaoxing_dashou":
			return 1.45
		"linzhaowan":
			return 1.18
		_:
			return 1.0

## 缓存 PackedScene：同屏 22 个 NPC 只 import/load 5 个 GLB 各一次。
## 优先使用 assets/glb/opt/ 下的优化版（第四轮 Kimi/Lead 优化产物）；
## 找不到就回退原模型。原文件保留，不覆盖。
static func opt_model_path(path: String) -> String:
	if path == "" or path.contains("/opt/"):
		return path
	var marker := "/assets/glb/"
	var i := path.find(marker)
	if i < 0 or not path.ends_with(".glb"):
		return path
	var candidate := path.substr(0, i) + "/assets/glb/opt/" + path.get_file()
	if ResourceLoader.exists(candidate):
		return candidate
	return path


static func scene_for(path: String) -> PackedScene:
	path = opt_model_path(path)
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path] as PackedScene

## 退出前清缓存：Godot dummy 渲染器在“缓存的 PackedScene 仍存活、带
## surface override 的实例被释放”时会在 teardown 打 `material is null`。
## 游戏里只在退出时调用；测试在 quit() 前调用，保证日志不新增 ERROR。
static func clear_scene_cache() -> void:
	_scene_cache.clear()
	_optimized_cache.clear()

## 优化后的场景：优先加载 tools/bake_character_meshes.gd 预生成的 .res
## （安卓首帧不用再花 ~1s/模型做 GDScript 清理）；没有预生成时退回运行时合并。
static func optimized_scene_for(path: String) -> PackedScene:
	if _optimized_cache.has(path):
		return _optimized_cache[path] as PackedScene
	var baked := "res://generated/characters/v1/%s.res" % path.get_file().get_basename()
	if ResourceLoader.exists(baked):
		var res := load(baked) as PackedScene
		if res != null:
			_optimized_cache[path] = res
			return res
	var raw := scene_for(path)
	if raw == null:
		return null
	var inst := raw.instantiate() as Node3D
	if inst == null:
		return null
	var base := path.get_file().get_basename()
	MeshOptimizer.optimize(inst, not (base in CLEAN_MODELS))
	var packed := PackedScene.new()
	if packed.pack(inst) != OK:
		inst.free()
		return null
	_optimized_cache[path] = packed
	inst.free()
	return _optimized_cache[path] as PackedScene

## Textured character: front is the usual toon (back-face culled). A second
## unshaded pass draws the inside so mesh holes stay covered in cloth colour
## instead of grey-lit back faces. The ink hull is chained after that.
static func make_textured(tex: Texture2D, tint: float, fill: Color,
		tint_color: Color = Color.WHITE, gain: float = 1.0,
		hole_grow: float = 0.006, gutter: float = 1.0) -> ShaderMaterial:
	var albedo := Color(tint, tint, tint, 1.0) * tint_color
	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_char_front.gdshader") as Shader
	toon.set_shader_parameter("albedo_tex", tex)
	toon.set_shader_parameter("albedo_tint", albedo)
	toon.set_shader_parameter("albedo_gain", gain)
	toon.set_shader_parameter("gutter_enabled", gutter)
	toon.set_shader_parameter("self_light", SELF_LIGHT * tint)
	toon.set_shader_parameter("fill_color", Vector3(fill.r, fill.g, fill.b))
	var back := ShaderMaterial.new()
	back.shader = load("res://shaders/toon_char.gdshader") as Shader
	back.set_shader_parameter("albedo_tex", tex)
	back.set_shader_parameter("albedo_tint", albedo)
	back.set_shader_parameter("albedo_gain", gain)
	back.set_shader_parameter("hole_grow", hole_grow)
	back.set_shader_parameter("fill_color", Vector3(fill.r, fill.g, fill.b))
	var hull := _make_hull()
	back.next_pass = hull
	toon.next_pass = back
	return toon

static func _make_hull() -> ShaderMaterial:
	var hull := ShaderMaterial.new()
	hull.shader = load("res://shaders/ink_hull.gdshader") as Shader
	hull.set_shader_parameter("grow", OUTLINE_GROW)
	hull.set_shader_parameter("depth_bias", OUTLINE_DEPTH_BIAS)
	hull.set_shader_parameter("dist_scale", OUTLINE_DIST_SCALE)
	hull.set_shader_parameter("min_distance", OUTLINE_MIN_DISTANCE)
	return hull

static var _white_tex_cache: Texture2D

## 1×1 白贴图：纯色角色/武器也走同一条 vcol shader，省一个材质分支。
static func _white_texture() -> Texture2D:
	if _white_tex_cache == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex_cache = ImageTexture.create_from_image(img)
	return _white_tex_cache

## 合并后单 surface 角色材质：贴图顶点与顶点色顶点混在同一个 surface。
## open_mesh=true 时加背面 pass 盖洞；干净封闭低模（shenyan_script）省掉。
static func make_vcol(tex: Texture2D, tint: float, fill: Color,
		tint_color: Color = Color.WHITE, gain: float = 1.0,
		open_mesh: bool = true) -> ShaderMaterial:
	var albedo := Color(tint, tint, tint, 1.0) * tint_color
	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_char_vcol.gdshader") as Shader
	toon.set_shader_parameter("albedo_tex", tex if tex != null else _white_texture())
	toon.set_shader_parameter("albedo_tint", albedo)
	toon.set_shader_parameter("albedo_gain", gain)
	toon.set_shader_parameter("self_light", SELF_LIGHT * tint)
	toon.set_shader_parameter("fill_color", Vector3(fill.r, fill.g, fill.b))
	var hull := _make_hull()
	if open_mesh:
		var back := ShaderMaterial.new()
		back.shader = load("res://shaders/toon_char_vcol_back.gdshader") as Shader
		back.set_shader_parameter("albedo_tex", tex if tex != null else _white_texture())
		back.set_shader_parameter("albedo_tint", albedo)
		back.set_shader_parameter("albedo_gain", gain)
		back.set_shader_parameter("fill_color", Vector3(fill.r, fill.g, fill.b))
		back.next_pass = hull
		toon.next_pass = back
	else:
		toon.next_pass = hull
	return toon

static func apply(node: Node, tint: float = 1.0, fill: Color = Color(0.86, 0.86, 0.88),
		tint_color: Color = Color.WHITE, gain: float = -1.0,
		hole_grow: float = 0.006, gutter: float = 1.0) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			# 只有身体投实时影；武器/配饰等小件交给身体阴影+blob 影，
			# 每个小件少一份 shadow pass（objects 预算）。
			var body_like: bool = mi.skin != null or bool(mi.get_meta("body", false))
			mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if body_like else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			if mi.get_meta("character_merged", false):
				var tex: Texture2D = null
				if mi.has_meta("albedo_tex"):
					tex = mi.get_meta("albedo_tex") as Texture2D
				var open_mesh := bool(mi.get_meta("open_mesh", true))
				mi.set_surface_override_material(0,
					make_vcol(tex, tint, fill, tint_color, gain, open_mesh))
			else:
				for i in mi.mesh.get_surface_count():
					var source := mi.get_active_material(i) as BaseMaterial3D
					var mat: Material
					if source != null and source.albedo_texture != null:
						mat = make_textured(source.albedo_texture, tint, fill, tint_color, gain, hole_grow, gutter)
					else:
						var toon := StandardMaterial3D.new()
						toon.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
						toon.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
						toon.roughness = 1.0
						toon.metallic = 0.0
						toon.metallic_specular = 0.0
						toon.cull_mode = BaseMaterial3D.CULL_BACK
						if source != null:
							toon.albedo_color = source.albedo_color * tint_color
						# BackPatch 补片用 robe fill 染色，避免灰紫色"补丁"感（第八轮吸收）。
						if mi.name == "BackPatch":
							toon.albedo_color = fill
						toon.next_pass = _make_hull()
						mat = toon
					mi.set_surface_override_material(i, mat)
	for child: Node in node.get_children():
		apply(child, tint, fill, tint_color, gain, hole_grow, gutter)

## Instantiate a GLB, normalize its height to [height_m] (0 = keep authored
## height), apply the toon look and start its looping idle clip.
## Returns null when the file is missing so callers can keep their fallback.
## tint < 1 tones down light-coloured textures (pale robes blow out under the
## toon sun); tint_color shifts hue/brightness per NPC instance.
static func instantiate(path: String, tint: float = 1.0, height_m: float = 0.0,
		tint_color: Color = Color.WHITE) -> Node3D:
	var packed := optimized_scene_for(path)
	if packed == null:
		packed = scene_for(path)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	return _finish_instance(model, path, tint, height_m, tint_color)

## 未合并/未清理的原始 GLB：只用于 closeup_before 对比图，回到第三轮外观。
static func instantiate_raw(path: String, tint: float = 1.0, height_m: float = 0.0,
		tint_color: Color = Color.WHITE) -> Node3D:
	var packed := scene_for(path)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	return _finish_instance(model, path, tint, height_m, tint_color)

static func _finish_instance(model: Node3D, path: String, tint: float,
		height_m: float, tint_color: Color) -> Node3D:
	_normalize(model, height_m)
	apply(model, tint, fill_color_for(path), tint_color, gain_for(path), hole_grow_for(path),
			gutter_for(path))
	IdleBreath.attach_to(model)
	_tweak_held_props(model)
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		for anim_name: String in ["idle", "walk"]:
			var clip := anim.get_animation(anim_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
		if anim.has_animation("idle"):
			anim.play("idle")
	return model

## 统一脚底到 y=0，并把“主身体”网格缩放到精确身高。
## 只量名字里带 Shenyan 的身体网格；刀/秤砣垂到脚面以下，不能拿来定身高。
static func _normalize(model: Node3D, height_m: float) -> void:
	var body: MeshInstance3D = null
	for candidate: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := candidate as MeshInstance3D
		# 主身体网格精确叫 "Shenyan"；"ShenyanBackSword" 是挂在胸骨上的背剑，不能拿来量身高。
		if mi.mesh != null and mi.name == "Shenyan":
			body = mi
			break
	if body == null or body.mesh == null:
		return
	var box := body.get_aabb()
	if box.size.y <= 0.01:
		return
	var scale := 1.0
	if height_m > 0.01:
		scale = height_m / box.size.y
		model.scale = Vector3.ONE * scale
	# 脚底锚点：把最低点平移到 y=0（含缩放后的偏移）。
	var min_y := box.position.y * scale
	if absf(min_y) > 0.0005:
		model.position.y -= min_y


## Keep 葛三秤's steelyard from swinging through the thigh: tip it slightly out.
static func _tweak_held_props(model: Node) -> void:
	var rod := model.find_child("GeSanChengRod", true, false) as Node3D
	if rod != null:
		rod.rotate_object_local(Vector3.FORWARD, 0.28)
		rod.rotate_object_local(Vector3.RIGHT, -0.08)
