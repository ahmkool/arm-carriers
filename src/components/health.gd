class_name Health
extends Node

signal damaged(amount: int, remaining: int, source_position: Vector3)
signal died(source_position: Vector3)

@export var max_hp: int = 3

var current_hp: int


func _ready() -> void:
	reset_to_full()


func is_alive() -> bool:
	return current_hp > 0


func reset_to_full() -> void:
	current_hp = max_hp


func take_damage(amount: int, source_position: Vector3 = Vector3.ZERO) -> void:
	if not is_alive():
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
