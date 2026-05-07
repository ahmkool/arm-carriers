extends Node

signal game_state_changed(is_ongoing: bool)
signal game_over_changed(is_game_over: bool)

@onready var _spawn_location: Node = get_node_or_null("../SpawnLocation")
@onready var _game_over_ui: Control = get_node_or_null("../UI/GameOverUI")
var is_game_ongoing: bool = false
var is_game_over: bool = false


func _ready():
	if _game_over_ui != null:
		_game_over_ui.visible = false
	_update_game_state()


func _process(_delta):
	if is_game_over:
		return
	_update_game_state()


func _update_game_state() -> void:
	var was_ongoing := is_game_ongoing
	is_game_ongoing = _get_player_count() >= 2 and not is_game_over

	if was_ongoing != is_game_ongoing:
		game_state_changed.emit(is_game_ongoing)
		print("Game state changed: ", is_game_ongoing)


func _get_player_count() -> int:
	if _spawn_location == null:
		return 0
	return _spawn_location.get_child_count()


func trigger_game_over() -> void:
	print("Triggering game over")
	if is_game_over:
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_game_over.rpc_id(1)
		return

	_set_game_over_on_all.rpc()


@rpc("any_peer", "reliable")
func _request_game_over() -> void:
	print("Requesting game over")
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if is_game_over:
		return
	_set_game_over_on_all.rpc()


@rpc("authority", "call_local", "reliable")
func _set_game_over_on_all() -> void:
	print("Setting game over on all")
	if is_game_over:
		return

	is_game_over = true
	is_game_ongoing = false

	if _game_over_ui != null:
		_game_over_ui.visible = true

	game_over_changed.emit(true)
	game_state_changed.emit(false)
