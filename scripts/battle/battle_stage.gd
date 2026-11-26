class_name BattleStage
extends Node3D
## A compact 3D bout: Shenyan and the enemy, lit and toon-shaded like the
## overworld, driven by CharacterAnim. Lives inside the battle panel viewport.

const PLAYER_PATH := "res://assets/glb/shenyan.glb"
const ENEMY_MODELS := {
	"ch2_thug": "res://assets/glb/yaoxing_dashou.glb",
	"ch3_stair": "res://assets/glb/yaoxing_dashou.glb",
	"ch3_herb_thief": "res://assets/glb/yaoxing_dashou.glb",
	"liheng": "res://assets/glb/liheng.glb",
	"ch2_liheng_spar": "res://assets/glb/liheng.glb",
	"ch2_gesancheng": "res://assets/glb/gesancheng.glb",
	"ch3_chutie": "res://assets/glb/liheng.glb",
}

var player_anim: CharacterAnim
var enemy_anim: CharacterAnim
var _player_model: Node3D
var _enemy_model: Node3D

func _ready() -> void:
	_build_set()

func _build_set() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.70, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.82, 0.76)
	e.ambient_light_energy = 0.55
	e.fog_enabled = false
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20.0, -50.0, 0.0)
	add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9.0, 9.0)
	floor.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.52, 0.42)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	floor.material_override = mat
	add_child(floor)
	var cam := Camera3D.new()
	cam.name = "BattleCam"
	cam.fov = 42.0
	cam.position = Vector3(0.0, 1.42, 3.60)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.92, 0.0), Vector3.UP)
	cam.current = true

func set_side_camera() -> void:
	var cam := find_child("BattleCam", true, false) as Camera3D
	if cam == null:
		return
	# 3/4 后方位角（第八轮自 grokbot fe 吸收）：拉近让战斗者填满 HUD 上方，
	# 抬高 0.11 让倒地者的脚部也留在画面里（原机位倒地脚部只剩 ~65px）。
	cam.position = Vector3(2.18, 1.46, 2.68)
	cam.fov = 46.0
	cam.look_at(Vector3(0.0, 0.68, 0.15), Vector3.UP)

func setup(battle_id: String) -> void:
	_clear_fighters()
	_player_model = ToonModel.instantiate(PLAYER_PATH, 1.0)
	if _player_model != null:
		_player_model.name = "PlayerFighter"
		_player_model.position = Vector3(-0.88, 0.0, 0.15)
		_player_model.rotation_degrees = Vector3(0.0, 58.0, 0.0)
		add_child(_player_model)
		player_anim = CharacterAnim.new()
		player_anim.attach(self, _player_model)
		player_anim.set_combat(true)
	var enemy_path := str(ENEMY_MODELS.get(battle_id, ""))
	if enemy_path == "":
		enemy_path = "res://assets/glb/yaoxing_dashou.glb"
	var tint := 1.0
	if battle_id == "ch3_chutie":
		tint = 0.78
	_enemy_model = ToonModel.instantiate(enemy_path, tint)
	if _enemy_model != null:
		_enemy_model.name = "EnemyFighter"
		_enemy_model.position = Vector3(0.88, 0.0, 0.15)
		_enemy_model.rotation_degrees = Vector3(0.0, -58.0, 0.0)
		add_child(_enemy_model)
		enemy_anim = CharacterAnim.new()
		enemy_anim.attach(self, _enemy_model)
		enemy_anim.set_combat(true)

func _clear_fighters() -> void:
	# 第10轮修复：先停动画姿态，再释放节点。原来先 queue_free 再调
	# player_anim.set_combat(false)，而 queue_free 只是排队、节点当帧还活着，
	# 但 _player_model 已被置空——set_combat 若回头摸模型就会拿到失效引用。
	if player_anim != null:
		player_anim.set_combat(false)
	if enemy_anim != null:
		enemy_anim.set_combat(false)
	if _player_model != null:
		_player_model.queue_free()
		_player_model = null
	if _enemy_model != null:
		_enemy_model.queue_free()
		_enemy_model = null
	player_anim = null
	enemy_anim = null

func clear_fighters() -> void:
	_clear_fighters()

func has_fighters() -> bool:
	if _player_model != null and is_instance_valid(_player_model):
		return true
	if _enemy_model != null and is_instance_valid(_enemy_model):
		return true
	return get_node_or_null("PlayerFighter") != null or get_node_or_null("EnemyFighter") != null

## Play the 3D beats that match one take_turn() result.
func play_turn(res: Dictionary) -> void:
	var action := str(res.get("action", ""))
	if action == "attack" or action == "skill":
		if player_anim != null:
			await player_anim.play_and_wait("attack")
		if bool(res.get("enemy_dead", false)):
			if enemy_anim != null:
				await enemy_anim.play_and_wait("hit")
				await enemy_anim.play_and_wait("down")
			return
		if int(res.get("player_damage", 0)) > 0 and enemy_anim != null:
			await enemy_anim.play_and_wait("hit")
	elif action == "guard":
		# Hold idle; the incoming blow is shown below.
		await get_tree().create_timer(0.15).timeout
	elif action == "potion":
		await get_tree().create_timer(0.25).timeout
	var eaction := str(res.get("enemy_action", ""))
	if eaction == "charge":
		# Wind-up uses the attack clip briefly, then returns to idle.
		if enemy_anim != null:
			enemy_anim.play_oneshot("attack")
			await get_tree().create_timer(0.35).timeout
			enemy_anim.reset_idle()
		return
	if eaction == "attack" or eaction == "heavy":
		if enemy_anim != null:
			await enemy_anim.play_and_wait("attack")
		if bool(res.get("player_dead", false)):
			if player_anim != null:
				await player_anim.play_and_wait("hit")
				await player_anim.play_and_wait("down")
			return
		if int(res.get("enemy_damage", 0)) > 0 and player_anim != null:
			await player_anim.play_and_wait("hit")

## Capture-only choreography: 出剑、受击、倒地, ~6s.
func play_demo() -> void:
	if player_anim != null:
		player_anim.reset_idle()
	if enemy_anim != null:
		enemy_anim.reset_idle()
	await get_tree().create_timer(0.55).timeout
	if player_anim != null:
		await player_anim.play_and_wait("attack")
	if enemy_anim != null:
		await enemy_anim.play_and_wait("hit")
	await get_tree().create_timer(0.12).timeout
	if enemy_anim != null:
		await enemy_anim.play_and_wait("attack")
	if player_anim != null:
		await player_anim.play_and_wait("hit")
	await get_tree().create_timer(0.12).timeout
	if player_anim != null:
		await player_anim.play_and_wait("attack")
	if enemy_anim != null:
		await enemy_anim.play_and_wait("hit")
		await enemy_anim.play_and_wait("down")
	await get_tree().create_timer(0.8).timeout
