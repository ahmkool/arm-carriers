extends Area3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerLocal
	if player == null:
		return
	var world := _find_world_local()
	if world == null:
		return
	var gsm := world.get_node_or_null("GameStateMachine") as GameStateMachine
	if gsm == null or gsm.current == null:
		return
	if gsm.current.name.to_lower() != "playing":
		return

	player.die()
	gsm.transition_to("gameoverlost")


func _find_world_local() -> WorldLocal:
	var n := get_parent()
	while n != null:
		var w := n as WorldLocal
		if w != null:
			return w
		n = n.get_parent()
	return null
