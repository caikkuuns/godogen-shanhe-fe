extends SceneTree
## 导出/开发期预烘焙：把 GLB 实例合并成单 surface 的 PackedScene，
## 存到 res://generated/characters/v1/<名字>.res。
##
## 用法（改完 CharacterMeshOptimizer 后重跑）：
##   godot --headless --path . -s tools/bake_character_meshes.gd
##
## 游戏里 ToonModel.optimized_scene_for() 优先加载这些 .res；文件缺失时
## 退回运行时合并（功能一致，只是首帧多花 ~1s/模型）。

const MeshOptimizer := preload("res://scripts/world/character_mesh_optimizer.gd")
const OUT_DIR := "res://generated/characters/v1"
const MODELS: Array[String] = [
	"res://assets/glb/shenyan_script.glb",
	"res://assets/glb/shenyan.glb",
	"res://assets/glb/linzhaowan.glb",
	"res://assets/glb/gesancheng.glb",
	"res://assets/glb/liheng.glb",
	"res://assets/glb/yaoxing_dashou.glb",
]
const CLEAN: Array[String] = ["shenyan_script"]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := 0
	for path: String in MODELS:
		var base := path.get_file().get_basename()
		var t0 := Time.get_ticks_msec()
		var raw := load(path) as PackedScene
		if raw == null:
			print("BAKE FAIL load ", path)
			failed += 1
			continue
		var inst := raw.instantiate() as Node3D
		var stats := MeshOptimizer.optimize(inst, not (base in CLEAN))
		var packed := PackedScene.new()
		var err := packed.pack(inst)
		var out := "%s/%s.res" % [OUT_DIR, base]
		if err == OK:
			err = ResourceSaver.save(packed, out)
		if err == OK:
			print("BAKE OK ", out, " ms=", Time.get_ticks_msec() - t0, " stats=", stats)
		else:
			print("BAKE FAIL ", path, " err=", err)
			failed += 1
		inst.free()
	print("BAKE DONE failed=", failed)
	quit(0 if failed == 0 else 1)
