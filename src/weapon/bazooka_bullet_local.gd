class_name BazookaBulletLocal
extends Node3D

const ExplosionScene := preload("res://src/vfx/explosion.tscn")

var velocity = Vector3.ZERO
var _spent := false

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_hit_area_body_entered(body: Node) -> void:
	if _spent:
		return
	if body is not EnemyLocal:
		return
	_spent = true
	set_physics_process(false)
	var explosion := ExplosionScene.instantiate() as Node3D
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	queue_free()
