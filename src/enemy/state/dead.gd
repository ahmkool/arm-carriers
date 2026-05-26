extends EnemyState

const PUFF_DISAPPEAR_SCENE := preload("res://src/vfx/puff_disappear.tscn")
const ENEMY_DAMAGE_SCENE := preload("res://src/vfx/enemy_damage.tscn")

@export var tween_delay: float = 2.0
@export var shrink_duration: float = 0.4


func enter() -> void:
	enemy.play_dead_animation()
	enemy.velocity = Vector3.ZERO
	_disable_collisions()
	_spawn_enemy_damage()
	_run_death_sequence()


func _disable_collisions() -> void:
	enemy.set_collision_layer_value(1, false)
	enemy.set_collision_layer_value(2, false)
	enemy.set_collision_layer_value(3, false)
	enemy.set_collision_mask_value(1, false)
	enemy.set_collision_mask_value(2, false)
	enemy.set_collision_mask_value(3, false)
	var hit_box := enemy.get_node_or_null("HitBox") as Area3D
	if hit_box == null:
		return
	hit_box.set_deferred("monitoring", false)
	hit_box.set_deferred("monitorable", false)
	for node in hit_box.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node != null:
			shape_node.set_deferred("disabled", true)


func _run_death_sequence() -> void:
	await enemy.get_tree().create_timer(tween_delay).timeout
	if not is_instance_valid(enemy):
		return
	await _tween_shrink_to_zero()
	if not is_instance_valid(enemy):
		return
	_spawn_disappear_puff()
	enemy.queue_free()

var almost_zero_vector = Vector3(0.01, 0.01, 0.01)

func _tween_shrink_to_zero() -> void:
	var tween := enemy.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(enemy, "scale", almost_zero_vector, shrink_duration)
	await tween.finished


func _spawn_enemy_damage() -> void:
	var world := enemy.get_tree().current_scene
	if world == null:
		return
	var fx := ENEMY_DAMAGE_SCENE.instantiate()
	if enemy.has_damage_source_position():
		fx.set_damage_source(enemy.get_damage_source_position())
	world.add_child(fx)
	fx.global_position = enemy.global_position


func _spawn_disappear_puff() -> void:
	var world := enemy.get_tree().current_scene
	if world == null:
		return
	var puff := PUFF_DISAPPEAR_SCENE.instantiate() as GPUParticles3D
	world.add_child(puff)
	puff.global_position = enemy.global_position
	puff.emitting = true
	var cleanup_delay := puff.lifetime + 0.5
	puff.get_tree().create_timer(cleanup_delay).timeout.connect(puff.queue_free)
