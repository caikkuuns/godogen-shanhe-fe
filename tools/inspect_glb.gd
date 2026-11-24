extends SceneTree
## 资源诊断：打印 GLB 导入后的节点/网格/surface/材质/骨骼结构。
## 用法：godot --headless --path . -s tools/inspect_glb.gd -- <glb 路径...>
## 只读，不改资源。

func _init() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = ["res://assets/glb/shenyan_script.glb", "res://assets/glb/shenyan.glb"]
	for path: String in paths:
		print("=== ", path)
		var packed := load(path) as PackedScene
		if packed == null:
			print("  LOAD FAILED")
			continue
		var inst := packed.instantiate()
		_dump(inst, 0)
		inst.free()
	quit()

func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var line := pad + node.name + " [" + node.get_class() + "]"
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		line += " skin=%s skeleton=%s" % [str(mi.skin != null), str(mi.skeleton)]
		print(line)
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				var detail := ""
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					detail = "tex=" + (str(bm.albedo_texture.get_size()) if bm.albedo_texture != null else "-")
				print(pad, "  surf[", i, "] verts=", mi.mesh.surface_get_array_len(i),
					" mat=", mat.resource_name if mat != null else "-", " ", detail)
			print(pad, "  aabb=", mi.mesh.get_aabb(),
				" blend_shapes=", mi.mesh.get_blend_shape_count(),
				" xform=", mi.transform)
	else:
		print(line)
		if node is Skeleton3D:
			var sk := node as Skeleton3D
			print(pad, "  bones=", sk.get_bone_count())
	for child: Node in node.get_children():
		_dump(child, depth + 1)
