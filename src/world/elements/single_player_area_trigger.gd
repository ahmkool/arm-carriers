class_name SinglePlayerAreaTrigger
extends EventAreaTrigger

## Fired once when any living [PlayerLocal] overlaps this area,
## then again only after everyone leaves and someone enters again.
signal player_inside

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
	return not _inside_ids.is_empty()

func _emit_triggered() -> void:
	player_inside.emit()
