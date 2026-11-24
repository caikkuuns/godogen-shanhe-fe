extends Control
## Thin ink bar used for 气血 / 内力 and overhead enemy health.

var max_value := 100.0
var value := 100.0
var fill_color := Color("#B24A4A")
var back_color := Color(0.05, 0.05, 0.055, 0.78)
var border_color := Color(0.69, 0.55, 0.34, 0.55)
var display_value := true
var value_text := ""

func set_stat(v: float, m: float) -> void:
	value = clampf(v, 0.0, m)
	max_value = maxf(m, 0.001)
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, back_color, true)
	var ratio := clampf(value / max_value, 0.0, 1.0)
	if ratio > 0.0:
		var fill_rect := Rect2(Vector2.ZERO, Vector2(maxf(1.0, r.size.x * ratio), r.size.y))
		draw_rect(fill_rect, fill_color, true)
		# A pale gleam along the top keeps the bar from reading as flat plastic.
		draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(fill_rect.size.x, maxf(1.0, r.size.y * 0.28))),
			Color(1.0, 1.0, 1.0, 0.16), true)
	draw_rect(r, border_color, false, 1.5)
	if display_value and value_text != "":
		var font := UiTheme.body_font()
		var baseline := size.y * 0.5 + 9.0
		draw_string(font, Vector2(0.0, baseline), value_text, HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 8.0, 24, Color(0.95, 0.93, 0.88, 0.9))
