extends SceneTree
## 沈砚精修前证据：固定光照、同一机位渲染原模型与 opt，脚与裤脚近景。
## 用法：godot --path . --resolution 800x1000 -s tools/capture_shenyan_round10.gd
var host: Node3D

func _init() -> void:
	_go.call_deferred()

func _go() -> void:
	host = Node3D.new()
	root.add_child(host)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("d9dfd3")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.86, 0.84)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	host.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -25, 0)
	sun.light_energy = 1.1
	host.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("a7afa1")
	floor.material_override = fm
	host.add_child(floor)
	var cam := Camera3D.new()
	cam.fov = 37
	host.add_child(cam)
	cam.current = true
	await _shot("res://assets/glb/opt/shenyan.glb", "round10_before", Vector3(0.55, 1.22, 3.0), Vector3(0, 0.86, 0))
	await _shot("res://assets/glb/opt/shenyan.glb", "round10_feet_before", Vector3(0.30, 0.38, 1.42), Vector3(0, 0.24, 0))
	await _shot("res://assets/glb/shenyan.glb", "round10_original_feet", Vector3(0.30, 0.38, 1.42), Vector3(0, 0.24, 0))
	quit()

func _shot(path: String, name: String, cp: Vector3, look: Vector3) -> void:
	var m := ToonModel.instantiate(path, 1.0, 1.70)
	m.name = "Hero"
	host.add_child(m)
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")
	var cam := host.get_children().filter(func(n): return n is Camera3D)[0] as Camera3D
	cam.position = cp
	cam.look_at(look)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/" + name + ".png")
	print("SHOT ", name)
	m.queue_free()
	await process_frame
