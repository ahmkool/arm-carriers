class_name WingedMechBehavior
extends EnemyBehavior
## Hovers above the carriers, slowly circling the middle of the pair, and picks between a gun burst and a dash.
## The states (`src/enemy/winged_mech/`) read the hover altitude and dash tuning from here.

@export_group("Hover")
## How far from the middle of the players the mech circles, flat. Kept inside the gameplay camera's view.
@export var orbit_radius := 10.0
## The orbit's reach on the camera's side (+z). The camera sits south of the carriers looking north, so a mech as far
## south as `orbit_radius`, and hovering, leaves the bottom of the screen. The ring eases between the two.
@export var camera_side_radius := 7.0
## Height of the mech's feet above the targeted player's. Low enough that the carriers' shots, which fly about a
## metre up, still reach its hurt box.
@export var hover_height := 0.6
## Up-and-down bob while hovering, in metres.
@export var bob_amplitude := 0.25
@export var bob_speed := 2.0
## How often, in seconds, the mech may flip the way it circles.
@export var orbit_flip_interval_min := 4.0
@export var orbit_flip_interval_max := 8.0
## Outside its ring it flies faster, up to this many times its speed, so it keeps up with carriers who run off or
## ride a moving barge. Each metre beyond the ring adds a third of its speed.
@export var catch_up_max := 3.0

@export_group("Attacks")
## Seconds after waking before the first attack.
@export var first_attack_delay := 1.5
@export var attack_cooldown_min := 2.0
@export var attack_cooldown_max := 3.5
## Chance that an attack is a dash instead of a gun burst. Never two dashes in a row.
@export_range(0.0, 1.0) var dash_chance := 0.4
## The gun only fires at a target within this flat distance.
@export var shoot_max_distance := 26.0
## The dash only starts when the target is within this flat distance.
@export var dash_max_distance := 20.0

@export_group("Dash")
@export var dash_windup_seconds := 0.7
@export var dash_speed := 22.0
## How far past the locked target point the dash keeps going.
@export var dash_overshoot := 4.0
@export var dash_max_seconds := 1.4
@export var dash_recover_seconds := 0.6
## Lowest height above the target's feet the dash flies at, so it skims the ground instead of diving into it.
@export var dash_floor_clearance := 0.9

var _orbit_sign := 1.0
var _orbit_flip_remaining := 0.0
var _attack_cooldown_remaining := 0.0
var _last_attack := &""
var _was_offensive := false
var _home_y := 0.0
var _has_home_y := false
var _bob_time := 0.0
## Height the hover state steers toward this frame.
var desired_altitude := 0.0
## Multiplier on the hover speed this frame: above 1 while catching up with its ring.
var speed_scale := 1.0


func _ready() -> void:
	super._ready()
	_orbit_sign = 1.0 if randf() < 0.5 else -1.0
	_orbit_flip_remaining = randf_range(orbit_flip_interval_min, orbit_flip_interval_max)


func _think(delta: float) -> void:
	if enemy == null:
		return
	_remember_home_altitude()
	_bob_time += delta
	desired_altitude = _home_y + _bob_offset()
	speed_scale = 1.0
	if _is_busy():
		return
	if not enemy.is_offensive:
		_was_offensive = false
		return
	_on_wake_up()
	_refresh_target()
	if not is_instance_valid(enemy.target_player):
		return
	_tick_timers(delta)
	_steer_orbit()
	_try_attack()


func _remember_home_altitude() -> void:
	if _has_home_y:
		return
	_home_y = enemy.global_position.y
	_has_home_y = true


func _bob_offset() -> float:
	return sin(_bob_time * bob_speed) * bob_amplitude


## The attack states run on their own; the behaviour waits for them to hand control back.
func _is_busy() -> bool:
	var machine := enemy.enemy_state_machine
	if machine == null:
		return true
	return machine.is_in_state("dead") or machine.is_in_state("shooting") or machine.is_in_state("dashing")


func _on_wake_up() -> void:
	if _was_offensive:
		return
	_was_offensive = true
	_attack_cooldown_remaining = first_attack_delay


## Always the nearer living carrier, so the gun and the dash go for whoever strays closest.
func _refresh_target() -> void:
	enemy.update_target_player()


func _tick_timers(delta: float) -> void:
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	_orbit_flip_remaining -= delta
	if _orbit_flip_remaining > 0.0:
		return
	_orbit_sign = -_orbit_sign
	_orbit_flip_remaining = randf_range(orbit_flip_interval_min, orbit_flip_interval_max)


## Circles the middle of the living players at `orbit_radius`, easing in or out to hold that ring.
func _steer_orbit() -> void:
	var centre := _players_centre()
	var target := enemy.target_player
	desired_altitude = target.global_position.y + hover_height + _bob_offset()
	intent.face_direction = _flat(target.global_position - enemy.global_position)
	var from_centre := _flat(enemy.global_position - centre)
	var distance := from_centre.length()
	if distance < 0.0001:
		intent.move_direction = Vector3.FORWARD
		return
	var outward := from_centre / distance
	var tangent := Vector3(-outward.z, 0.0, outward.x) * _orbit_sign
	var radius := lerpf(orbit_radius, camera_side_radius, maxf(outward.z, 0.0))
	var radial_error := clampf((distance - radius) / 2.0, -1.0, 1.0)
	intent.move_direction = (tangent - outward * radial_error).normalized()
	speed_scale = clampf(1.0 + (distance - radius) / 3.0, 1.0, catch_up_max)


func _try_attack() -> void:
	if _attack_cooldown_remaining > 0.0:
		return
	var attack := _pick_attack()
	if attack.is_empty():
		return
	_last_attack = attack
	_attack_cooldown_remaining = randf_range(attack_cooldown_min, attack_cooldown_max)
	intent.requested_locomotion = attack


func _pick_attack() -> StringName:
	var distance := _flat(enemy.target_player.global_position - enemy.global_position).length()
	if _wants_dash(distance):
		return &"dashing"
	if distance <= shoot_max_distance:
		return &"shooting"
	return &""


func _wants_dash(distance: float) -> bool:
	if enemy.holds_position:
		return false
	if _last_attack == &"dashing":
		return false
	if distance > dash_max_distance:
		return false
	return randf() < dash_chance


func _players_centre() -> Vector3:
	var players_node := enemy._get_players_node()
	if players_node == null:
		return enemy.target_player.global_position
	var sum := Vector3.ZERO
	var count := 0
	for child in players_node.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		sum += player.global_position
		count += 1
	if count == 0:
		return enemy.target_player.global_position
	return sum / count


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
