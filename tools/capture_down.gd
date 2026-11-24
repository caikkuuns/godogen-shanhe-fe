extends SceneTree
## Side-view stills of kneel / fall / land for a visual check.
const OUT := "res://captures/tmp_down_%s_p%.0f.png"

func _init() -> void:
	_go.call_deferred()

func _go() -> void:
	var world := Node3D.new()
	world.name = "DownPreview"
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 35, 0)
	light.light_energy = 1.15
	world.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(3.6, 0.70, 0.0)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)
	cam.current = true
	var floor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6, 0.02, 6)
	floor.mesh = box
	floor.position = Vector3(0, -0.01, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.62, 0.48)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor.material_override = mat
	world.add_child(floor)

	for pair: Array in [
		["shenyan", "res://assets/glb/shenyan.glb"],
		["dashou", "res://assets/glb/yaoxing_dashou.glb"],
	]:
		var id := str(pair[0])
		var model := ToonModel.instantiate(str(pair[1]))
		model.name = id
		model.position = Vector3(0, 0, 0.15)
		model.rotation_degrees = Vector3(0, 0, 0)  # face +Z, camera on +X = profile
		world.add_child(model)
		var anim := CharacterAnim.new()
		anim.attach(world, model)
		var breath := model.find_child("IdleBreath", true, false) as IdleBreath
		if breath == null:
			print("NO_BREATH ", id)
			continue
		breath.suppress_breath = true
		var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
		for phase in [1.0, 2.0, 3.0]:
			breath.down_phase = phase
			for _i in 6:
				await process_frame
			if skel != null:
				skel.force_update_all_bone_transforms()
				var bits: PackedStringArray = PackedStringArray()
				for bn: String in ["hips", "head", "foot.L", "foot.R", "hand.L", "hand.R"]:
					var bi := skel.find_bone(bn)
					if bi < 0:
						continue
					var p := (skel.global_transform * skel.get_bone_global_pose(bi)).origin
					bits.append("%s=(%.2f,%.2f,%.2f)" % [bn, p.x, p.y, p.z])
				print("POSE ", id, " p=", phase, " ticks=", breath.ticks, " cached=", breath._down_cached, " ", " ".join(bits))
			var path := "res://captures/tmp_down_%s_p%.0f.png" % [id, phase]
			world.get_viewport().get_texture()  # touch
			var img := cam.get_viewport().get_texture().get_image()
			# fallback: viewport
			var vp := root.get_viewport()
			if vp != null:
				img = vp.get_texture().get_image()
			if img != null:
				img.save_png(path)
				print("SAVED ", path, " ", img.get_width(), "x", img.get_height())
			else:
				print("NO_IMG ", path)
		model.queue_free()
		await process_frame
	quit()

func _process(_d: float) -> bool:
	return false
