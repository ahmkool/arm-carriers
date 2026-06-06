class_name EnemySpawner
extends Node3D

const SPAWN_ANIM := &"spawn"

@export var enemy_scene: PackedScene = preload("res://src/enemy/enemy_local.tscn")
@export var is_offensive: bool = true

var enemies_parent: Node

var _spawned := false

@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_animation_player.play(SPAWN_ANIM)


func spawn_enemy(anim_name: StringName) -> void:
	if anim_name != SPAWN_ANIM:
		return
	if _spawned:
		return
	_spawned = true
	_spawn_enemy()
	queue_free()


func _spawn_enemy() -> void:
	if enemy_scene == null:
		return
	if not is_instance_valid(enemies_parent):
		return
	var enemy := enemy_scene.instantiate() as EnemyLocal
	enemies_parent.add_child(enemy)
	enemy.global_transform = global_transform
	enemy.is_offensive = is_offensive
