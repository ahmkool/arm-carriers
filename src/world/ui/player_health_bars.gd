class_name PlayerHealthBars
extends MarginContainer

const PLAYER_HEALTH_BAR_SCENE := preload("res://src/world/ui/player_health_bar.tscn")
const MAX_PLAYERS := 2

@onready var _bars_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer

var _players: Players = null
var _bars: Array[PlayerHealthBar] = []


func _ready() -> void:
	hide()
	call_deferred("_try_bind_players")


func _exit_tree() -> void:
	_unbind_players()


func _try_bind_players() -> void:
	var world := LevelNodes.find_world(self)
	if world == null:
		return
	_players = world.players as Players
	if _players == null:
		return
	_ensure_bar_slots()
	_connect_players_signals()
	_sync_all_bars()


func _connect_players_signals() -> void:
	if _players.child_entered_tree.is_connected(_on_player_child_changed):
		return
	_players.child_entered_tree.connect(_on_player_child_changed)
	_players.child_exiting_tree.connect(_on_player_child_exiting)


func _unbind_players() -> void:
	if _players == null:
		return
	if _players.child_entered_tree.is_connected(_on_player_child_changed):
		_players.child_entered_tree.disconnect(_on_player_child_changed)
	if _players.child_exiting_tree.is_connected(_on_player_child_exiting):
		_players.child_exiting_tree.disconnect(_on_player_child_exiting)
	_players = null


func _ensure_bar_slots() -> void:
	while _bars.size() < MAX_PLAYERS:
		var bar := PLAYER_HEALTH_BAR_SCENE.instantiate() as PlayerHealthBar
		_bars_container.add_child(bar)
		_bars.append(bar)
		bar.hide_bar()


func _sync_all_bars() -> void:
	_ensure_bar_slots()
	var players := _get_sorted_players()
	if players.is_empty():
		hide()
	for i in MAX_PLAYERS:
		var bar := _bars[i]
		if i >= players.size():
			bar.hide_bar()
			continue
		bar.bind(players[i].health, players[i].health_bar_icon)
	if not players.is_empty():
		show()


func _get_sorted_players() -> Array[PlayerLocal]:
	var result: Array[PlayerLocal] = []
	if _players == null:
		return result
	for child in _players.get_children():
		var player := child as PlayerLocal
		if player == null:
			continue
		result.append(player)
	result.sort_custom(func(a: PlayerLocal, b: PlayerLocal) -> bool:
		return a.player_id < b.player_id
	)
	return result


func _on_player_child_changed(_node: Node) -> void:
	_sync_all_bars()


func _on_player_child_exiting(_node: Node) -> void:
	call_deferred("_sync_all_bars")
