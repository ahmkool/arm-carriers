class_name SwordSlash
extends Node3D
## Bright streak across an enemy that a sword strike just hit.

const DURATION_SEC := 0.14
const MAX_TILT_RADIANS := 0.45
const START_SCALE := Vector3(0.6, 0.16, 0.16)
const END_SCALE := Vector3(3.0, 0.01, 0.01)

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_mesh.scale = START_SCALE
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mesh, "scale", END_SCALE, DURATION_SEC)
	tween.tween_callback(queue_free)


## Lines the streak up with the blade's travel, with a random tilt so hits don't look alike.
func align_to(travel_direction: Vector3) -> void:
	var flat := Vector3(travel_direction.x, 0.0, travel_direction.z)
	if flat.length_squared() < 0.0001:
		return
	var along := flat.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var tilted := along.rotated(side, randf_range(-MAX_TILT_RADIANS, MAX_TILT_RADIANS))
	var up := side.cross(tilted).normalized()
	global_basis = Basis(tilted, up, side)
