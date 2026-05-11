extends GameState

## State to enter after WorldLocal (the game_state_machine parent) has finished _ready,
## so @onready on the world and the full subtree setup are done.
@export var next_state_name: String = "WaitingForPlayers"


func enter() -> void:
	if next_state_name.is_empty():
		push_error("AwaitWorldLocalReady: set next_state_name on the state node.")
		return
	if world == null:
		push_error("AwaitWorldLocalReady: world is null.")
		return
	if world.is_node_ready():
		game_state_machine.transition_to(next_state_name)
		return
	world.ready.connect(_on_world_ready, CONNECT_ONE_SHOT)


func exit() -> void:
	if world != null and world.ready.is_connected(_on_world_ready):
		world.ready.disconnect(_on_world_ready)


func _on_world_ready() -> void:
	game_state_machine.transition_to(next_state_name)
