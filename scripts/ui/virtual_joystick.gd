extends Control
## Dynamic multi-touch joystick. Uses _input + touch index so the right hand can
## press action buttons while the left thumb is dragging.

signal moved(vector: Vector2)

const DEADZONE := 0.20

var value := Vector2.ZERO

var _touch_index := -1
var _active := false
var _center := Vector2.ZERO
var _default_center := Vector2.ZERO
var _base_radius := 156.0
var _thumb_radius := 66.0
var _press_scale := 1.0
var _redraw_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("virtual_joystick")
	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_base_radius = UiScale.min_px(104.0, 312.0) * 0.5
	_thumb_radius = UiScale.min_px(44.0, 132.0) * 0.5
	var screen_point := Vector2(vp.x * 0.13, vp.y * 0.72)
	_default_center = screen_point - get_global_rect().position
	if not _active:
		_center = _default_center
	queue_redraw()

func _process(delta: float) -> void:
	var target := 0.92 if _active else 1.0
	_press_scale = lerpf(_press_scale, target, clampf(delta * 12.0, 0.0, 1.0))
	_redraw_time += delta
	if _active or _press_scale < 0.999:
		queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_active = true
			_center = touch.position - get_global_rect().position
			_update_from_point(touch.position)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_from_point(drag.position)
			get_viewport().set_input_as_handled()

func _update_from_point(screen_point: Vector2) -> void:
	var local := screen_point - get_global_rect().position
	var delta := local - _center
	var radius := _base_radius
	if radius <= 1.0:
		return
	var raw := delta / radius
	if raw.length() > 1.0:
		raw = raw.normalized()
	var strength := 0.0
	if raw.length() > DEADZONE:
		strength = (raw.length() - DEADZONE) / (1.0 - DEADZONE)
	value = raw.normalized() * strength if raw.length() > 0.001 else Vector2.ZERO
	_write_actions(value)
	moved.emit(value)
	queue_redraw()

func _write_actions(v: Vector2) -> void:
	_axis_action("move_right", v.x)
	_axis_action("move_left", -v.x)
	_axis_action("move_down", v.y)
	_axis_action("move_up", -v.y)

func _axis_action(action: String, amount: float) -> void:
	if amount > 0.001:
		Input.action_press(action, clampf(amount, 0.0, 1.0))
	else:
		Input.action_release(action)

func _release() -> void:
	_touch_index = -1
	_active = false
	value = Vector2.ZERO
	_center = _default_center
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	moved.emit(Vector2.ZERO)
	queue_redraw()

func cancel_touch() -> void:
	if _touch_index != -1:
		_release()

func _draw() -> void:
	var base_alpha := 0.34 if not _active else 0.72
	var center := _center
	var base_r := _base_radius * _press_scale
	var thumb_r := _thumb_radius * _press_scale
	var ink := Color(0.06, 0.065, 0.07, base_alpha)
	var ring := Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.72 if _active else 0.34)
	draw_circle(center, base_r, ink)
	draw_arc(center, base_r, 0.0, TAU, 64, ring, 3.0, true)
	draw_arc(center, base_r - 8.0, 0.0, TAU, 64, Color(ring.r, ring.g, ring.b, ring.a * 0.35), 1.5, true)
	# Four faint direction ticks.
	for i in 4:
		var ang := float(i) * TAU / 4.0
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(center + dir * (base_r - 34.0), center + dir * (base_r - 18.0), ring, 2.0, true)
	var thumb_pos := center + value * base_r
	var thumb_fill := Color(0.86, 0.78, 0.62, 0.88 if _active else 0.52)
	draw_circle(thumb_pos, thumb_r, Color(0.08, 0.075, 0.065, 0.9 if _active else 0.6))
	draw_arc(thumb_pos, thumb_r, 0.0, TAU, 48, thumb_fill, 3.0, true)
	draw_circle(thumb_pos, thumb_r * 0.35, Color(thumb_fill.r, thumb_fill.g, thumb_fill.b, 0.3))
