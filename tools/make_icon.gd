extends SceneTree
## 生成 Android/桌面应用图标：从现有沈砚立绘裁头肩，不引入新美术、不联网。
## 运行：godot --headless --path . -s tools/make_icon.gd

func _init() -> void:
	var src := load("res://docs/ref-characters-v3/shenyan_portrait_v2.png") as Texture2D
	if src == null:
		push_error("portrait missing")
		quit(1)
		return
	var img := src.get_image()
	img.convert(Image.FORMAT_RGBA8)
	# 661×1060 立绘：取上半身方形，居中裁切。
	var side := mini(img.get_height(), img.get_width())
	var region := Rect2i((img.get_width() - side) / 2, 60, side, side)
	region = region.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var crop := img.get_region(region)
	crop.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/branding"))
	var err := crop.save_png(ProjectSettings.globalize_path("res://assets/branding/icon_512.png"))
	print("ICON saved err=", err, " size=", crop.get_size())
	for size in [192, 432]:
		var scaled := crop.duplicate() as Image
		scaled.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var path := "res://assets/branding/icon_%d.png" % size
		var e := scaled.save_png(ProjectSettings.globalize_path(path))
		print("ICON ", path, " err=", e)
	quit(0 if err == OK else 1)
