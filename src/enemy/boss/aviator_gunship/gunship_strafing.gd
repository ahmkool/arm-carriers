extends GunshipState
## Phase 2's side switch: a red lane appears across the deck, straight ahead of the gunship, then it roars along it,
## low, to the opposite edge. Carriers in the lane as it passes are hit. The behavior has already set the new side.

const TELEGRAPH_SECONDS := 1.4
const SPEED := 20.0
## Half the lane's width: about the wingspan.
const LANE_HALF_WIDTH := 3.2
## How far ahead of and behind its centre the hull hits, along the lane.
const HIT_REACH := 3.0
const MAX_DASH_SECONDS := 4.0
const ARRIVE_DISTANCE := 1.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _elapsed := 0.0
var _hit := {}
var _lane: MeshInstance3D
var _lane_material: StandardMaterial3D


func enter() -> void:
	super.enter()
	var behavior := gunship()
	_from = enemy.global_position
	# The side has flipped, so the current lateral offset measured on it is the same line across the deck.
	_to = behavior.station_point(behavior.current_lateral())
	_elapsed = 0.0
	_hit.clear()
	_lane = enemy.get_node(^"StrafeLane") as MeshInstance3D
	_lane_material = _lane.get_active_material(0) as StandardMaterial3D
	_show_lane()


func exit() -> void:
	super.exit()
	_lane.visible = false


func is_dashing() -> bool:
	return _elapsed >= TELEGRAPH_SECONDS


func physics_update(delta: float) -> void:
	_elapsed += delta
	bank(delta)
	if _elapsed < TELEGRAPH_SECONDS:
		_hold(delta)
		return
	_dash(delta)
	_hit_carriers()
	if not _arrived():
		return
	gunship().finish_relocation()
	enemy_state_machine.transition_to("hovering")


## Holds at the start of the lane, nose down it, while the lane pulses.
func _hold(delta: float) -> void:
	fly_toward(_from, gunship().strafe_speed, delta)
	face(_direction(), delta * 3.0)
	_lane_material.albedo_color.a = 0.18 + 0.14 * absf(sin(_elapsed * 9.0))


func _dash(delta: float) -> void:
	var to_end := _to - enemy.global_position
	var flat := Vector3(to_end.x, 0.0, to_end.z)
	var step := minf(SPEED, flat.length() / maxf(delta, 0.001))
	var velocity := flat.normalized() * step if flat.length() > 0.001 else Vector3.ZERO
	enemy.velocity = Vector3(velocity.x, clampf(to_end.y * ALTITUDE_GAIN, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED), velocity.z)
	_lane_material.albedo_color.a = 0.35


func _hit_carriers() -> void:
	var direction := _direction()
	for player in _living_players():
		if _hit.has(player):
			continue
		var offset := player.global_position - enemy.global_position
		var flat := Vector3(offset.x, 0.0, offset.z)
		var along := flat.dot(direction)
		var across := (flat - direction * along).length()
		if absf(along) > HIT_REACH or across > LANE_HALF_WIDTH:
			continue
		_hit[player] = true
		if Health.apply_damage(player, gunship().strafe_damage, enemy.global_position):
			CameraFeedback.add_trauma_hurt()


func _arrived() -> bool:
	if _elapsed > TELEGRAPH_SECONDS + MAX_DASH_SECONDS:
		return true
	var off := _to - enemy.global_position
	return Vector2(off.x, off.z).length() <= ARRIVE_DISTANCE


func _direction() -> Vector3:
	var flat := Vector3(_to.x - _from.x, 0.0, _to.z - _from.z)
	if flat.length_squared() < 0.0001:
		return -enemy.global_basis.z
	return flat.normalized()


## A flat red strip on the deck from the gunship's start to its end, as wide as the lane.
func _show_lane() -> void:
	var direction := _direction()
	var length := Vector2(_to.x - _from.x, _to.z - _from.z).length()
	var middle := (_from + _to) * 0.5
	middle.y = gunship().floor_y() + 0.06
	var lane_basis := Basis.looking_at(direction, Vector3.UP) * Basis.from_scale(Vector3(LANE_HALF_WIDTH * 2.0, 1.0, length))
	_lane.global_transform = Transform3D(lane_basis, middle)
	_lane.visible = true


func _living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var players := enemy._get_players_node()
	if players == null:
		return living
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		living.append(player)
	return living
