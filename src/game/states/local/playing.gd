extends GameState

func enter() -> void:
	var info_message := self.world.get_node("UI/InfoMessage")
	InfoMessagePresenter.hide_feedback_controls(info_message)
	info_message.hide()

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
