class_name BuildingFactory
extends RefCounted
## 程序化 3D 建筑：村舍 / 门楼 / 山门 / 废祠。
## 全部按米建模（门高 2.2m），瓦/木/石/土墙用运行时 canvas 噪点纹理，
## 屋顶有瓦楞、檐口、起翘角；Mobile 渲染器下只保持必要的 MeshInstance。

var mats: Dictionary = {}
var rng := RandomNumberGenerator.new()

## 第八轮：画稿建筑素材根（来自 incoming/grokbot/wuxia-team/art 吸收拷贝）。
const PAINTED_ROOT := "res://assets/imported/scenery/"

func _init(seed_value: int = 20261121) -> void:
	rng.seed = seed_value
	_make_materials()

# ------------------------------------------------------------------ 材质

func _make_materials() -> void:
	mats["roof"] = _tex_mat(_make_tex("roof", Color("#3b3532")), 0.9)
	mats["roof_edge"] = _plain(Color("#292522"), 0.9)
	mats["wood"] = _tex_mat(_make_tex("wood", Color("#5a4032")), 0.8)
	mats["wood_dark"] = _tex_mat(_make_tex("wood", Color("#382a23")), 0.84)
	mats["wood_red"] = _tex_mat(_make_tex("wood", Color("#6b3530")), 0.76)
	mats["plaster"] = _tex_mat(_make_tex("plaster", Color("#c3b7a3")), 0.95)
	mats["plaster_old"] = _tex_mat(_make_tex("plaster", Color("#a99c88")), 0.96)
	mats["stone"] = _tex_mat(_make_tex("stone", Color("#8d8375")), 0.93)
	mats["stone_dark"] = _tex_mat(_make_tex("stone", Color("#5d5850")), 0.95)
	mats["earth"] = _tex_mat(_make_tex("plaster", Color("#8f7656")), 0.98)
	mats["gold"] = _plain(Color("#b08d57"), 0.45, 0.35)
	mats["window"] = _plain(Color("#c99d5c"), 0.55)
	mats["window"].emission_enabled = true
	mats["window"].emission = Color("#ffc47a")
	mats["window"].emission_energy_multiplier = 0.9
	mats["lantern"] = _plain(Color("#d06a45"), 0.55)
	mats["lantern"].emission_enabled = true
	mats["lantern"].emission = Color("#ff9a58")
	mats["lantern"].emission_energy_multiplier = 2.0
	mats["cloth_red"] = _plain(Color("#9d443a"), 0.9)
	mats["cloth_red"].cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["cloth_indigo"] = _plain(Color("#4e6283"), 0.9)
	mats["cloth_indigo"].cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["moss"] = _plain(Color("#5e6b3e"), 0.96)
	mats["black"] = _plain(Color("#1f1c19"), 0.95)

func _plain(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

## 画稿面片公共材质：无光照（与道具卡一致）、alpha scissor；
## 竖版单面（相机只从南面看），地版双面免得从斜上方看穿。
func _painted_mat(tex_path: String, vertical: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if vertical:
		mat.cull_mode = BaseMaterial3D.CULL_BACK
	else:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

## 只投影不显示的实体：画稿建筑没有真实体积，让地面仍接到建筑影子。
func _shadow_proxy(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(mi)

func _tex_mat(tex: Texture2D, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.texture_repeat = true
	return m

func _hash(x: int, y: int, salt: int) -> float:
	# 小整数散列，避免 64 位乘法溢出（纹理只需要稳定的伪随机感）。
	var n := x * 374761 + y * 668265 + salt * 69069 + 1013904223
	n = (n ^ (n >> 13)) * 1274126
	n = n ^ (n >> 16)
	return float((n & 0xffff) ^ ((n >> 16) & 0xffff)) / 65535.0

func _make_tex(kind: String, base: Color) -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var c := base
			var n := _hash(x, y, 77) * 2.0 - 1.0
			match kind:
				"roof":
					var row := y % 18
					if row < 2:
						c = base.darkened(0.38)
					elif row < 5:
						c = base.lightened(0.07)
					var rib := (x + int(row / 3) * 4) % 13
					if rib < 1:
						c = c.darkened(0.16)
					elif rib < 3:
						c = c.lightened(0.05)
					c = c.lightened(n * 0.06)
				"wood":
					var grain := sin(float(x) * 0.55 + sin(float(y) * 0.09) * 2.6) * 0.055
					c = base.lightened(grain + n * 0.045)
					if x % 41 == 0:
						c = c.darkened(0.16)
					if (x + y * 7) % 61 == 0:
						c = c.darkened(0.22)
				"stone":
					var bh := 22
					var row := int(y / bh)
					var bx := (x + (row % 2) * 26) % 48
					if y % bh < 2 or bx < 2:
						c = base.darkened(0.28)
					else:
						c = base.lightened((_hash(row, bx / 8, 31) - 0.5) * 0.13 + n * 0.035)
					if _hash(x / 4, y / 4, 5) > 0.94:
						c = c.lerp(Color("#5e6b3e"), 0.35)
				"plaster":
					c = base.lightened(n * 0.035)
					if y > size * 0.72:
						var streak := _hash(x / 3, y / 12, 19)
						if streak > 0.72:
							c = c.darkened(0.10 + (streak - 0.72) * 0.5)
					if _hash(x / 6, y / 6, 8) > 0.965:
						c = c.darkened(0.16)
				_:
					c = base.lightened(n * 0.03)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ primitives

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat_name: String,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mats[mat_name]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3,
		mat_name: String, segments: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mats[mat_name]
	mi.position = pos
	parent.add_child(mi)
	return mi

func _sphere(parent: Node3D, size: Vector3, pos: Vector3, mat_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	mi.mesh = mesh
	mi.material_override = mats[mat_name]
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi

func _prism(parent: Node3D, size: Vector3, pos: Vector3, mat_name: String,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = 0.5
	mi.mesh = mesh
	mi.material_override = mats[mat_name]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _quad(parent: Node3D, size: Vector2, pos: Vector3, mat_name: String,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mats[mat_name]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _collider(parent: Node3D, size: Vector3, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body

func _label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel: float,
		color: Color = Color("#d8b77a")) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = UiTheme.body_font()
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.78)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.position = pos
	parent.add_child(label)
	return label

# ------------------------------------------------------------------ 屋顶

func _roof(parent: Node3D, width: float, depth: float, base_y: float, rise: float,
		overhang: float = 0.8, mat_name: String = "roof") -> void:
	var half_run := depth * 0.5 + overhang
	var angle := rad_to_deg(atan2(rise, half_run))
	var slope_len := sqrt(half_run * half_run + rise * rise)
	# 前后两坡
	_box(parent, Vector3(width + overhang * 2.0, 0.13, slope_len),
		Vector3(0.0, base_y + rise * 0.5, half_run * 0.5), mat_name, Vector3(angle, 0.0, 0.0))
	_box(parent, Vector3(width + overhang * 2.0, 0.13, slope_len),
		Vector3(0.0, base_y + rise * 0.5, -half_run * 0.5), mat_name, Vector3(-angle, 0.0, 0.0))
	# 瓦楞（实际几何条，近看不是纯色块）
	for f: float in [0.18, 0.38, 0.58, 0.78]:
		var yy := base_y + rise * (1.0 - f) + 0.10
		var zz := half_run * f
		_box(parent, Vector3(width + overhang * 1.85, 0.045, 0.075), Vector3(0.0, yy, zz), "roof_edge")
		_box(parent, Vector3(width + overhang * 1.85, 0.045, 0.075), Vector3(0.0, yy, -zz), "roof_edge")
	# 正脊 + 檐口
	_box(parent, Vector3(width + overhang * 2.15, 0.2, 0.3),
		Vector3(0.0, base_y + rise + 0.14, 0.0), "roof_edge")
	_box(parent, Vector3(width + overhang * 2.1, 0.14, 0.18),
		Vector3(0.0, base_y + 0.05, half_run), "roof_edge")
	_box(parent, Vector3(width + overhang * 2.1, 0.14, 0.18),
		Vector3(0.0, base_y + 0.05, -half_run), "roof_edge")
	# 起翘檐角：四角各一根上翘短梁 + 金端头。
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner := Vector3(sx * (width * 0.5 + overhang * 0.92), base_y + 0.16,
				sz * (half_run - 0.12))
			_box(parent, Vector3(0.15, 0.12, 1.05), corner, "roof_edge",
				Vector3(sz * 24.0, 0.0, -sx * 8.0))
			_sphere(parent, Vector3(0.16, 0.16, 0.16),
				corner + Vector3(0.0, 0.20, sz * 0.48), "gold")
	# 脊端装饰
	for sx: float in [-1.0, 1.0]:
		_box(parent, Vector3(0.22, 0.42, 0.22),
			Vector3(sx * (width * 0.5 + overhang * 0.92), base_y + rise + 0.30, 0.0),
			"roof_edge", Vector3(0.0, 0.0, sx * 18.0))

# ------------------------------------------------------------------ 村舍

func village_house(parent: Node3D, pos: Vector3, yaw_deg: float, w: float, d: float,
		h: float, with_light: bool = false) -> Node3D:
	# 第八轮：外观换成 wuxia-team 画稿（house.png 910×849，白墙瓦顶木门格窗）。
	# 相机固定从南面朝北看，画稿正面朝 +Z（原程序化门也在 +Z 侧，朝向一致）；
	# 碰撞 AABB、门灯与灯光保留。画宽 ≈ 墙宽 + 两侧挑檐。
	var root := Node3D.new()
	root.name = "House"
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	var sc := (w + 1.8) / (910.0 * 0.00386)
	var height := 849.0 * 0.00386 * sc
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(910.0, 849.0) * 0.00386 * sc
	mi.mesh = quad
	mi.material_override = _painted_mat(PAINTED_ROOT + "house.png", true)
	mi.position = Vector3(0.0, height * 0.5, d * 0.5 + 0.18)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# 房体影子实体：画稿不投影，但地面仍接到房子影子。
	_shadow_proxy(root, Vector3(w, h + 1.4, d), Vector3(0.0, (h + 1.4) * 0.5, 0.0))
	# 门灯：画稿自带门灯画，但暖光点仍由这盏承担。
	var door_z := d * 0.5 + 0.06
	_sphere(root, Vector3(0.3, 0.42, 0.3), Vector3(1.0, 0.45 + 2.02, door_z + 0.42), "lantern")
	_box(root, Vector3(0.06, 0.28, 0.06), Vector3(1.0, 0.45 + 2.32, door_z + 0.42), "wood_dark")
	if with_light:
		var light := OmniLight3D.new()
		light.position = Vector3(1.0, 0.45 + 2.0, door_z + 0.42)
		light.light_color = Color("#ffc27a")
		light.light_energy = 0.9
		light.omni_range = 5.0
		light.shadow_enabled = false
		root.add_child(light)
	# 碰撞：整屋（门前留出台阶）
	_collider(root, Vector3(w + 0.5, h + 2.0, d + 0.4), Vector3(0.0, (h + 2.0) * 0.5, 0.0))
	return root

# ------------------------------------------------------------------ 门楼 / 山门

func gate_tower(parent: Node3D, pos: Vector3, yaw_deg: float, plaque_text: String = "山 河") -> Node3D:
	var root := Node3D.new()
	root.name = "GateTower"
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	# 石台与台阶
	_box(root, Vector3(9.6, 0.36, 4.2), Vector3(0.0, 0.18, 0.0), "stone")
	for i in 3:
		_box(root, Vector3(4.2, 0.18, 1.0), Vector3(0.0, 0.09 + float(i) * 0.18, 2.4 + float(i) * 0.55), "stone_dark")
	# 四柱（中间 3.2m 通行）
	for x: float in [-3.3, 3.3]:
		for z: float in [-1.35, 1.35]:
			_cyl(root, 0.24, 0.30, 3.8, Vector3(x, 0.36 + 1.9, z), "wood_red", 12)
			_box(root, Vector3(0.66, 0.18, 0.66), Vector3(x, 0.42, z), "stone_dark")
			_collider(root, Vector3(0.72, 3.9, 0.72), Vector3(x, 2.25, z))
	# 枋 / 斗拱 / 匾
	for z: float in [-1.35, 1.35]:
		_box(root, Vector3(7.4, 0.28, 0.3), Vector3(0.0, 3.6, z), "wood_red")
		_box(root, Vector3(7.0, 0.22, 0.26), Vector3(0.0, 4.08, z), "wood_dark")
		for x: float in [-3.0, -1.0, 1.0, 3.0]:
			_box(root, Vector3(0.7, 0.22, 0.26), Vector3(x, 3.84, z + 0.18), "wood_dark")
			_box(root, Vector3(0.24, 0.42, 0.2), Vector3(x, 3.68, z + 0.18), "wood_dark")
	_box(root, Vector3(4.4, 0.26, 0.3), Vector3(0.0, 3.3, 1.35), "wood_dark")
	_box(root, Vector3(1.9, 0.72, 0.12), Vector3(0.0, 4.05, 1.52), "wood_dark")
	_label(root, plaque_text, Vector3(0.0, 4.02, 1.60), 58, 0.0060)
	# 屋顶（重檐）
	_roof(root, 8.4, 3.5, 4.32, 1.25, 0.95, "roof")
	_roof(root, 6.2, 2.8, 5.35, 0.95, 0.75, "roof")
	# 灯笼 / 幡
	for x: float in [-2.1, 2.1]:
		_sphere(root, Vector3(0.32, 0.46, 0.32), Vector3(x, 2.95, 1.5), "lantern")
		_box(root, Vector3(0.07, 0.34, 0.07), Vector3(x, 3.35, 1.5), "wood_dark")
	for sx: float in [-1.0, 1.0]:
		_cyl(root, 0.08, 0.1, 4.5, Vector3(sx * 4.6, 2.25, 1.6), "wood_dark", 8)
		_quad(root, Vector2(0.8, 1.7), Vector3(sx * 4.25, 3.3, 1.62), "cloth_indigo",
			Vector3(0.0, sx * 8.0, 0.0))
	return root

func mountain_gate(parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	# 第八轮：改用 wuxia-team 分层画稿（assets/imported/scenery/gate_L*.png，
	# 数值依据 gate_layers.json：canvas 911×886、脚线锚点 y=744、门洞屏幕中心 x≈492）。
	# L0 石板铺地平铺，L1 后柱 / L2 前柱+屋顶面向 +Z；相机固定朝北看，
	# 角色在门洞以北时被 L2 前柱自然遮挡（深度缓冲），拱内可通行。
	var root := Node3D.new()
	root.name = "MountainGate"
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	# 缩放 2.2：门楼高 7.5m，匾额落在 4.6m——固定相机（FOV36/俯角28°/距离11.5m）
	# 在门线处的可视带上限约 4.6m，2.6 时匾额(5.4m)会被画面上缘切掉。
	# 门洞宽 1.78m，柱基恰好压在广场土路的路缘上。
	var s := 0.00386 * 2.2
	var arch_cx := 492.0
	var cx_off := (911.0 * 0.5 - arch_cx) * s
	var quad_size := Vector2(911.0, 886.0) * s
	# L0 石板铺地：画布"上"指向北，锚点行（py=744）落在门线。
	var ground := MeshInstance3D.new()
	var l0 := QuadMesh.new()
	l0.size = quad_size
	ground.mesh = l0
	ground.material_override = _painted_mat(PAINTED_ROOT + "gate_L0_ground.png", false)
	ground.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ground.position = Vector3(cx_off, 0.016, (886.0 * 0.5 - 744.0) * s)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	# L1 / L2 竖版面片：画布底边贴地。
	for pair: Array in [["gate_L1_back.png", -0.55], ["gate_L2_front.png", 0.0]]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = quad_size
		mi.mesh = q
		mi.material_override = _painted_mat(PAINTED_ROOT + str(pair[0]), true)
		mi.position = Vector3(cx_off, 886.0 * 0.5 * s, float(pair[1]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# 画稿匾额是空的，「山河」Label 贴上去（画布约 510,345px）。
	_label(root, "山 河", Vector3((510.0 - arch_cx) * s, (886.0 - 345.0) * s, 0.06), 58, 0.0088)
	# 柱基阻挡（blocked_pillar_bases 折算）：左 132..387px、右 597..802px，拱内可走。
	for block: Array in [[132.0, 387.0], [597.0, 802.0]]:
		var b0: float = block[0]
		var b1: float = block[1]
		var bx: float = ((b0 + b1) * 0.5 - arch_cx) * s
		var bw: float = (b1 - b0) * s
		_collider(root, Vector3(bw, 3.4, 1.1), Vector3(bx, 1.7, 0.0))
	# 门楼影子实体：朝东南投到进门路上。
	_shadow_proxy(root, Vector3(8.6, 6.0, 1.2), Vector3(0.0, 3.0, -0.2))
	# 两侧矮石墙把画稿边接到地形上。
	for side: float in [-1.0, 1.0]:
		var wall_x := side * (911.0 * 0.5 * s + 1.2)
		_box(root, Vector3(2.6, 1.15, 0.9), Vector3(wall_x, 0.575, -0.6), "stone")
		_collider(root, Vector3(2.6, 1.35, 0.9), Vector3(wall_x, 0.675, -0.6))
	# 仪仗幡杆（画稿边外）。
	for side: float in [-1.0, 1.0]:
		_cyl(root, 0.16, 0.16, 4.4, Vector3(side * 5.6, 2.2, 0.0), "wood_dark", 8)
		_quad(root, Vector2(0.85, 1.7), Vector3(side * 5.6 + side * 0.48, 3.25, 0.0), "cloth_indigo",
			Vector3(0.0, side * 8.0, 0.0))
	return root


# ------------------------------------------------------------------ 废祠 / 道具

func ruined_shrine(parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RuinedShrine"
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	_box(root, Vector3(11.0, 0.3, 11.0), Vector3(0.0, 0.15, 0.0), "stone_dark")
	# 残墙：留缺口，像塌了一半
	_box(root, Vector3(8.2, 2.6, 0.35), Vector3(0.0, 1.3, -5.0), "plaster_old")
	_collider(root, Vector3(8.2, 2.6, 0.35), Vector3(0.0, 1.3, -5.0))
	_box(root, Vector3(0.35, 2.2, 4.6), Vector3(-5.2, 1.1, -3.0), "plaster_old")
	_collider(root, Vector3(0.35, 2.2, 4.6), Vector3(-5.2, 1.1, -3.0))
	_box(root, Vector3(0.35, 1.3, 3.0), Vector3(5.2, 0.65, -1.6), "plaster_old")
	_box(root, Vector3(3.0, 1.9, 0.35), Vector3(3.4, 0.95, 5.0), "plaster_old")
	_box(root, Vector3(2.2, 0.7, 0.35), Vector3(-3.2, 0.35, 5.0), "plaster_old")
	# 半塌屋顶
	_roof(root, 7.2, 3.4, 2.65, 1.15, 0.65, "roof")
	# 柱与梁
	for x: float in [-3.6, 3.6]:
		_cyl(root, 0.2, 0.24, 3.0, Vector3(x, 1.5, 2.4), "wood_dark", 10)
		_collider(root, Vector3(0.5, 3.0, 0.5), Vector3(x, 1.5, 2.4))
	_box(root, Vector3(7.8, 0.22, 0.22), Vector3(0.0, 3.0, 2.4), "wood_dark")
	# 无头神像 + 供桌
	_box(root, Vector3(2.4, 0.55, 1.5), Vector3(0.0, 0.5, -2.8), "stone_dark")
	_box(root, Vector3(1.1, 1.5, 0.8), Vector3(0.0, 1.45, -3.2), "stone")
	_sphere(root, Vector3(0.95, 0.8, 0.7), Vector3(0.0, 2.15, -3.2), "stone")
	_box(root, Vector3(1.5, 0.16, 0.9), Vector3(0.0, 0.78, -2.0), "wood_dark")
	_collider(root, Vector3(2.4, 2.4, 1.6), Vector3(0.0, 1.2, -3.0))
	# 供桌暗格（机缘点视觉参照）
	_box(root, Vector3(0.4, 0.08, 0.3), Vector3(0.7, 0.7, -2.0), "black")
	# 残幡
	for sx: float in [-1.0, 1.0]:
		_quad(root, Vector2(0.7, 1.8), Vector3(sx * 2.9, 2.0, 2.4), "cloth_red",
			Vector3(0.0, sx * 10.0, 0.0))
	# 倒塌的梁
	_box(root, Vector3(5.0, 0.2, 0.2), Vector3(-1.2, 0.8, 1.0), "wood_dark", Vector3(0.0, 28.0, 14.0))
	return root

func stone_lantern(parent: Node3D, pos: Vector3, with_light: bool = false) -> Node3D:
	# 第八轮：改用 r4b 画稿石灯幢（round4b 评审版：中式亭顶替换日式旧顶）。
	# 画布 506×625、脚线锚点 (125,406)、pixel_size 0.00386 与道具卡一致；
	# 配套投影平铺。灯光位置对到画中的灯室（py≈190 → 1.68m）。
	var root := Node3D.new()
	root.name = "StoneLanternPainted"
	root.position = pos
	parent.add_child(root)
	var canvas := Vector2(506.0, 625.0)
	var anchor := Vector2(125.0, 406.0)
	var ps := 0.00386
	var body := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = canvas * ps
	body.mesh = quad
	body.material_override = _painted_mat(PAINTED_ROOT.replace("scenery", "props") + "prop_stonelantern_r4b.png", true)
	body.position = Vector3(0.0, canvas.y * ps * 0.5, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	# 画稿投影平铺（与道具卡同一对齐式）。
	var shadow := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = canvas * ps
	shadow.mesh = sq
	shadow.material_override = _painted_mat(PAINTED_ROOT.replace("scenery", "props") + "prop_stonelantern_shadow_r4b.png", false)
	shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shadow.position = Vector3((anchor.x - canvas.x * 0.5) * -ps, 0.022, (anchor.y - canvas.y * 0.5) * -ps)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)
	_collider(root, Vector3(0.5, 1.6, 0.5), Vector3(0.0, 0.8, 0.0))
	if with_light:
		var light := OmniLight3D.new()
		light.position = Vector3(0.0, 1.68, 0.0)
		light.light_color = Color("#ffc27a")
		light.light_energy = 0.9
		light.omni_range = 5.0
		light.shadow_enabled = false
		root.add_child(light)
	return root

func well(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	_cyl(root, 1.1, 1.15, 0.75, Vector3(0.0, 0.375, 0.0), "stone", 14)
	_cyl(root, 0.82, 0.82, 0.05, Vector3(0.0, 0.72, 0.0), "black", 14)
	for x: float in [-0.85, 0.85]:
		_box(root, Vector3(0.14, 1.8, 0.14), Vector3(x, 1.2, 0.0), "wood_dark")
	_box(root, Vector3(2.0, 0.14, 0.14), Vector3(0.0, 2.0, 0.0), "wood_dark")
	_box(root, Vector3(2.4, 0.16, 1.8), Vector3(0.0, 2.15, 0.0), "roof", Vector3(0.0, 0.0, 0.0))
	_collider(root, Vector3(2.25, 1.0, 2.25), Vector3(0.0, 0.5, 0.0))
	return root

func fence_line(parent: Node3D, from: Vector3, to: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Fence"
	parent.add_child(root)
	var delta := to - from
	var length := Vector2(delta.x, delta.z).length()
	if length < 0.5:
		return root
	var count := maxi(2, int(length / 1.8) + 1)
	var dir := Vector2(delta.x, delta.z).normalized()
	var yaw := rad_to_deg(atan2(dir.x, dir.y))
	for i in count:
		var t := float(i) / float(count - 1)
		var p := from.lerp(to, t)
		_box(root, Vector3(0.14, 1.15, 0.14), Vector3(p.x, 0.575, p.z), "wood")
		var mid := Vector3((from.x + to.x) * 0.5, 0.82, (from.z + to.z) * 0.5)
		if i == 0:
			_box(root, Vector3(0.07, 0.1, length), mid, "wood", Vector3(0.0, yaw, 0.0))
			_box(root, Vector3(0.07, 0.09, length), mid - Vector3(0.0, 0.34, 0.0), "wood", Vector3(0.0, yaw, 0.0))
	_collider(root, Vector3(absf(delta.x) + 0.5, 1.2, absf(delta.z) + 0.5),
		Vector3((from.x + to.x) * 0.5, 0.6, (from.z + to.z) * 0.5))
	return root

func stone_steps(parent: Node3D, from: Vector3, to: Vector3, width: float = 4.0) -> Node3D:
	var root := Node3D.new()
	root.name = "StoneSteps"
	parent.add_child(root)
	var delta := to - from
	var flat_len := Vector2(delta.x, delta.z).length()
	if flat_len < 0.5:
		return root
	var steps := maxi(2, int(flat_len / 1.1))
	var yaw := rad_to_deg(atan2(delta.x, delta.z))
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var p := from.lerp(to, t)
		_box(root, Vector3(width, 0.16, flat_len / float(steps) + 0.16),
			Vector3(p.x, p.y + 0.08, p.z), "stone" if i % 2 == 0 else "stone_dark",
			Vector3(0.0, yaw, 0.0))
	# 一条斜碰撞体，走起来平滑。
	var length := delta.length()
	var pitch := rad_to_deg(atan2(delta.y, flat_len))
	_collider(root, Vector3(width, 0.35, length),
		Vector3((from.x + to.x) * 0.5, (from.y + to.y) * 0.5, (from.z + to.z) * 0.5),
		Vector3(-pitch, yaw, 0.0))
	return root

func bridge(parent: Node3D, pos: Vector3, yaw_deg: float, span: float = 9.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	_box(root, Vector3(span, 0.22, 2.4), Vector3(0.0, 0.32, 0.0), "stone")
	_box(root, Vector3(span, 0.14, 0.3), Vector3(0.0, 0.52, 1.05), "stone_dark")
	_box(root, Vector3(span, 0.14, 0.3), Vector3(0.0, 0.52, -1.05), "stone_dark")
	for sx: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			_box(root, Vector3(0.16, 0.7, 0.16), Vector3(sx * span * 0.42, 0.75, z * 1.0), "stone_dark")
	_collider(root, Vector3(span, 0.35, 2.4), Vector3(0.0, 0.18, 0.0))
	return root

func scarecrow(parent: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	_box(root, Vector3(0.12, 1.8, 0.12), Vector3(0.0, 0.9, 0.0), "wood_dark")
	_box(root, Vector3(1.5, 0.1, 0.1), Vector3(0.0, 1.35, 0.0), "wood_dark")
	_box(root, Vector3(0.7, 0.85, 0.18), Vector3(0.0, 1.05, 0.0), "cloth_indigo")
	_sphere(root, Vector3(0.34, 0.36, 0.34), Vector3(0.0, 1.68, 0.0), "earth")
	_box(root, Vector3(0.08, 1.0, 0.04), Vector3(0.55, 1.0, 0.12), "wood", Vector3(0.0, 0.0, -28.0))
	_collider(root, Vector3(0.5, 1.8, 0.5), Vector3(0.0, 0.9, 0.0))
	return root

func notice_board(parent: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(root)
	for x: float in [-0.8, 0.8]:
		_box(root, Vector3(0.14, 2.1, 0.14), Vector3(x, 1.05, 0.0), "wood_dark")
	_box(root, Vector3(1.9, 1.1, 0.1), Vector3(0.0, 1.55, 0.0), "wood")
	_box(root, Vector3(1.6, 0.8, 0.04), Vector3(0.0, 1.55, 0.07), "plaster_old")
	_collider(root, Vector3(1.9, 2.1, 0.3), Vector3(0.0, 1.05, 0.0))
	return root
