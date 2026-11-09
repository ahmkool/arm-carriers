extends MechState
## Grenade shot: brakes, levels the launcher at the target, and fires grenades straight at it; each leaves the barrel
## flat and dips onto where the carrier stood (see `MechGrenade.launch_flat`). Then hands back to `return_state`.
## The ring and fuse leave time to step clear.

const LAUNCH_SOUND := preload("res://assets/sounds/bazooka_shot.wav")

@export var muzzle_node: Node3D
@export var grenade_scene: PackedScene
## The launcher's drum, turned a chamber's worth after each shot.
@export var drum: Node3D
@export var return_state := &"standing"
@export var grenade_count := 1
## Delay before the first grenade, so the stop and the levelled launcher read as a tell.
@export var aim_seconds := 0.6
@export var seconds_between_grenades := 0.5
@export var hold_after_seconds := 0.6
@export var brake := 8.0
## Grenade speed out of the barrel, in metres per second.
@export var launch_speed := 12.0
@export var recoil_kick_degrees := 6.0
@export var recoil_recovery := 7.0
## Grenades after the first land this far to either side of the target, so a volley covers ground.
@export var volley_spread := 1.8

var _grenades_left := 0
var _next_in := 0.0
var _hold_remaining := 0.0
var _recoil_degrees := 0.0
var _drum_turn_left := 0.0


func enter() -> void:
	super.enter()
	_grenades_left = grenade_count
	_next_in = aim_seconds
	_hold_remaining = hold_after_seconds
	_recoil_degrees = 0.0


func exit() -> void:
	aim_direction_override = Vector3.ZERO


func physics_update(delta: float) -> void:
	var w := 1.0 - exp(-brake * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, 0.0, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, 0.0, w)
	hold_height(delta)
	_recoil_degrees *= exp(-recoil_recovery * delta)
	aim_direction_override = _arc_direction()
	aim_gun(delta, _recoil_degrees)
	_turn_drum(delta)
	if _grenades_left > 0:
		_tick_volley(delta)
		return
	_hold_remaining -= delta
	if _hold_remaining > 0.0:
		return
	enemy_state_machine.transition_to(String(return_state))


## Level, toward the target: the launcher is held flat rather than tipped up.
func _arc_direction() -> Vector3:
	if not has_aim():
		return Vector3.ZERO
	var to_target := enemy.target_player.global_position - muzzle_node.global_position
	return Vector3(to_target.x, 0.0, to_target.z).normalized()


func _landing_spot(side: float) -> Vector3:
	var spot := enemy.target_player.global_position
	if is_zero_approx(side):
		return spot
	var to_target := spot - enemy.global_position
	var across := Vector3(-to_target.z, 0.0, to_target.x).normalized()
	return spot + across * side


func _tick_volley(delta: float) -> void:
	_next_in -= delta
	if _next_in > 0.0:
		return
	_next_in = seconds_between_grenades
	var index := grenade_count - _grenades_left
	_grenades_left -= 1
	_fire(_volley_side(index))


## 0 for the first grenade, then alternating sides.
func _volley_side(index: int) -> float:
	if index == 0:
		return 0.0
	var direction := 1.0 if index % 2 == 1 else -1.0
	return direction * volley_spread * ceilf(index / 2.0)


func _fire(side: float) -> void:
	_recoil_degrees = recoil_kick_degrees
	_drum_turn_left += TAU / 6.0
	if not has_aim() or grenade_scene == null:
		return
	var grenade := grenade_scene.instantiate() as MechGrenade
	var scene_root := enemy.get_tree().current_scene
	scene_root.add_child(grenade)
	grenade.global_position = muzzle_node.global_position
	grenade.launch_flat(muzzle_node.global_position, _landing_spot(side), launch_speed)
	_play_launch_sound()


func _turn_drum(delta: float) -> void:
	if drum == null or _drum_turn_left <= 0.0:
		return
	var step := minf(_drum_turn_left, TAU * 1.5 * delta)
	_drum_turn_left -= step
	drum.rotate_object_local(Vector3.BACK, step)


func _play_launch_sound() -> void:
	var sfx := AudioStreamPlayer3D.new()
	enemy.get_tree().current_scene.add_child(sfx)
	sfx.global_position = muzzle_node.global_position
	sfx.bus = "SFX"
	sfx.stream = LAUNCH_SOUND
	sfx.pitch_scale = 1.5
	sfx.volume_db = -4.0
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
