extends GunshipState
## Runs one gunship move while it keeps flying its side of the arena. Timing lives here; what each shot does to
## the world lives in GunshipMoves.
##
## guns: spin up, then alternate the two gatlings at the nearer carrier.
## rockets: launch from the wing pods in turn; each one marks where it will land.
## laser: charge (an aim line shows the beam's path), then fire straight across the arena while sliding slowly
## along the edge towards the carriers.

## start: seconds before the first shot. count: shots. every: seconds between shots. duration: whole move.
const SHOTS := {
	&"guns": {"start": 0.55, "count": 10, "every": 0.14, "duration": 2.3},
	&"rockets": {"start": 0.5, "count": 4, "every": 0.35, "duration": 2.1},
}
const LASER_CHARGE_SECONDS := 1.3
const LASER_FIRE_SECONDS := 3.5
const LASER_COOL_SECONDS := 0.5

var _move: StringName = &""
var _elapsed := 0.0
var _shots_fired := 0
var _laser_on := false
var _moves: GunshipMoves


func enter() -> void:
	super.enter()
	_moves = enemy.get_node("GunshipMoves") as GunshipMoves
	_move = gunship().intent.requested_attack
	_elapsed = 0.0
	_shots_fired = 0
	_laser_on = false
	_moves.begin_move(_move)


func exit() -> void:
	super.exit()
	_moves.end_move()


func current_move() -> StringName:
	return _move


func physics_update(delta: float) -> void:
	_elapsed += delta
	_steer(delta)
	_run_move(delta)
	if _elapsed < _duration():
		return
	enemy_state_machine.transition_to("hovering")


func _run_move(delta: float) -> void:
	if _move == AviatorGunshipBehavior.MOVE_LASER:
		_run_laser(delta)
		return
	_run_shots()


func _duration() -> float:
	if _move == AviatorGunshipBehavior.MOVE_LASER:
		return LASER_CHARGE_SECONDS + LASER_FIRE_SECONDS + LASER_COOL_SECONDS
	return SHOTS[_move]["duration"]


func _steer(delta: float) -> void:
	var behavior := gunship()
	face(behavior.facing(), delta)
	bank(delta)
	fly_toward(behavior.station_point(_wanted_lateral()), _wanted_speed(), delta)


## While charging the laser it holds still, so the aim line shows where the beam will start.
func _wanted_lateral() -> float:
	var behavior := gunship()
	if _move == AviatorGunshipBehavior.MOVE_LASER and _elapsed < LASER_CHARGE_SECONDS:
		return behavior.current_lateral()
	return behavior.players_lateral()


func _wanted_speed() -> float:
	var behavior := gunship()
	if _move == AviatorGunshipBehavior.MOVE_LASER:
		return behavior.laser_slide_speed()
	return behavior.move_speed(true)


func _run_shots() -> void:
	var timing: Dictionary = SHOTS[_move]
	_moves.spin_guns(_move == AviatorGunshipBehavior.MOVE_GUNS, get_physics_process_delta_time())
	if _shots_fired >= timing["count"]:
		return
	if _elapsed < timing["start"] + timing["every"] * _shots_fired:
		return
	_fire_shot(_shots_fired)
	_shots_fired += 1


func _fire_shot(index: int) -> void:
	match _move:
		AviatorGunshipBehavior.MOVE_GUNS:
			_moves.fire_gun(index)
		AviatorGunshipBehavior.MOVE_ROCKETS:
			_moves.launch_rocket(index)


func _run_laser(delta: float) -> void:
	if _elapsed < LASER_CHARGE_SECONDS:
		_moves.charge_laser(_elapsed / LASER_CHARGE_SECONDS)
		return
	if _elapsed < LASER_CHARGE_SECONDS + LASER_FIRE_SECONDS:
		_laser_on = true
		_moves.fire_laser(delta)
		return
	if not _laser_on:
		return
	_laser_on = false
	_moves.stop_laser()
