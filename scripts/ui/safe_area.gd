extends Control
## Shrinks the HUD to the system safe area (notches / gesture bar), plus 8dp.
## Desktop safe area is the whole window, so only the 8dp breathing room remains.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area.call_deferred()

func apply_safe_area() -> void:
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x <= 1.0 or win_size.y <= 1.0:
		win_size = get_viewport().get_visible_rect().size
	var vis := get_viewport().get_visible_rect().size
	var scale := Vector2(vis.x / maxf(win_size.x, 1.0), vis.y / maxf(win_size.y, 1.0))
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win_pos := Vector2(DisplayServer.window_get_position())
	safe.position -= win_pos
	# A missing / nonsensical safe area on desktop: use the full window.
	if safe.size.x <= 4.0 or safe.size.y <= 4.0:
		safe = Rect2(Vector2.ZERO, win_size)
	safe = safe.intersection(Rect2(Vector2.ZERO, win_size))
	var pad := maxf(12.0, UiScale.safe_padding())
	offset_left = safe.position.x * scale.x + pad
	offset_top = safe.position.y * scale.y + pad
	offset_right = -(win_size.x - safe.end.x) * scale.x - pad
	offset_bottom = -(win_size.y - safe.end.y) * scale.y - pad
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
