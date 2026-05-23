class_name EnemyStateMachine
extends Node

@export var initial_state_path: NodePath
var enemy: EnemyLocal
var states: Dictionary = {}
var current_state: EnemyState

func _ready() -> void:
	enemy = get_parent() as EnemyLocal
	for c in get_children():
		if c is EnemyState:
			var state := c as EnemyState
			state.enemy = enemy
			state.enemy_state_machine = self
			states[state.name.to_lower()] = state

	call_deferred("_enter_initial_state")


func _enter_initial_state() -> void:
	current_state = get_node(initial_state_path) as EnemyState
	if current_state == null:
		return
	current_state.enter()

func is_in_state(state_name: String) -> bool:
	var key := state_name.to_lower()
	if current_state == null or not states.has(key):
		return false
	return current_state == states[key]

func transition_to(state_name: String) -> void:
	var key := state_name.to_lower()
	if not states.has(key):
		print("Enemy state not found: ", state_name)
		return
	if current_state == states[key]:
		return
	if current_state:
		current_state.exit()
	current_state = states[key]
	#print("Transitioning to enemy state: ", state_name)
	current_state.enter()

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if enemy.behavior:
		enemy.behavior.tick(delta)
		_apply_behavior_locomotion_request()
	if current_state:
		current_state.physics_update(delta)
	enemy.move_and_slide()
	enemy.update_locomotion_blend()


func _apply_behavior_locomotion_request() -> void:
	var requested: StringName = enemy.behavior.intent.requested_locomotion
	if requested.is_empty():
		return
	if is_in_state("dead") or is_in_state("casting") or is_in_state("spawning"):
		return
	var requested_name := String(requested).to_lower()
	if current_state != null and current_state.name.to_lower() == requested_name:
		return
	transition_to(requested_name)
