class_name EnemyGroup
extends Node3D

signal enemies_defeated

var signal_emitted := false

func _physics_process(delta):
	if signal_emitted:
		return
	var enemies = get_children()
	var alive_enemies = enemies.filter(func(enemy): return enemy.is_alive())
	if alive_enemies.size() == 0:
		signal_emitted = true
		print("EnemyGroup: All enemies defeated")
		enemies_defeated.emit()

func mark_as_defeated():
	for enemy in get_children():
		enemy.queue_free()
	signal_emitted = true
