class_name SwordTrail
extends Node3D
## Ribbon swept by the blade during a strike, drawn in world space so it stays behind the
## moving sword. Fed by `SwordSpecifics`.

const FADE_SEC := 0.2
const COLOR := Color(1.0, 0.93, 0.75)
const BASE_ALPHA := 0.25
const TIP_ALPHA := 0.9

var _bases: Array[Vector3] = []
var _tips: Array[Vector3] = []
var _ages: Array[float] = []
var _immediate_mesh: ImmediateMesh

@onready var _mesh_instance: MeshInstance3D = $Mesh


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh


## Drops any fading ribbon so two strikes never join into one strip.
func begin_stroke() -> void:
	_bases.clear()
	_tips.clear()
	_ages.clear()


func add_sample(base: Vector3, tip: Vector3) -> void:
	_bases.append(base)
	_tips.append(tip)
	_ages.append(0.0)


func _process(delta: float) -> void:
	for index in _ages.size():
		_ages[index] += delta
	_remove_expired_samples()
	_rebuild_mesh()


func _remove_expired_samples() -> void:
	while not _ages.is_empty() and _ages[0] >= FADE_SEC:
		_bases.remove_at(0)
		_tips.remove_at(0)
		_ages.remove_at(0)


func _rebuild_mesh() -> void:
	_immediate_mesh.clear_surfaces()
	if _ages.size() < 2:
		return
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in _ages.size():
		var life := 1.0 - _ages[index] / FADE_SEC
		_immediate_mesh.surface_set_color(Color(COLOR, BASE_ALPHA * life))
		_immediate_mesh.surface_add_vertex(_bases[index])
		_immediate_mesh.surface_set_color(Color(COLOR, TIP_ALPHA * life))
		_immediate_mesh.surface_add_vertex(_tips[index])
	_immediate_mesh.surface_end()
