extends "res://src/enemy/state/dead.gd"
## Death for a flyer: the shared death sequence, but the wreck drops out of the air onto the floor below.

const GRAVITY := 20.0
const FLOOR_MASK := 4
const FLOOR_PROBE_DEPTH := 60.0

var _floor_y := -INF


func enter() -> void:
	_floor_y = _probe_floor_y()
	super.enter()


func physics_update(delta: float) -> void:
	super.physics_update(delta)
	enemy.velocity.y -= GRAVITY * delta
	if enemy.global_position.y + enemy.velocity.y * delta > _floor_y:
		return
	enemy.global_position.y = _floor_y
	enemy.velocity.y = 0.0


## Collisions are off while dead, so the floor is found once with a ray. Over a pit there is none: it falls away.
func _probe_floor_y() -> float:
	var from := enemy.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_PROBE_DEPTH, FLOOR_MASK)
	var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -INF
	return (hit.position as Vector3).y
