class_name Health
extends Node

signal damaged(amount: int, remaining: int, source_position: Vector3)
signal died(source_position: Vector3)
signal restored

@export var max_hp: int = 3

var current_hp: int
var _invulnerable_time_remaining := 0.0
## While up, takes every hit in place of this health (see `EnemyShield`).
var shield: EnemyShield
## Blocks hits that come from in front of the enemy (see `FrontalGuard`).
var guard: FrontalGuard

func get_scene_max_hp() -> int:
	print("Getting scene max HP for ", self, " with max_hp ", max_hp)
	return max_hp


func _ready() -> void:
	DevSettings.apply_to_health(self)
	reset_to_full()


func _process(delta: float) -> void:
	if _invulnerable_time_remaining <= 0.0:
		return
	_invulnerable_time_remaining = maxf(0.0, _invulnerable_time_remaining - delta)


func is_alive() -> bool:
	return current_hp > 0


func is_invulnerable() -> bool:
	return _invulnerable_time_remaining > 0.0


func grant_invulnerability(duration: float) -> void:
	_invulnerable_time_remaining = maxf(_invulnerable_time_remaining, duration)


func reset_to_full() -> void:
	current_hp = max_hp
	_invulnerable_time_remaining = 0.0
	restored.emit()


## Returns true only when the damage landed (target alive and not invulnerable).
func take_damage(amount: int, source_position: Vector3 = Vector3.ZERO) -> bool:
	if not is_alive():
		return false
	if is_invulnerable():
		return false
	if is_instance_valid(shield) and shield.is_up():
		shield.absorb(source_position)
		return false
	if is_instance_valid(guard) and guard.blocks(source_position):
		guard.absorb(source_position)
		return false
	var applied := mini(amount, current_hp)
	current_hp -= applied
	damaged.emit(applied, current_hp, source_position)
	if current_hp <= 0:
		died.emit(source_position)
	return true


## Ends the target outright, ignoring invulnerability, such as when it falls out of the level.
func kill(source_position: Vector3 = Vector3.ZERO) -> void:
	if not is_alive():
		return
	var applied := current_hp
	current_hp = 0
	damaged.emit(applied, current_hp, source_position)
	died.emit(source_position)


static func from_target(target: Node) -> Health:
	return target.get_node_or_null("Health") as Health


static func apply_damage(target: Node, amount: int, source_position: Vector3 = Vector3.ZERO) -> bool:
	var health := from_target(target)
	if health == null:
		return false
	return health.take_damage(amount, source_position)
