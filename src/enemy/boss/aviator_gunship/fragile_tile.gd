class_name FragileTile
extends StaticBody3D
## One piece of the gunship fight's fragile tracks: a plank (or a round pad at a turn) that holds the carriers
## until one steps on it, then shakes and reddens for `fuse_seconds` and falls away. Built in code by GunshipCourse.

const FLOOR_LAYER := 4
const FALL_DEPTH := 26.0
const FALL_SECONDS := 1.6
const RISE_SECONDS := 0.45
const SHAKE := 0.05
const HOT_COLOR := Color(1.0, 0.25, 0.1)
const SEAM := 0.1

var fuse_seconds := 3.0
var _fuse_left := -1.0
var _falling := false
var _base_color := Color.WHITE
var _rest := Vector3.ZERO
var _visual: MeshInstance3D
var _shape: CollisionShape3D
var _material: StandardMaterial3D


## A plank `length` long (along its local -z) and `width` wide, its top surface at the node's origin.
static func make_plank(length: float, width: float, thickness: float, fuse: float, material: StandardMaterial3D) -> FragileTile:
	var tile := FragileTile.new()
	var box := BoxMesh.new()
	# A thin seam between planks, so the track reads as pieces; the collision has none.
	box.size = Vector3(width, thickness, maxf(length - SEAM, 0.1))
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, length)
	tile._build(box, shape, thickness, fuse, material)
	return tile


## A round pad covering the joint at a turn, its top a little above the planks'.
static func make_pad(radius: float, thickness: float, fuse: float, material: StandardMaterial3D) -> FragileTile:
	var tile := FragileTile.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = thickness
	cylinder.radial_segments = 12
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = thickness
	tile._build(cylinder, shape, thickness, fuse, material)
	return tile


func _build(mesh: Mesh, shape: Shape3D, thickness: float, fuse: float, material: StandardMaterial3D) -> void:
	collision_layer = FLOOR_LAYER
	collision_mask = 0
	fuse_seconds = fuse
	set_meta(&"footstep_surface", &"metal")
	_material = material.duplicate() as StandardMaterial3D
	_base_color = _material.albedo_color
	_visual = MeshInstance3D.new()
	_visual.mesh = mesh
	_visual.material_override = _material
	_visual.position = Vector3.DOWN * thickness * 0.5
	add_child(_visual)
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position = _visual.position
	add_child(_shape)
	_rest = _visual.position


func is_lit() -> bool:
	return _fuse_left >= 0.0 or _falling


func is_falling() -> bool:
	return _falling


## A carrier stepped on it: start the fuse, once.
func step_on() -> void:
	if is_lit():
		return
	_fuse_left = fuse_seconds


## Rises from below into place after `delay`, with no collision until it arrives.
func rise(delay: float) -> void:
	_shape.disabled = true
	_visual.visible = false
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_show_lowered)
	tween.tween_property(_visual, "position", _rest, RISE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_shape.set_disabled.bind(false))


func _show_lowered() -> void:
	_visual.visible = true
	_visual.position = _rest + Vector3.DOWN * 5.0


func _physics_process(delta: float) -> void:
	if _falling or _fuse_left < 0.0:
		return
	_fuse_left -= delta
	var heat := 1.0 - clampf(_fuse_left / maxf(fuse_seconds, 0.01), 0.0, 1.0)
	_material.albedo_color = _base_color.lerp(HOT_COLOR, heat)
	_visual.position = _rest + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * SHAKE * heat
	if _fuse_left > 0.0:
		return
	_fall()


func _fall() -> void:
	_falling = true
	_shape.set_deferred("disabled", true)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * 2.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_visual, "position:y", _rest.y - FALL_DEPTH, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "rotation", spin, FALL_SECONDS)
	tween.chain().tween_callback(queue_free)
