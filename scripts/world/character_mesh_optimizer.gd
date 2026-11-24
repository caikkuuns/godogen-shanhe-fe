class_name CharacterMeshOptimizer
extends RefCounted
## 角色 GLB 网格优化（第四轮）。
##
## 目的：
## 1) 把同一 Skeleton3D 下所有 skinned MeshInstance3D + 全部 surface 合并成
##    一个 surface（保留 ARRAY_BONES / ARRAY_WEIGHTS），每实例只占 1 个渲染
##    对象；武器等非蒙皮小件在原节点内合并 surface，保留节点名和父级，
##    以免破坏 CharacterAnim 的拔刀/掉落逻辑。
## 2) 对 TripoSR 扫描网格做保守清理：
##    - 按“焊接后的位置”找连通岛，删掉小岛（此资产焊接后是单一连通体，
##      因此该规则只会命中真正悬空的碎片，不会把身体拆掉）
##    - 删退化三角形、极薄长条（扫描绒毛）
##    - 删“朝向身体内部”的微小翻面
##    - 合并时重算法线并平滑，减少碎面反光
## 3) 材质由 ToonModel 统一换成 vcol shader：大贴图 surface 保留 UV/贴图，
##    纯色小件（16×16 贴图 / 无贴图材质）烘成顶点色，同一 surface 里用
##    COLOR.a 区分“采样贴图 / 用顶点色”，从而真正做到单 surface。

const FLAT_TEXTURE_MAX := 32
## 小岛判定：顶点数 < 3% 或 AABB 体积 < 0.2%（按焊接后的连通体计算）。
const ISLAND_VERTEX_FRACTION := 0.03
const ISLAND_VOLUME_FRACTION := 0.002
## 极薄长条：厚度 < 0.4mm 且最长边 > 8mm。
const THIN_HEIGHT := 0.0004
const THIN_LONG_EDGE := 0.008
## 微小内翻面：面积小于中位数一半且法线明显朝内。
const INWARD_DOT := -0.45
const MIN_TRI_AREA := 1e-8

## 一次优化的统计，写进模型 meta，测试/日志可读。
static func optimize(model: Node3D, clean_scan: bool = true) -> Dictionary:
	var stats := {
		"skinned_groups": 0,
		"skinned_surfaces_before": 0,
		"skinned_surfaces_after": 0,
		"props_merged": 0,
		"removed_triangles": 0,
	}
	# 1) 收集每个 skeleton 下的蒙皮网格。
	var skeletons: Array[Skeleton3D] = []
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		skeletons.append(node as Skeleton3D)
	var merged_any := false
	for skeleton: Skeleton3D in skeletons:
		var members: Array[MeshInstance3D] = []
		for child: Node in skeleton.get_children():
			var mi := child as MeshInstance3D
			if mi != null and mi.skin != null and mi.mesh != null and mi.get_parent() == skeleton:
				members.append(mi)
		if members.is_empty():
			continue
		stats["skinned_groups"] = int(stats["skinned_groups"]) + 1
		var merged := _merge_skinned(skeleton, members, clean_scan, stats)
		if merged != null:
			merged_any = true
	# 2) 非蒙皮小件（武器/道具）：逐节点合并 surface，节点名/父级不变。
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.get_meta("character_merged", false):
			continue
		if mi.skin != null:
			continue
		if mi.mesh.get_surface_count() > 1:
			var mesh := _merge_prop(mi)
			if mesh != null:
				mi.mesh = mesh
				for i in mesh.get_surface_count():
					mi.set_surface_override_material(i, null)
				mi.set_meta("character_merged", true)
				mi.set_meta("flat_vcol", true)
				stats["props_merged"] = int(stats["props_merged"]) + 1
		else:
			# 单 surface 小件也转成顶点色，统一走 vcol 材质。
			var mesh2 := _flat_single(mi)
			if mesh2 != null:
				mi.mesh = mesh2
				mi.set_surface_override_material(0, null)
				mi.set_meta("character_merged", true)
				mi.set_meta("flat_vcol", true)
	if not merged_any and stats["props_merged"] == 0:
		pass
	model.set_meta("mesh_optimizer_stats", stats)
	return stats

# ------------------------------------------------------------------ skinned 合并

static func _merge_skinned(skeleton: Skeleton3D, members: Array[MeshInstance3D],
		clean_scan: bool, stats: Dictionary) -> MeshInstance3D:
	var body_texture: Texture2D = null
	var body_material: Material = null
	var body_name := ""
	# 先确定主身体贴图（最大贴图），以及合并后的节点名。
	var max_tex := 0
	for mi: MeshInstance3D in members:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var tex := _albedo_texture(mat)
			if tex != null:
				var size := maxi(tex.get_width(), tex.get_height())
				if size > max_tex and size > FLAT_TEXTURE_MAX:
					max_tex = size
					body_texture = tex
					body_material = mat
			stats["skinned_surfaces_before"] = int(stats["skinned_surfaces_before"]) + 1
		if body_name == "" and (mi.name == "Shenyan" or mi.name == "Body"):
			body_name = mi.name
	if body_texture == null:
		# 纯色角色（shenyan_script）：取第一个材质做兜底色。
		for mi: MeshInstance3D in members:
			if mi.mesh.get_surface_count() > 0:
				body_material = mi.get_active_material(0)
				break

	var max_bone_stride := 4
	for mi: MeshInstance3D in members:
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			if bones != null and (bones as PackedInt32Array).size() > 0:
				var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				if verts > 0:
					max_bone_stride = maxi(max_bone_stride,
						(bones as PackedInt32Array).size() / verts)

	var st := SurfaceTool.new()
	# set_skin_weight_count 必须在 begin() 之前调用。
	if max_bone_stride >= 8:
		st.set_skin_weight_count(SurfaceTool.SKIN_8_WEIGHTS)
	else:
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var vertex_count := 0
	var index_count := 0
	var merged_clean := clean_scan
	for mi: MeshInstance3D in members:
		# 网格相对 skeleton 的变换；这些资产里都是单位阵，仍按通式处理。
		var rel := _relative_transform(mi, skeleton)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var tex := _albedo_texture(mat)
			var textured := tex != null and maxi(tex.get_width(), tex.get_height()) > FLAT_TEXTURE_MAX
			if textured and body_texture == null:
				body_texture = tex
			var flat_color := Color.WHITE
			if not textured:
				flat_color = _material_flat_color(mat)
			var arrays := mi.mesh.surface_get_arrays(s)
			# 只清理扫描贴图的主表面；纯色衣袖/配饰本身是干净几何。
			if merged_clean and textured:
				arrays = _clean_arrays(arrays, stats)
			var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			vertex_count += _append_arrays(st, arrays, rel, textured, flat_color,
				max_bone_stride, true)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx != null:
				var packed := idx as PackedInt32Array
				for local_i: int in packed:
					st.add_index(vertex_count - n + local_i)
				index_count += packed.size()
			else:
				for local_i in n:
					st.add_index(vertex_count - n + local_i)
				index_count += n

	# 焊接完全相同的顶点，再平滑重算法线（扫描碎面的反光主要来自脏法线）。
	st.index()
	st.generate_normals()
	var merged_mesh := st.commit()
	if merged_mesh == null or merged_mesh.get_surface_count() == 0:
		return null
	# commit 之后法线已重新生成；清掉原 surface 材质，统一由 ToonModel 覆盖。
	var merged := MeshInstance3D.new()
	# 先起临时名：原 "Shenyan" 节点此时还在树里，同名会被 Godot 自动改名。
	merged.name = "MergedBody"
	merged.mesh = merged_mesh
	merged.skin = members[0].skin
	skeleton.add_child(merged)
	# PackedScene.pack() 只打包 owner 指向根节点的子节点；运行时新建的
	# 合并节点必须补 owner，否则优化后的场景里会“没有网格”。
	var root_owner := skeleton.owner
	if root_owner == null:
		var top: Node = skeleton
		while top.get_parent() != null:
			top = top.get_parent()
		root_owner = top
	merged.owner = root_owner
	merged.skeleton = merged.get_path_to(skeleton)
	merged.transform = Transform3D.IDENTITY
	merged.set_meta("character_merged", true)
	merged.set_meta("body", true)
	merged.set_meta("flat_vcol", body_texture == null)
	merged.set_meta("albedo_tex", body_texture)
	merged.set_meta("open_mesh", merged_clean)
	# 释放原来的蒙皮网格节点（动画只驱动骨骼，不引用这些节点）。
	for mi: MeshInstance3D in members:
		if is_instance_valid(mi):
			mi.free()
	# 原节点释放后再改成标准名，测试与 _normalize 都按 "Shenyan" 找主身体。
	merged.name = "Shenyan"
	stats["skinned_surfaces_after"] = int(stats["skinned_surfaces_after"]) + 1
	stats["merged_vertices"] = vertex_count
	stats["merged_indices"] = index_count
	return merged

## 把一个 surface 的数组写进 SurfaceTool；返回写入的顶点数。
static func _append_arrays(st: SurfaceTool, arrays: Array, xform: Transform3D,
		textured: bool, flat_color: Color, bone_stride: int,
		skinned: bool = false) -> int:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	var tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
	var nb := xform.basis.inverse().transposed()
	var color := Color.WHITE
	if not textured:
		color = flat_color
		color.a = 0.0
	var uv_fallback := Vector2(0.5, 0.5)
	# 源 surface 的骨架索引步长（4 或 8），逐 surface 推断。
	var src_stride := 4
	if skinned and bones != null and weights != null and verts.size() > 0:
		var ba_size := (bones as PackedInt32Array).size()
		var wa_size := (weights as PackedFloat32Array).size()
		var stride := ba_size / verts.size()
		if stride == 8 and wa_size / verts.size() == 8:
			src_stride = 8
	for i in verts.size():
		st.set_normal(((nb * (normals[i] as Vector3)).normalized())
			if normals != null else Vector3.UP)
		if tangents != null:
			var t: PackedFloat32Array = tangents
			var tv := Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])
			var tw := t[i * 4 + 3]
			tv = (xform.basis * tv).normalized()
			st.set_tangent(Plane(tv, tw))
		if uvs != null:
			st.set_uv(uvs[i] as Vector2)
		else:
			st.set_uv(uv_fallback)
		st.set_color(color if not textured else Color(1.0, 1.0, 1.0, 1.0))
		if skinned:
			var bone_arr := _bone_slice(bones, weights, i, src_stride, bone_stride)
			st.set_bones(bone_arr[0])
			st.set_weights(bone_arr[1])
		st.add_vertex(xform * (verts[i] as Vector3))
	return verts.size()

## 把 4/8 权重补齐/截断到 bone_stride 长，缺失时填 0。
static func _bone_slice(bones: Variant, weights: Variant, i: int,
		src_stride: int, bone_stride: int) -> Array:
	var out_b := PackedInt32Array()
	var out_w := PackedFloat32Array()
	out_b.resize(bone_stride)
	out_w.resize(bone_stride)
	if bones != null and weights != null:
		var ba: PackedInt32Array = bones
		var wa: PackedFloat32Array = weights
		for k in mini(src_stride, bone_stride):
			var at := i * src_stride + k
			if at < ba.size():
				out_b[k] = ba[at]
				out_w[k] = wa[at] if at < wa.size() else 0.0
	return [out_b, out_w]

# ------------------------------------------------------------------ 非蒙皮小件

## 合并一个 MeshInstance3D 的所有 surface（保留节点名/父级/变换）。
## 只处理纯色小件；若某 surface 带大贴图则放弃合并，避免丢贴图。
static func _merge_prop(mi: MeshInstance3D) -> ArrayMesh:
	for s in mi.mesh.get_surface_count():
		var tex := _albedo_texture(mi.get_active_material(s))
		if tex != null and maxi(tex.get_width(), tex.get_height()) > FLAT_TEXTURE_MAX:
			return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := 0
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		var flat := _material_flat_color(mat)
		var arrays := mi.mesh.surface_get_arrays(s)
		var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		total += _append_arrays(st, arrays, Transform3D.IDENTITY, false, flat, 0)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var base := total - n
		if idx != null:
			for local_i: int in (idx as PackedInt32Array):
				st.add_index(base + local_i)
		else:
			for local_i in n:
				st.add_index(base + local_i)
	st.index()
	st.generate_normals()
	return st.commit()

static func _flat_single(mi: MeshInstance3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := mi.get_active_material(0)
	var tex := _albedo_texture(mat)
	if tex != null and maxi(tex.get_width(), tex.get_height()) > FLAT_TEXTURE_MAX:
		return null
	var flat := _material_flat_color(mat)
	var arrays := mi.mesh.surface_get_arrays(0)
	_append_arrays(st, arrays, Transform3D.IDENTITY, false, flat, 0)
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	if idx != null:
		for local_i: int in (idx as PackedInt32Array):
			st.add_index(local_i)
	else:
		for local_i in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			st.add_index(local_i)
	st.index()
	st.generate_normals()
	return st.commit()

# ------------------------------------------------------------------ 扫描清理

## 返回清理后的 arrays（可能删三角形并压缩顶点）。
static func _clean_arrays(arrays: Array, stats: Dictionary) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx_v: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array()
	if idx_v != null:
		indices = idx_v
	else:
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	var tri_count := indices.size() / 3
	if tri_count == 0:
		return arrays

	# 焊接位置（0.1mm）后做连通分量；TripoSR 资产焊接后是单一连通体。
	var welded := PackedInt32Array()
	welded.resize(verts.size())
	var lookup: Dictionary = {}
	for i in verts.size():
		var key := Vector3i(
			roundi(verts[i].x * 10000.0),
			roundi(verts[i].y * 10000.0),
			roundi(verts[i].z * 10000.0))
		if lookup.has(key):
			welded[i] = int(lookup[key])
		else:
			lookup[key] = i
			welded[i] = i
	var parent: Array[int] = []
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	for t in tri_count:
		var a := welded[indices[t * 3]]
		var b := welded[indices[t * 3 + 1]]
		var c := welded[indices[t * 3 + 2]]
		_union(parent, a, b)
		_union(parent, b, c)
	# 分量统计（按焊接代表点）。
	var comp_verts: Dictionary = {}
	for i in verts.size():
		var r := _find(parent, welded[i])
		comp_verts[r] = int(comp_verts.get(r, 0)) + 1
	var total_welded := comp_verts.size()
	var comp_box: Dictionary = {}
	for i in verts.size():
		var r := _find(parent, welded[i])
		if comp_box.has(r):
			comp_box[r] = (comp_box[r] as AABB).expand(verts[i])
		else:
			comp_box[r] = AABB(verts[i], Vector3.ZERO)
	var total_box := AABB()
	var have_box := false
	for r: int in comp_box.keys():
		if not have_box:
			total_box = comp_box[r]
			have_box = true
		else:
			total_box = total_box.merge(comp_box[r])
	var total_vol := maxf(1e-12, total_box.size.x * total_box.size.y * total_box.size.z)
	var keep_comp: Dictionary = {}
	for r: int in comp_verts.keys():
		var box: AABB = comp_box[r]
		var vol := box.size.x * box.size.y * box.size.z
		var small_verts := int(comp_verts[r]) < maxi(8, int(float(total_welded) * ISLAND_VERTEX_FRACTION))
		var small_vol := vol < total_vol * ISLAND_VOLUME_FRACTION
		keep_comp[r] = not (small_verts or small_vol)

	# 中位面积与整体质心，用于识别薄片/内翻微面。
	var areas := PackedFloat32Array()
	areas.resize(tri_count)
	for t in tri_count:
		var a := verts[indices[t * 3]]
		var b := verts[indices[t * 3 + 1]]
		var c := verts[indices[t * 3 + 2]]
		areas[t] = 0.5 * (b - a).cross(c - a).length()
	var sorted := areas.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2] if sorted.size() > 0 else 0.0
	var centroid := Vector3.ZERO
	for v in verts:
		centroid += v
	centroid /= maxf(1.0, float(verts.size()))

	var kept := PackedInt32Array()
	var removed := 0
	# 双面共面重复三角形：同一组焊接顶点只保留第一次出现的那一个，
	# 避免 z-fighting / 近景闪烁（shenyan 1118 个、linzhaowan 435 个）。
	var seen_tris: Dictionary = {}
	for t in tri_count:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var root := _find(parent, welded[ia])
		if not bool(keep_comp.get(root, true)):
			removed += 1
			continue
		var wa := welded[ia]
		var wb := welded[ib]
		var wc := welded[ic]
		var lo := mini(wa, mini(wb, wc))
		var hi := maxi(wa, maxi(wb, wc))
		var tri_key := Vector3i(lo, wa + wb + wc - lo - hi, hi)
		if seen_tris.has(tri_key):
			removed += 1
			continue
		seen_tris[tri_key] = true
		var area := areas[t]
		if area < MIN_TRI_AREA:
			removed += 1
			continue
		var ab := (b - a).length()
		var bc := (c - b).length()
		var ca := (a - c).length()
		var longest := maxf(ab, maxf(bc, ca))
		if longest > THIN_LONG_EDGE and (2.0 * area / longest) < THIN_HEIGHT:
			removed += 1
			continue
		var normal := (b - a).cross(c - a)
		if normal.length_squared() > 1e-16:
			normal = normal.normalized()
			var dir := ((a + b + c) / 3.0) - centroid
			if dir.length() > 0.01 and area < median * 0.5 \
					and normal.dot(dir.normalized()) < INWARD_DOT:
				removed += 1
				continue
		kept.append(ia)
		kept.append(ib)
		kept.append(ic)

	stats["removed_triangles"] = int(stats["removed_triangles"]) + removed
	if removed == 0:
		var out := arrays.duplicate()
		out[Mesh.ARRAY_INDEX] = kept
		return out
	return _compact(arrays, kept)

## 删除未引用顶点并重建所有顶点数组。
static func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var used: Dictionary = {}
	for i: int in indices:
		used[i] = true
	var remap: Dictionary = {}
	for i: int in used.keys():
		remap[i] = remap.size()
	var out := arrays.duplicate()
	for key: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		var src: Variant = arrays[key]
		if src == null:
			continue
		match key:
			Mesh.ARRAY_VERTEX:
				var dst := PackedVector3Array()
				for i: int in used.keys():
					dst.append((src as PackedVector3Array)[i])
				out[key] = dst
			Mesh.ARRAY_NORMAL:
				var dst := PackedVector3Array()
				for i: int in used.keys():
					dst.append((src as PackedVector3Array)[i])
				out[key] = dst
			Mesh.ARRAY_TANGENT:
				var dst := PackedFloat32Array()
				for i: int in used.keys():
					dst.append_array((src as PackedFloat32Array).slice(i * 4, i * 4 + 4))
				out[key] = dst
			Mesh.ARRAY_TEX_UV:
				var dst := PackedVector2Array()
				for i: int in used.keys():
					dst.append((src as PackedVector2Array)[i])
				out[key] = dst
			Mesh.ARRAY_COLOR:
				var dst := PackedColorArray()
				for i: int in used.keys():
					dst.append((src as PackedColorArray)[i])
				out[key] = dst
			Mesh.ARRAY_BONES:
				var src_b: PackedInt32Array = src
				var stride := 4
				if src_b.size() % 8 == 0 and src_b.size() / 8 == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
					stride = 8
				var dst := PackedInt32Array()
				for i: int in used.keys():
					for k in stride:
						dst.append(src_b[i * stride + k])
				out[key] = dst
			Mesh.ARRAY_WEIGHTS:
				var src_w: PackedFloat32Array = src
				var stride := 4
				if src_w.size() % 8 == 0 and src_w.size() / 8 == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
					stride = 8
				var dst := PackedFloat32Array()
				for i: int in used.keys():
					for k in stride:
						dst.append(src_w[i * stride + k])
				out[key] = dst
	var dst_idx := PackedInt32Array()
	dst_idx.resize(indices.size())
	for i in indices.size():
		dst_idx[i] = int(remap[indices[i]])
	out[Mesh.ARRAY_INDEX] = dst_idx
	return out

# ------------------------------------------------------------------ 工具

static func _find(parent: Array[int], x: int) -> int:
	var root := x
	while parent[root] != root:
		root = parent[root]
	while parent[x] != root:
		var next := parent[x]
		parent[x] = root
		x = next
	return root

static func _union(parent: Array[int], a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra

static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			chain.append(cur as Node3D)
		cur = cur.get_parent()
	var xf := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		xf = xf * chain[i].transform
	return xf

static func _albedo_texture(mat: Material) -> Texture2D:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_texture
	return null

## 纯色材质颜色；16×16 小贴图取平均色，避免丢掉武器配色。
static func _material_flat_color(mat: Material) -> Color:
	var base := Color.WHITE
	var tex: Texture2D = null
	if mat is BaseMaterial3D:
		base = (mat as BaseMaterial3D).albedo_color
		tex = (mat as BaseMaterial3D).albedo_texture
	if tex != null and maxi(tex.get_width(), tex.get_height()) <= FLAT_TEXTURE_MAX:
		var img := tex.get_image()
		if img != null:
			var sum := Color(0.0, 0.0, 0.0, 0.0)
			var w := img.get_width()
			var h := img.get_height()
			var count := 0
			for y in h:
				for x in w:
					sum += img.get_pixel(x, y)
					count += 1
			if count > 0:
				base *= Color(sum.r / count, sum.g / count, sum.b / count, 1.0)
	# 顶点色按线性空间存，shader 直接乘。
	return Color(base.r, base.g, base.b, 1.0).srgb_to_linear()
