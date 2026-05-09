extends PlayerState

const DASH_DURATION_SEC := 0.04
const DASH_SPEED := 25.0

var _dash_time_remaining := 0.0
var _dash_direction := Vector3.ZERO


func enter() -> void:
	CameraFeedback.add_trauma_dash()
	_dash_time_remaining = DASH_DURATION_SEC
	_dash_direction = _get_dash_direction()
	player.velocity.y = 0.0
	player.velocity.x = _dash_direction.x * DASH_SPEED
	player.velocity.z = _dash_direction.z * DASH_SPEED


func exit() -> void:
	_dash_time_remaining = 0.0

func physics_update(delta: float) -> void:
	if not player.is_on_floor():
		player_state_machine.transition_to("falling")
		return

	_dash_time_remaining = maxf(0.0, _dash_time_remaining - delta)
	player.velocity.x = _dash_direction.x * DASH_SPEED
	player.velocity.z = _dash_direction.z * DASH_SPEED
	if _dash_direction.length_squared() > 0.0001:
		player.look_at(player.global_position + _dash_direction, Vector3.UP)

	if _dash_time_remaining > 0.0:
		return

	var direction := player.get_move_direction()
	if direction.length_squared() > 0.0001:
		player_state_machine.transition_to("running")
		return
	player_state_machine.transition_to("idle")


func _get_dash_direction() -> Vector3:
	var direction := player.get_move_direction()
	if direction.length_squared() > 0.0001:
		return direction
	var facing_forward := -player.global_transform.basis.z
	facing_forward.y = 0.0
	if facing_forward.length_squared() > 0.0001:
		return facing_forward.normalized()
	return Vector3.FORWARD
