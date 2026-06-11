class_name AllPlayersAreaTrigger
extends EventAreaTrigger

## Fired once when every `required_player_id` has a [PlayerLocal] overlapping this area,
## then again only after someone leaves and the full set enters again.
signal all_players_inside

@export var required_player_ids: Array[int] = [0, 1]

var _inside_ids: Dictionary = {}

func _clear_overlap_state() -> void:
	_inside_ids.clear()

func _handle_player_entered(player: PlayerLocal) -> void:
	_inside_ids[player.player_id] = true
	_try_emit()

func _handle_player_exited(player: PlayerLocal) -> void:
	_inside_ids.erase(player.player_id)
	_rearm_if_needed()

func _should_emit() -> bool:
	if required_player_ids.is_empty():
		return false
	for id in required_player_ids:
		if not _inside_ids.has(id):
			return false
	return true

func _emit_triggered() -> void:
	all_players_inside.emit()
