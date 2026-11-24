class_name SheathFollow
extends Node3D
## Keeps the sheathed sword on the character's left back in *model* space.
## Parenting to spine/chest made the scabbard swing to the front or side
## whenever those bones twisted, because the offset was in bone-local axes.
##
## ShenyanBackSword's visual blade is *not* along local +Y: the mesh origin
## is the scabbard mouth, the tip is about (-0.17, -0.67, 0.24), and the
## pommel sits near (0.05, 0.19, -0.06). This node maps that real blade
## onto a diagonal on the left back, mouth at the shoulder, tip at the
## hip, close to the robe.

var model: Node3D
var skeleton: Skeleton3D
var following := true

## Chest-relative mouth (mesh origin), in model space: +X left, +Y up, −Z back.
var local_offset := Vector3(0.12, 0.10, -0.20)
var local_basis := Basis.IDENTITY

## Measured on ShenyanBackSword (vertex clusters, not the loose AABB).
const HILT := Vector3(0.0, 0.0, 0.0)
const TIP := Vector3(-0.1736, -0.6718, 0.2434)

func _ready() -> void:
	process_priority = 80
	# Mouth → tip in model space: toward the spine (−X) and down, almost
	# no extra back so the tip stays on the robe instead of flying out.
	var want := Vector3(-0.28, -0.95, 0.08).normalized()
	var blade := (TIP - HILT).normalized()
	var mesh_side := blade.cross(Vector3.RIGHT)
	if mesh_side.length() < 0.15:
		mesh_side = blade.cross(Vector3.UP)
	mesh_side = mesh_side.normalized()
	var mesh_n := blade.cross(mesh_side).normalized()
	# "Out the back" stays in the plane of the back, not along the blade.
	var model_side := want.cross(Vector3(0.0, 0.0, -1.0))
	if model_side.length() < 0.15:
		model_side = want.cross(Vector3.UP)
	model_side = model_side.normalized()
	var model_n := want.cross(model_side).normalized()
	# Prefer the side that keeps the scabbard on the left back.
	if model_n.dot(Vector3(0.0, 0.0, -1.0)) < 0.0:
		model_side = -model_side
		model_n = -model_n
	var mesh_b := Basis(mesh_side, blade, mesh_n)
	var model_b := Basis(model_side, want, model_n)
	local_basis = (model_b * mesh_b.inverse()).orthonormalized()


func _process(_delta: float) -> void:
	if not following or model == null or skeleton == null:
		return
	if not is_inside_tree() or not model.is_inside_tree():
		return
	var chest := skeleton.find_bone("chest")
	if chest < 0:
		chest = skeleton.find_bone("spine")
	if chest < 0:
		return
	var chest_pos := (skeleton.global_transform * skeleton.get_bone_global_pose(chest)).origin
	var basis := model.global_transform.basis
	global_position = chest_pos + basis * local_offset
	global_basis = (basis * local_basis).orthonormalized()
