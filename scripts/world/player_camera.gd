class_name PlayerCamera
extends Camera3D
## HD-2.5D 斜俯视跟随相机：pitch -28°、FOV 36、look_height 1.05、
## 阻尼 0.12s。距离按硬指标（人物屏高 20–24%）取 11.5m：FOV 36 下
## 9m 实测约 27%，会让人物过高、挡住宅门；7.5–8m 只会更大。
## 支持 --pitch= / --dist= / --fov= 仅用于 A/B 截图。

const DEFAULT_PITCH := -28.0
const DEFAULT_DISTANCE := 11.5
const DEFAULT_FOV := 36.0
const DAMPING_SECONDS := 0.12

var target: Node3D
var pitch_deg := DEFAULT_PITCH
var distance := DEFAULT_DISTANCE
var fov_deg := DEFAULT_FOV
var offset := Vector3.ZERO
var look_height := 1.05
var smoothing := 1.0 / DAMPING_SECONDS

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	near = 0.15
	far = 160.0
	keep_aspect = Camera3D.KEEP_HEIGHT
	current = true
	_apply_cli_overrides()
	_apply_values()

func _apply_cli_overrides() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pitch="):
			pitch_deg = float(arg.trim_prefix("--pitch="))
		elif arg.begins_with("--dist="):
			distance = float(arg.trim_prefix("--dist="))
		elif arg.begins_with("--fov="):
			fov_deg = float(arg.trim_prefix("--fov="))
		elif arg.begins_with("--look="):
			look_height = float(arg.trim_prefix("--look="))

func configure(pitch_value: float, distance_value: float, fov_value: float = -1.0,
		look_value: float = -1.0) -> void:
	pitch_deg = pitch_value
	distance = distance_value
	if fov_value > 0.0:
		fov_deg = fov_value
	if look_value > 0.0:
		look_height = look_value
	_apply_values()
	snap()

func _apply_values() -> void:
	fov = fov_deg
	offset = _offset_for(pitch_deg, distance)

func _offset_for(pitch_value: float, distance_value: float) -> Vector3:
	var p := deg_to_rad(absf(pitch_value))
	return Vector3(0.0, sin(p) * distance_value, cos(p) * distance_value)

func _process(delta: float) -> void:
	if target == null:
		return
	var desired := target.global_position + offset
	var t := 1.0 - exp(-delta / DAMPING_SECONDS)
	global_position = global_position.lerp(desired, t)
	look_at(target.global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)

func snap() -> void:
	if target == null:
		return
	global_position = target.global_position + offset
	look_at(target.global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)

## 用于验收打印：1.70m 人物在屏幕上的像素高度。
func player_screen_height_px() -> float:
	if target == null:
		return 0.0
	var a := unproject_position(target.global_position)
	var b := unproject_position(target.global_position + Vector3(0.0, 1.70, 0.0))
	return absf(a.y - b.y)
