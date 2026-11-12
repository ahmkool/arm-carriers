extends GunshipState
## Default state: holds its side of the arena, drifting along the edge to stay level with the carriers.
## Before the fight starts it holds its spot.


func physics_update(delta: float) -> void:
	var behavior := gunship()
	if behavior == null:
		return
	var lateral := behavior.players_lateral() if enemy.is_offensive else behavior.current_lateral()
	fly_toward(behavior.station_point(lateral), behavior.strafe_speed, delta)
	face(behavior.facing(), delta)
	bank(delta)
