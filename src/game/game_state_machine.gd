class_name GameStateMachine
extends Node

@export var initial_state_path: NodePath
var world: WorldLocal

var current: GameState
var states: Dictionary = {}

func _ready():
	world = get_parent() as WorldLocal
	for c in get_children():
		if c is GameState:
			var state = c as GameState
			state.game_state_machine = self
			state.world = world
			states[state.name.to_lower()] = state
	
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	start()

func _on_joy_connection_changed(device: int, connected: bool):
	print("Joypad ", device, " connected: ", connected)
	_print_connected_joypads()

func _print_connected_joypads() -> void:
	var pads := Input.get_connected_joypads()
	print("Connected joypads (device ids): ", pads)
	for device in pads:
		print("  device=", device,
			" name=", Input.get_joy_name(device),
			" guid=", Input.get_joy_guid(device))

func start():
	current = get_node(initial_state_path) as GameState
	print("Starting game state: ", current.name)
	current.enter()

func transition_to(state_name: String):
	if not states.has(state_name.to_lower()):
		print("State not found: ", state_name)
		return
	if current:
		current.exit()
	print("Transitioning to game state: ", state_name)
	current = states[state_name.to_lower()]
	current.enter()

func _process(delta: float):
	if current:
		current.update(delta)

func _physics_process(delta: float):
	if current:
		current.physics_update(delta)
