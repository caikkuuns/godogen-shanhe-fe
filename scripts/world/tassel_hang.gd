class_name TasselHang
extends Node3D
## Soft scabbard tassel: hangs world-down from the pommel and lags behind
## the scabbard's motion. Child segments are named SwordTasselSeg* and are
## aimed with increasing droop so the cord reads as a bent tassel, not a rod.

var segments: Array[Node3D] = []
var _dir := Vector3.DOWN
var _prev_origin := Vector3.ZERO
var _have_prev := false

func _ready() -> void:
	process_priority = 90
	set_process(true)
	if segments.is_empty():
		_collect_segments()


func _collect_segments() -> void:
	segments.clear()
	var n: Node = self
	while n != null:
		var next: Node3D = null
		for child in n.get_children():
			if child is Node3D and str(child.name).begins_with("SwordTasselSeg"):
				next = child
				break
		if next == null:
			break
		segments.append(next)
		n = next


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if segments.is_empty():
		_collect_segments()
	var origin := global_position
	var inertia := Vector3.ZERO
	if _have_prev and delta > 0.0001:
		inertia = (origin - _prev_origin) / delta
	_prev_origin = origin
	_have_prev = true
	# Hang off the pommel, not back down the handle. Reject the scabbard
	# axis so the cord stays visible as a soft J even in a still frame.
	var rest := Vector3.DOWN
	var sword := get_parent() as Node3D
	if sword != null:
		var down_handle := sword.to_global(Vector3.ZERO) - global_position
		if down_handle.length() > 0.02:
			var axis := down_handle.normalized()
			var off := Vector3.DOWN - axis * Vector3.DOWN.dot(axis)
			if off.length() < 0.2:
				off = axis.cross(Vector3.BACK)
				if off.length() < 0.2:
					off = axis.cross(Vector3.RIGHT)
			# Lean the top out ~40° and keep a little world-down so lower
			# segments can droop into a J.
			rest = (off.normalized() * 1.10 + Vector3.DOWN * 0.32).normalized()
	var desired := (rest * 9.0 - inertia * 0.28)
	if desired.length() < 0.001:
		desired = rest
	desired = desired.normalized()
	var ang := Vector3.DOWN.angle_to(desired)
	if ang > 0.70:
		desired = Vector3.DOWN.slerp(desired, 0.70 / ang)
	_dir = _dir.slerp(desired, clampf(delta * 7.0, 0.0, 1.0)).normalized()
	_aim_node(self, _dir)
	# Each lower segment droops a little more toward world-down and lags.
	var dir := _dir
	for i in segments.size():
		var droop := 0.34 + 0.22 * float(i)
		dir = dir.slerp(Vector3.DOWN, clampf(droop, 0.0, 0.8)).normalized()
		_aim_node(segments[i], dir)


func _aim_node(node: Node3D, aim: Vector3) -> void:
	if node == null or not node.is_inside_tree():
		return
	# Local +Y points at the parent (opposite the hang direction) so a
	# cylinder of height H placed at (0, -H/2, 0) hangs along `aim`.
	var y := -aim
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.2:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var world_b := Basis(x, y, z).orthonormalized()
	if node == self:
		node.global_basis = world_b
		return
	var parent := node.get_parent() as Node3D
	if parent == null:
		return
	# Keep the authored local offset (half a segment down the parent) and
	# only change rotation, so the cord stays connected.
	node.basis = (parent.global_transform.basis.inverse() * world_b).orthonormalized()
