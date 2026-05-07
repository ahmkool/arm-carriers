extends GameState


func enter() -> void:
	# Show InfoMessage
	self.world.get_node("UI/InfoMessage").show()
	self.world.get_node("UI/InfoMessage/PanelContainer/MarginContainer/InfoLabel").text = "Game Over - Press Start to restart"

func exit() -> void:
	pass

func update(delta: float) -> void:
	pass

func physics_update(delta: float) -> void:
	if Input.is_action_just_pressed("p0_start") or Input.is_action_just_pressed("p1_start"):
		self.world.restart_game()
