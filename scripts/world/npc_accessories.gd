class_name NpcAccessories
extends RefCounted
## 第四轮：程序化 NPC 配饰（斗笠 / 头巾 / 背篓 / 围巾 / 腰带 / 提灯）。
##
## 每个散人 NPC 按固定 seed 抽 1 种主配饰；年龄大的再加胡子（同一头部网格）。
## 所有部件按“骨骼组”合并成一个 ArrayMesh + 顶点色，只增加 1–2 个
## MeshInstance3D，不额外增加 surface/draw pass。
## 挂点用 BoneAttachment3D：配件随骨骼动画一起动，但位置在 skeleton 静止
## 空间里算好再转成骨骼局部矩阵，避免不同 GLB 的骨骼轴向差异。

const KINDS: Array[String] = ["hat", "headscarf", "scarf", "basket", "belt", "lantern"]
const KIND_LABELS := {
	"hat": "斗笠", "headscarf": "头巾", "scarf": "围巾",
	"basket": "背篓", "belt": "腰带", "lantern": "提灯",
}
const OLD_AGE := 0.62

## 返回 {kind, age, nodes}，供截图/调试读取。
static func attach(model: Node3D, seed_value: int, height_m: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 2654435761 + 911
	var kind: String = KINDS[rng.randi_range(0, KINDS.size() - 1)]
	var age := rng.randf()
	var hue := rng.randf_range(0.0, 1.0)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return {"kind": kind, "age": age, "nodes": []}
	var groups: Dictionary = {}  # bone_name -> Builder
	var beard := age > OLD_AGE
	var palette := _palette(hue)
	match kind:
		"hat":
			_add_hat(_builder(groups, "head"), palette, age)
		"headscarf":
			_add_headscarf(_builder(groups, "head"), palette, age)
		"scarf":
			_add_scarf(_builder(groups, "chest"), palette)
		"basket":
			_add_basket(_builder(groups, "chest"), palette)
		"belt":
			_add_belt(_builder(groups, "hips"), palette)
		"lantern":
			_add_lantern(_builder(groups, "hand.R"), palette)
	if beard:
		_add_beard(_builder(groups, "head"), age)
	var nodes: Array[Node] = []
	for bone_variant: Variant in groups.keys():
		var bone_name := str(bone_variant)
		var b: Builder = groups[bone_variant]
		var mesh := b.commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Accessory_%s" % bone_name.replace(".", "_")
		mi.mesh = mesh
		mi.material_override = _material()
		# 配饰很小，身体阴影已足够；关掉可少一份 shadow pass 对象。
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("procedural_accessory", true)
		var bone_idx := _bone_index(skeleton, bone_name)
		if bone_idx < 0:
			mi.free()
			continue
		var att := BoneAttachment3D.new()
		att.name = "AccessoryAttach_%s" % bone_name.replace(".", "_")
		att.bone_name = skeleton.get_bone_name(bone_idx)
		skeleton.add_child(att)
		att.add_child(mi)
		var bone_rest := skeleton.get_bone_global_pose(bone_idx)
		var desired := _desired_transform(bone_name, bone_rest)
		mi.transform = bone_rest.affine_inverse() * desired
		nodes.append(mi)
	return {"kind": kind, "age": age, "nodes": nodes}

# ------------------------------------------------------------------ 部件

static func _add_hat(b: Builder, palette: Dictionary, age: float) -> void:
	var straw: Color = palette["straw"]
	if age > OLD_AGE:
		straw = straw.lerp(Color("#d8d2c2"), 0.45)
	# 斗笠：宽檐 + 锥顶 + 深色箍。
	b.cylinder(Vector3(0, 0.115, 0), 0.40, 0.35, 0.04, 16, straw)
	b.cylinder(Vector3(0, 0.150, 0), 0.37, 0.33, 0.025, 16, straw.darkened(0.18))
	b.cone(Vector3(0, 0.265, 0), 0.30, 0.03, 0.20, 16, straw)
	b.cylinder(Vector3(0, 0.205, 0), 0.32, 0.29, 0.025, 16, straw.darkened(0.28))
	# 帽带：两侧细绳。
	b.box(Vector3(0.17, 0.02, 0.02), Vector3(0.012, 0.18, 0.012), straw.darkened(0.45))
	b.box(Vector3(-0.17, 0.02, 0.02), Vector3(0.012, 0.18, 0.012), straw.darkened(0.45))

static func _add_headscarf(b: Builder, palette: Dictionary, age: float) -> void:
	var cloth: Color = palette["cloth"]
	if age > OLD_AGE:
		cloth = cloth.lerp(Color("#d9d5ca"), 0.35)
	b.cylinder(Vector3(0, 0.10, 0), 0.185, 0.172, 0.09, 14, cloth)
	b.box(Vector3(0.15, 0.105, -0.01), Vector3(0.06, 0.06, 0.06), cloth.darkened(0.15))
	b.box(Vector3(0.17, -0.03, -0.10), Vector3(0.07, 0.30, 0.020), cloth.darkened(0.10))
	b.box(Vector3(0.12, 0.00, -0.12), Vector3(0.06, 0.25, 0.018), cloth.darkened(0.22))

static func _add_scarf(b: Builder, palette: Dictionary) -> void:
	var cloth: Color = palette["cloth"]
	b.torus(Vector3(0, 0.13, 0), 0.145, 0.045, 14, 6, cloth)
	b.box(Vector3(0.05, -0.02, 0.12), Vector3(0.08, 0.28, 0.025), cloth.darkened(0.10))
	b.box(Vector3(-0.04, -0.03, 0.115), Vector3(0.07, 0.24, 0.022), cloth.darkened(0.20))

static func _add_basket(b: Builder, palette: Dictionary) -> void:
	var wicker: Color = palette["wicker"]
	# 背篓挂在背后（skeleton −Z 为背）。
	b.cylinder(Vector3(0, 0.03, -0.22), 0.17, 0.23, 0.36, 14, wicker)
	b.torus(Vector3(0, 0.21, -0.22), 0.23, 0.026, 14, 5, wicker.darkened(0.25))
	b.box(Vector3(0, -0.15, -0.22), Vector3(0.40, 0.03, 0.12), wicker.darkened(0.35))
	# 两条背带从肩膀绕到胸前。
	b.box(Vector3(0.115, 0.06, 0.10), Vector3(0.045, 0.40, 0.025), wicker.darkened(0.20))
	b.box(Vector3(-0.115, 0.06, 0.10), Vector3(0.045, 0.40, 0.025), wicker.darkened(0.20))

static func _add_belt(b: Builder, palette: Dictionary) -> void:
	var leather: Color = palette["leather"]
	b.torus(Vector3(0, 0.075, 0), 0.21, 0.04, 16, 5, leather)
	b.box(Vector3(0.0, 0.075, 0.215), Vector3(0.09, 0.08, 0.03), Color("#c9a24a"))
	b.box(Vector3(0.06, -0.07, 0.17), Vector3(0.06, 0.28, 0.025), leather.darkened(0.12))
	b.box(Vector3(0.11, -0.04, 0.15), Vector3(0.045, 0.19, 0.02), leather.darkened(0.28))

static func _add_lantern(b: Builder, palette: Dictionary) -> void:
	var glow: Color = palette["lantern"]
	var dark := Color("#2a2622")
	# 提灯：提梁 + 暖色灯身 + 上下深色盖。
	b.box(Vector3(0, 0.02, 0), Vector3(0.015, 0.11, 0.015), dark)
	b.box(Vector3(0, -0.05, 0), Vector3(0.14, 0.015, 0.14), dark)
	b.cylinder(Vector3(0, -0.13, 0), 0.06, 0.06, 0.15, 8, glow)
	b.cone(Vector3(0, -0.22, 0), 0.085, 0.025, 0.05, 8, dark)
	b.cylinder(Vector3(0, -0.055, 0), 0.08, 0.08, 0.025, 8, dark)

static func _add_beard(b: Builder, age: float) -> void:
	var hair := Color("#d9d5cb") if age > 0.8 else Color("#b9b4a8")
	# 下巴处的短须：上宽下窄的锥体。
	b.cone(Vector3(0, -0.02, 0.09), 0.065, 0.012, 0.16, 8, hair)
	b.box(Vector3(0.05, 0.02, 0.095), Vector3(0.03, 0.08, 0.022), hair.darkened(0.08))
	b.box(Vector3(-0.05, 0.02, 0.095), Vector3(0.03, 0.08, 0.022), hair.darkened(0.08))

# ------------------------------------------------------------------ 挂点

static func _desired_transform(bone_name: String, bone_rest: Transform3D) -> Transform3D:
	var origin := bone_rest.origin
	# 头部配饰以 head 骨骼原点为锚（帽檐/头巾/胡子按米在部件里排布）。
	if bone_name == "head":
		return Transform3D(Basis.IDENTITY, origin)
	if bone_name == "chest":
		return Transform3D(Basis.IDENTITY, origin + Vector3(0, 0.10, 0))
	if bone_name == "hips":
		return Transform3D(Basis.IDENTITY, origin + Vector3(0, 0.04, 0))
	if bone_name == "hand.R":
		return Transform3D(Basis.IDENTITY, origin)
	return bone_rest

static func _bone_index(skeleton: Skeleton3D, wanted: String) -> int:
	var idx := skeleton.find_bone(wanted)
	if idx >= 0:
		return idx
	if wanted == "head":
		idx = skeleton.find_bone("head_2")
		if idx >= 0:
			return idx
		return skeleton.find_bone("neck")
	return idx

static func _builder(groups: Dictionary, bone: String) -> Builder:
	if not groups.has(bone):
		groups[bone] = Builder.new()
	return groups[bone]

static func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = false
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func _palette(hue: float) -> Dictionary:
	return {
		"straw": Color.from_hsv(0.10 + hue * 0.05, 0.48, 0.80),
		"cloth": Color.from_hsv(fposmod(hue, 1.0), 0.42, 0.70),
		"wicker": Color.from_hsv(0.08 + hue * 0.04, 0.55, 0.54),
		"leather": Color.from_hsv(0.06 + hue * 0.04, 0.50, 0.36),
		"lantern": Color.from_hsv(0.10, 0.78, 0.98),
	}

# ------------------------------------------------------------------ 低模构造

class Builder:
	var st := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func vertex(p: Vector3, n: Vector3, c: Color) -> int:
		st.set_normal(n.normalized() if n.length_squared() > 0.0 else Vector3.UP)
		st.set_color(c.srgb_to_linear())
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)
		count += 1
		return count - 1

	func tri(a: int, b: int, c: int) -> void:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)

	func box(center: Vector3, size: Vector3, color: Color) -> void:
		var h := size * 0.5
		var faces := [
			[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
			[Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
			[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		]
		for f: Array in faces:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1] * h
			var v: Vector3 = f[2] * h
			var o := center + n * _half_extent(n, h)
			var p0 := o + u + v
			var p1 := o - u + v
			var p2 := o - u - v
			var p3 := o + u - v
			var a := vertex(p0, n, color)
			var b := vertex(p1, n, color)
			var c := vertex(p2, n, color)
			var d := vertex(p3, n, color)
			tri(a, b, c)
			tri(a, c, d)

	func cylinder(center: Vector3, r_bottom: float, r_top: float, height: float,
			segments: int, color: Color) -> void:
		var y0 := -height * 0.5
		var y1 := height * 0.5
		var ring0: Array[int] = []
		var ring1: Array[int] = []
		for i in segments:
			var a := TAU * float(i) / float(segments)
			var dir := Vector3(cos(a), 0, sin(a))
			var n := Vector3(dir.x, (r_bottom - r_top) / maxf(height, 0.001), dir.z).normalized()
			ring0.append(vertex(center + Vector3(dir.x * r_bottom, y0, dir.z * r_bottom), n, color))
			ring1.append(vertex(center + Vector3(dir.x * r_top, y1, dir.z * r_top), n, color))
		for i in segments:
			var j := (i + 1) % segments
			tri(ring0[i], ring0[j], ring1[i])
			tri(ring0[j], ring1[j], ring1[i])
		# 上下盖（平法线）。
		if r_bottom > 0.001:
			var cb := vertex(center + Vector3(0, y0, 0), Vector3.DOWN, color.darkened(0.15))
			for i in segments:
				var j := (i + 1) % segments
				tri(cb, ring0[j], ring0[i])
		if r_top > 0.001:
			var ct := vertex(center + Vector3(0, y1, 0), Vector3.UP, color)
			for i in segments:
				var j := (i + 1) % segments
				tri(ct, ring1[i], ring1[j])

	func cone(center: Vector3, radius: float, tip_radius: float, height: float,
			segments: int, color: Color) -> void:
		cylinder(center, radius, maxf(tip_radius, 0.001), height, segments, color)

	func torus(center: Vector3, major_r: float, minor_r: float,
			seg_major: int, seg_minor: int, color: Color) -> void:
		var grid: Array = []
		for i in seg_major:
			var a := TAU * float(i) / float(seg_major)
			var row: Array[int] = []
			for j in seg_minor:
				var b := TAU * float(j) / float(seg_minor)
				var n := Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b))
				var p := center + Vector3(cos(a) * (major_r + minor_r * cos(b)),
					minor_r * sin(b), sin(a) * (major_r + minor_r * cos(b)))
				row.append(vertex(p, n, color))
			grid.append(row)
		for i in seg_major:
			var j := (i + 1) % seg_major
			for k in seg_minor:
				var l := (k + 1) % seg_minor
				var a: int = (grid[i] as Array)[k]
				var b: int = (grid[i] as Array)[l]
				var c: int = (grid[j] as Array)[l]
				var d: int = (grid[j] as Array)[k]
				tri(a, b, c)
				tri(a, c, d)

	func commit() -> ArrayMesh:
		if count == 0:
			return null
		return st.commit()

	func _half_extent(n: Vector3, h: Vector3) -> float:
		return absf(n.x) * h.x + absf(n.y) * h.y + absf(n.z) * h.z
