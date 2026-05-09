class_name PlayerStateMachine
extends Node

@export var initial_state_path: NodePath
var player: PlayerLocal
var states: Dictionary = {}
var current_state: PlayerState

func _ready():
	player = get_parent() as PlayerLocal
	for c in get_children():
		if c is PlayerState:
			var state = c as PlayerState
			state.player = player
			state.player_state_machine = self
			states[state.name.to_lower()] = state
	
	current_state = get_node(initial_state_path) as PlayerState
	# Parent PlayerLocal._ready runs after this node's _ready; defer so @onready (e.g. AnimationTree) exists.
	call_deferred("_deferred_initial_enter")

func _deferred_initial_enter() -> void:
	if current_state:
		current_state.enter()

func transition_to(state_name: String):
	if not states.has(state_name.to_lower()):
		print("State not found: ", state_name)
		return
	if current_state:
		current_state.exit()
	#print("Transitioning to player state: ", state_name)
	current_state = states[state_name.to_lower()]
	current_state.enter()

func _process(delta: float):
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float):
	if current_state:
		current_state.physics_update(delta)
	player.move_and_slide()
	player.update_locomotion_blend()
