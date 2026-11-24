class_name CharacterModel
extends Node3D
## 探索态 3D 卡通人物统一组件（沈砚 + 全部 NPC）。
##
## 第三轮替换 Sprite3D 立绘：
## - 只用 assets/glb 里现有模型；PackedScene 静态缓存，不重复 load
## - 身高精确按米缩放（主身体网格为准），脚底固定在 y=0
## - idle / walk 循环；移动时按速度方向平滑旋转模型 Y 轴（不做 8 向贴图）
## - toon 材质 + 反向外壳描边（8–15m 约 1px）+ 主光实时投影
## - 额外叠一张软 blob 影补接触阴影，避免脚底悬空
## - LOD：15m 外冻结骨骼动画，20m 外隐藏并停更；同屏由 OpenWorld 限制 10 个

const MODELS := {
	# 第十一轮：近景主角改用精修的 shenyan_hero（TripoSR 清理版，7.5k tri / 2.18MB）。
	# 战斗场景仍用 shenyan.glb（带 attack/down/hit 动画），见 battle_stage.gd。
	"shenyan": "res://assets/glb/opt/shenyan_hero.glb",
	"shenyan_hero": "res://assets/glb/opt/shenyan_hero.glb",
	"shenyan_script": "res://assets/glb/shenyan_script.glb",
	"shenyan_legacy": "res://assets/glb/shenyan.glb",
	"linzhaowan": "res://assets/glb/linzhaowan.glb",
	"gesancheng": "res://assets/glb/gesancheng.glb",
	"yaoxing_dashou": "res://assets/glb/yaoxing_dashou.glb",
	"liheng": "res://assets/glb/liheng.glb",
}
## NPC 轮换池：固定顺序，保证每个 NPC 每次运行拿到同一个模型。
## 第四轮加入干净低模 shenyan_script，让约 1/5 散人不再背 TripoSR 扫描碎片。
const NPC_POOL: Array[String] = ["linzhaowan", "gesancheng", "yaoxing_dashou", "liheng", "shenyan_script"]
## preload 避免新脚本尚未进入 global class cache 时 headless 运行报错。
const Accessories := preload("res://scripts/world/npc_accessories.gd")

## 第四轮：>20m 不渲染（visible=false），>15m 冻结骨骼动画。
const HIDE_DISTANCE := 20.0
const FREEZE_DISTANCE := 15.0
const WALK_BASE_SPEED := 2.0
const MOVE_XFADE := 0.10
const MIN_WALK_SPEED := 0.08
const BLOB_SIZE := Vector2(0.95, 0.48)

var model_id := "shenyan"
var model_glb := MODELS["shenyan"]
var height_m := 1.70
var moving := false
var _speed_smoothed := 0.0
var _bob_t := 0.0
var speed_mps := 2.0
var facing := 0
## 区域色温，幅度 ≤8%；与 NPC 自身色相微调相乘。
var tint := Color.WHITE
## 第四轮 NPC 差异：体型宽窄 ±8%、年龄感、程序化配饰。
var width_scale := 1.0
var age := 0.0
var accessory_kind := ""
var dress_up := false
## 截图对比用：跳过合并/清理，直接 instantiate_raw（第三轮外观）。
var use_raw_model := false

var model: Node3D
var shadow: MeshInstance3D

var _pivot: Node3D
var _anim: AnimationPlayer
var _breath: IdleBreath
var _base_tint := Color.WHITE
var _target_yaw := 0.0
var _built := false
var _lod_visible := true
var _budget_visible := true
var _frozen := false
var _current_clip := ""
var _keep_accessories := true
var _seed_value := 0
## 远距 NPC 只保留 blob 影：>12m 关掉身体实时投影，减少 shadow pass 对象。
var _body_meshes: Array[MeshInstance3D] = []
var _shadow_cast := true
## >15m 关掉描边/背面 pass（sub-pixel），再省 1–2 个渲染对象/角色。
var _detail_materials: Array[ShaderMaterial] = []
var _detail_next_passes: Array[Material] = []
var _detail_passes := true

func setup(model_key: String, character_height: float, tint_color: Color = Color.WHITE,
		seed_value: int = 0, keep_accessories: bool = true, procedural: bool = false,
		raw: bool = false) -> void:
	model_id = model_key if MODELS.has(model_key) else _pool_pick(seed_value)
	model_glb = MODELS[model_id]
	height_m = character_height
	tint = tint_color
	_base_tint = tint_color
	_keep_accessories = keep_accessories
	dress_up = procedural
	use_raw_model = raw
	_seed_value = seed_value
	if _built:
		_apply_tint()

static func _pool_pick(seed_value: int) -> String:
	return NPC_POOL[absi(seed_value) % NPC_POOL.size()]

## 给散人 NPC 的确定性色相/明度微调：色相 ±10%、明度 ±10%、饱和 ±10%。
## 第四轮把幅度从 ±2% 色相提高到 ±10%，让同模型的黑白衣也能一眼分开。
static func variant_tint(base: Color, seed_value: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 2654435761 + 17
	var h := rng.randf_range(-0.10, 0.10)
	var v := 1.0 + rng.randf_range(-0.10, 0.10)
	var s := 1.0 + rng.randf_range(-0.10, 0.10)
	var shifted := Color.from_hsv(fposmod(base.h + h, 1.0),
		clampf(base.s * s, 0.0, 1.0), clampf(base.v * v, 0.0, 1.0), 1.0)
	return Color(shifted.r, shifted.g, shifted.b, base.a)

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	_pivot = Node3D.new()
	_pivot.name = "Facing"
	add_child(_pivot)

	if use_raw_model:
		model = ToonModel.instantiate_raw(model_glb, 1.0, height_m, _base_tint)
	else:
		model = ToonModel.instantiate(model_glb, 1.0, height_m, _base_tint)
	if model == null:
		model = _fallback_model()
	model.name = "Model"
	# NPC 体型宽窄 ±8%（非均匀缩放，脚底锚点不受影响）；玩家保持原始比例。
	var vrng := RandomNumberGenerator.new()
	vrng.seed = _seed_value * 2246822519 + 7
	width_scale = vrng.randf_range(0.92, 1.08) if dress_up else 1.0
	model.scale.x *= width_scale
	model.scale.z *= width_scale
	if dress_up:
		var acc := Accessories.attach(model, _seed_value, height_m)
		accessory_kind = str(acc.get("kind", ""))
		age = float(acc.get("age", 0.0))
	_pivot.add_child(model)
	# 收集主身体网格，供 LOD 开关实时投影。
	_body_meshes.clear()
	_detail_materials.clear()
	_detail_next_passes.clear()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.skin != null or mi.get_meta("body", false):
			_body_meshes.append(mi)
		var mat := mi.get_surface_override_material(0) as ShaderMaterial
		if mat != null and mat.next_pass != null:
			_detail_materials.append(mat)
			_detail_next_passes.append(mat.next_pass)
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		for clip_name: String in ["idle", "walk"]:
			var clip := _anim.get_animation(clip_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
		_anim.play("idle")
		_current_clip = "idle"
	_breath = model.find_child("IdleBreath", true, false) as IdleBreath
	_pivot.rotation.y = _target_yaw
	_build_shadow()
	if not _keep_accessories:
		_strip_accessories()

## 散人 NPC 只保留主身体/衣袖，隐藏刀剑/秤杆等小件：
## 每个小件有 2–4 个 surface × 3 个 pass，同屏多人时 draw call 很可观。
func _strip_accessories() -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for token: String in ["Sword", "Dao", "Club", "Rod", "Weight"]:
			if token in mi.name:
				mi.visible = false
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break

func _fallback_model() -> Node3D:
	# 资源缺失兜底：低模胶囊也比空节点强，测试/导出不会因此崩。
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = height_m
	mi.mesh = cap
	mi.position.y = height_m * 0.5
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.albedo_color = _base_tint
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root

func _build_shadow() -> void:
	shadow = MeshInstance3D.new()
	shadow.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = BLOB_SIZE
	shadow.mesh = quad
	shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shadow.position = Vector3(0.0, 0.018, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = BlobShadow.texture()
	mat.albedo_color = Color(0.07, 0.086, 0.118, 0.52)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow.material_override = mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

func _process(delta: float) -> void:
	if _pivot == null:
		return
	# 平滑转向：不是 8 方向贴图，任意速度方向都直接转 Y 轴。
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _target_yaw, clampf(delta * 12.0, 0.0, 1.0))

	# 速度缓动：起步/停步不再是瞬间切换（原来的"僵硬感"主要来源）。
	var target_speed := speed_mps if moving else 0.0
	var accel := 9.0 if target_speed > _speed_smoothed else 12.0
	_speed_smoothed = move_toward(_speed_smoothed, target_speed, accel * delta)
	var t := clampf(_speed_smoothed / maxf(WALK_BASE_SPEED, 0.01), 0.0, 1.0)

	if _anim != null:
		var wants_walk := _speed_smoothed > MIN_WALK_SPEED
		var wanted := "walk" if wants_walk else "idle"
		if _current_clip != wanted and _anim.has_animation(wanted):
			# 停步用更长的淡出，起步用短淡入，减少"啪"一下切动画。
			var xfade := MOVE_XFADE if wants_walk else MOVE_XFADE * 2.2
			_anim.play(wanted, xfade)
			_current_clip = wanted
		# 播放速度跟随平滑速度，避免脚底打滑或原地空转。
		_anim.speed_scale = clampf(_speed_smoothed / WALK_BASE_SPEED, 0.20, 1.8) if wants_walk else 1.0

	# 程序化身体动态：走路上下起伏 + 轻微前倾 + 左右摆，补足 GLB 动画的僵硬感。
	_bob_t += delta * (2.0 + 8.0 * t)
	var bob := sin(_bob_t * 3.0) * 0.018 * t
	if model != null:
		model.position.y = bob - 0.006 * t
		model.rotation.x = lerp(model.rotation.x, -0.05 * t, clampf(delta * 6.0, 0.0, 1.0))
		model.rotation.z = lerp(model.rotation.z, sin(_bob_t * 1.5) * 0.02 * t, clampf(delta * 5.0, 0.0, 1.0))

	if shadow != null:
		shadow.scale = Vector3(1.0 + 0.08 * t, 1.0, 1.0 + 0.05 * t)

## 移动方向 → 目标朝向。模型作者朝向 +Z，所以 yaw = atan2(x, z)。
func set_direction(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	_target_yaw = atan2(dir.x, dir.z)
	facing = wrapi(int(round(_target_yaw / (PI * 0.25))), 0, 8)

## 兼容旧接口：0=down(+Z), 2=right(+X), 4=up(−Z)。
func set_facing(index: int) -> void:
	facing = wrapi(index, 0, 8)
	_target_yaw = float(facing) * PI * 0.25

func face_towards(pos: Vector3) -> void:
	set_direction(pos - global_position)

func set_moving(value: bool) -> void:
	# 只在 _process 统一切换，避免接口与动画循环重复触发不同淡出时长。
	moving = value

func set_speed(value: float) -> void:
	speed_mps = maxf(0.0, value)

func set_tint(color: Color, _instant: bool = false) -> void:
	if tint.is_equal_approx(color):
		return
	tint = color
	_apply_tint()

func _apply_tint() -> void:
	if model == null:
		return
	var applied := Color(_base_tint.r * tint.r, _base_tint.g * tint.g,
		_base_tint.b * tint.b, 1.0)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.get_meta("procedural_accessory", false):
			var acc_mat := mi.material_override as StandardMaterial3D
			if acc_mat != null:
				acc_mat.albedo_color = applied
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i) as ShaderMaterial
			if mat != null and mat.shader != null:
				mat.set_shader_parameter("albedo_tint", applied)
				# 背面/描边 pass 也吃同一份 tint，避免色温只改前脸。
				var nxt := mat.next_pass as ShaderMaterial
				if nxt != null and nxt.shader != null and "ink_hull" not in nxt.shader.resource_path:
					nxt.set_shader_parameter("albedo_tint", applied)

## 每帧由 NPC/玩家调用：距离 + 同屏预算决定显示/动画更新。
func apply_lod(distance: float, budget_visible: bool = true) -> void:
	_budget_visible = budget_visible
	var show := budget_visible and distance <= HIDE_DISTANCE
	var animate := show and distance <= FREEZE_DISTANCE
	if show != _lod_visible:
		_lod_visible = show
		visible = show
		set_process(show)
	if _anim != null:
		_anim.active = animate
	if _breath != null:
		_breath.process_mode = (
			Node.PROCESS_MODE_INHERIT if animate else Node.PROCESS_MODE_DISABLED
		)
	# >12m 只保留 blob 影，省掉实时 shadow pass；近景仍有投影。
	var cast := show and distance <= 12.0
	if cast != _shadow_cast:
		_shadow_cast = cast
		for mi: MeshInstance3D in _body_meshes:
			if is_instance_valid(mi):
				mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
					if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# >15m 描边/背面 pass 已经 sub-pixel，直接关掉。
	var detail := show and distance <= FREEZE_DISTANCE
	if detail != _detail_passes:
		_detail_passes = detail
		for i in _detail_materials.size():
			_detail_materials[i].next_pass = _detail_next_passes[i] if detail else null
	_frozen = not animate

func is_frozen() -> bool:
	return _frozen

## 屏幕像素高度（按精确身高算），验收 20%~24% 用。
func screen_height_px(cam: Camera3D) -> float:
	if cam == null:
		return 0.0
	var a := cam.unproject_position(global_position)
	var b := cam.unproject_position(global_position + Vector3(0.0, height_m, 0.0))
	return absf(a.y - b.y)
