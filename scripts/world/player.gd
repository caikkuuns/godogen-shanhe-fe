class_name ExplorerPlayer
extends CharacterBody3D
## 沈砚（探索态）：3D 卡通模型 + 移动/朝向/碰撞。
## 模型/材质/影子/动画由 CharacterModel 统一负责；本脚本只做移动与朝向。

const DIRS: Array[String] = ["down", "downright", "right", "upright", "up", "upleft", "left", "downleft"]
const BODY_HEIGHT := 1.70
const SPEED := 2.0
const GRAVITY := 24.0
const INPUT_DEADZONE := 0.20
const ACCELERATION := 12.0
const DECELERATION := 18.0

var active := true
var facing := 0
var moving := false
var character: CharacterModel

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_build_character()
	_build_collision()
	set_facing(0)

func _build_character() -> void:
	character = CharacterModel.new()
	character.name = "Character"
	character.setup("shenyan", BODY_HEIGHT, Color.WHITE, 0)
	character.set_speed(SPEED)
	add_child(character)

func _build_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.62
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.81, 0.0)
	add_child(col)

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		moving = false
		_apply_visual()
		return
	var ix := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var iy := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var wish := normalize_move_input(Vector2(ix, iy))
	var planar := Vector2(velocity.x, velocity.z)
	var target := wish * SPEED
	# 起步和停步都经过速度斜坡；不会因摇杆回中而从全速瞬间归零。
	var rate := ACCELERATION if wish.length_squared() > 0.0 else DECELERATION
	planar = planar.move_toward(target, rate * delta)
	velocity.x = planar.x
	velocity.z = planar.y
	if planar.length() > 0.04:
		character.set_direction(Vector3(planar.x, 0.0, planar.y))
		facing = character.facing
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# 动画必须跟随碰撞后的真实位移；贴墙时不再原地滑步。
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	moving = actual_speed > CharacterModel.MIN_WALK_SPEED
	character.set_speed(actual_speed)
	_apply_visual()

## 摇杆/键盘共用：死区内归零，死区外线性恢复力度，斜向永远不超过 1。
static func normalize_move_input(raw: Vector2) -> Vector2:
	var length := raw.length()
	if length <= INPUT_DEADZONE:
		return Vector2.ZERO
	var strength := clampf((length - INPUT_DEADZONE) / (1.0 - INPUT_DEADZONE), 0.0, 1.0)
	return raw / length * strength

func _apply_visual() -> void:
	if character == null:
		return
	if not active:
		character.set_speed(0.0)
	character.set_moving(moving and active)

func set_facing(index: int) -> void:
	facing = wrapi(index, 0, 8)
	if character != null:
		character.set_facing(facing)

func teleport(pos: Vector3, face: int) -> void:
	global_position = pos
	set_facing(face)
	velocity = Vector3.ZERO
	reset_physics_interpolation()

func set_active(value: bool) -> void:
	active = value
	if not value:
		velocity = Vector3.ZERO
		moving = false
	_apply_visual()

## 区块环境色，幅度 ≤8%；只改材质 tint。
func set_region_tint(color: Color, instant: bool = false) -> void:
	if character != null:
		character.set_tint(color, instant)

func facing_name() -> String:
	return DIRS[facing]

func screen_height_px(cam: Camera3D) -> float:
	return character.screen_height_px(cam) if character != null else 0.0
