class_name AimedBoltEmitter
extends FireballEmitter
## A muzzle that aims in 3D, for a shooter above its target. FireballEmitter aims flat, which would fly over the
## carriers' heads.

@export var shooter: EnemyLocal
## Point on the target to aim at, above its feet.
@export var aim_height := 0.9


func _get_launch_direction() -> Vector3:
	if shooter == null or not is_instance_valid(shooter.target_player):
		return -global_basis.z.normalized()
	var aim_point := shooter.target_player.global_position + Vector3.UP * aim_height
	var to_target := aim_point - global_position
	if to_target.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_target.normalized()
