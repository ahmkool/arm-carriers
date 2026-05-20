class_name EnemyBehavior
extends Node

var enemy: EnemyLocal
var intent: EnemyIntent = EnemyIntent.new()

func _ready() -> void:
	enemy = get_parent() as EnemyLocal

func tick(delta: float) -> void:
	intent = EnemyIntent.new()
	_think(delta)

func _think(_delta: float) -> void:
	pass

func get_move_direction() -> Vector3:
	return intent.move_direction

func get_face_direction() -> Vector3:
	if intent.face_direction.length_squared() > 0.0001:
		return intent.face_direction
	return intent.move_direction
