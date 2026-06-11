class_name EventAreaTrigger
extends Area3D

var _emitted_for_current_overlap := false

func _reset() -> void:
	_clear_overlap_state()
	_emitted_for_current_overlap = false
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

func _mark_area_as_inactive() -> void:
	_clear_overlap_state()
	_emitted_for_current_overlap = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _clear_overlap_state() -> void:
	pass

func _handle_player_entered(_player: PlayerLocal) -> void:
	pass

func _handle_player_exited(_player: PlayerLocal) -> void:
	pass

func _should_emit() -> bool:
	return false

func _emit_triggered() -> void:
	pass

func _on_body_entered(body: Node3D) -> void:
	var player := _player_from_body(body)
	if player == null:
		return
	_handle_player_entered(player)

func _on_body_exited(body: Node3D) -> void:
	var player := body as PlayerLocal
	if player == null:
		return
	_handle_player_exited(player)

func _player_from_body(body: Node3D) -> PlayerLocal:
	var player := body as PlayerLocal
	if player == null:
		return null
	if player.is_in_dead_state():
		return null
	return player

func _try_emit() -> void:
	if _emitted_for_current_overlap:
		return
	if not _should_emit():
		return
	_emitted_for_current_overlap = true
	_emit_triggered()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func _rearm_if_needed() -> void:
	if _should_emit():
		return
	_emitted_for_current_overlap = false
