class_name Health
extends Node

signal damaged(amount: int, remaining: int, source_position: Vector3)
signal died(source_position: Vector3)
signal restored

@export var max_hp: int = 3

var current_hp: int
var _invulnerable_time_remaining := 0.0

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


func take_damage(amount: int, source_position: Vector3 = Vector3.ZERO) -> void:
	if not is_alive():
		return
	if is_invulnerable():
		return
	var applied := mini(amount, current_hp)
	current_hp -= applied
	damaged.emit(applied, current_hp, source_position)
	if current_hp <= 0:
		died.emit(source_position)


static func from_target(target: Node) -> Health:
	return target.get_node_or_null("Health") as Health


static func apply_damage(target: Node, amount: int, source_position: Vector3 = Vector3.ZERO) -> bool:
	var health := from_target(target)
	if health == null:
		return false
	health.take_damage(amount, source_position)
	return true
