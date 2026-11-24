extends SceneTree
func _init() -> void:
	_go.call_deferred()
func _go() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var model := ToonModel.instantiate("res://assets/glb/shenyan.glb")
	host.add_child(model)
	var anim := CharacterAnim.new()
	anim.attach(host, model)
	var sword := model.find_child("ShenyanBackSword", true, false) as MeshInstance3D
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sword != null and sword.mesh != null:
		var aabb := sword.mesh.get_aabb()
		print("AABB min=", aabb.position, " size=", aabb.size, " end=", aabb.end)
		print("longest axis hint: size=", aabb.size)
	# wait a couple frames so SheathFollow runs
	await process_frame
	await process_frame
	if sword != null:
		print("sword local xf=", sword.transform)
		print("sword global pos=", sword.global_position)
		print("sword parent=", sword.get_parent().name if sword.get_parent() else "null")
		var p := sword.get_parent() as Node3D
		if p != null:
			print("parent global pos=", p.global_position)
			print("parent global basis=", p.global_transform.basis)
		# world positions of mesh aabb corners along each local axis
		if sword.mesh != null:
			var a: AABB = sword.mesh.get_aabb()
			for axis: Vector3 in [Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)]:
				var mid: Vector3 = a.position + a.size * 0.5
				var d: Vector3 = a.size * axis
				var a0: Vector3 = sword.global_transform * (mid - d * 0.5)
				var a1: Vector3 = sword.global_transform * (mid + d * 0.5)
				print("axis ", axis, " world from ", a0, " to ", a1, " len=", a0.distance_to(a1))
	quit()
func _process(_d: float) -> bool:
	return false
