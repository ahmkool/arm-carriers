class_name CatapultOperatorBehavior
extends EnemyBehavior
## Works a SiegeCatapult (a child of the enemy): picks the throw that lands nearest the nearer carrier, walks to the
## spot behind the catapult that gives it (round the stake to turn it, nearer or further to change the angle), stands
## still with a faint ring on the landing spot while he lines it up, then throws. Faces the stake throughout.

## Seconds between fresh aims; the carriers can move off the spot in between.
@export var aim_interval := 0.35
## Standing on his spot this long before a throw: the warning.
@export var settle_seconds := 0.8
@export var cooldown := 3.5
@export var cooldown_jitter := 1.0
## Throws landing further than this from the carrier aren't worth making: out of reach, or blocked.
@export var max_aim_error := 2.0
@export var arrive_distance := 0.35

var _catapult: SiegeCatapult
var _aim := {}
var _aim_left := 0.0
var _settled := 0.0
var _cooldown_left := 0.0


func _ready() -> void:
	super._ready()
	_catapult = _find_catapult()
	_cooldown_left = cooldown


func _find_catapult() -> SiegeCatapult:
	for child in enemy.get_children():
		if child is SiegeCatapult:
			return child as SiegeCatapult
	return null


func _think(delta: float) -> void:
	if not _can_work():
		return
	_cooldown_left -= delta
	_refresh_aim(delta)
	intent.face_direction = _toward_stake()
	if not _has_throw():
		_catapult.hide_aim()
		return
	var spot := _catapult.spot_for(_aim.gap, enemy.target_player.global_position)
	if _flat_distance(enemy.global_position, spot) > arrive_distance:
		_settled = 0.0
		_catapult.hide_aim()
		intent.move_direction = enemy.get_path_direction_to(spot)
		return
	_settled += delta
	_catapult.show_aim(_aim.landing)
	if _settled < settle_seconds or _cooldown_left > 0.0:
		return
	if not _catapult.fire():
		return
	_settled = 0.0
	_cooldown_left = cooldown + randf_range(-cooldown_jitter, cooldown_jitter)


func _can_work() -> bool:
	if enemy == null or not enemy.is_offensive or _catapult == null:
		return false
	if not is_instance_valid(enemy.target_player) or enemy.target_player.is_dead:
		enemy.update_target_player()
	return is_instance_valid(enemy.target_player)


func _refresh_aim(delta: float) -> void:
	_aim_left -= delta
	if _aim_left > 0.0:
		return
	_aim_left = aim_interval
	_aim = _catapult.aim_at(enemy.target_player.global_position)


func _has_throw() -> bool:
	return not _aim.is_empty() and float(_aim.error) <= max_aim_error


func _toward_stake() -> Vector3:
	var to_stake := _catapult.stake_position() - enemy.global_position
	to_stake.y = 0.0
	if to_stake.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_stake.normalized()


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
