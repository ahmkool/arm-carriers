class_name AllPlayersAreaTrigger
extends Area3D

## Fired once when every `required_player_id` has a [PlayerLocal] overlapping this area,
## then again only after someone leaves and the full set enters again.
signal all_players_inside

@export var required_player_ids: Array[int] = [0, 1]

var _inside_ids: Dictionary = {}
var _emitted_for_current_overlap := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerLocal
	if player == null:
		return
	_inside_ids[player.player_id] = true
	_try_emit_all_inside()


func _on_body_exited(body: Node3D) -> void:
	var player := body as PlayerLocal
	if player == null:
		return
	_inside_ids.erase(player.player_id)
	if not _all_required_inside():
		_emitted_for_current_overlap = false


func _all_required_inside() -> bool:
	if required_player_ids.is_empty():
		return false
	for id in required_player_ids:
		if not _inside_ids.has(id):
			return false
	return true


func _try_emit_all_inside() -> void:
	if _emitted_for_current_overlap:
		return
	if not _all_required_inside():
		return
	_emitted_for_current_overlap = true
	all_players_inside.emit()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
