extends Control
## Hand-inked local map for the 菜单/地图 overlay.

var player_ref: Node3D
var world_ref: Node3D

const WORLD_RECT := Rect2(-24.0, -38.0, 48.0, 64.0)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _to_map(x: float, z: float) -> Vector2:
	var pad := 34.0
	var w := size.x - pad * 2.0
	var h := size.y - pad * 2.0
	var u := (x - WORLD_RECT.position.x) / WORLD_RECT.size.x
	var v := (z - WORLD_RECT.position.y) / WORLD_RECT.size.y
	return Vector2(pad + u * w, pad + v * h)

func _draw() -> void:
	var font := UiTheme.body_font()
	# River
	var river := PackedVector2Array()
	for i in 21:
		var z := -34.0 + float(i) * 3.2
		river.append(_to_map(15.0 + sin(float(i) * 0.5) * 0.8, z))
	draw_polyline(river, Color(0.32, 0.48, 0.55, 0.75), 14.0, true)
	draw_polyline(river, Color(0.62, 0.74, 0.78, 0.35), 4.0, true)
	# Path
	var path := PackedVector2Array()
	for i in 33:
		var z := 24.0 - float(i) * 2.0
		path.append(_to_map(sin((z + 6.0) * 0.11) * 1.3, z))
	draw_polyline(path, Color(0.78, 0.7, 0.55, 0.9), 9.0, true)
	# Houses
	for i in 4:
		var hx: float = [-8.8, -9.4, 8.6, 9.2][i]
		var hz: float = [14.5, 7.6, 13.0, 4.8][i]
		var p := _to_map(hx, hz)
		draw_rect(Rect2(p - Vector2(13.0, 17.0), Vector2(26.0, 34.0)), Color(0.55, 0.48, 0.4, 0.9), true)
		draw_rect(Rect2(p - Vector2(13.0, 17.0), Vector2(26.0, 34.0)), Color(0.85, 0.73, 0.5, 0.6), false, 2.0)
	# Gate
	var gate := _to_map(0.7, -0.6)
	draw_line(gate + Vector2(-30.0, 0.0), gate + Vector2(30.0, 0.0), Color(0.85, 0.73, 0.5, 0.95), 5.0)
	# Bamboo mass
	for i in 46:
		var a := float(i) * 2.4
		var bx := sin(a * 1.7) * 17.0
		var bz := -9.0 + cos(a * 1.3) * 21.0
		if absf(bx) < 5.0 or (bx > 11.0 and bx < 19.0):
			continue
		var p := _to_map(bx, bz)
		draw_circle(p, 3.0, Color(0.3, 0.43, 0.25, 0.65))
	# NPC markers
	var markers := [
		[Vector3(-4.8, 0.0, 10.6), "周伯"],
		[Vector3(4.6, 0.0, 16.8), "明澄"],
		[Vector3(-4.2, 0.0, -12.0), "照晚"],
		[Vector3(0.3, 0.0, -23.0), "厉横"],
	]
	for m: Array in markers:
		var p := _to_map(m[0].x, m[0].z)
		draw_circle(p, 5.0, Color(0.86, 0.78, 0.62, 0.85))
		draw_string(font, p + Vector2(9.0, 9.0), str(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color(0.9, 0.86, 0.78, 0.9))
	# Player
	if player_ref != null:
		var pp := _to_map(player_ref.global_position.x, player_ref.global_position.z)
		draw_circle(pp, 8.0, Color(0.9, 0.3, 0.28, 0.95))
		draw_arc(pp, 11.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.6, 0.9), 2.0)
	# Labels
	draw_string(font, _to_map(-2.0, 20.0) + Vector2(-20.0, -18.0), "村口", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color(0.95, 0.9, 0.8, 0.9))
	draw_string(font, gate + Vector2(-16.0, 26.0), "山门", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color(0.95, 0.9, 0.8, 0.9))
	draw_string(font, _to_map(-3.0, -30.0), "竹林", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color(0.95, 0.9, 0.8, 0.9))
