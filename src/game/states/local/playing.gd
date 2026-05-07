extends GameState

func enter() -> void:
	# Hide InfoMessage
	self.world.get_node("UI/InfoMessage").hide()

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	for child in self.world.players.get_children():
		var player := child as PlayerLocal
		if player == null:
			continue
		if player.is_dead:
			self.game_state_machine.transition_to("gameoverlost")
			return
