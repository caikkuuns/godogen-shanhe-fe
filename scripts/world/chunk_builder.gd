class_name ChunkBuilder
extends RefCounted
## 60m 高度场区块：程序化地形 + 顶点色 + 地表细节 MultiMesh +
## 区块 POI（村舍/山门/废祠/桥/石阶/竹林…）。区块卸载时整棵树 queue_free。

const CHUNK_SIZE := 60.0
const GRID := 24
## 同屏地面细节上限：9 块 × 每块约 220 实例 ≈ 1980，竹/作物另计仍 < 3000。
const GRASS_COUNT := 150
const CLUMP_COUNT := 18
const BUSH_COUNT := 8
const FLOWER_COUNT := 20
const STONE_COUNT := 20
const LEAF_COUNT := 18
const FOOTPRINT_COUNT := 18
const PATCH_COUNT := 12
const PUDDLE_COUNT := 3
const BAMBOO_CLUSTERS := 38
const CROP_COUNT := 100
const REED_COUNT := 80

var world: Node
var factory: BuildingFactory
var rng := RandomNumberGenerator.new()

var _terrain_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D
var _crop_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _grass_mesh: ArrayMesh
var _leaf_quad: QuadMesh
var _stone_mesh: SphereMesh
var _crop_mesh: ArrayMesh
var _bamboo_stalk: CylinderMesh
var _bamboo_leaf: ArrayMesh
var _bamboo_stalk_mat: StandardMaterial3D
var _bamboo_leaf_mat: StandardMaterial3D
var _pine_mat: StandardMaterial3D
var _flower_mat: StandardMaterial3D
var _patch_mesh: ArrayMesh
var _patch_mat: StandardMaterial3D
var _foot_mat: StandardMaterial3D
var _bush_mesh: SphereMesh
var _clump_mesh: ArrayMesh

func _init(world_node: Node, building_factory: BuildingFactory) -> void:
	world = world_node
	factory = building_factory
	_make_shared()

# ------------------------------------------------------------------ 共享资源

func _make_shared() -> void:
	var noise_tex := _make_noise_texture()
	_terrain_mat = StandardMaterial3D.new()
	# 第八轮：地形贴图换 wuxia-team 画稿草地 tile（顶视无缝），色调仍由
	# 各区域色板的顶点色承担；uv 已按 wx*0.24 缩放，约 4.2m 一块。
	# 第十轮：画稿 tile 均值亮度远低于原 noise 贴图，r6→r8 地形整体变暗
	# （全图均色 #7E7757→#615D44，lum 118.2→92.2）。理论比值≈5.3 但 Filmic
	# tonemap 非线性，按实测定稿 1.92/1.87/2.23：explore 均色 #7D784D / lum 117.8
	# （目标 #7E7757 / 118.2）。只动本材质，不碰光照/环境/modulate。
	_terrain_mat.albedo_texture = load("res://assets/imported/terrain/ground_grass_tile.png")
	_terrain_mat.albedo_color = Color(1.92, 1.87, 2.23)
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.vertex_color_is_srgb = true
	_terrain_mat.roughness = 0.97
	_terrain_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_terrain_mat.texture_repeat = true
	_terrain_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)

	_grass_mesh = _make_grass_mesh()
	_grass_mat = _unshaded_vertex_color(Color("#6f7d42"))
	_leaf_quad = QuadMesh.new()
	_leaf_quad.size = Vector2(0.28, 0.2)
	_leaf_mat = _unshaded_vertex_color(Color("#8a6a3c"), 0.9)
	_stone_mesh = SphereMesh.new()
	_stone_mesh.radius = 0.5
	_stone_mesh.height = 1.0
	_stone_mesh.radial_segments = 8
	_stone_mesh.rings = 4
	_stone_mat = StandardMaterial3D.new()
	_stone_mat.albedo_color = Color("#8a8378")
	_stone_mat.roughness = 0.95
	_crop_mesh = _make_crop_mesh()
	_crop_mat = _unshaded_vertex_color(Color("#8d8d4c"))
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.30, 0.47, 0.53, 0.66)
	_water_mat.roughness = 0.12
	_water_mat.metallic = 0.12
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bamboo_stalk = CylinderMesh.new()
	_bamboo_stalk.top_radius = 0.032
	_bamboo_stalk.bottom_radius = 0.055
	_bamboo_stalk.height = 1.0
	_bamboo_stalk.radial_segments = 6
	_bamboo_stalk.rings = 2
	_bamboo_leaf = _make_bamboo_leaf_mesh()
	_bamboo_stalk_mat = StandardMaterial3D.new()
	_bamboo_stalk_mat.albedo_color = Color("#7a8a52")
	_bamboo_stalk_mat.roughness = 0.55
	_bamboo_leaf_mat = StandardMaterial3D.new()
	_bamboo_leaf_mat.albedo_color = Color("#6f8a45")
	_bamboo_leaf_mat.vertex_color_use_as_albedo = true
	_bamboo_leaf_mat.vertex_color_is_srgb = true
	_bamboo_leaf_mat.roughness = 0.95
	_bamboo_leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bamboo_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pine_mat = StandardMaterial3D.new()
	_pine_mat.albedo_color = Color("#3d4f36")
	_pine_mat.roughness = 0.95
	_pine_mat.vertex_color_use_as_albedo = true
	_pine_mat.vertex_color_is_srgb = true
	_flower_mat = _unshaded_vertex_color(Color.WHITE)
	_patch_mesh = _make_patch_mesh()
	_patch_mat = _unshaded_vertex_color(Color(0.30, 0.40, 0.18, 0.55))
	_foot_mat = _unshaded_vertex_color(Color(0.24, 0.18, 0.12, 0.30))
	_bush_mesh = SphereMesh.new()
	_bush_mesh.radius = 0.5
	_bush_mesh.height = 1.0
	_bush_mesh.radial_segments = 7
	_bush_mesh.rings = 3
	_clump_mesh = _make_clump_mesh()

func _unshaded_vertex_color(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.98
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _make_noise_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n := (
				sin(float(x) * 0.71 + float(y) * 0.37)
				+ sin(float(x) * 0.19 - float(y) * 0.53) * 0.6
				+ sin(float(x + y) * 0.07) * 0.5
				+ sin(float(x * 3 + y) * 0.91) * 0.25
			) / 2.35
			var v := 0.94 + n * 0.045
			if (x * 37 + y * 19) % 211 == 0:
				v -= 0.07
			if (x * 13 - y * 29) % 307 == 0:
				v += 0.05
			img.set_pixel(x, y, Color(v, v, v * 0.98, 1.0))
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ 地形

func height_at(wx: float, wz: float, region: Dictionary) -> float:
	var h := 0.18 * sin(wx * 0.043) + 0.14 * cos(wz * 0.051) + 0.07 * sin((wx + wz) * 0.11)
	var feature := str(region.get("feature", ""))
	if feature == "brook":
		var d := _segment_distance(wx, wz, Vector2(-112.0, -54.0), Vector2(-68.0, -8.0))
		h -= 0.62 * (1.0 - smoothstep(3.0, 7.5, d))
	elif feature == "cliff":
		h += smoothstep(96.0, 112.0, wx) * 1.15
	elif feature == "bamboo":
		h += sin(wx * 0.21 + wz * 0.14) * 0.07
	# 村口/山门/废祠的 POI 找平，让建筑与 NPC 站稳。
	if feature in ["village", "gate", "shrine", "farmland"]:
		for poi: Variant in region.get("pois", []):
			if typeof(poi) == TYPE_ARRAY and (poi as Array).size() >= 2:
				var p := Vector2(float(poi[0]), float(poi[1]))
				var d := Vector2(wx, wz).distance_to(p)
				if d < 9.0:
					var t := 1.0 - smoothstep(4.0, 9.0, d)
					h = lerpf(h, 0.16, t * 0.85)
	# 土路/石阶压平；道路是区块间连通的主干。
	var road_d := float(world.call("road_distance", wx, wz))
	var rt := 1.0 - smoothstep(1.8, 3.4, road_d)
	h = lerpf(h, 0.14, rt * 0.92)
	return h

func _segment_distance(px: float, pz: float, a: Vector2, b: Vector2) -> float:
	var p := Vector2(px, pz)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func build(region: Dictionary, chunk: Vector2i) -> Node3D:
	var center: Vector2 = world.call("chunk_center", chunk)
	rng.seed = int(center.x * 73856093) ^ int(center.y * 19349663) ^ (chunk.x * 31 + chunk.y * 17)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	root.position = Vector3(center.x, 0.0, center.y)
	_build_terrain(root, region, center)
	if str(region.get("feature", "")) == "brook":
		_build_water(root, center)
	_build_decor(root, region, center)
	_build_region_props(root, region, center)
	_batch_static_meshes(root)
	# 雾在 58m 结束；90m 外的区块几何剔除，省掉远景静态批与地表 MultiMesh。
	# visibility_range_* 属于 GeometryInstance3D，不能设在 Node3D 根上。
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = 90.0
	return root

## 静态建筑/道具按“材质 + 投影状态”合并，减少 draw call。
## 地形/水面/半透明物与 MultiMesh 不参与；碰撞体保持原样。
func _batch_static_meshes(root: Node3D) -> void:
	var groups: Dictionary = {}
	for child: Node in root.get_children():
		_collect_static(child, Transform3D.IDENTITY, groups)
	for key: int in groups:
		var items: Array = groups[key]
		if items.size() < 2:
			continue
		var mat: Material = items[0][0]
		var shadow := int(items[0][1])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var appended := false
		for item: Array in items:
			var mesh: Mesh = item[2]
			var xform: Transform3D = item[3]
			for surface in mesh.get_surface_count():
				st.append_from(mesh, surface, xform)
				appended = true
		if not appended:
			continue
		var merged := st.commit()
		if merged == null or merged.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "StaticBatch_%d" % key
		mi.mesh = merged
		mi.material_override = mat
		mi.cast_shadow = shadow
		root.add_child(mi)
		for item: Array in items:
			var node: MeshInstance3D = item[4]
			if is_instance_valid(node):
				node.free()

func _collect_static(node: Node, parent_xform: Transform3D, groups: Dictionary) -> void:
	if node is Node3D:
		var node3d := node as Node3D
		var xform := parent_xform * node3d.transform
		if node3d is MeshInstance3D:
			var mi := node3d as MeshInstance3D
			if mi.mesh != null and mi.material_override != null and mi.name != "Terrain" and mi.name != "Water":
				var mat := mi.material_override as BaseMaterial3D
				if mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					var key := int(mat.get_instance_id()) * 8 + mi.cast_shadow
					if not groups.has(key):
						groups[key] = []
					(groups[key] as Array).append([mat, mi.cast_shadow, mi.mesh, xform, mi])
		for child: Node in node3d.get_children():
			_collect_static(child, xform, groups)

func _build_terrain(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := CHUNK_SIZE / float(GRID)
	var verts := GRID + 1
	for iz in verts:
		for ix in verts:
			var lx := -CHUNK_SIZE * 0.5 + float(ix) * step
			var lz := -CHUNK_SIZE * 0.5 + float(iz) * step
			var wx := center.x + lx
			var wz := center.y + lz
			var h := height_at(wx, wz, region)
			st.set_color(_terrain_color(wx, wz, h, region))
			st.set_uv(Vector2(wx * 0.24, wz * 0.24))
			st.add_vertex(Vector3(lx, h, lz))
	for iz in GRID:
		for ix in GRID:
			var i := iz * verts + ix
			# 逆时针（从上往下看）以保证法线朝上，避免被背面剔除。
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + verts)
			st.add_index(i + 1)
			st.add_index(i + verts + 1)
			st.add_index(i + verts)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = _terrain_mat
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	# 双面碰撞：高度场从上方/下方都能站住，避免绕序导致穿地。
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)
	root.add_child(body)

func _terrain_color(wx: float, wz: float, _h: float, region: Dictionary) -> Color:
	var p: Dictionary = region.get("palette", {})
	var grass_a := Color(str(p.get("grassA", "#5f6c3c"))).darkened(0.08)
	var grass_b := Color(str(p.get("grassB", "#7d844e"))).darkened(0.05)
	var grass_c := Color(str(p.get("grassC", "#4a5430"))).darkened(0.10)
	var dirt_a := Color(str(p.get("dirtA", "#a8916e")))
	var dirt_b := Color(str(p.get("dirtB", "#c2ad8a")))
	var stone := Color(str(p.get("stone", "#8b8377")))
	var moss := Color(str(p.get("moss", "#5a6a3c")))
	var n1 := 0.5 + 0.5 * sin(wx * 0.31 + wz * 0.17) * cos(wx * 0.07 - wz * 0.23)
	var n2 := 0.5 + 0.5 * sin(wx * 0.83 - wz * 0.61 + 1.7)
	var col := grass_a.lerp(grass_b, n1).lerp(grass_c, n2 * 0.48)
	var patch := 0.5 + 0.5 * sin(wx * 0.19 + 0.7) * sin(wz * 0.16 - 1.1)
	col = col.lerp(grass_c, patch * 0.28)
	var feature := str(region.get("feature", ""))
	if feature == "farmland":
		var furrow := 0.5 + 0.5 * sin(wz * 0.95 + sin(wx * 0.06) * 1.6)
		col = col.lerp(dirt_a, furrow * 0.34)
	elif feature == "bamboo":
		col = col.lerp(grass_c, 0.22)
	elif feature == "brook":
		var d := _segment_distance(wx, wz, Vector2(-112.0, -54.0), Vector2(-68.0, -8.0))
		var t := 1.0 - smoothstep(2.5, 7.0, d)
		col = col.lerp(stone, t * 0.55).lerp(moss, (1.0 - t) * n2 * 0.18)
	elif feature == "cliff":
		col = col.lerp(stone, smoothstep(99.0, 111.0, wx) * 0.62)
	elif feature == "shrine":
		col = col.lerp(moss, n2 * 0.26)
	# 土路颜色
	var road := 1.0 - smoothstep(1.5, 2.9, float(world.call("road_distance", wx, wz)))
	var dirt := dirt_a.darkened(0.06).lerp(dirt_b, n2)
	col = col.lerp(dirt, road * 0.98)
	# 路缘压暗，让土路从草地里“读”出来。
	var edge := (1.0 - smoothstep(2.6, 3.6, absf(float(world.call("road_distance", wx, wz)) - 2.8))) * 0.18
	col = col.darkened(edge)
	if feature in ["village", "gate"]:
		var plaza := 1.0 - smoothstep(4.0, 9.0, Vector2(wx, wz).distance_to(Vector2(-30.0, 30.0) if feature == "village" else Vector2(30.0, 30.0)))
		col = col.lerp(dirt, plaza * 0.55)
	elif feature == "mountain_road":
		col = col.lerp(stone, road * 0.38)
	# 细碎明暗，避免整片纯色
	var v := 0.86 + 0.28 * (0.5 + 0.5 * sin(wx * 1.93 + wz * 2.71))
	col = col.lightened(maxf(0.0, v - 1.0) * 0.7).darkened(maxf(0.0, 1.0 - v) * 0.7)
	return col

# ------------------------------------------------------------------ 水

func _build_water(root: Node3D, center: Vector2) -> void:
	var mid := Vector2(-90.0, -31.0)
	var a := Vector2(-112.0, -54.0)
	var b := Vector2(-68.0, -8.0)
	var yaw := rad_to_deg(atan2(b.x - a.x, b.y - a.y))
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.4, 54.0)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = _water_mat
	mi.position = Vector3(mid.x - center.x, -0.20, mid.y - center.y)
	mi.rotation_degrees = Vector3(0.0, yaw, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

# ------------------------------------------------------------------ 地表细节

func _build_decor(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var feature := str(region.get("feature", ""))
	var ground_transforms: Array[Transform3D] = []
	var ground_colors: Array[Color] = []
	var stone_transforms: Array[Transform3D] = []
	var stone_colors: Array[Color] = []
	var leaf_transforms: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var foot_transforms: Array[Transform3D] = []
	var puddle_transforms: Array[Transform3D] = []
	var clump_transforms: Array[Transform3D] = []
	var clump_colors: Array[Color] = []
	var bush_transforms: Array[Transform3D] = []
	var bush_colors: Array[Color] = []
	var flower_transforms: Array[Transform3D] = []
	var flower_colors: Array[Color] = []
	var patch_transforms: Array[Transform3D] = []
	var patch_colors: Array[Color] = []
	# 草簇
	var tries := 0
	while ground_transforms.size() < GRASS_COUNT and tries < GRASS_COUNT * 8:
		tries += 1
		var lx := rng.randf_range(-29.0, 29.0)
		var lz := rng.randf_range(-29.0, 29.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 3.3:
			continue
		if feature == "brook" and _segment_distance(wx, wz, Vector2(-112.0, -54.0), Vector2(-68.0, -8.0)) < 4.0:
			continue
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(1.0, 2.1)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 1.2, s))
		ground_transforms.append(Transform3D(basis, Vector3(lx, h, lz)))
		var tint := rng.randf_range(0.68, 1.12)
		ground_colors.append(Color(tint * 0.86, tint, tint * 0.70, 1.0))
	# 大块草皮/灌木影，压住“纯色平地”。
	var clump_tries := 0
	while clump_transforms.size() < CLUMP_COUNT and clump_tries < CLUMP_COUNT * 8:
		clump_tries += 1
		var lx := rng.randf_range(-27.0, 27.0)
		var lz := rng.randf_range(-27.0, 27.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 3.6:
			continue
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(0.9, 2.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s))
		clump_transforms.append(Transform3D(basis, Vector3(lx, h + 0.01, lz)))
		var tint := rng.randf_range(0.62, 0.95)
		clump_colors.append(Color(tint * 0.72, tint * 0.94, tint * 0.52, 1.0))
	# 苔痕/草色斑块：低频色块，先铺一层，别让草地是一整块纯色。
	for i in PATCH_COUNT:
		var lx := rng.randf_range(-27.0, 27.0)
		var lz := rng.randf_range(-27.0, 27.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(1.4, 3.8)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s))
		patch_transforms.append(Transform3D(basis, Vector3(lx, h + 0.012, lz)))
		var tint := rng.randf_range(0.55, 0.95)
		patch_colors.append(Color(tint * 0.7, tint, tint * 0.55, 0.7))
	# 灌木/花点：打破草地的均匀感。
	var bush_tries := 0
	while bush_transforms.size() < BUSH_COUNT and bush_tries < BUSH_COUNT * 10:
		bush_tries += 1
		var lx := rng.randf_range(-27.0, 27.0)
		var lz := rng.randf_range(-27.0, 27.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 4.2:
			continue
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(0.55, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.2, s, s * 1.1))
		bush_transforms.append(Transform3D(basis, Vector3(lx, h + s * 0.35, lz)))
		var tint := rng.randf_range(0.55, 0.9)
		bush_colors.append(Color(tint * 0.66, tint * 0.82, tint * 0.52, 1.0))
	for i in FLOWER_COUNT:
		var lx := rng.randf_range(-27.0, 27.0)
		var lz := rng.randf_range(-27.0, 27.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 3.1:
			continue
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(0.38, 0.75)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		flower_transforms.append(Transform3D(basis, Vector3(lx, h, lz)))
		var pick := rng.randi_range(0, 2)
		flower_colors.append([Color("#e9d98a"), Color("#e6b7bd"), Color("#eef0e2")][pick])
	# 石子
	for i in STONE_COUNT:
		var lx := rng.randf_range(-28.0, 28.0)
		var lz := rng.randf_range(-28.0, 28.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(0.10, 0.42)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s, s))
		stone_transforms.append(Transform3D(basis, Vector3(lx, h + s * 0.18, lz)))
		var g := rng.randf_range(0.72, 1.08)
		stone_colors.append(Color(g, g * 0.98, g * 0.92, 1.0))
	# 路心踏步石：让土路有“走出来的路”的层次。
	var path_stones := 0
	var path_tries := 0
	while path_stones < 10 and path_tries < 60:
		path_tries += 1
		var lx := rng.randf_range(-28.0, 28.0)
		var lz := rng.randf_range(-28.0, 28.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var road := float(world.call("road_distance", wx, wz))
		if road < 0.4 or road > 1.6:
			continue
		path_stones += 1
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(0.28, 0.55)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.4, s * 0.28, s))
		stone_transforms.append(Transform3D(basis, Vector3(lx, h + 0.035, lz)))
		var g := rng.randf_range(0.72, 1.02)
		stone_colors.append(Color(g, g * 0.97, g * 0.9, 1.0))
	# 落叶
	for i in LEAF_COUNT:
		var lx := rng.randf_range(-28.0, 28.0)
		var lz := rng.randf_range(-28.0, 28.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var h := height_at(wx, wz, region)
		var basis := Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
		leaf_transforms.append(Transform3D(basis, Vector3(lx, h + 0.03, lz)))
		var g := rng.randf_range(0.6, 1.0)
		leaf_colors.append(Color(g, g * 0.72, g * 0.42, 0.9))
	# 踏痕（沿路边）
	for i in FOOTPRINT_COUNT:
		var lx := rng.randf_range(-28.0, 28.0)
		var lz := rng.randf_range(-28.0, 28.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var road := float(world.call("road_distance", wx, wz))
		if road < 0.6 or road > 3.2:
			continue
		var h := height_at(wx, wz, region)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.7, 1.0, 0.35))
		foot_transforms.append(Transform3D(basis, Vector3(lx, h + 0.025, lz)))
	# 水洼（低洼/路边；竹林木桥、溪谷多几个）
	var puddle_wanted := PUDDLE_COUNT + (2 if feature in ["brook", "bamboo"] else 0)
	for i in puddle_wanted:
		var lx := rng.randf_range(-24.0, 24.0)
		var lz := rng.randf_range(-24.0, 24.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var h := height_at(wx, wz, region)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(rng.randf_range(0.9, 2.0), 1.0, rng.randf_range(0.6, 1.3)))
		puddle_transforms.append(Transform3D(basis, Vector3(lx, h + 0.035, lz)))

	_add_mm(root, _bush_mesh, _pine_mat, bush_transforms, bush_colors, true, 40.0, "Bushes")
	_add_mm(root, _grass_mesh, _flower_mat, flower_transforms, flower_colors, false, 30.0, "Flowers")
	_add_mm(root, _patch_mesh, _patch_mat, patch_transforms, patch_colors, false, 30.0, "GrassPatches")
	_add_mm(root, _clump_mesh, _grass_mat, clump_transforms, clump_colors, false, 38.0, "GrassClumps")
	_add_mm(root, _grass_mesh, _grass_mat, ground_transforms, ground_colors, false, 46.0, "GrassTufts")
	_add_mm(root, _stone_mesh, _stone_mat, stone_transforms, stone_colors, false, 40.0, "Pebbles")
	_add_mm(root, _leaf_quad, _leaf_mat, leaf_transforms, leaf_colors, false, 34.0, "FallenLeaves")
	_add_mm(root, _patch_mesh, _foot_mat, foot_transforms, [], false, 40.0, "Footprints")
	_add_mm(root, _patch_mesh, _water_mat, puddle_transforms, [], false, 34.0, "Puddles")

	match feature:
		"bamboo":
			_build_bamboo(root, region, center)
		"farmland":
			_build_crops(root, region, center)
		"brook":
			_build_reeds(root, region, center)
	# 较大的石块/树木，给远景剪影
	_build_boulders(root, region, center)
	_build_pines(root, region, center)

func _add_mm(root: Node3D, mesh: Mesh, material: Material, transforms: Array[Transform3D],
		colors: Array[Color], cast_shadow: bool, visible_range: float, node_name: String) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = visible_range
	root.add_child(mmi)

# ------------------------------------------------------------------ 特色地被

func _build_bamboo(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var stalk_xforms: Array[Transform3D] = []
	var leaf_xforms: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	# 第八轮：画稿竹丛（本体+落地影）的变换收集。
	var _clump_xforms: Array[Transform3D] = []
	var _clump_colors: Array[Color] = []
	var _clump_shadow_xforms: Array[Transform3D] = []
	var clusters := 0
	var attempts := 0
	while clusters < BAMBOO_CLUSTERS and attempts < BAMBOO_CLUSTERS * 12:
		attempts += 1
		var lx := rng.randf_range(-28.0, 28.0)
		var lz := rng.randf_range(-28.0, 28.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 4.4:
			continue
		clusters += 1
		var h := height_at(wx, wz, region)
		var cluster_h := rng.randf_range(6.5, 10.2)
		var count := rng.randi_range(2, 3)
		for s in count:
			var hh := cluster_h + rng.randf_range(-0.8, 1.0)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, hh, 1.0))
			var pos := Vector3(lx + rng.randf_range(-1.0, 1.0), h, lz + rng.randf_range(-1.0, 1.0))
			stalk_xforms.append(Transform3D(basis, pos))
			for f: float in [0.55, 0.78]:
				var ls := rng.randf_range(1.2, 2.1)
				leaf_xforms.append(Transform3D(
					Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ls, ls, ls)),
					pos + Vector3(0.0, hh * f, 0.0)
				))
				var g := rng.randf_range(0.78, 1.12)
				leaf_colors.append(Color(g * 0.9, g, g * 0.82, 1.0))
		# 第八轮：每丛 1~2 张画稿竹丛，垫在根部。
		for c in (1 + (rng.randi() % 2)):
			var cs := rng.randf_range(1.5, 2.2)
			_clump_xforms.append(Transform3D(
				Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)).scaled(Vector3(cs, cs, 1.0)),
				Vector3(lx + rng.randf_range(-0.9, 0.9), h + 744.0 * 0.00386 * 0.5 * cs,
					lz + rng.randf_range(-0.6, 0.4))))
			var ct := rng.randf_range(0.86, 1.06)
			_clump_colors.append(Color(ct * 0.95, ct, ct * 0.9, 1.0))
			var shs := cs * 0.86
			_clump_shadow_xforms.append(Transform3D(
				Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(shs, shs, 1.0)),
				Vector3(lx, h + 0.02, lz - 744.0 * 0.00386 * 0.5)))
		if clusters <= 8:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.position = Vector3(lx, h + 1.8, lz)
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 0.42
			shape.height = 3.6
			cs.shape = shape
			body.add_child(cs)
			root.add_child(body)
	_add_mm(root, _bamboo_stalk, _bamboo_stalk_mat, stalk_xforms, [], false, 48.0, "BambooStalks")
	_add_mm(root, _bamboo_leaf, _bamboo_leaf_mat, leaf_xforms, leaf_colors, false, 48.0, "BambooLeaves")
	# 第八轮：画稿竹丛（wuxia-team/art bamboo_v3b）垫在竹丛脚下补下层枝叶。
	# 相机固定从南面朝北看，面片统一面向 +Z 即可；两张 MultiMesh 共 2 个 draw call。
	if _clump_xforms.size() > 0:
		var clump_mesh := QuadMesh.new()
		clump_mesh.size = Vector2(622.0, 744.0) * 0.00386
		var clump_mat := factory._painted_mat("res://assets/imported/scenery/bamboo_v3b.png", true)
		clump_mat.vertex_color_use_as_albedo = true
		clump_mat.vertex_color_is_srgb = true
		_add_mm(root, clump_mesh, clump_mat, _clump_xforms, _clump_colors, false, 48.0, "BambooPaintedClumps")
		var sh_mesh := QuadMesh.new()
		sh_mesh.size = Vector2(622.0, 744.0) * 0.00386
		var sh_mat := factory._painted_mat("res://assets/imported/scenery/bamboo_v3b_shadow.png", false)
		_add_mm(root, sh_mesh, sh_mat, _clump_shadow_xforms, [], false, 48.0, "BambooPaintedShadows")
	# 倒竹
	for i in 4:
		var lx := rng.randf_range(-20.0, 20.0)
		var lz := rng.randf_range(-20.0, 20.0)
		var h := height_at(center.x + lx, center.y + lz, region)
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.12
		mesh.height = rng.randf_range(2.4, 4.0)
		mi.mesh = mesh
		mi.material_override = _bamboo_stalk_mat
		mi.position = Vector3(lx, h + 0.12, lz)
		mi.rotation_degrees = Vector3(90.0, rng.randf() * 180.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

func _build_crops(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var rows := 6
	var per_row := CROP_COUNT / rows
	for row in rows:
		var base_z := -16.0 + float(row) * 6.0
		for i in per_row:
			var lx := -24.0 + float(i) * (48.0 / float(per_row - 1)) + rng.randf_range(-0.5, 0.5)
			var lz := base_z + rng.randf_range(-0.6, 0.6)
			var wx := center.x + lx
			var wz := center.y + lz
			if float(world.call("road_distance", wx, wz)) < 3.6:
				continue
			var h := height_at(wx, wz, region)
			var s := rng.randf_range(0.75, 1.2)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			xforms.append(Transform3D(basis, Vector3(lx, h, lz)))
			var g := rng.randf_range(0.82, 1.12)
			colors.append(Color(g * 0.92, g, g * 0.55, 1.0))
	_add_mm(root, _crop_mesh, _crop_mat, xforms, colors, false, 42.0, "Crops")

func _build_reeds(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var attempts := 0
	while xforms.size() < REED_COUNT and attempts < REED_COUNT * 8:
		attempts += 1
		var lx := rng.randf_range(-28.0, 28.0)
		var lz := rng.randf_range(-28.0, 28.0)
		var d := _segment_distance(center.x + lx, center.y + lz, Vector2(-112.0, -54.0), Vector2(-68.0, -8.0))
		if d < 3.0 or d > 6.2:
			continue
		var h := height_at(center.x + lx, center.y + lz, region)
		var s := rng.randf_range(0.8, 1.5)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		xforms.append(Transform3D(basis, Vector3(lx, h, lz)))
		var g := rng.randf_range(0.8, 1.1)
		colors.append(Color(g * 0.88, g, g * 0.72, 1.0))
	_add_mm(root, _crop_mesh, _crop_mat, xforms, colors, false, 38.0, "Reeds")

func _build_boulders(root: Node3D, region: Dictionary, center: Vector2) -> void:
	for i in 3:
		var lx := rng.randf_range(-24.0, 24.0)
		var lz := rng.randf_range(-24.0, 24.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 4.5:
			continue
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(1.0, 2.6)
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 9
		mesh.rings = 5
		mi.mesh = mesh
		mi.material_override = _stone_mat
		mi.position = Vector3(lx, h + s * 0.25, lz)
		mi.scale = Vector3(s * 1.25, s * 0.85, s)
		mi.rotation_degrees = Vector3(rng.randf_range(-8.0, 8.0), rng.randf() * 180.0,
			rng.randf_range(-8.0, 8.0))
		root.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(lx, h + s * 0.3, lz)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(s * 1.1, s * 0.8, s * 0.9)
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)

func _build_pines(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var count := 5 if str(region.get("feature", "")) == "wild" else 3
	for i in count:
		var lx := rng.randf_range(-25.0, 25.0)
		var lz := rng.randf_range(-25.0, 25.0)
		var wx := center.x + lx
		var wz := center.y + lz
		if float(world.call("road_distance", wx, wz)) < 6.5:
			continue
		if str(region.get("feature", "")) in ["village", "gate"] and Vector2(lx, lz).length() < 13.0:
			continue
		var h := height_at(wx, wz, region)
		var tree := Node3D.new()
		tree.position = Vector3(lx, h, lz)
		root.add_child(tree)
		var trunk := MeshInstance3D.new()
		var tmesh := CylinderMesh.new()
		tmesh.top_radius = 0.12
		tmesh.bottom_radius = 0.22
		tmesh.height = 3.6
		trunk.mesh = tmesh
		trunk.material_override = _bamboo_stalk_mat
		trunk.position = Vector3(0.0, 1.8, 0.0)
		tree.add_child(trunk)
		for layer in 3:
			var cone := MeshInstance3D.new()
			var cmesh := CylinderMesh.new()
			cmesh.top_radius = 0.0
			cmesh.bottom_radius = 1.9 - float(layer) * 0.5
			cmesh.height = 2.3
			cmesh.radial_segments = 8
			cone.mesh = cmesh
			cone.material_override = _pine_mat
			cone.position = Vector3(0.0, 3.0 + float(layer) * 1.15, 0.0)
			tree.add_child(cone)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(lx, h + 1.6, lz)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.3
		shape.height = 3.2
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)

# ------------------------------------------------------------------ 区块 POI

func _build_region_props(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var feature := str(region.get("feature", ""))
	match feature:
		"village":
			_build_village(root, region, center)
		"farmland":
			_build_farmland(root, region, center)
		"bamboo":
			_build_bamboo_poi(root, region, center)
		"brook":
			_build_brook_poi(root, region, center)
		"mountain_road":
			_build_road_poi(root, region, center)
		"gate":
			_build_gate_poi(root, region, center)
		"cliff":
			_build_cliff_poi(root, region, center)
		"shrine":
			_build_shrine_poi(root, region, center)
	# 路边石灯：每个区块 1~2 个，只在村口/山门/山道点亮。
	if feature in ["village", "gate", "mountain_road", "shrine"]:
		var lx := 0.0
		var lz := 0.0
		var wx := center.x + lx
		var wz := center.y + lz
		var h := height_at(wx, wz, region)
		factory.stone_lantern(root, Vector3(lx, h, lz), feature in ["village", "gate"])

func _world_y(region: Dictionary, lx: float, lz: float, center: Vector2) -> float:
	return height_at(center.x + lx, center.y + lz, region)

func _build_village(root: Node3D, region: Dictionary, center: Vector2) -> void:
	# 村口牌坊（门楼），主路穿过。
	var gate_y := _world_y(region, 0.0, -4.0, center)
	factory.gate_tower(root, Vector3(0.0, gate_y, -4.0), 0.0, "村 口")
	# 四座村舍
	# 立面朝道路与相机：左侧 +35°、右侧 -35°，正门/窗/檐口都能看到。
	var houses := [
		[-7.2, 7.0, 35.0, 5.2, 4.4, 3.0, true],
		[7.4, 5.5, -35.0, 4.8, 4.2, 2.9, false],
		[-10.5, 19.5, 42.0, 4.4, 3.8, 2.75, false],
		[10.2, 18.0, -42.0, 4.0, 3.6, 2.6, false],
	]
	for hspec: Array in houses:
		var lx: float = hspec[0]
		var lz: float = hspec[1]
		var y := _world_y(region, lx, lz, center)
		factory.village_house(root, Vector3(lx, y, lz), float(hspec[2]),
			float(hspec[3]), float(hspec[4]), float(hspec[5]), bool(hspec[6]))
	# 第二排背景屋：更小、更远，给村口制造建筑纵深。
	for spec: Array in [[-16.0, -7.0, 20.0, 3.4, 3.2, 2.7], [16.0, -9.0, -20.0, 3.2, 3.0, 2.6]]:
		var lx: float = spec[0]
		var lz: float = spec[1]
		var y2 := _world_y(region, lx, lz, center)
		factory.village_house(root, Vector3(lx, y2, lz), float(spec[2]),
			float(spec[3]), float(spec[4]), float(spec[5]), false)
	# 背景竹丛：卡在屋脊之间，补一层深色纵深。
	for bx: float in [-14.0, 14.0]:
		var by := _world_y(region, bx, -3.0, center)
		var grove := Node3D.new()
		grove.position = Vector3(bx, by, -3.0)
		root.add_child(grove)
		for s in 4:
			var mi := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.035
			mesh.bottom_radius = 0.08
			mesh.height = 1.0
			mesh.radial_segments = 5
			mi.mesh = mesh
			mi.material_override = _bamboo_stalk_mat
			var h := 7.0 + float(s) * 0.8
			mi.position = Vector3(float(s) * 0.45 - 0.6, h * 0.5, float(s % 2) * 0.5)
			mi.scale = Vector3(1.0, h, 1.0)
			mi.rotation_degrees = Vector3(0.0, 0.0, float(s - 1.5) * 3.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			grove.add_child(mi)
	var well_y := _world_y(region, 4.0, 11.0, center)
	factory.well(root, Vector3(4.0, well_y, 11.0))
	# 告示牌原本在周伯正前方，对话镜头里会把 NPC 整个挡住；西移 5m。
	var board_y := _world_y(region, -11.5, 13.0, center)
	factory.notice_board(root, Vector3(-11.5, board_y, 13.0), 12.0)
	# 近景摊位/木箱/木桶：让村口不是一个空广场。
	var stall_y := _world_y(region, -8.0, 4.0, center)
	var stall := Node3D.new()
	stall.position = Vector3(-8.0, stall_y, 4.0)
	root.add_child(stall)
	for sx: float in [-1.4, 1.4]:
		for sz: float in [-0.9, 0.9]:
			factory._box(stall, Vector3(0.12, 2.0, 0.12), Vector3(sx, 1.0, sz), "wood_dark")
			factory._collider(stall, Vector3(0.25, 2.0, 0.25), Vector3(sx, 1.0, sz))
	factory._box(stall, Vector3(3.1, 0.12, 2.1), Vector3(0.0, 2.05, 0.0), "cloth_red",
		Vector3(0.0, 0.0, 0.0))
	factory._box(stall, Vector3(2.6, 0.55, 0.9), Vector3(0.0, 0.55, 0.5), "wood")
	factory._box(stall, Vector3(0.9, 0.18, 0.7), Vector3(-0.7, 0.95, 0.5), "wood_dark")
	factory._sphere(stall, Vector3(0.25, 0.22, 0.25), Vector3(0.4, 0.9, 0.55), "lantern")
	for crate_spec: Vector3 in [Vector3(5.6, 0.0, 6.5), Vector3(-5.2, 0.0, 19.0), Vector3(6.4, 0.0, 16.0)]:
		var cy := _world_y(region, crate_spec.x, crate_spec.z, center)
		factory._box(root, Vector3(0.62, 0.62, 0.62), Vector3(crate_spec.x, cy + 0.31, crate_spec.z), "wood")
		factory._collider(root, Vector3(0.7, 0.7, 0.7), Vector3(crate_spec.x, cy + 0.35, crate_spec.z))
	var barrel_y := _world_y(region, 5.2, 8.0, center)
	factory._cyl(root, 0.28, 0.3, 0.8, Vector3(5.2, barrel_y + 0.4, 8.0), "wood", 10)
	_build_foreground_grass(root, region, center)
	# 竹篱：村舍之间与路边
	var f1 := _world_y(region, -14.0, 14.0, center)
	factory.fence_line(root, Vector3(-15.0, f1, 2.0), Vector3(-15.0, _world_y(region, -15.0, 26.0, center), 26.0))
	var f2 := _world_y(region, 14.0, 14.0, center)
	factory.fence_line(root, Vector3(14.0, f2, 0.0), Vector3(14.0, _world_y(region, 14.0, 24.0, center), 24.0))
	# 石灯两对：近景一对、门楼前一对。
	for lx: float in [-3.4, 3.4]:
		var y := _world_y(region, lx, 14.0, center)
		factory.stone_lantern(root, Vector3(lx, y, 14.0), lx > 0.0)
		var y2 := _world_y(region, lx, 2.0, center)
		factory.stone_lantern(root, Vector3(lx, y2, 2.0), false)

## 近景高草：沿村口主路两侧，压住画面底部，让地面有层次。
func _build_foreground_grass(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 54:
		var side := -1.0 if i % 2 == 0 else 1.0
		var lx := side * rng.randf_range(3.4, 8.8)
		var lz := rng.randf_range(10.0, 26.0)
		var wx := center.x + lx
		var wz := center.y + lz
		var h := height_at(wx, wz, region)
		var s := rng.randf_range(0.6, 1.15)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 1.15, s))
		xforms.append(Transform3D(basis, Vector3(lx, h, lz)))
		var tint := rng.randf_range(0.45, 0.8)
		colors.append(Color(tint * 0.78, tint, tint * 0.52, 1.0))
	_add_mm(root, _grass_mesh, _grass_mat, xforms, colors, false, 32.0, "ForegroundGrass")

func _build_farmland(root: Node3D, region: Dictionary, center: Vector2) -> void:
	for spec: Array in [[-10.0, 8.0, 14.0], [12.0, -2.0, -22.0]]:
		var lx: float = spec[0]
		var lz: float = spec[1]
		var y := _world_y(region, lx, lz, center)
		factory.scarecrow(root, Vector3(lx, y, lz), float(spec[2]))
	var y1 := _world_y(region, -18.0, 20.0, center)
	factory.fence_line(root, Vector3(-18.0, y1, 8.0), Vector3(-18.0, _world_y(region, -18.0, -18.0, center), -18.0))
	var y2 := _world_y(region, 18.0, 16.0, center)
	factory.fence_line(root, Vector3(18.0, y2, 6.0), Vector3(18.0, _world_y(region, 18.0, -16.0, center), -16.0))
	var y3 := _world_y(region, 0.0, -24.0, center)
	factory.notice_board(root, Vector3(2.0, y3, -24.0), 180.0)

func _build_bamboo_poi(root: Node3D, region: Dictionary, center: Vector2) -> void:
	# 竹亭：四柱、矮栏、起翘小顶。
	var y := _world_y(region, 0.0, 4.0, center)
	var pav := Node3D.new()
	pav.position = Vector3(0.0, y, 4.0)
	root.add_child(pav)
	for x: float in [-1.6, 1.6]:
		for z: float in [-1.4, 1.4]:
			factory._cyl(pav, 0.14, 0.16, 2.6, Vector3(x, 1.3, z), "wood_red", 10)
			factory._collider(pav, Vector3(0.34, 2.6, 0.34), Vector3(x, 1.3, z))
	factory._box(pav, Vector3(4.0, 0.18, 3.6), Vector3(0.0, 2.7, 0.0), "wood_dark")
	factory._roof(pav, 3.6, 3.2, 2.8, 0.9, 0.7, "roof")
	factory._label(pav, "听 竹", Vector3(0.0, 2.55, 1.9), 46, 0.0055)
	var yd := _world_y(region, 6.0, -10.0, center)
	factory.stone_lantern(root, Vector3(6.0, yd, -10.0), false)

func _build_brook_poi(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var y := _world_y(region, 0.0, 5.0, center)
	factory.bridge(root, Vector3(0.0, y + 0.06, 5.0), -34.0, 14.0)
	var yl := _world_y(region, -8.0, 0.0, center)
	factory.stone_lantern(root, Vector3(-8.0, yl, 0.0), false)
	var yb := _world_y(region, 10.0, -9.0, center)
	factory.notice_board(root, Vector3(10.0, yb, -9.0), -20.0)
	# 岸边大石
	for i in 5:
		var lx := rng.randf_range(-20.0, 20.0)
		var lz := rng.randf_range(-20.0, 20.0)
		var d := _segment_distance(center.x + lx, center.y + lz, Vector2(-112.0, -54.0), Vector2(-68.0, -8.0))
		if d < 3.0 or d > 5.5:
			continue
		var yy := height_at(center.x + lx, center.y + lz, region)
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 8
		mesh.rings = 4
		mi.mesh = mesh
		mi.material_override = factory.mats["stone"]
		mi.position = Vector3(lx, yy + 0.2, lz)
		var s := rng.randf_range(0.5, 1.2)
		mi.scale = Vector3(s * 1.4, s, s * 1.2)
		root.add_child(mi)

func _build_road_poi(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var a := Vector3(-10.0, _world_y(region, -10.0, 20.0, center), 20.0)
	var b := Vector3(4.0, _world_y(region, 4.0, 2.0, center), 2.0)
	var c := Vector3(13.0, _world_y(region, 13.0, -18.0, center), -18.0)
	factory.stone_steps(root, a, b, 4.2)
	factory.stone_steps(root, b, c, 3.8)
	var y := _world_y(region, -4.0, -6.0, center)
	factory.stone_lantern(root, Vector3(-4.0, y, -6.0), true)
	var yb := _world_y(region, 7.0, 8.0, center)
	factory.notice_board(root, Vector3(7.0, yb, 8.0), 20.0)

func _build_gate_poi(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var y := _world_y(region, 0.0, 0.0, center)
	factory.mountain_gate(root, Vector3(0.0, y, 0.0), 0.0)
	for lx: float in [-5.0, 5.0]:
		var ly := _world_y(region, lx, 8.0, center)
		factory.stone_lantern(root, Vector3(lx, ly, 8.0), true)
	var yb := _world_y(region, -9.0, -8.0, center)
	factory.notice_board(root, Vector3(-9.0, yb, -8.0), 25.0)

func _build_cliff_poi(root: Node3D, region: Dictionary, center: Vector2) -> void:
	for spec: Array in [[13.0, -6.0, 3.4], [17.0, 5.0, 2.6], [-14.0, -12.0, 2.2]]:
		var lx: float = spec[0]
		var lz: float = spec[1]
		var s: float = spec[2]
		var yy := _world_y(region, lx, lz, center)
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 9
		mesh.rings = 5
		mi.mesh = mesh
		mi.material_override = factory.mats["stone"]
		mi.position = Vector3(lx, yy + s * 0.35, lz)
		mi.scale = Vector3(s * 1.2, s, s)
		mi.rotation_degrees = Vector3(0.0, rng.randf() * 180.0, 8.0)
		root.add_child(mi)
		factory._collider(root, Vector3(s * 1.1, s, s), Vector3(lx, yy + s * 0.4, lz))
	# 测风幡
	var y := _world_y(region, -4.0, 4.0, center)
	factory._cyl(root, 0.07, 0.09, 4.2, Vector3(-4.0, y + 2.1, 4.0), "wood_dark", 8)
	factory._quad(root, Vector2(0.8, 1.5), Vector3(-3.6, y + 3.2, 4.0), "cloth_red",
		Vector3(0.0, 12.0, 0.0))
	var yl := _world_y(region, 6.0, -2.0, center)
	factory.stone_lantern(root, Vector3(6.0, yl, -2.0), false)

func _build_shrine_poi(root: Node3D, region: Dictionary, center: Vector2) -> void:
	var y := _world_y(region, 0.0, 2.0, center)
	factory.ruined_shrine(root, Vector3(0.0, y, 2.0), 0.0)
	var yl := _world_y(region, -8.0, 8.0, center)
	factory.stone_lantern(root, Vector3(-8.0, yl, 8.0), true)
	# 枯树
	for i in 3:
		var lx := rng.randf_range(-16.0, 16.0)
		var lz := rng.randf_range(-16.0, 16.0)
		var yy := _world_y(region, lx, lz, center)
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06
		mesh.bottom_radius = 0.24
		mesh.height = rng.randf_range(2.6, 4.2)
		mesh.radial_segments = 7
		mi.mesh = mesh
		mi.material_override = _bamboo_stalk_mat
		mi.position = Vector3(lx, yy + 1.6, lz)
		mi.rotation_degrees = Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-10.0, 10.0))
		root.add_child(mi)

# ------------------------------------------------------------------ 网格

func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var ang := float(i) * PI / 3.0
		var side := Vector3(cos(ang), 0.0, sin(ang)) * 0.095
		var tip := Vector3(sin(ang) * 0.22, 0.68 + 0.15 * float(i % 2), cos(ang) * 0.22)
		st.add_vertex(-side)
		st.add_vertex(side)
		st.add_vertex(tip)
	return st.commit()

func _make_crop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var ang := float(i) * TAU / 4.0
		var side := Vector3(cos(ang), 0.0, sin(ang)) * 0.1
		var tip := Vector3(sin(ang) * 0.22, 0.9 + 0.18 * float(i % 2), cos(ang) * 0.22)
		st.add_vertex(-side)
		st.add_vertex(side)
		st.add_vertex(tip)
	return st.commit()

func _make_bamboo_leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var ang := float(i) * TAU / 12.0
		var lift := 0.25 + 0.35 * absf(sin(float(i) * 1.9))
		var dir := Vector3(cos(ang), lift, sin(ang)).normalized()
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * 0.13
		var base := Vector3(0.0, -0.06 - 0.04 * float(i % 3), 0.0)
		var tip := base + dir * (0.78 + 0.28 * absf(cos(float(i) * 2.3)))
		tip.y -= 0.22
		var mid := base + dir * 0.42
		st.add_vertex(base - side)
		st.add_vertex(base + side)
		st.add_vertex(mid + side * 0.6)
		st.add_vertex(mid + side * 0.6)
		st.add_vertex(mid - side * 0.6)
		st.add_vertex(tip)
	return st.commit()

func _make_patch_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 10
	for i in segments:
		var a0 := float(i) * TAU / float(segments)
		var a1 := float(i + 1) * TAU / float(segments)
		var r := 0.5 * (0.8 + 0.2 * sin(float(i) * 2.3))
		st.add_vertex(Vector3(0.0, 0.0, 0.0))
		st.add_vertex(Vector3(cos(a0) * r, 0.0, sin(a0) * r))
		st.add_vertex(Vector3(cos(a1) * r, 0.0, sin(a1) * r))
	return st.commit()

func _make_clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var ang := float(i) * TAU / 5.0
		var r := 0.18
		var c := Vector3(cos(ang) * r, 0.015, sin(ang) * r)
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * 0.06
		st.add_vertex(c - side)
		st.add_vertex(c + side)
		st.add_vertex(c + Vector3(cos(ang) * 0.05, 0.08, sin(ang) * 0.05))
	return st.commit()
