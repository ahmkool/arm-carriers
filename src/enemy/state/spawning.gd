extends EnemyState

const POST_APPEAR_DELAY_SECONDS := 2.0


func enter() -> void:
	super.enter()
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	_disable_offensive_hit_box()
	enemy.play_spawn_animation()
	_run_post_appear_delay()


func _run_post_appear_delay() -> void:
	await enemy.get_tree().create_timer(POST_APPEAR_DELAY_SECONDS).timeout
	if not _is_still_spawning():
		return
	_transition_after_spawn()


func _is_still_spawning() -> bool:
	if not is_instance_valid(enemy):
		return false
	return enemy_state_machine.is_in_state("spawning")


func exit() -> void:
	enemy._sync_hit_box_to_offensive_state()


func _disable_offensive_hit_box() -> void:
	if not enemy.is_offensive:
		return
	var hit_box := enemy.get_node_or_null("HitBox") as Area3D
	if hit_box == null:
		return
	hit_box.set_deferred("monitoring", false)


func physics_update(delta: float) -> void:
	_apply_gravity_and_zero_horizontal(delta)


func _apply_gravity_and_zero_horizontal(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy.velocity += enemy.get_gravity() * delta
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.speed)
	enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.speed)


func _transition_after_spawn() -> void:
	if enemy.is_on_floor():
		enemy_state_machine.transition_to("idle")
		return
	enemy_state_machine.transition_to("falling")
