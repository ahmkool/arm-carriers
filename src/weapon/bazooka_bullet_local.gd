class_name BazookaBulletLocal
extends Node3D

var velocity = Vector3.ZERO

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	var enemy := body as EnemyLocal
	if enemy != null:
		enemy.die()
